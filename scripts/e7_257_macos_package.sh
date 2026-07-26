#!/usr/bin/env bash
# #257 E7-03：安装 4.6.1 macOS export template（如缺失）并导出 Alpha 包到 /tmp/mahjong-e7-257-*。
# 仅 ad-hoc 签名；禁止 Developer ID / 公证 / Apple 凭证。
# 网络端到端未验证。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAMP="${E7_257_STAMP:-$(date +%Y%m%d%H%M%S)-$$}"
OUT_ROOT="${E7_257_OUT_ROOT:-/tmp/mahjong-e7-257-export-${STAMP}}"
LOG="${E7_257_PACKAGE_LOG:-/tmp/mahjong-e7-257-package-${STAMP}.log}"
TEMPLATE_VER="4.6.1.stable"
TEMPLATE_HOME="${GODOT_EXPORT_TEMPLATES_DIR:-$HOME/Library/Application Support/Godot/export_templates/$TEMPLATE_VER}"
TPZ_URL="${E7_257_TPZ_URL:-https://github.com/godotengine/godot/releases/download/4.6.1-stable/Godot_v4.6.1-stable_export_templates.tpz}"
CACHE_DIR="${E7_257_TEMPLATE_CACHE:-/tmp/mahjong-e7-257-templates-${STAMP}}"
GODOT_BIN="${GODOT_BIN:-godot}"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "OK: $*"; }

case "$OUT_ROOT" in
  /tmp/mahjong-e7-257-*) ;;
  *) fail "OUT_ROOT must be under /tmp/mahjong-e7-257-*" ;;
esac
case "$CACHE_DIR" in
  /tmp/mahjong-e7-257-*) ;;
  *) fail "CACHE_DIR must be under /tmp/mahjong-e7-257-*" ;;
esac

# 禁止 Developer ID 环境
if [[ -n "${GODOT_MACOS_CODESIGN_CERTIFICATE_FILE:-}" || -n "${GODOT_MACOS_CODESIGN_CERTIFICATE_PASSWORD:-}" ]]; then
  fail "Developer ID / cert env set — forbidden for #257 (ad-hoc only)"
fi

mkdir -p "$OUT_ROOT" "$CACHE_DIR"
exec > >(tee -a "$LOG") 2>&1
echo "== #257 macOS package =="
echo "out_root=$OUT_ROOT"
echo "template_home=$TEMPLATE_HOME"
echo "godot=$("$GODOT_BIN" --version 2>/dev/null || true)"

# --- ensure export templates ---
if [[ ! -f "$TEMPLATE_HOME/macos.zip" ]]; then
  echo "installing export templates to $TEMPLATE_HOME"
  mkdir -p "$TEMPLATE_HOME"
  TPZ_PATH="$CACHE_DIR/Godot_v4.6.1-stable_export_templates.tpz"
  if [[ ! -f "$TPZ_PATH" ]]; then
    echo "downloading $TPZ_URL"
    curl -fL --retry 3 --retry-delay 2 -o "$TPZ_PATH" "$TPZ_URL" \
      || fail "template download failed"
  fi
  # tpz 实为 zip：内含 templates/*
  EXTRACT="$CACHE_DIR/extract"
  rm -rf "$EXTRACT"
  mkdir -p "$EXTRACT"
  unzip -q "$TPZ_PATH" -d "$EXTRACT" || fail "unzip tpz failed"
  if [[ -f "$EXTRACT/templates/macos.zip" ]]; then
    cp -f "$EXTRACT/templates/macos.zip" "$TEMPLATE_HOME/macos.zip"
    # version.txt 可选但 Godot 有时检查
    if [[ -f "$EXTRACT/templates/version.txt" ]]; then
      cp -f "$EXTRACT/templates/version.txt" "$TEMPLATE_HOME/version.txt"
    else
      echo "$TEMPLATE_VER" >"$TEMPLATE_HOME/version.txt"
    fi
  else
    # 某些 tpz 直接是 templates 目录内容
    if [[ -f "$EXTRACT/macos.zip" ]]; then
      cp -f "$EXTRACT/macos.zip" "$TEMPLATE_HOME/macos.zip"
      echo "$TEMPLATE_VER" >"$TEMPLATE_HOME/version.txt"
    else
      fail "macos.zip not found inside tpz"
    fi
  fi
  pass "installed macos.zip template"
else
  pass "export template already present"
fi

[[ -f "$TEMPLATE_HOME/macos.zip" ]] || fail "macos.zip still missing"

# --- export ---
export E7_257_STAMP="$STAMP"
export E7_257_OUT_ROOT="$OUT_ROOT"
export E7_257_EXPORT_LOG="${E7_257_EXPORT_LOG:-/tmp/mahjong-e7-257-export-${STAMP}.log}"
export GODOT_BIN
bash "$ROOT/godot/tools/e7_257_export_macos.sh"

APP_PATH="$OUT_ROOT/MahjongGame.app"
[[ -d "$APP_PATH" ]] || fail "app missing after export"
# 记录清单
{
  echo "app=$APP_PATH"
  echo "size_bytes=$(du -sk "$APP_PATH" | awk '{print $1*1024}')"
  echo "stamp=$STAMP"
} >"$OUT_ROOT/MANIFEST.txt"
pass "package ready: $APP_PATH"
echo "E7_257_APP_PATH=$APP_PATH"
echo "E7_257_PACKAGE_LOG=$LOG"
exit 0
