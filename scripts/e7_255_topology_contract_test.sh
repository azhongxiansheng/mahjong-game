#!/usr/bin/env bash
# #255 E7-01：Compose 测试拓扑契约（不启动重型服务）。
# 证明四服务、端口、healthcheck、密钥/模型边界文档契约存在且可解析。
# 严禁把展开后的密钥/token 写入日志或失败输出。
# 网络端到端未验证。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMPOSE_FILE="$ROOT/services/control-plane/docker-compose.e7.yml"
ENV_EXAMPLE="$ROOT/services/control-plane/.env.example"
COMPOSE_BIN="${COMPOSE_BIN:-}"
# 本轮唯一假密钥：验证后输出中不得出现该精确值。
FAKE_SECRET="e7-255-r2-fake-secret-$(date +%s)-$$-MUST-NOT-LEAK"

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

# 失败时不得回显可能含密钥的命令输出正文。
compose_quiet() {
  # shellcheck disable=SC2086
  if ! $COMPOSE_BIN -f "$COMPOSE_FILE" --env-file "$1" config --quiet >/dev/null 2>&1; then
    fail "compose config --quiet failed (details omitted to avoid secret leakage)"
  fi
}

echo "== #255 topology contract =="
echo "compose_bin=$COMPOSE_BIN"
echo "compose_file=$COMPOSE_FILE"

# --- required files ---
[[ -f "$COMPOSE_FILE" ]] || fail "missing $COMPOSE_FILE"
[[ -f "$ROOT/services/control-plane/Dockerfile" ]] || fail "missing control-plane Dockerfile"
[[ -f "$ROOT/services/stt/Dockerfile" ]] || fail "missing stt Dockerfile"
[[ -f "$ROOT/godot/server/Dockerfile.headless_worker" ]] || fail "missing godot Dockerfile.headless_worker"
[[ -f "$ROOT/services/stt/scripts/healthcheck_ws.py" ]] || fail "missing STT healthcheck_ws.py"
[[ -f "$ROOT/godot/tools/healthcheck_ws.py" ]] || fail "missing worker healthcheck_ws.py"
[[ -f "$ENV_EXAMPLE" ]] || fail "missing .env.example"
[[ -f "$ROOT/scripts/e7_255_topology_smoke.sh" ]] || fail "missing topology smoke script"
[[ -f "$ROOT/services/stt/requirements.runtime.lock.txt" ]] || fail "missing STT requirements.runtime.lock.txt"
pass "required files present"

# --- compose config parse（quiet：不打印展开配置）---
compose_quiet "$ENV_EXAMPLE"
pass "compose config --quiet ok"

# --- four services via config --services（不输出 env 值）---
# shellcheck disable=SC2086
SERVICES="$($COMPOSE_BIN -f "$COMPOSE_FILE" --env-file "$ENV_EXAMPLE" config --services 2>/dev/null)" \
  || fail "compose config --services failed (details omitted)"
# #256 起至少两个 Worker；兼容历史名 worker → worker-a/worker-b
for svc in redis control-plane stt; do
  echo "$SERVICES" | grep -qx "$svc" || fail "service missing: $svc"
done
if echo "$SERVICES" | grep -qx "worker-a" && echo "$SERVICES" | grep -qx "worker-b"; then
  pass "services redis control-plane stt worker-a worker-b present"
elif echo "$SERVICES" | grep -qx "worker"; then
  pass "services redis control-plane stt worker present (legacy single worker)"
else
  fail "need worker-a+worker-b (#256) or legacy worker"
fi

# --- host port bindings prefer 127.0.0.1（只读 compose 源文件，不读展开 config）---
grep -E '127\.0\.0\.1:6379:6379' "$COMPOSE_FILE" >/dev/null || fail "redis must bind 127.0.0.1:6379"
grep -E '127\.0\.0\.1:8081:8081' "$COMPOSE_FILE" >/dev/null || fail "control-plane must bind 127.0.0.1:8081"
grep -E '127\.0\.0\.1:9000:9000' "$COMPOSE_FILE" >/dev/null || fail "worker-a game ws must bind 127.0.0.1:9000"
grep -E '127\.0\.0\.1:9001:9001' "$COMPOSE_FILE" >/dev/null || fail "worker-a voice ws must bind 127.0.0.1:9001"
grep -E '127\.0\.0\.1:9100:9100' "$COMPOSE_FILE" >/dev/null || fail "stt must bind 127.0.0.1:9100"
pass "loopback host bindings documented"

