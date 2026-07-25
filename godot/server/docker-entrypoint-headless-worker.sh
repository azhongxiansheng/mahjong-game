#!/bin/sh
# #255 Headless Worker 容器入口：校验内置 Godot 缓存后监听游戏/语音 WebSocket。
# 密钥只读环境变量；不打印 TOKEN_SIGNING_SECRET。
# 缺失/损坏缓存不得静默启动；补 import 走与镜像相同的两轮门禁（不吞失败）。
# 网络端到端未验证。
set -eu

if [ -z "${TOKEN_SIGNING_SECRET:-}" ]; then
  echo "TOKEN_SIGNING_SECRET is required" >&2
  exit 2
fi

# nobody 默认 HOME=/nonexistent；Godot 需要可写 user data / 日志目录。
export HOME="${HOME:-/tmp/godot-home}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
mkdir -p \
  "$HOME" \
  "$XDG_DATA_HOME" \
  "$XDG_CONFIG_HOME" \
  "$XDG_CACHE_HOME" \
  "$HOME/.local/share/godot/app_userdata/MahjongGame/logs"

HOST="${WORKER_BIND_HOST:-0.0.0.0}"
PORT="${WORKER_PORT:-9000}"
VOICE_PORT="${VOICE_WORKER_PORT:-9001}"
PROJECT="/app/godot"

# 镜像构建期应已烘焙有效 .godot 缓存。缺失时不得 || true 吞错。
if [ ! -f "${PROJECT}/.godot/global_script_class_cache.cfg" ]; then
  echo "headless_worker: baked godot cache missing; running import gate" >&2
  if [ ! -x /usr/local/bin/godot_import_gate.sh ]; then
    echo "headless_worker: godot_import_gate.sh missing; refusing to start" >&2
    exit 3
  fi
  /usr/local/bin/godot_import_gate.sh "$PROJECT"
  if [ ! -f "${PROJECT}/.godot/global_script_class_cache.cfg" ]; then
    echo "headless_worker: import gate did not produce class cache; refusing to start" >&2
    exit 3
  fi
fi

echo "headless_worker: starting host=${HOST} port=${PORT} voice_port=${VOICE_PORT}"
# STT_SERVICE_URL / VOICE_WORKER_PORT 由 headless_worker_main.gd 读环境变量。
exec godot --headless --path "${PROJECT}" \
  -s res://server/headless_worker_main.gd \
  -- --host="${HOST}" --port="${PORT}" --voice-port="${VOICE_PORT}"
