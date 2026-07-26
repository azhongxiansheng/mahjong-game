#!/usr/bin/env bash
# #257：干净 macOS 用户目录风格 smoke（仅 /tmp/mahjong-e7-257-*）。
# 检查 bundle / Info.plist / ad-hoc codesign --verify --deep --strict / 包内无大模型 / 主场景启动。
# 真实 Godot 4.6 user:// = ~/Library/Application Support/Godot/app_userdata/MahjongGame
# 网络端到端未验证；真实麦克风授权需可见人工操作。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAMP="${E7_257_STAMP:-$(date +%Y%m%d%H%M%S)-$$}"
SMOKE_ROOT="${E7_257_SMOKE_ROOT:-/tmp/mahjong-e7-257-smoke-${STAMP}}"
LOG="${E7_257_SMOKE_LOG:-/tmp/mahjong-e7-257-smoke-${STAMP}.log}"
APP_PATH="${E7_257_APP_PATH:-}"
REAL_USER_DATA="$HOME/Library/Application Support/Godot/app_userdata/MahjongGame"
GODOT_BIN="${GODOT_BIN:-godot}"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "OK: $*"; }

case "$SMOKE_ROOT" in
  /tmp/mahjong-e7-257-*) ;;
  *) fail "SMOKE_ROOT must be under /tmp/mahjong-e7-257-*" ;;
esac

if [[ "$SMOKE_ROOT" == "$REAL_USER_DATA"* ]]; then
  fail "refusing to use real user:// path as smoke root"
fi

mkdir -p "$SMOKE_ROOT"
exec > >(tee -a "$LOG") 2>&1
echo "== #257 macOS package smoke =="
echo "smoke_root=$SMOKE_ROOT"
echo "NOTE: never touch $REAL_USER_DATA"

if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
  export E7_257_STAMP="$STAMP"
  export E7_257_OUT_ROOT="$SMOKE_ROOT/export"
  bash "$ROOT/scripts/e7_257_macos_package.sh"
  APP_PATH="$SMOKE_ROOT/export/MahjongGame.app"
fi
case "$APP_PATH" in
  /tmp/mahjong-e7-257-*) ;;
  *) fail "APP_PATH must be under /tmp/mahjong-e7-257-* (got $APP_PATH)" ;;
esac
[[ -d "$APP_PATH" ]] || fail "app not found: $APP_PATH"
pass "app present: $APP_PATH"

INFO="$APP_PATH/Contents/Info.plist"
[[ -f "$INFO" ]] || fail "missing Info.plist"
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO" 2>/dev/null | grep -qx 'com.lovteam.MahjongGame' \
  || fail "CFBundleIdentifier mismatch"
MIC_DESC="$(/usr/libexec/PlistBuddy -c 'Print :NSMicrophoneUsageDescription' "$INFO" 2>/dev/null || true)"
[[ -n "$MIC_DESC" ]] || fail "NSMicrophoneUsageDescription missing"
echo "$MIC_DESC" | grep -E '麦克风|按住说话|欢乐' >/dev/null \
  || fail "mic usage description not clear: $MIC_DESC"
pass "Info.plist bundle id + mic usage"

# 严格 codesign
set +e
codesign --verify --deep --strict "$APP_PATH" 2>"$SMOKE_ROOT/codesign_verify.txt"
CS_EC=$?
set -e
[[ "$CS_EC" -eq 0 ]] || fail "codesign --verify --deep --strict failed (exit $CS_EC)"
CODESIGN_OUT="$(codesign -dv --verbose=4 "$APP_PATH" 2>&1 || true)"
echo "$CODESIGN_OUT" | tee "$SMOKE_ROOT/codesign.txt" >/dev/null
if echo "$CODESIGN_OUT" | grep -Ei 'Developer ID Application' >/dev/null; then
  fail "app signed with Developer ID — #257 requires ad-hoc only"
fi
echo "$CODESIGN_OUT" | grep -qi 'Signature=adhoc' \
  || fail "Signature=adhoc not found"
echo "$CODESIGN_OUT" | grep -E 'Format=.*universal \(x86_64 arm64\)' >/dev/null \
  || fail "expected universal x86_64 arm64 binary"
pass "ad-hoc + universal + codesign --verify ok"