# --- real healthchecks ---
grep -n 'redis-cli' "$COMPOSE_FILE" | head -1 | grep -qi PING || fail "redis healthcheck missing PING"
grep -E 'readyz' "$COMPOSE_FILE" >/dev/null || fail "control-plane healthcheck must include /readyz (Redis-backed)"
grep -E 'healthcheck_ws\.py' "$COMPOSE_FILE" >/dev/null || fail "compose must use healthcheck_ws.py for WS services"
pass "healthcheck commands reference real probes"

# --- secrets via env ---
grep -E 'TOKEN_SIGNING_SECRET' "$COMPOSE_FILE" >/dev/null || fail "TOKEN_SIGNING_SECRET must be env-injected"
if grep -E 'sk-[A-Za-z0-9]{10,}|ghp_[A-Za-z0-9]{10,}|xox[baprs]-' "$COMPOSE_FILE" \
  "$ENV_EXAMPLE" 2>/dev/null; then
  fail "looks like a real token pattern was committed"
fi
grep -E 'TOKEN_SIGNING_SECRET=.+' "$ENV_EXAMPLE" >/dev/null \
  || fail ".env.example must provide a non-empty example TOKEN_SIGNING_SECRET"
grep -E 'dev-only|example|CHANGE_ME|local-test' "$ENV_EXAMPLE" >/dev/null \
  || fail ".env.example secret should be marked as dev/example"
pass "secrets env-injected; no obvious real tokens in topology files"

# --- STT model cache boundary ---
grep -E 'STT_MODEL_CACHE|stt_model_cache|model.cache|model_cache' "$COMPOSE_FILE" >/dev/null \
  || fail "STT model cache volume/path must be declared"
if grep -E 'COPY.*\.(bin|pt|gguf|onnx)|FROM.*whisper.*model' \
  "$ROOT/services/stt/Dockerfile" 2>/dev/null; then
  fail "STT Dockerfile must not bake model binaries"
fi
pass "STT model cache boundary present; no baked models in Dockerfile"

# --- STT runtime lock as sole pip input ---
grep -E 'requirements\.runtime\.lock\.txt' "$ROOT/services/stt/Dockerfile" >/dev/null \
  || fail "STT Dockerfile must install from requirements.runtime.lock.txt"
if grep -E 'numpy>=|onnxruntime>=|av>=|tokenizers>=|pip install --no-cache-dir \\\s*$' \
  "$ROOT/services/stt/Dockerfile" 2>/dev/null; then
  # 禁止范围表达式依赖；Dockerfile 内不应再手写包版本清单
  if grep -EEn '"(numpy|onnxruntime|av|tokenizers|faster-whisper|websockets|httpx|ctranslate2)(>=|==)' \
    "$ROOT/services/stt/Dockerfile" 2>/dev/null; then
    fail "STT Dockerfile must not hardcode package version pins/ranges; use lock file only"
  fi
fi
# 锁文件为精确 == 且不含 pytest
grep -E '^[a-zA-Z0-9_.-]+=+.+$' "$ROOT/services/stt/requirements.runtime.lock.txt" >/dev/null \
  || fail "runtime lock must contain exact pins"
! grep -E '^pytest' "$ROOT/services/stt/requirements.runtime.lock.txt" >/dev/null \
  || fail "runtime lock must not include pytest package pins"
! grep -E '>=|<' "$ROOT/services/stt/requirements.runtime.lock.txt" >/dev/null \
  || fail "runtime lock must not use version ranges"
# 关键版本与 requirements.lock.txt 一致
for pin in \
  'faster-whisper==1.2.1' \
  'ctranslate2==4.7.1' \
  'websockets==14.2' \
  'httpx==0.28.1' \
  'numpy==2.2.6' \
  'onnxruntime==1.28.0' \
  'av==18.0.0' \
  'tokenizers==0.23.1'; do
  grep -qx "$pin" "$ROOT/services/stt/requirements.runtime.lock.txt" \
    || fail "runtime lock missing exact pin $pin"
  grep -qx "$pin" "$ROOT/services/stt/requirements.lock.txt" \
    || fail "source requirements.lock.txt missing $pin (drift)"
