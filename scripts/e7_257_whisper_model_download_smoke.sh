#!/usr/bin/env bash
# #257：用最终导出 MahjongGame.app 执行真实 WhisperModelManager 生产下载 + size/SHA。
# 默认强制导出 app（Contents/MacOS/MahjongGame）；仅 E7_257_ALLOW_EDITOR=1 时允许编辑器二进制。
# 从空 /tmp/mahjong-e7-257-* models root；禁止复用 stage / 预置 active。
# 不写真实 ~/Library/Application Support/Godot/app_userdata/MahjongGame。
# 网络端到端（四端/公网整场）未验证。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAMP="${E7_257_STAMP:-$(date +%Y%m%d%H%M%S)-$$}"
STAGE="${E7_257_MODEL_STAGE:-/tmp/mahjong-e7-257-model-${STAMP}}"
LOG="${E7_257_MODEL_LOG:-/tmp/mahjong-e7-257-model-${STAMP}.log}"
APP_PATH="${E7_257_APP_PATH:-}"
ALLOW_EDITOR="${E7_257_ALLOW_EDITOR:-0}"
REAL_USER_DATA="$HOME/Library/Application Support/Godot/app_userdata/MahjongGame"

PROD_SIZE="${E7_257_MODEL_SIZE:-487601967}"
PROD_SHA="${E7_257_MODEL_SHA256:-1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b}"
FILENAME="ggml-small.bin"
VERSION_DIR="ggml-small@5359861c739e955e79d9a303bcbc70fb988958b1"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "OK: $*"; }

case "$STAGE" in
  /tmp/mahjong-e7-257-*) ;;
  *) fail "STAGE must be under /tmp/mahjong-e7-257-*" ;;
esac

if [[ -e "$STAGE" ]]; then
  fail "stage already exists (refuse reuse): $STAGE — use a fresh E7_257_STAMP"
fi
mkdir -p "$STAGE"
MGR_ROOT="$STAGE/whisper_root"
mkdir -p "$MGR_ROOT"
if find "$MGR_ROOT" -type f | grep -q .; then
  fail "models root not empty: $MGR_ROOT"
fi

# --- 定位导出 app 可执行文件（默认强制，禁止编辑器冒充）---
resolve_app_exe() {
  if [[ -n "$APP_PATH" && -d "$APP_PATH" ]]; then
    :
  elif [[ -n "${E7_257_OUT_ROOT:-}" && -d "${E7_257_OUT_ROOT}/MahjongGame.app" ]]; then
    APP_PATH="${E7_257_OUT_ROOT}/MahjongGame.app"
  else
    # 取最新 /tmp/mahjong-e7-257-export-*/MahjongGame.app
    APP_PATH="$(ls -dt /tmp/mahjong-e7-257-export-*/MahjongGame.app 2>/dev/null | head -1 || true)"
  fi
  [[ -n "$APP_PATH" && -d "$APP_PATH" ]] || fail "missing exported MahjongGame.app (set E7_257_APP_PATH)"
  case "$APP_PATH" in
    /tmp/mahjong-e7-257-*) ;;
    *) fail "APP_PATH must be under /tmp/mahjong-e7-257-* (got $APP_PATH)" ;;
  esac
  local exe="$APP_PATH/Contents/MacOS/MahjongGame"
  [[ -x "$exe" ]] || fail "missing executable: $exe"
  # 拒绝误用编辑器路径
  if echo "$exe" | grep -Ei 'Godot\.app|/opt/homebrew/bin/godot|/usr/local/bin/godot' >/dev/null; then
    fail "refusing editor binary path: $exe"
  fi
  if [[ "$ALLOW_EDITOR" != "1" ]]; then
    # 可执行文件名须为 MahjongGame
    [[ "$(basename "$exe")" == "MahjongGame" ]] || fail "expected MahjongGame executable"
  fi
  echo "$exe"
}

EXE="$(resolve_app_exe)"
pass "using exported app exe: $EXE (app=$APP_PATH)"

exec > >(tee -a "$LOG") 2>&1
echo "== #257 real model download via EXPORTED app =="
echo "stage=$STAGE"
echo "models_root=$MGR_ROOT"
echo "app=$APP_PATH"
echo "exe=$EXE"
echo "expected_size=$PROD_SIZE"
echo "expected_sha256=$PROD_SHA"
echo "NOTE: must not read/write $REAL_USER_DATA"
echo "NOTE: default path uses exported app, not editor godot"

