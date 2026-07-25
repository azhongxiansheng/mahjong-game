#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${STT_PORT:-19123}"
export STT_HOST=127.0.0.1 STT_PORT="$PORT" HF_HUB_OFFLINE=1
PY="${STT_PYTHON:-/tmp/mahjong-stt-venv-247/bin/python}"
cd "$ROOT"
exec "$PY" -m stt_service
