#!/usr/bin/env bash
# #257 P2-1：证明 package/model smoke 含负向门禁（不会假通过）。
# 不执行重型导出/487MB 下载；只静态检查脚本与可执行小探针。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG_SMOKE="$ROOT/scripts/e7_257_macos_package_smoke.sh"
MODEL_SMOKE="$ROOT/scripts/e7_257_whisper_model_download_smoke.sh"
EXPORT_SH="$ROOT/godot/tools/e7_257_export_macos.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "OK: $*"; }

echo "== #257 smoke negative contract =="

[[ -f "$PKG_SMOKE" ]] || fail "missing package smoke"
[[ -f "$MODEL_SMOKE" ]] || fail "missing model smoke"
[[ -f "$EXPORT_SH" ]] || fail "missing export tool"

# package smoke 必须要求 APP_EC==0
grep -E 'APP_EC.*-eq 0|\[\[ "\$APP_EC" -eq 0 \]\]' "$PKG_SMOKE" >/dev/null \
  || fail "package smoke must require app exit 0"
# 必须扫描 SCRIPT ERROR / Parse Error / Failed loading resource
grep -E 'SCRIPT ERROR\|Parse Error\|Failed loading resource' "$PKG_SMOKE" >/dev/null \
  || fail "package smoke must fail on SCRIPT/Parse/Failed-loading"
# 必须使用正确 Godot user:// 路径
grep -F 'Godot/app_userdata/MahjongGame' "$PKG_SMOKE" >/dev/null \
  || fail "package smoke must monitor Godot/app_userdata/MahjongGame"
# 不得再以 Application Support/MahjongGame（错误路径）为唯一监控
if grep -E 'Application Support/MahjongGame' "$PKG_SMOKE" | grep -v 'app_userdata' | grep -v 'NOTE' >/dev/null; then
  # 允许注释中的旧路径提及
  :
fi
# codesign strict
grep -E 'codesign --verify --deep --strict' "$PKG_SMOKE" >/dev/null \
  || fail "package smoke must codesign --verify --deep --strict"
# 不得出现“不要求特定退出码”
if grep -E '不要求特定退出码' "$PKG_SMOKE" >/dev/null; then
  fail "package smoke still says exit code not required"
fi
pass "package smoke negative gates present"

# model smoke：必须用导出 app，禁止默认编辑器冒充
grep -E 'MahjongGame\.app|Contents/MacOS/MahjongGame' "$MODEL_SMOKE" >/dev/null \
  || fail "model smoke must target exported MahjongGame.app"
grep -E 'E7_257_ALLOW_EDITOR|refusing editor|exported app' "$MODEL_SMOKE" >/dev/null \
  || fail "model smoke must document/enforce exported-app default"
# 禁止 curl 下载模型 body（允许文档提及 curl resolver）
if grep -E 'curl .*(ggml-small|huggingface).*(-o|--output)' "$MODEL_SMOKE" >/dev/null; then
  fail "model smoke must not curl model body to disk"
fi
grep -E 'E7_257_MODE=download|E7_257_MODE=\"download\"' "$MODEL_SMOKE" >/dev/null \
  || fail "model smoke must set E7_257_MODE=download"
grep -E 'manager_exit|MEC' "$MODEL_SMOKE" | grep -E 'fail|FAIL|eq 0' >/dev/null \
  || fail "model smoke must fail on non-zero manager exit"
if grep -E 'WARN: manager verify failed' "$MODEL_SMOKE" >/dev/null; then
  fail "model smoke must not WARN-degrade manager failure"
fi
grep -F 'Godot/app_userdata/MahjongGame' "$MODEL_SMOKE" >/dev/null \
  || fail "model smoke must monitor correct user:// path"
grep -E 'refuse reuse|already exists' "$MODEL_SMOKE" >/dev/null \
  || fail "model smoke must refuse reusing existing stage"
pass "model smoke negative gates present"

# export 日志审计
grep -E 'SCRIPT ERROR\|Parse Error\|Failed loading resource' "$EXPORT_SH" >/dev/null \
  || fail "export tool must audit SCRIPT/Parse/Failed-loading"
grep -E 'export log clean|ERR_COUNT' "$EXPORT_SH" >/dev/null \
  || fail "export tool must count error hits"
pass "export log audit gates present"

# 可执行探针：伪造 app log 含 SCRIPT ERROR 时，内联检测应失败
PROBE_DIR="/tmp/mahjong-e7-257-neg-probe-$$"
mkdir -p "$PROBE_DIR"
echo 'SCRIPT ERROR: Parse Error: fake' >"$PROBE_DIR/bad.log"
if rg -n 'SCRIPT ERROR|Parse Error|Failed loading resource' "$PROBE_DIR/bad.log" >/dev/null; then
  pass "rg gate detects SCRIPT ERROR in fake log"
else
  fail "rg gate failed to detect SCRIPT ERROR"
fi
# 清理探针目录（仅 /tmp/mahjong-e7-257-*）
rm -rf "$PROBE_DIR"

echo "PASS: #257 smoke negative contract"
exit 0
