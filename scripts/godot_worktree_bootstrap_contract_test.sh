#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

fail() {
	printf 'FAIL: %s\n' "$1" >&2
	exit 1
}

for required_path in \
	"godot/.godot/.gdignore" \
	"godot/.godot/global_script_class_cache.cfg" \
	"godot/.godot/imported/" \
	"godot/.godot/uid_cache.bin"
do
	grep -Fx -- "$required_path" "$REPO_ROOT/.worktreeinclude" >/dev/null 2>&1 \
		|| fail ".worktreeinclude 缺少 $required_path"
done

test -f "$REPO_ROOT/godot/tests/health/fixtures/architecture_boundaries/.gdignore" \
	|| fail "架构纯文本 fixture 缺少 .gdignore"

test -x "$REPO_ROOT/scripts/godot_bootstrap.sh" \
	|| fail "scripts/godot_bootstrap.sh 不存在或不可执行"

for runner in test_run_core.sh test_run_slow.sh
do
	grep -F -- 'godot_bootstrap.sh' "$REPO_ROOT/scripts/$runner" >/dev/null \
		|| fail "$runner 未接入统一 bootstrap"
	if grep -F -- ' --import' "$REPO_ROOT/scripts/$runner" >/dev/null; then
		fail "$runner 仍直接运行 import"
	fi
done

grep -F -- 'godot_bootstrap.sh' "$REPO_ROOT/AGENTS.md" >/dev/null \
	|| fail "AGENTS.md 未声明 focused GUT 的 bootstrap 前置"

GODOT=true "$REPO_ROOT/scripts/godot_bootstrap.sh" >/dev/null \
	|| fail "bootstrap 应接受两轮均为 0 的 Godot 命令"

set +e
failure_output="$(GODOT=false "$REPO_ROOT/scripts/godot_bootstrap.sh" 2>&1)"
failure_rc=$?
set -e
if [[ "$failure_rc" -eq 0 ]]; then
	fail "bootstrap 不得接受第二轮非零退出"
fi
while IFS= read -r failure_log
do
	[[ "$failure_log" == /tmp/mahjong-godot-* ]] && rm -f "$failure_log"
done < <(printf '%s\n' "$failure_output" | sed -n 's/^godot_bootstrap: .*_log=//p')

printf 'PASS: Godot worktree bootstrap contract\n'
