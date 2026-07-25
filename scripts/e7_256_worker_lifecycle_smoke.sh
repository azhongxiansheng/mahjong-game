#!/usr/bin/env bash
# #256 E7-02 round-2：真实双 Worker 注册/完成释放容量/精确失联 ROOM_FAILED/恢复接房。
# STT 外网模型不可用时 best-effort。网络端到端未验证。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CP_DIR="$ROOT/services/control-plane"
COMPOSE_FILE="$CP_DIR/docker-compose.e7.yml"
ENV_FILE="${ENV_FILE:-$CP_DIR/.env.example}"
LOG="${LOG:-/tmp/mahjong-issue-256-r2-e7-smoke.log}"
COMPOSE_BIN="${COMPOSE_BIN:-}"
KEEP_UP="${KEEP_UP:-0}"
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

append_cmd_log() {
  local tmp
  tmp="$(mktemp)"
  if ! "$@" >"$tmp" 2>&1; then
    local snippet
    snippet="$(rg -n 'error|Error|FAIL|exited|denied|Bind for' "$tmp" 2>/dev/null | head -20 || true)"
    rm -f "$tmp"
    log "FAIL: command failed: $*"
    [[ -n "$snippet" ]] && log "fail_hints: $snippet"
    return 1
  fi
  if [[ -n "${TOKEN_VALUE_FOR_SCAN:-}" ]] && grep -F -- "$TOKEN_VALUE_FOR_SCAN" "$tmp" >/dev/null 2>&1; then
    rm -f "$tmp"; log "FAIL: TOKEN leaked"; return 1
  fi
  if [[ -n "${REG_VALUE_FOR_SCAN:-}" ]] && grep -F -- "$REG_VALUE_FOR_SCAN" "$tmp" >/dev/null 2>&1; then
    rm -f "$tmp"; log "FAIL: REG token leaked"; return 1
  fi
  cat "$tmp" >>"$LOG"
  rm -f "$tmp"
}

cleanup() {
  if [[ "$KEEP_UP" == "1" ]]; then log "KEEP_UP=1"; return 0; fi
  log "cleanup: compose down --remove-orphans"
  append_cmd_log compose down --remove-orphans || true
}
trap cleanup EXIT

: >"$LOG"
log "== #256 r2 worker lifecycle smoke =="

TOKEN_VALUE_FOR_SCAN="$(grep -E '^TOKEN_SIGNING_SECRET=' "$ENV_FILE" | head -1 | cut -d= -f2-)"
REG_VALUE_FOR_SCAN="$(grep -E '^WORKER_REGISTRATION_TOKEN=' "$ENV_FILE" | head -1 | cut -d= -f2-)"
[[ -n "$TOKEN_VALUE_FOR_SCAN" && -n "$REG_VALUE_FOR_SCAN" && "$TOKEN_VALUE_FOR_SCAN" != "$REG_VALUE_FOR_SCAN" ]] \
  || { log "FAIL: secrets"; exit 1; }

compose config --quiet >/dev/null 2>&1 || { log "FAIL: config"; exit 1; }

log "== up redis+cp =="
append_cmd_log compose up -d --build --wait --wait-timeout "$WAIT_TIMEOUT_SEC" redis control-plane \
  || { log "FAIL: redis/cp"; exit 1; }
compose up -d --build stt >>"$LOG" 2>&1 || log "stt best-effort failed"
log "== up workers --no-deps =="
append_cmd_log compose up -d --build --no-deps --wait --wait-timeout "$WAIT_TIMEOUT_SEC" worker-a worker-b \
  || { log "FAIL: workers"; exit 1; }

compose exec -T redis redis-cli PING | grep -qx PONG
curl -fsS http://127.0.0.1:8081/readyz | grep -q '"status":"ready"'
python3 "$ROOT/godot/tools/healthcheck_ws.py" --mode worker --url ws://127.0.0.1:9000 --timeout 6 | tee -a "$LOG"
python3 "$ROOT/godot/tools/healthcheck_ws.py" --mode worker --url ws://127.0.0.1:9002 --timeout 6 | tee -a "$LOG"

# wait both registered
ok_reg=""
for _ in $(seq 1 60); do
  idx="$(compose exec -T redis redis-cli SMEMBERS 'cp:v1:workers' | tr -d '\r' || true)"
  echo "$idx" | grep -q 'e7-worker-a' && echo "$idx" | grep -q 'e7-worker-b' && { ok_reg=1; break; }
  sleep 1
done
[[ -n "$ok_reg" ]] || { log "FAIL: not registered"; exit 1; }
log "registered both workers"

guest_post() {
  curl -fsS -X POST http://127.0.0.1:8081/v1/guest-sessions
}
enqueue() {
  local tok="$1"
  curl -fsS -X POST http://127.0.0.1:8081/v1/queues/casual \
    -H "Authorization: Bearer ${tok}" -H 'Content-Type: application/json' \
    -d '{"round_kind":"EAST","game_mode":"STANDARD"}'
}
get_ticket() {
  local tok="$1" tid="$2"
  curl -fsS -H "Authorization: Bearer ${tok}" "http://127.0.0.1:8081/v1/queues/casual/${tid}"
}

