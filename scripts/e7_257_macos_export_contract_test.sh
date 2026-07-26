#!/usr/bin/env bash
# #257 E7-03：macOS Alpha 导出预设与打包入口契约（不执行重型导出/下载）。
# 网络端到端未验证。禁止使用 Developer ID / 公证凭证。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PRESET="$ROOT/godot/export_presets.cfg"
PACK_SH="$ROOT/scripts/e7_257_macos_package.sh"
SMOKE_SH="$ROOT/scripts/e7_257_macos_package_smoke.sh"
MODEL_SMOKE="$ROOT/scripts/e7_257_whisper_model_download_smoke.sh"
TOOL_EXPORT="$ROOT/godot/tools/e7_257_export_macos.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "OK: $*"; }

echo "== #257 macOS export contract =="

NEG_SH="$ROOT/scripts/e7_257_smoke_negative_contract_test.sh"
[[ -f "$PRESET" ]] || fail "missing godot/export_presets.cfg"
[[ -f "$PACK_SH" ]] || fail "missing scripts/e7_257_macos_package.sh"
[[ -f "$SMOKE_SH" ]] || fail "missing scripts/e7_257_macos_package_smoke.sh"
[[ -f "$MODEL_SMOKE" ]] || fail "missing scripts/e7_257_whisper_model_download_smoke.sh"
[[ -f "$TOOL_EXPORT" ]] || fail "missing godot/tools/e7_257_export_macos.sh"
[[ -f "$NEG_SH" ]] || fail "missing scripts/e7_257_smoke_negative_contract_test.sh"
pass "required files present"

# 负向门禁契约
bash "$NEG_SH" || fail "negative contract failed"

# 必须存在 macOS 预设
grep -E 'platform="macOS"' "$PRESET" >/dev/null || fail "no macOS platform preset"
grep -E 'name="macOS Alpha"' "$PRESET" >/dev/null || fail "preset name must be macOS Alpha"

# 稳定 bundle id
grep -E 'application/bundle_identifier="com\.lovteam\.MahjongGame"' "$PRESET" >/dev/null \
  || fail "bundle id must be com.lovteam.MahjongGame"

# 麦克风用途说明（中文清晰）
grep -E 'privacy/microphone_usage_description=' "$PRESET" >/dev/null \
  || fail "missing privacy/microphone_usage_description"
grep -E '麦克风|按住说话|欢乐' "$PRESET" >/dev/null \
  || fail "microphone usage description must explain PTT / 欢乐场 purpose"

# Audio Input entitlement
grep -E 'codesign/entitlements/audio_input=true' "$PRESET" >/dev/null \
  || fail "codesign/entitlements/audio_input must be true"

# ad-hoc only：codesign=1（Built-in ad-hoc）；禁止 identity 填 Developer ID
grep -E 'codesign/codesign=1' "$PRESET" >/dev/null \
  || fail "codesign/codesign must be 1 (Built-in ad-hoc only)"
# identity 必须为空或 "-"
if grep -E 'codesign/identity="[^"]+"' "$PRESET" >/dev/null; then
  ident="$(grep -E 'codesign/identity=' "$PRESET" | head -1)"
  echo "$ident" | grep -E 'codesign/identity=""|codesign/identity="-"' >/dev/null \
    || fail "codesign/identity must be empty for ad-hoc (got $ident)"
fi

# 禁止公证
grep -E 'notarization/notarization=0' "$PRESET" >/dev/null \
  || fail "notarization must be disabled (0)"

# 证书相关 secret 字段须为空（不得写入本机凭证路径）
for key in codesign/certificate_file codesign/certificate_password notarization/apple_id_name \
  notarization/apple_id_password notarization/api_uuid notarization/api_key notarization/api_key_id; do
  if grep -F "${key}=" "$PRESET" >/dev/null 2>&1; then
    line="$(grep -F "${key}=" "$PRESET" | head -1)"
    # 允许空字符串
    echo "$line" | grep -E "${key}=\"\"|${key}=$" >/dev/null \
      || fail "secret field must be empty: $line"
  fi
done
pass "ad-hoc + audio_input + mic usage + no notarization secrets"

# 打包脚本必须把产物限制在 /tmp/mahjong-e7-257-*
for f in "$PACK_SH" "$SMOKE_SH" "$MODEL_SMOKE" "$TOOL_EXPORT"; do
  grep -E 'mahjong-e7-257' "$f" >/dev/null || fail "$f must use /tmp/mahjong-e7-257-* paths"
  # 不得清理真实用户 Application Support
  if grep -E 'Application Support/MahjongGame' "$f" >/dev/null 2>&1; then
    # 仅允许作为“禁止路径”检查出现，不得 rm -rf 该路径
    if grep -E 'rm[[:space:]]+(-[a-zA-Z]*f[a-zA-Z]*|[[:space:]]).*Application Support/MahjongGame' "$f" >/dev/null; then
      fail "$f must not rm real Application Support/MahjongGame"
    fi
  fi
  # 不得引用 Developer ID 作为默认签名
  if grep -Ei 'Developer ID Application' "$f" >/dev/null 2>&1; then
    # 允许在注释/检测中拒绝 Developer ID
    grep -Ei '禁止|forbid|reject|must not|不得|ad-hoc|adhoc' "$f" >/dev/null \
      || fail "$f mentions Developer ID without reject language"
  fi
done
pass "staging path isolation markers present"

# 文档：Gatekeeper / 未公证 / 网络未 e2e
DOC_OK=0
for d in "$ROOT/CLAUDE.md" "$ROOT/Claude.md" "$ROOT/docs/superpowers"; do
  if [[ -e "$d" ]]; then
    if rg -n 'Gatekeeper|未公证|ad-hoc|#257|e7_257' "$d" >/dev/null 2>&1; then
      DOC_OK=1
      break
    fi
  fi
done
[[ "$DOC_OK" -eq 1 ]] || fail "docs must mention #257 / Gatekeeper / ad-hoc"
pass "docs mention #257 packaging constraints"

echo "PASS: #257 macOS export contract"
exit 0
