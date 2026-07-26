#!/usr/bin/env bash
# #258 E7-04：Windows Alpha 包 / 导出预设 / 首次说明 / 模型不入包 / PowerShell smoke 契约。
# 静态检查 + 可选包内容校验；不冒充真实 Windows smoke / 麦克风 / 公网整场。
# 网络端到端未验证。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PRESET="$ROOT/godot/export_presets.cfg"
PKG_SCRIPT="$ROOT/scripts/package_windows_alpha.sh"
SMOKE_SH="$ROOT/scripts/windows_clean_smoke.sh"
SMOKE_PS1="$ROOT/scripts/windows_clean_smoke.ps1"
DOC="$ROOT/docs/superpowers/specs/2026-07-26-windows-alpha-packaging.md"
MODEL_SIZE="487601967"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "OK: $*"; }

echo "== #258 Windows Alpha contract =="
echo "root=$ROOT"
echo "network_e2e=未验证"
echo "windows_clean_smoke=本机不执行真机验收"

# --- required files ---
[[ -f "$PRESET" ]] || fail "missing $PRESET"
[[ -f "$PKG_SCRIPT" ]] || fail "missing $PKG_SCRIPT"
[[ -x "$PKG_SCRIPT" ]] || fail "package script not executable: $PKG_SCRIPT"
[[ -f "$SMOKE_SH" ]] || fail "missing $SMOKE_SH"
[[ -x "$SMOKE_SH" ]] || fail "smoke sh not executable: $SMOKE_SH"
[[ -f "$SMOKE_PS1" ]] || fail "missing PowerShell smoke $SMOKE_PS1"
[[ -f "$DOC" ]] || fail "missing packaging doc $DOC"
pass "required files present"

# --- export_presets：exclude denylist + Windows x86_64 unsigned ---
grep -q 'name="Windows Desktop"' "$PRESET" || fail "preset name must be Windows Desktop"
grep -q 'platform="Windows Desktop"' "$PRESET" || fail "platform must be Windows Desktop"
grep -q 'binary_format/architecture="x86_64"' "$PRESET" || fail "architecture must be x86_64"
grep -q 'codesign/enable=false' "$PRESET" || fail "Alpha must be unsigned (codesign/enable=false)"
grep -q 'binary_format/embed_pck=false' "$PRESET" || fail "prefer external .pck"
grep -q 'export_filter="exclude"' "$PRESET" || fail "must use export_filter=exclude (all minus denylist)"
if ! grep -E 'exclude_filter=.*tests' "$PRESET" >/dev/null; then
  fail "export exclude_filter must exclude tests"
fi
if ! grep -E 'exclude_filter=.*addons/gut' "$PRESET" >/dev/null; then
  fail "export exclude_filter must exclude addons/gut"
fi
for legacy in 'res://scripts/game_ui.gd' 'res://scripts/card_tile.gd' 'res://scripts/hand_display.gd' 'res://scripts/main_simple.gd' 'res://main.tscn'; do
  grep -q "$legacy" "$PRESET" || fail "export_files denylist must include $legacy"
done
pass "export_presets.cfg exclude-denylist Windows x86_64 unsigned"

if grep -F "$MODEL_SIZE" "$PRESET" >/dev/null 2>&1; then
  fail "export_presets must not reference model size $MODEL_SIZE"
fi
if grep -Ei 'ggml-small|models/whisper' "$PRESET" >/dev/null 2>&1; then
  fail "export_presets must not reference whisper model paths/URLs"
fi
pass "export_presets does not embed whisper model refs"

