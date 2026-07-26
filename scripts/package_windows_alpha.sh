#!/usr/bin/env bash
# #258 E7-04：可重复生成 Windows x86_64 Alpha ZIP（未签名）。
# 使用 Godot 4.6.1 官方 --export-release "Windows Desktop"。
# 包内仅运行时 exe/pck/必要原生依赖；禁止 .godot、tests、addons/gut、源码工具、ggml-small / 487601967 模型。
# 模型路径：user://models/whisper/<version>（按需下载 + SHA-256，不入包）。
# SmartScreen / 来源未知：未签名 Alpha 的预期风险。
# 网络端到端未验证。真实 Windows clean smoke / 麦克风 / 公网整场不在本脚本内冒充通过。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-godot}"
GODOT_PROJECT="$ROOT/godot"
PRESET_NAME="Windows Desktop"
OUT_DIR="${WINDOWS_ALPHA_OUT_DIR:-$ROOT/dist/windows-alpha}"
STAGE_DIR="$OUT_DIR/stage"
EXE_NAME="MahjongGame.exe"
PCK_NAME="MahjongGame.pck"
ZIP_NAME="MahjongGame-windows-x86_64-alpha.zip"
ZIP_PATH="$OUT_DIR/$ZIP_NAME"
MODEL_SIZE="487601967"
TEMPLATE_VERSION="4.6.1.stable"
TEMPLATE_DIR_DEFAULT="$HOME/Library/Application Support/Godot/export_templates/${TEMPLATE_VERSION}"
# Linux fallback
if [[ ! -d "$TEMPLATE_DIR_DEFAULT" && -d "$HOME/.local/share/godot/export_templates/${TEMPLATE_VERSION}" ]]; then
  TEMPLATE_DIR_DEFAULT="$HOME/.local/share/godot/export_templates/${TEMPLATE_VERSION}"
fi
TEMPLATE_DIR="${GODOT_EXPORT_TEMPLATES_DIR:-$TEMPLATE_DIR_DEFAULT}"
TPZ_URL="${GODOT_EXPORT_TEMPLATES_URL:-https://github.com/godotengine/godot/releases/download/4.6.1-stable/Godot_v4.6.1-stable_export_templates.tpz}"
SKIP_EXPORT="${WINDOWS_ALPHA_SKIP_EXPORT:-0}"
INSTALL_TEMPLATES="${WINDOWS_ALPHA_INSTALL_TEMPLATES:-1}"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "OK: $*"; }
note() { echo "NOTE: $*"; }

echo "== #258 package Windows Alpha =="
echo "godot_bin=$GODOT_BIN"
echo "out_dir=$OUT_DIR"
echo "template_dir=$TEMPLATE_DIR"
echo "网络端到端未验证"
echo "SmartScreen: unsigned Alpha may show unknown publisher"

command -v "$GODOT_BIN" >/dev/null 2>&1 || fail "godot not found (set GODOT_BIN)"
"$GODOT_BIN" --version 2>/dev/null | grep -q '4.6.1' \
  || note "expected Godot 4.6.1; got: $($GODOT_BIN --version 2>/dev/null || true)"

[[ -f "$GODOT_PROJECT/export_presets.cfg" ]] || fail "missing export_presets.cfg"
grep -q 'name="Windows Desktop"' "$GODOT_PROJECT/export_presets.cfg" \
  || fail "export_presets missing Windows Desktop"
grep -q 'binary_format/architecture="x86_64"' "$GODOT_PROJECT/export_presets.cfg" \
  || fail "export_presets must be x86_64"
grep -q 'codesign/enable=false' "$GODOT_PROJECT/export_presets.cfg" \
  || fail "Alpha must keep codesign disabled"
# exclude 模式 = 全部减去 denylist（scenes-only 因 preload 登记不全会得到不可运行极小包）
grep -q 'export_filter="exclude"' "$GODOT_PROJECT/export_presets.cfg" \
  || fail "export_filter must be exclude (all minus denylist) for complete runnable pack"
grep -q 'res://scripts/game_ui.gd' "$GODOT_PROJECT/export_presets.cfg" \
  || fail "export_files denylist must include res://scripts/game_ui.gd"
grep -q 'res://main.tscn' "$GODOT_PROJECT/export_presets.cfg" \
  || fail "export_files denylist must include res://main.tscn (pulls game_ui)"
grep -q 'addons/gut' "$GODOT_PROJECT/export_presets.cfg" \
  || fail "exclude_filter must denylist addons/gut"