# --- A) 正常完成释放容量：capacity 模拟用 complete 内部 API + capacity=2 的真实分配 ---
# 匹配一房 → complete 该 room → 再匹配必须成功（释放证据）
tickets=()
for i in 1 2 3 4; do
  gj="$(guest_post)"
  gt="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["session_token"])' <<<"$gj")"
  tj="$(enqueue "$gt")"
  tid="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["ticket_id"])' <<<"$tj")"
  tickets+=("${gt}|${tid}")
done
assigned="" worker_ep="" room_id=""
for _ in $(seq 1 50); do
  sleep 0.2
  line="${tickets[0]}"; gt="${line%%|*}"; tid="${line##*|}"
  body="$(get_ticket "$gt" "$tid")"
  st="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))' <<<"$body")"
  if [[ "$st" == "assigned" ]]; then
    assigned=1
    worker_ep="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("worker",""))' <<<"$body")"
    room_id="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("room_id",""))' <<<"$body")"
    break
  fi
done
[[ -n "$assigned" && -n "$room_id" && -n "$worker_ep" ]] || { log "FAIL: first assign"; exit 1; }
log "first assigned room=$room_id worker_ep=$worker_ep"

# 解析实际 worker_id / compose service
worker_id="$(compose exec -T redis redis-cli HGET "cp:v1:casual:room:${room_id}" worker_id | tr -d '\r')"
[[ -n "$worker_id" ]] || { log "FAIL: room missing worker_id"; exit 1; }
log "room worker_id=$worker_id"
case "$worker_id" in
  e7-worker-a) svc=worker-a; other=worker-b; other_id=e7-worker-b ;;
  e7-worker-b) svc=worker-b; other=worker-a; other_id=e7-worker-a ;;
  *) log "FAIL: unexpected worker_id=$worker_id"; exit 1 ;;
esac

# 正常完成释放（真实内部协议）
complete_body="$(python3 -c 'import json; print(json.dumps({"worker_id":"'"$worker_id"'","room_id":"'"$room_id"'"}))')"
# 从容器内 CP 调 complete：用宿主 curl 到 CP 需要 reg token 不落盘到失败输出
creg="$(curl -sS -o /tmp/mahjong-issue-256-r2-complete-body.json -w '%{http_code}' \
  -X POST http://127.0.0.1:8081/v1/internal/workers/rooms/complete \
  -H "Authorization: Bearer ${REG_VALUE_FOR_SCAN}" \
  -H 'Content-Type: application/json' \
  -d "$complete_body")"
# 扫描响应不得含 token
if grep -F -- "$REG_VALUE_FOR_SCAN" /tmp/mahjong-issue-256-r2-complete-body.json >/dev/null 2>&1; then
  log "FAIL: complete response leaked token"; exit 1
fi
[[ "$creg" == "200" ]] || { log "FAIL: complete HTTP $creg"; cat /tmp/mahjong-issue-256-r2-complete-body.json >>"$LOG" || true; exit 1; }
rst="$(compose exec -T redis redis-cli HGET "cp:v1:casual:room:${room_id}" status | tr -d '\r')"
[[ "$rst" == "completed" ]] || { log "FAIL: room status=$rst want completed"; exit 1; }
log "room completed; capacity released"

# 再开一房必须成功
tickets2=()
for i in 1 2 3 4; do
  gj="$(guest_post)"; gt="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["session_token"])' <<<"$gj")"
  tj="$(enqueue "$gt")"; tid="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["ticket_id"])' <<<"$tj")"
  tickets2+=("${gt}|${tid}")
done
ok2="" room2=""
for _ in $(seq 1 50); do
  sleep 0.2
  line="${tickets2[0]}"; gt="${line%%|*}"; tid="${line##*|}"
  body="$(get_ticket "$gt" "$tid")"
  st="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))' <<<"$body")"
  if [[ "$st" == "assigned" ]]; then
    ok2=1
    room2="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("room_id",""))' <<<"$body")"
    break
  fi
done
[[ -n "$ok2" && -n "$room2" && "$room2" != "$room_id" ]] || { log "FAIL: post-complete match"; exit 1; }
log "post-complete new room=$room2"

# --- B) 精确失联：停实际承载 room2 的 service，无条件 ROOM_FAILED ---
worker_id2="$(compose exec -T redis redis-cli HGET "cp:v1:casual:room:${room2}" worker_id | tr -d '\r')"
[[ -n "$worker_id2" ]] || { log "FAIL: room2 worker_id empty"; exit 1; }
case "$worker_id2" in
  e7-worker-a) svc2=worker-a; keep2=worker-b; keep2_id=e7-worker-b ;;
  e7-worker-b) svc2=worker-b; keep2=worker-a; keep2_id=e7-worker-a ;;
  *) log "FAIL: unexpected worker_id2=$worker_id2"; exit 1 ;;