EXE="$(find "$APP_PATH/Contents/MacOS" -type f 2>/dev/null | head -1)"
[[ -n "$EXE" && -x "$EXE" ]] || fail "missing executable under Contents/MacOS"
pass "runtime executable present"

find "$APP_PATH" -name '*.pck' | grep -q . || fail "PCK missing"
pass "PCK present"

BAD=0
while IFS= read -r -d '' f; do
  base="$(basename "$f")"
  case "$base" in
    ggml-small.bin|*.partial|*.partial.chunk|ggml-*.bin)
      echo "FAIL path: $f"
      BAD=1
      ;;
  esac
  sz="$(stat -f%z "$f" 2>/dev/null || echo 0)"
  if [[ "$sz" -ge 400000000 ]]; then
    echo "FAIL oversized file (>=400MB): $f ($sz)"
    BAD=1
  fi
done < <(find "$APP_PATH" -type f -print0)
[[ "$BAD" -eq 0 ]] || fail "package contains model or oversized artifacts"
pass "no ggml-small.bin / partial / 487MB model in bundle"

# --- 真实 user:// 只读快照 ---
snapshot_user_data() {
  local out="$1"
  if [[ -d "$REAL_USER_DATA" ]]; then
    (
      cd "$REAL_USER_DATA"
      # 仅路径集合：忽略 logs/settings/shader_cache 等易变项；本 smoke 用隔离 HOME，不应新增业务路径
      find . -type f \
        ! -path './logs/*' \
        ! -path './shader_cache/*' \
        ! -name 'settings.json' \
        ! -name 'godot.log' \
        2>/dev/null | sort
    ) >"$out" || true
  else
    echo "__ABSENT__" >"$out"
  fi
}
SNAP_BEFORE="$SMOKE_ROOT/real_user_before.txt"
SNAP_AFTER="$SMOKE_ROOT/real_user_after.txt"
snapshot_user_data "$SNAP_BEFORE"

FAKE_HOME="$SMOKE_ROOT/fake-home"
mkdir -p "$FAKE_HOME"
# headless 启动足够帧加载主场景；要求 exit 0
set +e
HOME="$FAKE_HOME" "$EXE" --headless --quit-after 30 >"$SMOKE_ROOT/app_run.log" 2>&1
APP_EC=$?
set -e
echo "app_headless_exit=$APP_EC"
[[ "$APP_EC" -eq 0 ]] || fail "exported app headless exit=$APP_EC (must be 0); see $SMOKE_ROOT/app_run.log"

# 阻断模式：SCRIPT ERROR / Parse Error / Failed loading resource
if rg -n 'SCRIPT ERROR|Parse Error|Failed loading resource' "$SMOKE_ROOT/app_run.log" >/dev/null; then
  rg -n 'SCRIPT ERROR|Parse Error|Failed loading resource' "$SMOKE_ROOT/app_run.log" | head -20 >&2 || true
  fail "app log contains SCRIPT ERROR / Parse Error / Failed loading resource"
fi
pass "app headless start clean (exit 0, no parse/script/resource errors)"

# 隔离 HOME 内必须出现 Godot user:// 对应路径
FAKE_USER="$FAKE_HOME/Library/Application Support/Godot/app_userdata/MahjongGame"
if [[ ! -d "$FAKE_USER" ]]; then
  # 至少应有 Godot 用户数据树的一部分
  if ! find "$FAKE_HOME" -type d -name 'MahjongGame' 2>/dev/null | grep -q .; then
    find "$FAKE_HOME" 2>/dev/null | head -40 >&2 || true
    fail "fake HOME did not create Godot app_userdata/MahjongGame tree"
  fi
fi
pass "fake HOME created isolated user data under Godot/app_userdata"

snapshot_user_data "$SNAP_AFTER"
if ! cmp -s "$SNAP_BEFORE" "$SNAP_AFTER"; then
  echo "BEFORE:"; head -20 "$SNAP_BEFORE"
  echo "AFTER:"; head -20 "$SNAP_AFTER"
  fail "real Godot user:// path changed during package smoke"
fi
pass "real user:// path unchanged"

du -sh "$APP_PATH" | tee "$SMOKE_ROOT/app_size.txt"
echo "PASS: #257 macOS package smoke"
echo "E7_257_APP_PATH=$APP_PATH"
echo "E7_257_SMOKE_LOG=$LOG"
exit 0
