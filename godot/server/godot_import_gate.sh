#!/bin/sh
# #255 Godot import 门禁：首轮 bootstrap（静默）+ 第二轮 clean import 审计。
# 第二轮非零退出或命中稳定错误模式时硬失败；通过后删除临时日志。
# 不得只依赖 Godot 退出码。网络端到端未验证。
set -eu

PROJECT="${1:-/app/godot}"
if [ ! -d "$PROJECT" ]; then
  echo "godot_import_gate: project dir missing: $PROJECT" >&2
  exit 2
fi

BOOT_LOG="$(mktemp /tmp/godot-import-bootstrap.XXXXXX)"
CLEAN_LOG="$(mktemp /tmp/godot-import-clean.XXXXXX)"
cleanup() {
  rm -f "$BOOT_LOG" "$CLEAN_LOG"
}
trap cleanup EXIT

echo "godot_import_gate: bootstrap import (stdout/stderr discarded)"
set +e
godot --headless --path "$PROJECT" --import >"$BOOT_LOG" 2>&1
boot_ec=$?
set -e
# 首轮允许已知 bootstrap 噪声；仅记录退出码供诊断，不作为放行依据。
echo "godot_import_gate: bootstrap exit=${boot_ec}"

echo "godot_import_gate: clean import (audited)"
set +e
godot --headless --path "$PROJECT" --import >"$CLEAN_LOG" 2>&1
clean_ec=$?
set -e

fail_clean() {
  reason="$1"
  echo "godot_import_gate: FAIL ${reason}" >&2
  echo "godot_import_gate: clean_exit=${clean_ec}" >&2
  # 有界诊断：错误命中行 + 日志尾部
  echo "godot_import_gate: --- clean log matches (bounded) ---" >&2
  # shellcheck disable=SC2002
  cat "$CLEAN_LOG" 2>/dev/null | grep -n -E 'SCRIPT ERROR|Parse Error|Compile Error|Failed loading resource|Failed to load script|Unrecognized UID' | head -n 40 >&2 || true
  echo "godot_import_gate: --- clean log tail ---" >&2
  tail -n 80 "$CLEAN_LOG" >&2 || true
  exit 1
}

if [ "$clean_ec" -ne 0 ]; then
  fail_clean "clean import non-zero exit"
fi

# 第二轮显式错误模式门禁（任一命中即失败）
for pat in \
  "SCRIPT ERROR" \
  "Parse Error" \
  "Compile Error" \
  "Failed loading resource" \
  "Failed to load script" \
  "Unrecognized UID"
do
  if grep -F -- "$pat" "$CLEAN_LOG" >/dev/null 2>&1; then
    fail_clean "pattern hit: ${pat}"
  fi
done

echo "godot_import_gate: clean import ok (no forbidden patterns)"
# trap 删除临时日志；构建输出不暴露首轮 bootstrap 正文
exit 0
