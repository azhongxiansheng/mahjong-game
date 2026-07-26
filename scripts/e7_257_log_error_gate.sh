#!/usr/bin/env bash
# #257：审计日志中 manager/playable_table 生命周期阻断模式为 0。
set -euo pipefail
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "OK: $*"; }
[[ $# -ge 1 ]] || fail "usage: $0 <log> [log...]"
PATTERN='Object is locked|Attempted to free a locked object|new orphans|Thread object is being destroyed without|wait_to_finish|SCRIPT ERROR'
TOTAL=0
for log in "$@"; do
  [[ -f "$log" ]] || fail "missing log: $log"
  hits="$(rg -n "$PATTERN" "$log" 2>/dev/null || true)"
  if [[ -n "$hits" ]]; then
    echo "$hits" | head -50 >&2
    fail "blocked lifecycle patterns in $log"
  fi
  TOTAL=$((TOTAL + 1))
done
pass "lifecycle error gate clean for $TOTAL log(s)"
exit 0