# --- package script：export + log error gate + pck scan ---
grep -q -- '--export-release' "$PKG_SCRIPT" || fail "package script must call godot --export-release"
grep -q 'Windows Desktop' "$PKG_SCRIPT" || fail "package script must target Windows Desktop preset"
grep -q '\.exe' "$PKG_SCRIPT" || fail "package script must expect .exe"
grep -q '\.pck' "$PKG_SCRIPT" || fail "package script must expect .pck"
grep -q '\.zip' "$PKG_SCRIPT" || fail "package script must produce .zip"
grep -q 'scan_godot_log_errors\|SCRIPT ERROR' "$PKG_SCRIPT" || fail "package must fail on SCRIPT/Parse errors in export log"
grep -q 'scan_export_stored_files\|Storing File' "$PKG_SCRIPT" || fail "package must scan export Storing File list"
grep -q 'scan_pck_no_model_blob\|ggml-small' "$PKG_SCRIPT" || fail "package must scan pck for model blobs"
for needle in '\.godot' 'addons/gut' 'tests/' "$MODEL_SIZE" 'ggml-small'; do
  grep -E "$needle" "$PKG_SCRIPT" >/dev/null || fail "package script must guard against packing: $needle"
done
grep -q 'user://models/whisper' "$PKG_SCRIPT" || fail "package script must document model path user://models/whisper"
grep -q '网络端到端未验证' "$PKG_SCRIPT" || fail "package script must declare 网络端到端未验证"
grep -q 'SmartScreen' "$PKG_SCRIPT" || fail "package script must mention SmartScreen risk"
grep -q 'game_ui.gd\|main_simple.gd' "$PKG_SCRIPT" || fail "package must reject legacy broken entries in pck scan"
pass "package script export + log gate + pck scan + exclusions"

# --- PowerShell 真机入口契约（macOS 静态；不伪造 Windows 运行）---
grep -qi 'Windows' "$SMOKE_PS1" || fail "ps1 must mention Windows"
grep -q 'Expand-Archive' "$SMOKE_PS1" || fail "ps1 must Expand-Archive ZIP"
grep -q 'MahjongGame.exe' "$SMOKE_PS1" || fail "ps1 must check MahjongGame.exe"
grep -q 'MahjongGame.pck' "$SMOKE_PS1" || fail "ps1 must check MahjongGame.pck"
grep -q 'Start-Process' "$SMOKE_PS1" || fail "ps1 must launch exported EXE"
# 早退非零必须 FAIL（不得把任意退出当成功）
grep -q 'early-exit non-zero\|early_exit_nonzero' "$SMOKE_PS1" \
  || fail "ps1 must FAIL on early non-zero EXE exit"
if ! grep -E 'ExitCode.*-ne 0|launchExitCode -ne 0' "$SMOKE_PS1" >/dev/null; then
  fail "ps1 must branch on non-zero ExitCode"
fi
# 存活观察后精确终止 PID
grep -q 'Stop-Process\|Kill' "$SMOKE_PS1" || fail "ps1 must stop survived process by PID"
# ZIP SHA-256
grep -q 'Get-FileHash' "$SMOKE_PS1" || fail "ps1 must Get-FileHash SHA256 of ZIP"
grep -q 'SHA256' "$SMOKE_PS1" || fail "ps1 must use SHA256"
# 严格顶层布局：恰一个预期目录
grep -q 'MahjongGame-windows-x86_64-alpha' "$SMOKE_PS1" || fail "ps1 must require expected top-level dir name"
grep -q 'exactly 1 top-level\|Count -ne 1' "$SMOKE_PS1" || fail "ps1 must enforce exactly one top-level entry"
# 结构化 JSON 证据；拒绝旧四 token
grep -q 'ConvertFrom-Json' "$SMOKE_PS1" || fail "ps1 must parse structured JSON evidence"
grep -q 'zip_sha256' "$SMOKE_PS1" || fail "ps1 evidence must bind zip_sha256"
grep -q 'first_public_connect_notice' "$SMOKE_PS1" || fail "ps1 evidence must require first_public_connect_notice"
grep -q 'first_ptt_notice' "$SMOKE_PS1" || fail "ps1 evidence must require first_ptt_notice"
grep -q 'real_microphone' "$SMOKE_PS1" || fail "ps1 evidence must require real_microphone"
grep -q 'model_resume_and_sha256' "$SMOKE_PS1" || fail "ps1 evidence must require model_resume_and_sha256"
# 完整牌局语义（非一手 hand）
grep -q 'public_match_complete' "$SMOKE_PS1" || fail "ps1 evidence must require public_match_complete"
grep -q 'public_match_full_hand is rejected\|legacy field public_match_full_hand' "$SMOKE_PS1" \
  || fail "ps1 must reject legacy public_match_full_hand field"