grep -q 'tests/' "$GODOT_PROJECT/export_presets.cfg" \
  || fail "exclude_filter must denylist tests/"
# 模型不得出现在预设
if grep -F "$MODEL_SIZE" "$GODOT_PROJECT/export_presets.cfg" >/dev/null 2>&1; then
  fail "export_presets must not reference model size $MODEL_SIZE"
fi
if grep -Ei 'ggml-small|models/whisper' "$GODOT_PROJECT/export_presets.cfg" >/dev/null 2>&1; then
  fail "export_presets must not reference whisper model"
fi
pass "export_presets.cfg present (Windows Desktop x86_64, unsigned, exclude-denylist)"

# 导出/import 日志错误模式扫描（退出码 0 不够）
scan_godot_log_errors() {
  local logf="$1"
  local label="$2"
  [[ -f "$logf" ]] || fail "missing $label log: $logf"
  local hits
  hits="$(rg -n 'SCRIPT ERROR|Parse Error|Compile Error|Failed to load script|Failed loading resource' "$logf" || true)"
  if [[ -n "$hits" ]]; then
    echo "$hits" | head -40 >&2
    fail "$label log contains SCRIPT/Parse/Compile/load errors (see $logf)"
  fi
  pass "$label log error patterns = 0"
}

# 以 export 日志 “Storing File:” 为权威导出清单。
# 说明：PCK 内 global_script_class_cache.cfg / uid_cache 可能嵌入全仓 class 路径字符串，
# 不能用裸 strings 误判为“已打包 tests”。
scan_export_stored_files() {
  local logf="$1"
  [[ -f "$logf" ]] || fail "missing export log for stored-file scan: $logf"
  local list_file
  list_file="$(mktemp /tmp/mahjong-issue-258-export-stored.XXXXXX)"
  rg -o 'Storing File: [^[:space:]]+' "$logf" \
    | sed 's/^Storing File: //' | sort -u > "$list_file" || true
  echo "export_stored_list=$list_file"
  local count
  count=$(wc -l < "$list_file" | tr -d ' ')
  (( count > 0 )) || fail "export log has zero Storing File entries"
  rg -q 'lobby_shell' "$list_file" || fail "export stored list missing lobby_shell"
  # 禁止打包的资源路径（Storing File 权威）
  if rg -q 'res://tests/|res://addons/gut/|res://tools/asset_gen/' "$list_file"; then
    rg -n 'res://tests/|res://addons/gut/|res://tools/asset_gen/' "$list_file" | head -30 >&2
    fail "export stored files include tests/gut/asset_gen"
  fi
  for legacy in \
    'res://scripts/game_ui.gd' \
    'res://scripts/card_tile.gd' \
    'res://scripts/hand_display.gd' \
    'res://scripts/main_simple.gd' \
    'res://scripts/game_ui.gdc' \
    'res://scripts/card_tile.gdc' \
    'res://scripts/hand_display.gdc' \
    'res://scripts/main_simple.gdc'
  do
    if rg -F "$legacy" "$list_file" >/dev/null; then
      fail "export stored files include broken legacy: $legacy"
    fi
  done
  # 允许 .godot/exported（场景转换产物）与 global_script_class_cache（引擎元数据）
  pass "export stored-file list ok (count=$count; no tests/gut/tool/legacy)"
}

# 辅助：PCK 体积与模型探测（不把 class_cache 字符串当打包清单）
scan_pck_no_model_blob() {
  local pck="$1"
  [[ -f "$pck" ]] || fail "missing pck: $pck"
  local pck_sz
  pck_sz=$(wc -c < "$pck" | tr -d ' ')
  if (( pck_sz >= 400000000 )); then
    fail "pck size ${pck_sz} >=400MB; possible model leak"
  fi
  # 二进制级探测超大 ggml 标记
  if strings -a "$pck" 2>/dev/null | rg -q 'ggml-small\.bin|487601967'; then
    fail "pck strings reference ggml-small / model size"
  fi
  pass "pck size/model-string scan ok (sz=$pck_sz)"
}

