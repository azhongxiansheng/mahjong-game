#!/usr/bin/env bash
# 日常快速门禁：纯规则、战斗、技能、AI、meta 与资源健康检查。
# 重型协议、整局、UI、STT 回归请运行 scripts/test_run_slow.sh。
# Usage: scripts/test_run_core.sh [optional GUT args]
# Override Godot binary via GODOT env var, e.g.:
#   GODOT=/path/to/Godot_v4.5-stable_linux.x86_64 scripts/test_run_core.sh
set -euo pipefail

PROJ_DIR="$(cd "$(dirname "$0")/.." && pwd)/godot"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_BIN="${GODOT:-godot}"

GODOT="$GODOT_BIN" "$REPO_ROOT/scripts/godot_bootstrap.sh"

"$GODOT_BIN" --headless --path "$PROJ_DIR" \
	-s addons/gut/gut_cmdln.gd \
	"-gdir=res://tests/core,res://tests/battle,res://tests/skills,res://tests/ai,res://tests/meta,res://tests/health" \
	-ginclude_subdirs \
	-gpaint_after=0 \
	-gexit \
	"$@"