done
pass "STT runtime lock is sole pip input with exact versions"

# --- #256 worker registration / dual workers（拓扑已升级）---
grep -E 'WORKER_REGISTRATION_TOKEN' "$COMPOSE_FILE" >/dev/null \
  || fail "WORKER_REGISTRATION_TOKEN must be env-injected for worker registration"
grep -E 'CONTROL_PLANE_URL' "$COMPOSE_FILE" >/dev/null \
  || fail "workers must register via CONTROL_PLANE_URL"
grep -E 'worker-a|worker-b' "$COMPOSE_FILE" >/dev/null \
  || fail "compose must declare dual workers for #256 lifecycle"
pass "#256 registration + dual-worker topology present"

# --- Godot SHA-512 hard verification in Dockerfile ---
WORKER_DF="$ROOT/godot/server/Dockerfile.headless_worker"
GATE_SH="$ROOT/godot/server/godot_import_gate.sh"
ENTRY_SH="$ROOT/godot/server/docker-entrypoint-headless-worker.sh"
grep -E 'GODOT_SHA512_LINUX_ARM64=' "$WORKER_DF" >/dev/null || fail "worker Dockerfile missing ARM64 SHA-512"
grep -E 'GODOT_SHA512_LINUX_X86_64=' "$WORKER_DF" >/dev/null || fail "worker Dockerfile missing x86_64 SHA-512"
grep -F '7301207e346dc2064f3f6b474c199ebbc904b045c0620a98580ee6ff3743e185c3ff24b414c974cb9b4e79494356149c52c0614c9a778444de5d01f42c18160c' \
  "$WORKER_DF" >/dev/null || fail "worker Dockerfile ARM64 SHA-512 mismatch vs official"
grep -F 'a76fd0fe1d44a2dd6c065b6f7b434ad75f5593c07bda3d3017f8304f2d069acbcf0f39cb5d0976f0434b56e9ea852032ddbcbdb7e0ce1c75a47e1dacb6794bd7' \
  "$WORKER_DF" >/dev/null || fail "worker Dockerfile x86_64 SHA-512 mismatch vs official"
grep -E 'sha512sum -c' "$WORKER_DF" >/dev/null || fail "worker Dockerfile must run sha512sum -c before unzip"
pass "Godot official SHA-512 pins and checksum enforcement present"

# --- Godot two-pass clean import gate (bootstrap + audited second pass) ---
[[ -f "$GATE_SH" ]] || fail "missing godot_import_gate.sh"
grep -E 'godot_import_gate\.sh' "$WORKER_DF" >/dev/null \
  || fail "Dockerfile must invoke godot_import_gate.sh for import"
# 门禁脚本必须包含第二轮错误模式检查
for pat in \
  'SCRIPT ERROR' \
  'Parse Error' \
  'Compile Error' \
  'Failed loading resource' \
  'Failed to load script' \
  'Unrecognized UID'
do
  grep -F -- "$pat" "$GATE_SH" >/dev/null \
    || fail "godot_import_gate.sh must gate on pattern: $pat"
done
# 两轮：bootstrap 日志重定向 + clean 审计（不得只信退出码注释/实现）
grep -E 'bootstrap|BOOT' "$GATE_SH" >/dev/null || fail "import gate must have bootstrap pass"
grep -E 'clean|CLEAN' "$GATE_SH" >/dev/null || fail "import gate must have clean second pass"
grep -E 'grep -F' "$GATE_SH" >/dev/null || fail "import gate must pattern-scan clean log"
# entrypoint 不得吞 import 失败
[[ -f "$ENTRY_SH" ]] || fail "missing docker-entrypoint-headless-worker.sh"
if grep -nE 'godot[[:space:]].*--import.*\|\|[[:space:]]*true|--import[[:space:]]*\|\|[[:space:]]*true' "$ENTRY_SH" >/dev/null; then
  fail "entrypoint must not swallow godot import failures with || true"