ensure_templates() {
  local win_rel="$TEMPLATE_DIR/windows_release_x86_64.exe"
  if [[ -f "$win_rel" ]]; then
    pass "export template present: $win_rel"
    return 0
  fi
  if [[ "$INSTALL_TEMPLATES" != "1" ]]; then
    fail "missing Windows export template at $win_rel (set WINDOWS_ALPHA_INSTALL_TEMPLATES=1 to download)"
  fi
  note "downloading official Godot 4.6.1 export templates (large)"
  local tmp_tpz
  tmp_tpz="$(mktemp /tmp/godot-export-templates-XXXXXX.tpz)"
  curl -fL --retry 3 -o "$tmp_tpz" "$TPZ_URL" \
    || fail "failed to download export templates from $TPZ_URL"
  mkdir -p "$TEMPLATE_DIR"
  # tpz is zip; templates live under templates/
  local unpack
  unpack="$(mktemp -d /tmp/godot-templates-unpack-XXXXXX)"
  unzip -q "$tmp_tpz" -d "$unpack" || fail "failed to unzip export templates tpz"
  if [[ -d "$unpack/templates" ]]; then
    # copy all template files into versioned dir
    cp -R "$unpack/templates/." "$TEMPLATE_DIR/"
  else
    fail "unexpected tpz layout (no templates/)"
  fi
  # version stamp if missing
  if [[ ! -f "$TEMPLATE_DIR/version.txt" ]]; then
    echo "$TEMPLATE_VERSION" > "$TEMPLATE_DIR/version.txt"
  fi
  rm -rf "$unpack" "$tmp_tpz"
  [[ -f "$win_rel" ]] || fail "after install still missing $win_rel"
  pass "installed export templates to $TEMPLATE_DIR"
}

validate_stage() {
  local stage="$1"
  [[ -d "$stage" ]] || fail "stage dir missing: $stage"
  local exe="$stage/$EXE_NAME"
  local pck="$stage/$PCK_NAME"
  [[ -f "$exe" ]] || fail "missing $exe"
  [[ -f "$pck" ]] || fail "missing $pck"
  # size sanity: pck should exist and not look like 487MB model alone
  local pck_sz
  pck_sz=$(wc -c < "$pck" | tr -d ' ')
  if (( pck_sz >= 400000000 )); then
    fail "pck size ${pck_sz} suspiciously large (>=400MB); possible model leak"
  fi
  # forbid forbidden names in stage tree
  if find "$stage" \( -iname '*.godot' -o -path '*/.godot/*' \) 2>/dev/null | grep -q .; then
    fail "stage contains .godot"
  fi
  if find "$stage" \( -path '*/tests/*' -o -path '*/addons/gut/*' \) 2>/dev/null | grep -q .; then
    fail "stage contains tests/ or addons/gut/"
  fi
  if find "$stage" \( -iname 'ggml-small*' -o -iname '*.gguf' \) 2>/dev/null | grep -q .; then
    fail "stage contains whisper model artifacts"
  fi
  # any file near model size
  while IFS= read -r -d '' f; do
    local sz
    sz=$(wc -c < "$f" | tr -d ' ')
    if (( sz >= 400000000 )); then
      fail "oversized stage file (${sz}): $f — refuse packing model-sized blob"
    fi
  done < <(find "$stage" -type f -print0)
  pass "stage content ok (exe+pck, no .godot/tests/gut/model; user://models/whisper is runtime-only)"
}

if [[ "$SKIP_EXPORT" == "1" ]]; then
  note "WINDOWS_ALPHA_SKIP_EXPORT=1 — skip godot export; validate existing stage if present"
  if [[ -d "$STAGE_DIR" ]]; then
    validate_stage "$STAGE_DIR"
  else
    fail "SKIP_EXPORT set but no stage at $STAGE_DIR"
  fi
else
  ensure_templates
  mkdir -p "$STAGE_DIR"
  rm -rf "${STAGE_DIR:?}/"*
  # import then export (official CLI)
  local_import_log="/tmp/mahjong-issue-258-grok-round2-windows-import.log"
  local_export_log="/tmp/mahjong-issue-258-grok-round2-windows-export.log"
  note "godot --import → $local_import_log"
  "$GODOT_BIN" --headless --path "$GODOT_PROJECT" --import \
    >"$local_import_log" 2>&1 \
    || fail "godot --import failed (see $local_import_log)"
  scan_godot_log_errors "$local_import_log" "import"
  note "godot --export-release '$PRESET_NAME' → $local_export_log"
  # export_path in preset is relative; force path argument
  set +e
  "$GODOT_BIN" --headless --path "$GODOT_PROJECT" \
    --export-release "$PRESET_NAME" "$STAGE_DIR/$EXE_NAME" \
    >"$local_export_log" 2>&1
  export_rc=$?
  set -e
  # 即使 exit 0 也必须扫描错误模式
  scan_godot_log_errors "$local_export_log" "export"
  [[ $export_rc -eq 0 ]] || fail "godot --export-release exit=$export_rc (see $local_export_log)"
  validate_stage "$STAGE_DIR"
  scan_export_stored_files "$local_export_log"
  scan_pck_no_model_blob "$STAGE_DIR/$PCK_NAME"
  # 固化本轮导出清单供契约复用
  cp -f "$local_export_log" "$OUT_DIR/last-export.log"
  rg -o 'Storing File: [^[:space:]]+' "$local_export_log" \
    | sed 's/^Storing File: //' | sort -u > "$OUT_DIR/last-export-stored-files.txt"