# 不得再把 full_hand 当作 requiredItems
if grep -n 'requiredItems' -A30 "$SMOKE_PS1" | grep -q 'public_match_full_hand'; then
  fail "requiredItems must not include public_match_full_hand"
fi
# 三个独立检查必须都存在，禁止合并成单一 OR 正则
# 1) room/session
grep -q 'missing room/session identifier' "$SMOKE_PS1" \
  || fail "ps1 must independently check room/session in public_match_complete.note"
# 2) round kind 独立
grep -q 'missing round kind' "$SMOKE_PS1" \
  || fail "ps1 must independently check round kind (东风/EAST or 半庄/HANCHAN)"
# 3) completion/settlement 独立
grep -q 'missing complete-match completion/settlement' "$SMOKE_PS1" \
  || fail "ps1 must independently check complete-match settlement semantics"
# 禁止把场种与 settlement 用单一 OR 合并（旧漏洞形态）
if grep -n 'public_match_complete' -A25 "$SMOKE_PS1" | grep -E "东风\|半庄\|EAST\|HANCHAN\|settlement\|结算\|整场" >/dev/null; then
  fail "ps1 must not OR-merge round-kind with settlement in one regex"
fi
# PENDING 文案不得残留 public full hand
if grep -qi 'public full hand' "$SMOKE_PS1"; then
  fail "ps1 PENDING text must not say public full hand; use public complete match"
fi
grep -qi 'public complete match\|公网完整牌局' "$SMOKE_PS1" \
  || fail "ps1 PENDING text must mention public complete match / 公网完整牌局"
grep -q 'firewall_behavior' "$SMOKE_PS1" || fail "ps1 evidence must require firewall_behavior"
grep -q 'clean_profile' "$SMOKE_PS1" || fail "ps1 evidence must require clean_profile"
grep -q 'bare tokens\|MIC_OK' "$SMOKE_PS1" || fail "ps1 must explicitly reject legacy bare MIC_OK tokens"
# windows_version 严格比较（normalize 后相等，不能只判非空）
grep -q 'Normalize-WindowsVersion' "$SMOKE_PS1" || fail "ps1 must normalize windows_version for compare"
grep -q 'windows_version mismatch' "$SMOKE_PS1" || fail "ps1 must fail on windows_version mismatch"
# timestamp_utc 可解析 + 时区
grep -q 'TryParse\|DateTimeOffset' "$SMOKE_PS1" || fail "ps1 must parse timestamp_utc as DateTimeOffset"
grep -q 'timezone designator\|Z or' "$SMOKE_PS1" || fail "ps1 must require UTC/timezone on timestamp_utc"
# evidence 文件 SHA 写入 report
grep -q 'evidence_file_sha256' "$SMOKE_PS1" || fail "ps1 report must record evidence_file_sha256"
grep -q 'Get-FileHash -LiteralPath $EvidenceFile -Algorithm SHA256' "$SMOKE_PS1" \
  || fail "ps1 must Get-FileHash of EvidenceFile"
# 证据不足 exit 3；早退非零 exit 1
grep -E 'exit 3' "$SMOKE_PS1" >/dev/null || fail "ps1 must exit 3 when evidence PENDING"
grep -E 'exit 1' "$SMOKE_PS1" >/dev/null || fail "ps1 must exit 1 on launch/layout FAIL"
# 结构化 report
grep -q 'ConvertTo-Json' "$SMOKE_PS1" || fail "ps1 must write structured smoke report JSON"
# bash helper
grep -q 'windows_clean_smoke.ps1' "$SMOKE_SH" || fail "bash helper must point to PowerShell canonical entry"
grep -q 'NOT_RUN' "$SMOKE_SH" || fail "bash helper must support NOT_RUN"
# 文档不得再把四裸 token 当放行条件
if grep -q 'MIC_OK MODEL_OK PUBLIC_MATCH_OK CLEAN_PROFILE_OK' "$SMOKE_SH"; then
  fail "bash helper must not document legacy bare-token evidence"