esac
log "stopping exact service=$svc2 for room2"

line="${tickets2[0]}"; gt2="${line%%|*}"; tid2="${line##*|}"
compose stop "$svc2" >/dev/null
sleep 20
body="$(get_ticket "$gt2" "$tid2")"
st="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))' <<<"$body")"
code="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("code",""))' <<<"$body")"
log "after stop $svc2: status=$st code=$code"
[[ "$st" == "failed" && "$code" == "ROOM_FAILED" ]] || { log "FAIL: expected ROOM_FAILED unconditionally"; exit 1; }
rst2="$(compose exec -T redis redis-cli HGET "cp:v1:casual:room:${room2}" status | tr -d '\r')"
[[ "$rst2" == "failed" ]] || { log "FAIL: room2 status=$rst2"; exit 1; }

# 失联 Worker 不应在索引中
idx="$(compose exec -T redis redis-cli SMEMBERS 'cp:v1:workers' | tr -d '\r' || true)"
if echo "$idx" | grep -qx "$worker_id2"; then
  log "FAIL: failed worker still in selection index"
  exit 1
fi

# --- C) 恢复该精确 Worker；停掉另一 Worker 并等其租约过期/出索引，避免心跳覆盖竞态 ---
compose start "$svc2" >/dev/null
recovered=""
for _ in $(seq 1 60); do
  sleep 0.5
  lease="$(compose exec -T redis redis-cli HGET "cp:v1:worker:${worker_id2}" lease_expires_at_ms | tr -d '\r')"
  now_ms="$(python3 -c 'import time; print(int(time.time()*1000))')"
  in_idx="$(compose exec -T redis redis-cli SISMEMBER 'cp:v1:workers' "$worker_id2" | tr -d '\r')"
  if [[ -n "$lease" && "$lease" =~ ^[0-9]+$ && "$lease" -gt "$now_ms" && "$in_idx" == "1" ]]; then
    recovered=1
    break
  fi
done
[[ -n "$recovered" ]] || { log "FAIL: worker $worker_id2 did not re-register within timeout"; exit 1; }
log "recovered $worker_id2"

log "stopping non-target $keep2 so only recovered worker is selectable"
compose stop "$keep2" >/dev/null
# 等待另一 Worker 租约过期并被 reaper 移出索引（默认 lease 15s）
other_gone=""
for _ in $(seq 1 40); do
  sleep 1
  in_other="$(compose exec -T redis redis-cli SISMEMBER 'cp:v1:workers' "$keep2_id" | tr -d '\r')"
  if [[ "$in_other" == "0" ]]; then
    other_gone=1
    break
  fi
done
[[ -n "$other_gone" ]] || { log "FAIL: non-target $keep2_id still in selection index"; exit 1; }
# 目标仍在索引
in_tgt="$(compose exec -T redis redis-cli SISMEMBER 'cp:v1:workers' "$worker_id2" | tr -d '\r')"
[[ "$in_tgt" == "1" ]] || { log "FAIL: recovered worker left index unexpectedly"; exit 1; }
log "only recovered worker selectable"

tickets3=()
for i in 1 2 3 4; do
  gj="$(guest_post)"; gt="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["session_token"])' <<<"$gj")"
  tj="$(enqueue "$gt")"; tid="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["ticket_id"])' <<<"$tj")"
  tickets3+=("${gt}|${tid}")
done
ok3="" wid3=""
for _ in $(seq 1 50); do
  sleep 0.2
  line="${tickets3[0]}"; gt="${line%%|*}"; tid="${line##*|}"
  body="$(get_ticket "$gt" "$tid")"
  st="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))' <<<"$body")"
  if [[ "$st" == "assigned" ]]; then
    rid3="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("room_id",""))' <<<"$body")"
    wid3="$(compose exec -T redis redis-cli HGET "cp:v1:casual:room:${rid3}" worker_id | tr -d '\r')"
    ok3=1
    break
  fi
done
[[ -n "$ok3" ]] || { log "FAIL: no assignment after recovery"; exit 1; }
[[ "$wid3" == "$worker_id2" ]] || { log "FAIL: new room worker_id=$wid3 want recovered $worker_id2"; exit 1; }
# 旧失败保持
body="$(get_ticket "$gt2" "$tid2")"
st="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))' <<<"$body")"
[[ "$st" == "failed" ]] || { log "FAIL: old ticket resurrected as $st"; exit 1; }
log "recovered worker accepted new room; old failed preserved"

if grep -F -- "$TOKEN_VALUE_FOR_SCAN" "$LOG" >/dev/null 2>&1; then log "FAIL: TOKEN in log"; exit 1; fi
if grep -F -- "$REG_VALUE_FOR_SCAN" "$LOG" >/dev/null 2>&1; then log "FAIL: REG in log"; exit 1; fi

log "== ALL #256 R3 SMOKE CHECKS PASSED =="
log "note: 网络端到端未验证"
exit 0