snapshot_user_data() {
  local out="$1"
  if [[ -d "$REAL_USER_DATA" ]]; then
    (
      cd "$REAL_USER_DATA"
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

SNAP_BEFORE="$STAGE/real_user_before.txt"
SNAP_AFTER="$STAGE/real_user_after.txt"
snapshot_user_data "$SNAP_BEFORE"

export E7_257_MODELS_ROOT="$MGR_ROOT"
export E7_257_MODE="download"
FAKE_HOME="$STAGE/fake-home"
mkdir -p "$FAKE_HOME"

echo "starting manager production download via exported app (may take several minutes)…"
# release 模板禁用 --script/--path；通过 GameManager 环境变量门闩跑生产 ensure_ready 后 quit
set +e
HOME="$FAKE_HOME" \
  E7_257_MODELS_ROOT="$MGR_ROOT" \
  E7_257_MODE=download \
  "$EXE" --headless \
  >"$STAGE/manager_download.log" 2>&1
MEC=$?
set -e
echo "manager_exit=$MEC"

rg -n 'E7_257_|ERROR|SCRIPT ERROR|Parse Error' "$STAGE/manager_download.log" | tail -50 || true

[[ "$MEC" -eq 0 ]] || fail "exported-app manager process exit=$MEC (must be ready)"
rg -n 'E7_257_MANAGER_STATE=ready' "$STAGE/manager_download.log" >/dev/null \
  || fail "manager log missing STATE=ready"
rg -n 'E7_257_MANAGER_READY=true' "$STAGE/manager_download.log" >/dev/null \
  || fail "manager log missing READY=true"
pass "manager ready via exported app ensure_ready"

# 证明跑的是导出 app：日志或进程不应依赖编辑器
if rg -n 'Editor|editor build' "$STAGE/manager_download.log" >/dev/null 2>&1; then
  echo "WARN: log mentions editor (inspect)"
fi

ACTIVE="$MGR_ROOT/$VERSION_DIR/$FILENAME"
[[ -f "$ACTIVE" ]] || fail "active model missing: $ACTIVE"
if [[ -f "${ACTIVE}.partial" ]]; then
  fail "unexpected leftover partial after ready: ${ACTIVE}.partial"
fi
if [[ -f "${ACTIVE}.partial.chunk" ]]; then
  fail "unexpected leftover chunk after ready: ${ACTIVE}.partial.chunk"
fi

ACTUAL_SIZE="$(stat -f%z "$ACTIVE")"
[[ "$ACTUAL_SIZE" == "$PROD_SIZE" ]] || fail "size mismatch: got $ACTUAL_SIZE want $PROD_SIZE"
pass "independent size ok ($ACTUAL_SIZE)"

ACTUAL_SHA="$(shasum -a 256 "$ACTIVE" | awk '{print $1}')"
[[ "$ACTUAL_SHA" == "$PROD_SHA" ]] || fail "sha256 mismatch: got $ACTUAL_SHA"
pass "independent sha256 ok"

rg -n 'E7_257_PROGRESS' "$STAGE/manager_download.log" >/dev/null \
  || fail "manager log has no E7_257_PROGRESS mid samples"
pass "manager emitted progress samples"

REPO_HIT="$(find "$ROOT" -name 'ggml-small.bin' 2>/dev/null | head -5 || true)"
[[ -z "$REPO_HIT" ]] || fail "ggml-small.bin found in repo: $REPO_HIT"
pass "repo clean of ggml-small.bin"

if [[ -d "$FAKE_HOME/Library/Application Support/Godot/app_userdata/MahjongGame" ]] \
  || find "$FAKE_HOME" -type d -name 'MahjongGame' 2>/dev/null | grep -q .; then
  pass "fake HOME has isolated Godot user data"
else
  if find "$FAKE_HOME" -type f 2>/dev/null | grep -q .; then
    pass "fake HOME has isolated writes"
  else
    echo "WARN: fake HOME empty (absolute models_root)"
  fi
fi

snapshot_user_data "$SNAP_AFTER"
if ! cmp -s "$SNAP_BEFORE" "$SNAP_AFTER"; then
  echo "BEFORE:"; head -20 "$SNAP_BEFORE"
  echo "AFTER:"; head -20 "$SNAP_AFTER"
  fail "real Godot user:// path changed during smoke"
fi
pass "real user:// path unchanged"

if [[ "${E7_257_CLEAN_MODEL:-0}" == "1" ]]; then
  case "$STAGE" in
    /tmp/mahjong-e7-257-*) rm -rf "$STAGE"; pass "cleaned $STAGE" ;;
    *) fail "refuse clean outside staging" ;;
  esac
else
  echo "evidence retained: $ACTIVE"
  ls -lh "$ACTIVE"
fi

echo "PASS: #257 real model download via exported app"
echo "E7_257_APP_PATH=$APP_PATH"
echo "E7_257_MODEL_PATH=$ACTIVE"
echo "E7_257_MODEL_LOG=$LOG"
exit 0
