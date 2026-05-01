#!/usr/bin/env bash
# Run GUT tests headless across core / battle / skills.
# Usage: scripts/test_run_core.sh [optional GUT args]
# Override Godot binary via GODOT env var, e.g.:
#   GODOT=/path/to/Godot_v4.5-stable_linux.x86_64 scripts/test_run_core.sh
set -euo pipefail

PROJ_DIR="$(cd "$(dirname "$0")/.." && pwd)/godot"
GODOT_BIN="${GODOT:-godot}"

# Ensure GUT class names are registered in the project cache before running.
# `|| true` because --import can return non-zero on benign warnings;
# stderr is intentionally NOT suppressed so real project-load failures stay visible.
"$GODOT_BIN" --headless --path "$PROJ_DIR" --import || true

"$GODOT_BIN" --headless --path "$PROJ_DIR" \
    -s addons/gut/gut_cmdln.gd \
    "-gdir=res://tests/core,res://tests/battle,res://tests/skills" \
    -gexit \
    "$@"
