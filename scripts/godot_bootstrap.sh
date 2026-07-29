#!/usr/bin/env bash
# 为新 worktree 安全建立 Godot import/class_name 缓存。
# 第一轮只负责 bootstrap；第二轮必须退出 0 且不含稳定错误模式。
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_DIR="$REPO_ROOT/godot"
PROJECT_FILE="$PROJECT_DIR/project.godot"
GODOT_BIN="${GODOT:-godot}"
BOOT_LOG="$(mktemp /tmp/mahjong-godot-bootstrap.XXXXXX)"
CLEAN_LOG="$(mktemp /tmp/mahjong-godot-clean-import.XXXXXX)"

cleanup_success() {
	rm -f "$BOOT_LOG" "$CLEAN_LOG"
}

project_hash_before="$(git -C "$REPO_ROOT" hash-object "$PROJECT_FILE")"
tracked_before="$(git -C "$REPO_ROOT" status --porcelain --untracked-files=no)"

set +e
"$GODOT_BIN" --headless --path "$PROJECT_DIR" --import >"$BOOT_LOG" 2>&1
boot_rc=$?
set -e

project_hash_after_boot="$(git -C "$REPO_ROOT" hash-object "$PROJECT_FILE")"
if [[ "$project_hash_after_boot" != "$project_hash_before" ]]; then
	printf 'godot_bootstrap: FAIL project.godot 被首轮 import 改写；未自动恢复\n' >&2
	printf 'godot_bootstrap: bootstrap_log=%s\n' "$BOOT_LOG" >&2
	printf 'godot_bootstrap: clean_log=%s（未执行）\n' "$CLEAN_LOG" >&2
	exit 1
fi

set +e
"$GODOT_BIN" --headless --path "$PROJECT_DIR" --import >"$CLEAN_LOG" 2>&1
clean_rc=$?
set -e

fail_clean() {
	local reason="$1"
	printf 'godot_bootstrap: FAIL %s\n' "$reason" >&2
	printf 'godot_bootstrap: bootstrap_exit=%s clean_exit=%s\n' "$boot_rc" "$clean_rc" >&2
	printf 'godot_bootstrap: bootstrap_log=%s\n' "$BOOT_LOG" >&2
	printf 'godot_bootstrap: clean_log=%s\n' "$CLEAN_LOG" >&2
	grep -En 'SCRIPT ERROR|Parse Error|Compile Error|Failed loading resource|Failed to load script|Unrecognized UID' \
		"$CLEAN_LOG" | head -40 >&2 || true
	exit 1
}

if [[ "$clean_rc" -ne 0 ]]; then
	fail_clean "第二轮 import 非零退出"
fi

if grep -Eq 'SCRIPT ERROR|Parse Error|Compile Error|Failed loading resource|Failed to load script|Unrecognized UID' "$CLEAN_LOG"; then
	fail_clean "第二轮 import 命中禁止错误"
fi

project_hash_after_clean="$(git -C "$REPO_ROOT" hash-object "$PROJECT_FILE")"
if [[ "$project_hash_after_clean" != "$project_hash_before" ]]; then
	fail_clean "project.godot 被第二轮 import 改写；未自动恢复"
fi

tracked_after="$(git -C "$REPO_ROOT" status --porcelain --untracked-files=no)"
if [[ "$tracked_after" != "$tracked_before" ]]; then
	fail_clean "import 改变了 tracked Git 现场；未自动恢复"
fi

printf 'godot_bootstrap: ok (bootstrap_exit=%s, clean_exit=%s)\n' "$boot_rc" "$clean_rc"
cleanup_success