fi

# README inside package (clear unzip layout + risks)
cat > "$STAGE_DIR/README-Windows-Alpha.txt" << EOF
MahjongGame Windows x86_64 Alpha (unsigned ZIP)
================================================
解压后运行: ${EXE_NAME}
配套数据: ${PCK_NAME}（须与 exe 同目录）

未签名说明:
- 本 Alpha 不做代码签名，不经 Microsoft Store。
- Windows SmartScreen / 「来源未知」提示属预期风险，请仅从可信渠道获取本包。

网络与麦克风:
- 客户端仅发起出站连接；若 Windows 防火墙询问，仅允许所需网络。
- 系统防火墙/麦克风弹窗不保证出现；应用内首次公共连接与首次 PTT 有说明。
- 网络端到端未验证。

语音模型（欢乐场）:
- 不随本包内置。
- 运行时按需下载至 user://models/whisper/<version>，SHA-256 校验后启用。
- 生产模型体积参考 ${MODEL_SIZE} 字节；STANDARD 模式不请求麦克风/模型。

真机验收:
- Windows 规范入口：scripts/windows_clean_smoke.ps1（PowerShell）
- 启动观察：观察窗口内非零退出 = FAIL；exit 0 或存活至超时 = 启动通过
- 人工证据：结构化 JSON EvidenceFile（绑定 ZIP SHA-256 + 本机 windows_version；
  public_match_complete=完整牌局结算，非一手）；缺省 exit 3 PENDING
- 开发辅助/非 Windows NOT_RUN：scripts/windows_clean_smoke.sh
- 规格：docs/superpowers/specs/2026-07-26-windows-alpha-packaging.md
- 需要真实 Windows 10/11 x64、真实麦克风、干净用户目录、联网与公网测试房。
- 网络端到端未验证。
EOF

# Build ZIP with clear top-level folder
rm -f "$ZIP_PATH"
(
  cd "$OUT_DIR"
  rm -rf "MahjongGame-windows-x86_64-alpha"
  mkdir -p "MahjongGame-windows-x86_64-alpha"
  cp -R "$STAGE_DIR"/. "MahjongGame-windows-x86_64-alpha/"
  # re-check copy
  if find "MahjongGame-windows-x86_64-alpha" \( -path '*/.godot/*' -o -path '*/tests/*' -o -path '*/addons/gut/*' -o -iname 'ggml-small*' \) 2>/dev/null | grep -q .; then
    fail "zip staging contains forbidden .godot/tests/addons/gut/ggml-small"
  fi
  if find "MahjongGame-windows-x86_64-alpha" -type f -size +400M 2>/dev/null | grep -q .; then
    fail "zip staging has file >400M (possible model)"
  fi
  # 使用 zip -X 去掉 macOS 扩展属性/__MACOSX，保持解压形态清晰
  COPYFILE_DISABLE=1 zip -r -X -q "$ZIP_NAME" "MahjongGame-windows-x86_64-alpha"
)
[[ -f "$ZIP_PATH" ]] || fail "zip not created: $ZIP_PATH"

# Final zip listing checks
if command -v unzip >/dev/null 2>&1; then
  listing="$(unzip -l "$ZIP_PATH")"
  echo "$listing" | grep -Ei '\.exe$' >/dev/null || fail "zip missing exe"
  echo "$listing" | grep -Ei '\.pck$' >/dev/null || fail "zip missing pck"
  echo "$listing" | grep -E '\.godot|/tests/|addons/gut|ggml-small' >/dev/null && \
    fail "zip listing contains forbidden path"
  while read -r sz _path; do
    [[ -z "${sz:-}" ]] && continue
    if [[ "$sz" =~ ^[0-9]+$ ]] && (( sz >= 400000000 )); then
      fail "zip oversized entry ${sz}: $_path"
    fi
  done < <(unzip -l "$ZIP_PATH" | awk '/^[ ]*[0-9]+/ {print $1, $4}')
fi

pass "ZIP ready: $ZIP_PATH"
echo "model_path=user://models/whisper (not in package)"
echo "network_e2e=未验证"
echo "windows_clean_smoke=待真实 Windows 设备"
exit 0
