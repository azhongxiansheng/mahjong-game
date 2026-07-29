#!/usr/bin/env bash
# 显式慢速回归：协议、服务器、整局集成、会话、UI、音频/STT 与性能测试。
# Usage: scripts/test_run_slow.sh [optional GUT args]
set -euo pipefail

PROJ_DIR="$(cd "$(dirname "$0")/.." && pwd)/godot"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_BIN="${GODOT:-godot}"

GODOT="$GODOT_BIN" "$REPO_ROOT/scripts/godot_bootstrap.sh"

"$GODOT_BIN" --headless --path "$PROJ_DIR" \
	-s addons/gut/gut_cmdln.gd \
	"-gdir=res://tests/integration,res://tests/protocol,res://tests/server,res://tests/session,res://tests/stt,res://tests/audio,res://tests/ui,res://tests/tools,res://tests/perf,res://tests/scenes" \
	-ginclude_subdirs \
	-gpaint_after=0 \
	-gexit \
	"$@"