fi
if [[ "$(uname -s)" != "Windows_NT" && "$(uname -s)" != MINGW* && "$(uname -s)" != CYGWIN* ]]; then
  set +e
  out="$("$SMOKE_SH" 2>&1)"
  rc=$?
  set -e
  if [[ $rc -eq 0 ]] && echo "$out" | grep -Eqi 'PASS|全部通过|clean smoke passed'; then
    fail "bash smoke on non-Windows must not claim full PASS (rc=$rc)"
  fi
  if ! echo "$out" | grep -Eq '未执行|NOT_RUN|非 Windows|no real Windows|PowerShell'; then
    fail "bash smoke on non-Windows must report NOT_RUN / PowerShell entry"
  fi
  # 静态局限说明：本机无法实际启动 Windows EXE 验证早退分支；契约靠源码门禁
  echo "NOTE: macOS static contract cannot execute Windows EXE early-exit path; enforced via source gates"
  pass "bash smoke on non-Windows host reports NOT_RUN (rc=$rc)"
else
  pass "host appears Windows; skip NOT_RUN host assertion"
fi
pass "PowerShell smoke: early-nonzero FAIL + structured evidence + strict layout contract"

# --- 文档 ---
for needle in 'SmartScreen' '防火墙' '麦克风' 'SHA-256' 'user://models/whisper' '网络端到端未验证' '未签名' 'windows_clean_smoke.ps1' 'denylist' 'Storing File' 'zip_sha256' 'structured' 'early' 'public_match_complete' 'windows_version'; do
  grep -qi "$needle" "$DOC" || fail "doc missing: $needle"
done
# 文档不得再示例四裸 token 放行，也不得再要求 full_hand 一手语义
if grep -q 'MIC_OK MODEL_OK PUBLIC_MATCH_OK CLEAN_PROFILE_OK' "$DOC"; then
  fail "doc must not advertise legacy bare-token evidence"
fi
# 文档可提及“拒绝旧字段 public_match_full_hand”，但不得作为 JSON 示例键或必填列表项
if grep -q '"public_match_full_hand"' "$DOC"; then
  fail "doc JSON example must not use public_match_full_hand key"
fi
if grep -E '^\s*-\s+`public_match_full_hand`' "$DOC" >/dev/null; then
  fail "doc must not list public_match_full_hand as required evidence item"
fi
# 禁止把验收写成“单手完成”正向示例（允许讨论拒绝一手语义）
if grep -qiE 'note".*full hand completed|"note": ".*full hand' "$DOC"; then
  fail "doc must not use full-hand-only note as acceptance example"
fi
grep -q 'public_match_complete' "$DOC" || fail "doc must document public_match_complete"
grep -q '规范化\|normalize' "$DOC" || fail "doc must document windows_version normalize compare"
pass "packaging doc covers Alpha risks, PowerShell structured evidence, denylist export"
echo "NOTE: macOS static contract does not replace real Windows execution of smoke.ps1"

# --- 生产代码：Windows 专属首次说明 ---
SM="$ROOT/godot/meta/settings_manager.gd"
NOTICE="$ROOT/godot/platform/platform_first_use_notices.gd"
SHELL_GD="$ROOT/godot/ui/lobby/lobby_shell.gd"
TABLE_GD="$ROOT/godot/ui/four_player_table/playable_table.gd"
[[ -f "$NOTICE" ]] || fail "missing $NOTICE"
if grep -q '^class_name PlatformFirstUseNotices' "$NOTICE"; then
  fail "PlatformFirstUseNotices must not use global class_name (use preload)"
fi
grep -q 'windows_first_public_connect_notice_acked' "$SM" || fail "SettingsManager missing windows_first_public_connect_notice_acked"
grep -q 'windows_first_ptt_notice_acked' "$SM" || fail "SettingsManager missing windows_first_ptt_notice_acked"
# 通用旧键不得再作为主字段
if grep -E $'^\tvar first_public_connect_notice_acked' "$SM" >/dev/null; then
  fail "legacy non-windows first_public_connect_notice_acked field must be removed"
