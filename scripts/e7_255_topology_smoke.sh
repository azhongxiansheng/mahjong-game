#!/usr/bin/env bash
# #255 E7-01：真实构建并启动四服务，校验 health/readiness 后清理。
# 启动复用文档主命令语义：up -d --build --wait --wait-timeout。
# 严禁把展开后的密钥写入日志。网络端到端未验证。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CP_DIR="$ROOT/services/control-plane"
COMPOSE_FILE="$CP_DIR/docker-compose.e7.yml"
ENV_FILE="${ENV_FILE:-$CP_DIR/.env.example}"
LOG="${LOG:-/tmp/mahjong-game-issue-255-grok-smoke.log}"
COMPOSE_BIN="${COMPOSE_BIN:-}"
KEEP_UP="${KEEP_UP:-0}"
# 与文档主命令一致：覆盖 STT 冷启动拉模型 + Worker import/health。
WAIT_TIMEOUT_SEC="${WAIT_TIMEOUT_SEC:-900}"

if [[ -z "$COMPOSE_BIN" ]]; then
  if command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_BIN="$(command -v docker-compose)"
  elif docker compose version >/dev/null 2>&1; then
    COMPOSE_BIN="docker compose"
  else
    echo "FAIL: neither docker-compose nor docker compose available" >&2
    exit 2
  fi
fi

# shellcheck disable=SC2086
compose() { $COMPOSE_BIN -f "$COMPOSE_FILE" --env-file "$ENV_FILE" "$@"; }

ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }
log() { echo "[$(ts)] $*" | tee -a "$LOG"; }

# 将命令输出写入日志，但若检测到密钥值则拒绝落盘并失败。
# 调用方传入 SECRET_SCAN_VALUES（换行分隔）可选。
append_cmd_log() {
  local tmp
  tmp="$(mktemp)"
  # shellcheck disable=SC2068
  if ! "$@" >"$tmp" 2>&1; then
    # 不把可能含密钥的输出写入主日志；只记稳定失败
    rm -f "$tmp"
    log "FAIL: command failed (output omitted to avoid secret leakage): $*"
    return 1
  fi
  if [[ -n "${SECRET_SCAN_VALUE:-}" ]] && grep -F -- "$SECRET_SCAN_VALUE" "$tmp" >/dev/null 2>&1; then
    rm -f "$tmp"
    log "FAIL: command output contained SECRET_SCAN_VALUE; refusing to log"
    return 1
  fi
  # 额外扫描 env 文件中的 TOKEN 值（若可解析）
  if [[ -n "${TOKEN_VALUE_FOR_SCAN:-}" ]] && grep -F -- "$TOKEN_VALUE_FOR_SCAN" "$tmp" >/dev/null 2>&1; then
    rm -f "$tmp"
    log "FAIL: command output contained TOKEN_SIGNING_SECRET value; refusing to log"
    return 1
  fi
  cat "$tmp" >>"$LOG"
  rm -f "$tmp"
  return 0
}

cleanup() {
  if [[ "$KEEP_UP" == "1" ]]; then
    log "KEEP_UP=1; leave stack running"
    return 0
  fi
  log "cleanup: compose down -v --remove-orphans"
  # down 输出通常不含密钥；仍做扫描
  append_cmd_log compose down -v --remove-orphans || true
}
trap cleanup EXIT

: >"$LOG"
log "== #255 topology smoke start =="
log "compose_bin=$COMPOSE_BIN"
log "compose_file=$COMPOSE_FILE"
log "env_file=$ENV_FILE"
log "log=$LOG"
log "wait_timeout_sec=$WAIT_TIMEOUT_SEC"

[[ -f "$COMPOSE_FILE" ]] || { log "missing compose"; exit 1; }
[[ -f "$ENV_FILE" ]] || { log "missing env file"; exit 1; }

if ! grep -qE '^TOKEN_SIGNING_SECRET=.+' "$ENV_FILE"; then
  log "FAIL: TOKEN_SIGNING_SECRET missing in env file"
  exit 1
