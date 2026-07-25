#!/usr/bin/env bash
# #256 E7-02：Worker 注册/租约/容量/双 Worker 拓扑契约（不启动重型服务）。
# 严禁把展开后的密钥/token 写入日志或失败输出。
# 网络端到端未验证。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMPOSE_FILE="$ROOT/services/control-plane/docker-compose.e7.yml"
ENV_EXAMPLE="$ROOT/services/control-plane/.env.example"
COMPOSE_BIN="${COMPOSE_BIN:-}"
FAKE_SECRET="e7-256-r1-fake-secret-$(date +%s)-$$-MUST-NOT-LEAK"
FAKE_REG="e7-256-r1-reg-token-$(date +%s)-$$-MUST-NOT-LEAK"

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

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "OK: $*"; }

echo "== #256 worker lifecycle contract =="
echo "compose_bin=$COMPOSE_BIN"

[[ -f "$COMPOSE_FILE" ]] || fail "missing compose"
[[ -f "$ENV_EXAMPLE" ]] || fail "missing .env.example"
[[ -f "$ROOT/scripts/e7_256_worker_lifecycle_smoke.sh" ]] || fail "missing #256 smoke"

# services
# shellcheck disable=SC2086
SERVICES="$($COMPOSE_BIN -f "$COMPOSE_FILE" --env-file "$ENV_EXAMPLE" config --services 2>/dev/null)" \
  || fail "compose config --services failed"
for svc in redis control-plane stt worker-a worker-b; do
  echo "$SERVICES" | grep -qx "$svc" || fail "service missing: $svc"
done
pass "dual workers + cp + redis + stt"

# ports
grep -E '127\.0\.0\.1:9000:9000' "$COMPOSE_FILE" >/dev/null || fail "worker-a :9000"
grep -E '127\.0\.0\.1:9002:9002' "$COMPOSE_FILE" >/dev/null || fail "worker-b :9002"
grep -E '127\.0\.0\.1:8081:8081' "$COMPOSE_FILE" >/dev/null || fail "cp :8081"
pass "distinct host ports for two workers"

# registration env
grep -E 'WORKER_REGISTRATION_TOKEN' "$COMPOSE_FILE" >/dev/null || fail "missing WORKER_REGISTRATION_TOKEN in compose"
grep -E 'CONTROL_PLANE_URL' "$COMPOSE_FILE" >/dev/null || fail "missing CONTROL_PLANE_URL"
grep -E 'WORKER_GAME_ENDPOINT|WORKER_A_GAME_ENDPOINT' "$COMPOSE_FILE" "$ENV_EXAMPLE" >/dev/null \
  || fail "missing game endpoint registration config"
grep -E 'WORKER_CAPACITY|WORKER_A_CAPACITY' "$COMPOSE_FILE" "$ENV_EXAMPLE" >/dev/null \
  || fail "missing capacity config"
grep -E 'WORKER_REGISTRATION_TOKEN=.+' "$ENV_EXAMPLE" >/dev/null \
  || fail ".env.example must provide WORKER_REGISTRATION_TOKEN"
# 不得与 signing secret 示例相同
SIGN_EX="$(grep -E '^TOKEN_SIGNING_SECRET=' "$ENV_EXAMPLE" | head -1 | cut -d= -f2-)"
REG_EX="$(grep -E '^WORKER_REGISTRATION_TOKEN=' "$ENV_EXAMPLE" | head -1 | cut -d= -f2-)"
[[ -n "$SIGN_EX" && -n "$REG_EX" && "$SIGN_EX" != "$REG_EX" ]] \
  || fail "registration token example must differ from signing secret example"
pass "registration token/capacity/endpoints documented"

# CP readiness remains Redis-backed (not worker presence)
grep -E 'readyz' "$COMPOSE_FILE" >/dev/null || fail "cp healthcheck must use readyz"
pass "cp readiness still Redis-backed"

# Go registration path markers
grep -R -n 'internal/workers' "$ROOT/services/control-plane/cmd/control-plane/main.go" >/dev/null \
  || fail "main must wire workers package"
grep -R -n 'Register' "$ROOT/services/control-plane/internal/httpserver/workers.go" >/dev/null \
  || fail "HTTP register handler missing"
grep -n 'WorkerControlPlaneClient\|CONTROL_PLANE_URL' \
  "$ROOT/godot/server/headless_worker.gd" \
  "$ROOT/godot/server/headless_worker_main.gd" \
  "$ROOT/godot/server/worker_control_plane_client.gd" >/dev/null \
  || fail "Godot registration wiring missing"
pass "production registration call chain present"

# secret non-leak
TMP_ENV="$(mktemp)"
TMP_OUT="$(mktemp)"
cleanup() { rm -f "$TMP_ENV" "$TMP_OUT"; }
trap cleanup EXIT
{
  echo "TOKEN_SIGNING_SECRET=${FAKE_SECRET}"
  echo "WORKER_REGISTRATION_TOKEN=${FAKE_REG}"
} >"$TMP_ENV"
# shellcheck disable=SC2086
if ! $COMPOSE_BIN -f "$COMPOSE_FILE" --env-file "$TMP_ENV" config --quiet >"$TMP_OUT" 2>&1; then
  fail "compose config --quiet failed"
fi
if grep -F -- "$FAKE_SECRET" "$TMP_OUT" >/dev/null 2>&1; then
  fail "leaked FAKE_SECRET"
fi
if grep -F -- "$FAKE_REG" "$TMP_OUT" >/dev/null 2>&1; then
  fail "leaked FAKE_REG"
fi
pass "fake secrets not leaked by compose config"

echo "== ALL #256 CONTRACT CHECKS PASSED =="
exit 0
