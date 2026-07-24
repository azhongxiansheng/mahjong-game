#!/usr/bin/env bash
# #240 round-2 隔离真实多进程 smoke：
# 独立 Redis 容器（动态端口）+ 独立 CP + 独立 Worker + 4 客户端
# JOIN/READY + 合法 Action + ACTION_APPLIED（NBC 消费）
# 网络端到端未验证。勿打印完整 token/secret。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CP_DIR="$ROOT/services/control-plane"
UNIQUE="240-$(date +%s)-$$"
LOG_DIR="$(mktemp -d "/tmp/mahjong-game-issue-240-smoke-${UNIQUE}.XXXXXX")"
chmod 700 "$LOG_DIR"

pick_port() {
  python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()'
}

REDIS_PORT="$(pick_port)"
CP_PORT="$(pick_port)"
WORKER_PORT="$(pick_port)"
SECRET="dev-only-smoke-secret-32bytes-xx!"
REDIS_NAME="mj-smoke-redis-${UNIQUE}"
export TOKEN_SIGNING_SECRET="$SECRET"
export WORKER_ENDPOINT="ws://127.0.0.1:${WORKER_PORT}"
export HTTP_ADDR="127.0.0.1:${CP_PORT}"
export REDIS_ADDR="127.0.0.1:${REDIS_PORT}"
CP_URL="http://127.0.0.1:${CP_PORT}"
WS_URL="ws://127.0.0.1:${WORKER_PORT}"

CP_PID=""
WORKER_PID=""
declare -a CLIENT_PIDS=()

cleanup() {
  for p in "${CLIENT_PIDS[@]:-}"; do
    kill "$p" 2>/dev/null || true
  done
  if [[ -n "${WORKER_PID}" ]]; then kill "$WORKER_PID" 2>/dev/null || true; fi
  if [[ -n "${CP_PID}" ]]; then kill "$CP_PID" 2>/dev/null || true; fi
  docker rm -f "$REDIS_NAME" >/dev/null 2>&1 || true
  rm -f "$LOG_DIR"/token_*.txt "$LOG_DIR"/session_*.txt 2>/dev/null || true
}
trap cleanup EXIT

json_field() {
  printf '%s' "$1" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d[sys.argv[1]])' "$2"
}

echo "== smoke isolated ports redis=$REDIS_PORT cp=$CP_PORT worker=$WORKER_PORT dir=$LOG_DIR =="

echo "== redis container =="
docker run -d --name "$REDIS_NAME" \
  -p "127.0.0.1:${REDIS_PORT}:6379" \
  redis:7-alpine >/dev/null
REDIS_CID="$(docker inspect -f '{{.Id}}' "$REDIS_NAME")"
for _ in $(seq 1 40); do
  if docker exec "$REDIS_NAME" redis-cli PING 2>/dev/null | grep -q PONG; then break; fi
  sleep 0.1
done
docker exec "$REDIS_NAME" redis-cli PING | grep -q PONG
echo "redis_ok container=${REDIS_NAME:0:20}... cid_prefix=${REDIS_CID:0:12}"

echo "== control plane =="
(cd "$CP_DIR" && go run ./cmd/control-plane) >"$LOG_DIR/cp.log" 2>&1 &
CP_PID=$!
for _ in $(seq 1 100); do
  if kill -0 "$CP_PID" 2>/dev/null && curl -sf "$CP_URL/healthz" >/dev/null 2>&1; then break; fi
  sleep 0.1
done
kill -0 "$CP_PID"
curl -sf "$CP_URL/readyz" >/dev/null
echo "cp_ok pid=$CP_PID"

echo "== headless worker =="
godot --headless --path "$ROOT/godot" -s res://server/headless_worker_main.gd \
  -- --host=127.0.0.1 --port="$WORKER_PORT" \
  >"$LOG_DIR/worker.log" 2>&1 &
WORKER_PID=$!
for _ in $(seq 1 60); do
  if kill -0 "$WORKER_PID" 2>/dev/null && grep -q "headless_worker listening" "$LOG_DIR/worker.log" 2>/dev/null; then
    break
  fi
  sleep 0.1
done
kill -0 "$WORKER_PID"
grep -q "headless_worker listening" "$LOG_DIR/worker.log"
echo "worker_ok pid=$WORKER_PID"