fi
# 提取密钥值仅用于负向扫描，绝不 log 该值
TOKEN_VALUE_FOR_SCAN="$(grep -E '^TOKEN_SIGNING_SECRET=' "$ENV_FILE" | head -1 | cut -d= -f2-)"
if [[ -z "$TOKEN_VALUE_FOR_SCAN" ]]; then
  log "FAIL: empty TOKEN_SIGNING_SECRET"
  exit 1
fi

log "== compose config --quiet =="
if ! compose config --quiet >/dev/null 2>&1; then
  log "FAIL: compose config --quiet failed (details omitted)"
  exit 1
fi
log "compose config --quiet ok"

log "== build =="
# 不强制 --pull：测试拓扑优先可复现本地构建。
if ! append_cmd_log compose build; then
  exit 1
fi
log "build ok"

# STT 模型不进镜像。若宿主已有 HF 缓存，则预热命名卷。
seed_stt_model_volume() {
  local host_hub="${HF_HUB_CACHE:-$HOME/.cache/huggingface/hub}"
  local model_dir="${host_hub}/models--Systran--faster-whisper-small"
  if [[ ! -d "$model_dir" ]]; then
    log "stt seed skip: no host model (runtime may download)"
    return 0
  fi
  log "stt seed: volume mahjong_e7_stt_model_cache from host hub"
  docker volume create mahjong_e7_stt_model_cache >>"$LOG" 2>&1 || true
  if ! docker run --rm \
    -v mahjong_e7_stt_model_cache:/dest \
    -v "${host_hub}:/src:ro" \
    debian:bookworm-slim \
    bash -c 'mkdir -p /dest && cp -a /src/models--Systran--faster-whisper-small /dest/ && chmod -R a+rX /dest' \
    >>"$LOG" 2>&1; then
    log "FAIL: stt seed failed"
    return 1
  fi
  log "stt seed ok"
}
seed_stt_model_volume

log "== up -d --build --wait --wait-timeout ${WAIT_TIMEOUT_SEC} =="
# 文档主命令语义：成功退出即四服务 healthy。
if ! append_cmd_log compose up -d --build --wait --wait-timeout "$WAIT_TIMEOUT_SEC"; then
  log "FAIL: compose up --wait failed"
  exit 1
fi
log "up --wait ok (all services healthy per compose)"

log "== host-side probes =="
# Redis PING
pong="$(compose exec -T redis redis-cli PING)"
echo "$pong" | tee -a "$LOG" | grep -qx PONG
log "redis PING=PONG"

# CP healthz + readyz
hz="$(curl -fsS http://127.0.0.1:8081/healthz)"
echo "$hz" | tee -a "$LOG" | grep -q '"status":"ok"'
rz="$(curl -fsS http://127.0.0.1:8081/readyz)"
echo "$rz" | tee -a "$LOG" | grep -q '"status":"ready"'
log "control-plane healthz+readyz ok"

# STT PING/PONG
python3 "$ROOT/services/stt/scripts/healthcheck_ws.py" \
  --mode stt --url ws://127.0.0.1:9100 --timeout 5 | tee -a "$LOG"
log "stt PING/PONG ok"

# Worker protocol probes
python3 "$ROOT/godot/tools/healthcheck_ws.py" \
  --mode worker --url ws://127.0.0.1:9000 --timeout 6 | tee -a "$LOG"
python3 "$ROOT/godot/tools/healthcheck_ws.py" \
  --mode worker --url ws://127.0.0.1:9001 --timeout 6 | tee -a "$LOG"
log "worker game+voice protocol probes ok"

# 健康 JSON 与主日志不得含密钥精确值
if echo "$hz$rz" | grep -F -- "$TOKEN_VALUE_FOR_SCAN" >/dev/null 2>&1; then
  log "FAIL: TOKEN value appeared in health JSON"
  exit 1
fi
if grep -F -- "$TOKEN_VALUE_FOR_SCAN" "$LOG" >/dev/null 2>&1; then
  log "FAIL: TOKEN value leaked into smoke log"
  exit 1
fi

log "== ALL SMOKE CHECKS PASSED =="
log "note: 网络端到端未验证"
exit 0
