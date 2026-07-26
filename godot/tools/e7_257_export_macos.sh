#!/usr/bin/env bash
# #257：Godot 4.6.1 macOS Alpha 导出入口（ad-hoc only）。
# 产物仅写入 /tmp/mahjong-e7-257-* ；禁止 Developer ID / 公证。
# exit 0 后仍审计导出日志：SCRIPT ERROR / Parse Error / Failed loading resource → 失败。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GODOT_DIR="$ROOT/godot"
PRESET_NAME="macOS Alpha"
STAMP="${E7_257_STAMP:-$(date +%Y%m%d%H%M%S)-$$}"
OUT_ROOT="${E7_257_OUT_ROOT:-/tmp/mahjong-e7-257-export-${STAMP}}"
APP_PATH="$OUT_ROOT/MahjongGame.app"
LOG="${E7_257_EXPORT_LOG:-/tmp/mahjong-e7-257-export-${STAMP}.log}"
GODOT_BIN="${GODOT_BIN:-godot}"
TEMPLATE_VER="4.6.1.stable"
TEMPLATE_DIR="${GODOT_EXPORT_TEMPLATES_DIR:-$HOME/Library/Application Support/Godot/export_templates/$TEMPLATE_VER}"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "OK: $*"; }

case "$OUT_ROOT" in
  /tmp/mahjong-e7-257-*) ;;
  *) fail "OUT_ROOT must be under /tmp/mahjong-e7-257-* (got $OUT_ROOT)" ;;
esac

mkdir -p "$OUT_ROOT"

if [[ -n "${GODOT_MACOS_CODESIGN_CERTIFICATE_FILE:-}" ]]; then
  fail "GODOT_MACOS_CODESIGN_CERTIFICATE_FILE is set; #257 forbids Developer ID / cert export"
fi
if [[ -n "${GODOT_MACOS_CODESIGN_CERTIFICATE_PASSWORD:-}" ]]; then
  fail "GODOT_MACOS_CODESIGN_CERTIFICATE_PASSWORD is set; #257 forbids Developer ID"
fi
if [[ -n "${GODOT_MACOS_NOTARIZATION_APPLE_ID_NAME:-}" || -n "${GODOT_MACOS_NOTARIZATION_API_UUID:-}" ]]; then
  fail "Notarization env vars set; #257 forbids notarization"
fi

PRESET_CFG="$GODOT_DIR/export_presets.cfg"
[[ -f "$PRESET_CFG" ]] || fail "missing export_presets.cfg"
grep -E 'name="macOS Alpha"' "$PRESET_CFG" >/dev/null || fail "preset macOS Alpha missing"
grep -E 'codesign/codesign=1' "$PRESET_CFG" >/dev/null || fail "preset must use ad-hoc codesign=1"
grep -E 'codesign/entitlements/audio_input=true' "$PRESET_CFG" >/dev/null || fail "audio_input must be true"

if [[ ! -f "$TEMPLATE_DIR/macos.zip" ]]; then
  fail "missing export template macos.zip at $TEMPLATE_DIR"
fi
pass "export template present: $TEMPLATE_DIR/macos.zip"

# 清理旧 app
rm -rf "$APP_PATH"

echo "exporting to $APP_PATH (log $LOG)"
set +e
"$GODOT_BIN" --headless --path "$GODOT_DIR" --export-release "$PRESET_NAME" "$APP_PATH" >"$LOG" 2>&1
EC=$?
set -e
if [[ $EC -ne 0 ]]; then
  echo "export failed exit=$EC (see $LOG)" >&2
  rg -n 'ERROR|error|Failed|failed|Export' "$LOG" 2>/dev/null | tail -40 >&2 || true
  exit "$EC"
fi

[[ -d "$APP_PATH" ]] || fail "export did not produce $APP_PATH"

# 导出日志阻断审计（0 命中）
ERR_COUNT="$(rg -c 'SCRIPT ERROR|Parse Error|Failed loading resource' "$LOG" 2>/dev/null || true)"
ERR_COUNT="${ERR_COUNT:-0}"
if [[ "$ERR_COUNT" != "0" ]]; then
  rg -n 'SCRIPT ERROR|Parse Error|Failed loading resource' "$LOG" | head -40 >&2 || true
  fail "export log contains $ERR_COUNT SCRIPT ERROR / Parse Error / Failed loading resource hits"
fi
pass "export log clean (0 SCRIPT/Parse/Failed-loading hits)"

# 配置错误消息
if rg -n 'Cannot export project with preset|configuration errors' "$LOG" >/dev/null; then
  fail "export log reports configuration errors"
fi

pass "exported $APP_PATH"
echo "E7_257_APP_PATH=$APP_PATH"
echo "E7_257_OUT_ROOT=$OUT_ROOT"
echo "E7_257_EXPORT_LOG=$LOG"
echo "E7_257_EXPORT_ERROR_HITS=0"
exit 0