fi
if grep -E $'^\tvar first_ptt_notice_acked' "$SM" >/dev/null; then
  fail "legacy non-windows first_ptt_notice_acked field must be removed"
fi
if grep -q 'func save_now' "$SM"; then
  fail "save_now test-only API must be removed"
fi
grep -q 'is_windows_runtime\|has_feature\("windows"\)' "$NOTICE" || fail "notices must gate on Windows runtime"
grep -q 'preload("res://platform/platform_first_use_notices.gd")' "$SHELL_GD" \
  || fail "lobby_shell must preload first-use notices"
grep -q 'preload("res://platform/platform_first_use_notices.gd")' "$TABLE_GD" \
  || fail "playable_table must preload first-use notices"
grep -q 'DEFAULT_MODELS_ROOT := "user://models/whisper"' \
  "$ROOT/godot/stt/whisper_model_manager.gd" || fail "whisper root must remain user://models/whisper"
pass "production Windows-gated first-use + whisper root wiring present"

# --- 可选 ZIP / PCK ---
ZIP_CANDIDATES=(
  "$ROOT/dist/windows-alpha/MahjongGame-windows-x86_64-alpha.zip"
  "$ROOT/dist/MahjongGame-windows-x86_64-alpha.zip"
)
ZIP=""
for z in "${ZIP_CANDIDATES[@]}"; do
  if [[ -f "$z" ]]; then ZIP="$z"; break; fi
done
if [[ -n "$ZIP" ]]; then
  echo "checking existing zip: $ZIP"
  if command -v unzip >/dev/null 2>&1; then
    listing="$(unzip -l "$ZIP" 2>/dev/null || true)"
    echo "$listing" | grep -Ei '\.exe$' >/dev/null || fail "zip missing .exe"
    echo "$listing" | grep -Ei '\.pck$' >/dev/null || fail "zip missing .pck"
    echo "$listing" | grep -E '\.godot|/tests/|addons/gut|ggml-small' >/dev/null && \
      fail "zip contains forbidden path (.godot/tests/gut/model)"
    while read -r sz path; do
      [[ -z "${sz:-}" ]] && continue
      if [[ "$sz" =~ ^[0-9]+$ ]] && (( sz >= 400000000 )); then
        fail "zip has oversized entry (${sz} bytes): $path — possible model leak"
      fi
    done < <(unzip -l "$ZIP" | awk '/^[ ]*[0-9]+/ {print $1, $4}')
    pass "zip content layout ok (exe+pck, no model/tests)"
  else
    fail "unzip required to validate package contents"
  fi
  # 权威清单：export Storing File 列表（不是 class_cache 的 strings 误报）
  STORED="$ROOT/dist/windows-alpha/last-export-stored-files.txt"
  EXP_LOG="$ROOT/dist/windows-alpha/last-export.log"
  if [[ -f "$STORED" ]]; then
    rg -q 'lobby_shell' "$STORED" || fail "stored-files list missing lobby_shell"
    if rg -q 'res://tests/|res://addons/gut/|res://tools/asset_gen/' "$STORED"; then
      fail "stored-files list includes tests/gut/asset_gen"
    fi
    for legacy in game_ui.gd card_tile.gd hand_display.gd main_simple.gd; do
      rg -q "$legacy" "$STORED" && fail "stored-files list includes legacy $legacy"
    done
    pass "last-export-stored-files.txt ok"
  elif [[ -f "$EXP_LOG" ]]; then
    rg -q 'Storing File:.*lobby_shell' "$EXP_LOG" || fail "export log missing lobby_shell store"
    if rg -q 'Storing File: res://(tests/|addons/gut/|tools/asset_gen/)' "$EXP_LOG"; then
      fail "export log stores tests/gut/asset_gen"
    fi
    pass "last-export.log stored-file scan ok"
  else
    echo "NOTE: no last-export stored list yet (run package_windows_alpha.sh)"
  fi
else
  echo "NOTE: no built zip yet; package generation is validated by package script when templates available"
fi

echo "== #258 contract PASS =="
echo "reminder: 网络端到端未验证；真实 Windows clean smoke / 麦克风 / 公网整场仍待真机"
exit 0
