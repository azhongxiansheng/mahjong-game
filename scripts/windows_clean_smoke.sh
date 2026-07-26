#!/usr/bin/env bash
# #258 E7-04：非 Windows 开发辅助 / NOT_RUN 入口。
# Windows 真机规范入口是 scripts/windows_clean_smoke.ps1（PowerShell），本脚本不得冒充真机验收通过。
# 网络端到端未验证。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PS1="$ROOT/scripts/windows_clean_smoke.ps1"
DOC="$ROOT/docs/superpowers/specs/2026-07-26-windows-alpha-packaging.md"
ZIP_DEFAULT="$ROOT/dist/windows-alpha/MahjongGame-windows-x86_64-alpha.zip"
ZIP_PATH="${WINDOWS_ALPHA_ZIP:-$ZIP_DEFAULT}"

echo "== #258 Windows clean smoke (bash helper / NOT_RUN on non-Windows) =="
echo "canonical_windows_entry=$PS1"
echo "checklist_doc=$DOC"
echo "zip_path=$ZIP_PATH"
echo "网络端到端未验证"

[[ -f "$PS1" ]] || { echo "FAIL: missing PowerShell smoke entry $PS1" >&2; exit 1; }
[[ -f "$DOC" ]] || { echo "FAIL: missing packaging doc $DOC" >&2; exit 1; }

cat << 'EOF'
--- Windows 10/11 x64 clean smoke（真机 + PowerShell 规范入口）---
真机命令:
  powershell -ExecutionPolicy Bypass -File scripts\windows_clean_smoke.ps1
  powershell -ExecutionPolicy Bypass -File scripts\windows_clean_smoke.ps1 `
    -EvidenceFile path\to\evidence.json

启动观察规则:
  - 观察窗口内非零退出 → FAIL (exit 1)，不得当成功
  - 观察窗口内 exit 0 或存活至超时（再精确杀 PID）→ 启动观察通过
  - 未提供合格结构化证据 → exit 3 PENDING

结构化 evidence.json 必须：
  - zip_sha256 与当前 ZIP 一致
  - windows_version 与本机 smoke 采集值规范化后严格相等
  - timestamp_utc 可解析且带时区（Z/±HH:MM）
  - operator 非空
  - clean_profile / first_public_connect_notice / first_ptt_notice /
    firewall_behavior / real_microphone / model_resume_and_sha256 /
    public_match_complete（完整牌局至结算，非一手 full hand）
    每项 ok=true 且非空 note（须含房间/场次 + 东风或半庄 + 结算）
  - 拒绝 public_match_full_hand 与 MIC_OK 四裸 token
  - report 含 evidence_file_sha256

清单:
[ ] 干净用户目录
[ ] 解压：恰一个顶层 MahjongGame-windows-x86_64-alpha/（exe+pck+README）
[ ] SmartScreen / 来源未知（未签名预期）
[ ] 首次公共连接应用内说明（仅 Windows）
[ ] STANDARD 零麦克风/零模型
[ ] 首次 PTT 说明 + 隐私麦克风
[ ] 模型 user://models/whisper + 断点/SHA-256
[ ] 真实麦克风
[ ] 公网整场
[ ] 标注：网络端到端未验证
EOF

is_windows=0
case "$(uname -s 2>/dev/null || echo unknown)" in
  MINGW*|MSYS*|CYGWIN*|Windows_NT) is_windows=1 ;;
esac
if [[ "${OS:-}" == "Windows_NT" ]]; then
  is_windows=1
fi

if [[ "$is_windows" -ne 1 ]]; then
  echo "NOT_RUN: 非 Windows 宿主（$(uname -s 2>/dev/null || echo unknown)）"
  echo "NOT_RUN: 请在真实 Windows 10/11 x64 使用 PowerShell 入口 windows_clean_smoke.ps1"
  echo "zip_present=$([[ -f "$ZIP_PATH" ]] && echo yes || echo no)"
  if [[ -f "$ZIP_PATH" ]] && command -v shasum >/dev/null 2>&1; then
    echo "zip_sha256_hint=$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"
  fi
  exit 2
fi

if command -v powershell.exe >/dev/null 2>&1; then
  exec powershell.exe -ExecutionPolicy Bypass -File "$PS1" -ZipPath "$ZIP_PATH"
elif command -v pwsh >/dev/null 2>&1; then
  exec pwsh -ExecutionPolicy Bypass -File "$PS1" -ZipPath "$ZIP_PATH"
else
  echo "FAIL: Windows host but no powershell.exe/pwsh — cannot run canonical smoke" >&2
  exit 1
fi