echo "== 4 guests match =="
declare -a TICKETS=()
for i in 0 1 2 3; do
  sess_json=$(curl -sf -X POST "$CP_URL/v1/guest-sessions")
  stok=$(json_field "$sess_json" session_token)
  printf '%s' "$stok" >"$LOG_DIR/session_$i.txt"
  chmod 600 "$LOG_DIR/session_$i.txt"
  join_json=$(curl -sf -X POST "$CP_URL/v1/queues/casual" \
    -H "Authorization: Bearer $stok" \
    -H 'Content-Type: application/json' \
    -d '{"round_kind":"EAST","game_mode":"STANDARD"}')
  TICKETS+=("$(json_field "$join_json" ticket_id)")
done

ROOM_ID=""
declare -a SEATS=()
for _ in $(seq 1 100); do
  all_ok=1
  for i in 0 1 2 3; do
    stok=$(cat "$LOG_DIR/session_$i.txt")
    q=$(curl -sf "$CP_URL/v1/queues/casual/${TICKETS[$i]}" -H "Authorization: Bearer $stok")
    if [[ "$(json_field "$q" status)" != "assigned" ]]; then all_ok=0; break; fi
  done
  if [[ "$all_ok" == "1" ]]; then
    for i in 0 1 2 3; do
      stok=$(cat "$LOG_DIR/session_$i.txt")
      q=$(curl -sf "$CP_URL/v1/queues/casual/${TICKETS[$i]}" -H "Authorization: Bearer $stok")
      ROOM_ID=$(json_field "$q" room_id)
      SEATS[$i]=$(json_field "$q" seat)
      printf '%s' "$(json_field "$q" room_token)" >"$LOG_DIR/token_$i.txt"
      chmod 600 "$LOG_DIR/token_$i.txt"
    done
    break
  fi
  sleep 0.1
done
[[ -n "$ROOM_ID" ]]
# 找 seat0 作为 actor（东起始常为 seat0 TURN）
ACTOR_IDX=0
for i in 0 1 2 3; do
  if [[ "${SEATS[$i]}" == "0" ]]; then ACTOR_IDX=$i; break; fi
done
echo "assigned seats=${SEATS[*]} actor_idx=$ACTOR_IDX (room/token redacted)"

echo "== 4 clients JOIN/READY/Action =="
for i in 0 1 2 3; do
  (
    export SMOKE_WS_URL="$WS_URL"
    export SMOKE_ROOM_ID="$ROOM_ID"
    export SMOKE_SEAT="${SEATS[$i]}"
    export SMOKE_ROOM_TOKEN
    SMOKE_ROOM_TOKEN="$(cat "$LOG_DIR/token_$i.txt")"
    if [[ "$i" == "$ACTOR_IDX" ]]; then
      export SMOKE_IS_ACTOR=1
    else
      export SMOKE_IS_ACTOR=0
    fi
    godot --headless --path "$ROOT/godot" -s res://tools/e3_worker_smoke_client.gd \
      >"$LOG_DIR/client_$i.log" 2>&1
  ) &
  CLIENT_PIDS+=($!)
done

fail=0
for i in 0 1 2 3; do
  if ! wait "${CLIENT_PIDS[$i]}"; then
    echo "client $i failed"
    rg -n "ERROR|error|smoke_|SMOKE_|ACTION|ROOM_SNAPSHOT|NBC" "$LOG_DIR/client_$i.log" | head -30 || true
    fail=1
  fi
done

if [[ "$fail" != "0" ]]; then
  echo "SMOKE FAILED"
  rg -n "ERROR|error|listening" "$LOG_DIR/worker.log" | head -20 || true
  exit 1
fi

# 断言所有客户端日志含 ACTION_APPLIED
for i in 0 1 2 3; do
  if ! grep -q "ACTION_APPLIED" "$LOG_DIR/client_$i.log"; then
    echo "client $i missing ACTION_APPLIED"
    fail=1
  fi
done
if [[ "$fail" != "0" ]]; then
  exit 1
fi

echo "SMOKE OK: isolated Redis+CP+Worker+4 clients JOIN/READY/ACTION_APPLIED"
echo "网络端到端未验证"
exit 0