fi
if grep -nE '\|\|[[:space:]]*true' "$ENTRY_SH" | grep -i import >/dev/null 2>&1; then
  fail "entrypoint must not || true around import"
fi
# 缺失缓存须走门禁或硬失败，不得静默继续
grep -E 'global_script_class_cache|godot_import_gate' "$ENTRY_SH" >/dev/null \
  || fail "entrypoint must check baked cache or invoke import gate"
pass "Godot two-pass clean import gate and entrypoint hard-fail present"

# --- healthcheck scripts syntax ---
python3 -m py_compile "$ROOT/services/stt/scripts/healthcheck_ws.py" \
  || fail "STT healthcheck_ws.py syntax error"
python3 -m py_compile "$ROOT/godot/tools/healthcheck_ws.py" \
  || fail "worker healthcheck_ws.py syntax error"
for f in \
  "$ROOT/services/stt/scripts/healthcheck_ws.py" \
  "$ROOT/godot/tools/healthcheck_ws.py"; do
  grep -E 'stt|worker|PING|PONG|COMMAND_REJECTED|protocol' "$f" >/dev/null \
    || fail "$f missing protocol probe keywords"
done
pass "healthcheck scripts compile and reference protocol probes"

# --- documentation: one-command with --wait + cleanup + e2e ---
README="$ROOT/services/control-plane/README.md"
[[ -f "$README" ]] || fail "missing control-plane README"
grep -E 'docker-compose\.e7\.yml|e7_255' "$README" >/dev/null \
  || fail "README must document e7 compose / smoke entrypoint"
grep -E 'docker-compose|docker compose' "$README" >/dev/null \
  || fail "README must document compose command"
grep -E -- '--wait' "$README" >/dev/null \
  || fail "README main up command must include --wait"
grep -E -- '--wait-timeout' "$README" >/dev/null \
  || fail "README main up command must include --wait-timeout"
grep -E -- '--wait' "$COMPOSE_FILE" >/dev/null \
  || fail "compose file top comments must document --wait main command"
grep -E 'down' "$README" >/dev/null || fail "README must document cleanup/down"
grep -E '网络端到端未验证' "$README" >/dev/null \
  || fail "README must state 网络端到端未验证"
# CLAUDE.md 同步
if [[ -f "$ROOT/CLAUDE.md" ]]; then
  grep -E -- '--wait' "$ROOT/CLAUDE.md" >/dev/null \
    || fail "CLAUDE.md E7 command must include --wait"
fi
pass "README/docs document --wait start/cleanup and e2e disclaimer"

# --- secret non-leak regression with unique fake secret ---
TMP_ENV="$(mktemp)"
TMP_OUT="$(mktemp)"
cleanup_tmp() { rm -f "$TMP_ENV" "$TMP_OUT"; }
trap cleanup_tmp EXIT
{
  echo "TOKEN_SIGNING_SECRET=${FAKE_SECRET}"
  echo "WORKER_REGISTRATION_TOKEN=dev-only-worker-reg-token-fake"
} >"$TMP_ENV"
# quiet config
# shellcheck disable=SC2086
if ! $COMPOSE_BIN -f "$COMPOSE_FILE" --env-file "$TMP_ENV" config --quiet >"$TMP_OUT" 2>&1; then
  fail "compose config --quiet with fake secret failed (details omitted)"
fi
if grep -F -- "$FAKE_SECRET" "$TMP_OUT" >/dev/null 2>&1; then
  fail "compose config --quiet output leaked FAKE_SECRET"
fi
# services listing
# shellcheck disable=SC2086
if ! $COMPOSE_BIN -f "$COMPOSE_FILE" --env-file "$TMP_ENV" config --services >"$TMP_OUT" 2>&1; then
  fail "compose config --services with fake secret failed (details omitted)"
fi
if grep -F -- "$FAKE_SECRET" "$TMP_OUT" >/dev/null 2>&1; then
  fail "compose config --services output leaked FAKE_SECRET"
fi
pass "unique fake secret not leaked by config --quiet/--services"

echo "== ALL CONTRACT CHECKS PASSED =="
exit 0
