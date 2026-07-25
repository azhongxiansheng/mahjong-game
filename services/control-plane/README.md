# Control Plane（E3 匹配控制面）

独立 Go module：配置入口、探针、游客会话签发、房间令牌内部服务、**公共休闲队列**与 **30 秒 AI 补位匹配**（#238–#239）。

**网络端到端未验证。** Headless Worker 牌局在 Godot 进程（`godot/server/headless_worker*.gd`，#240）；本目录不跑日麻规则。房间快照重连 / Worker 注册续租见 #241/#256。匹配结果中的 Worker 地址来自静态环境变量 `WORKER_ENDPOINT`（过渡契约，须指向真实监听中的 Worker）。

## 环境变量

| 变量 | 默认 | 说明 |
|---|---|---|
| `HTTP_ADDR` | `:8081` | HTTP 监听地址 |
| `REDIS_ADDR` | `127.0.0.1:6379` | Redis 地址 |
| `REDIS_PASSWORD` | （空） | Redis 密码 |
| `REDIS_DB` | `0` | Redis DB 编号 |
| `TOKEN_SIGNING_SECRET` | **必填** | HMAC 签名密钥，长度 ≥ 32；缺失/过短时进程拒绝启动。**勿提交真实密钥** |
| `WORKER_ENDPOINT` | **必填** | 匹配分配返回的静态 Worker 地址（trim 后非空）；缺失/空白时进程拒绝启动。**不**做多 Worker 选择 |
| `VOICE_WORKER_ENDPOINT` | **必填** | #244 独立语音 WebSocket 地址（trim 后非空）。Matcher 启动时强制配置；**仅** `TRASH_TALK` 的 room/ticket/HTTP assigned 写入并返回 `voice_worker`；`STANDARD` **不写** Redis 字段且 HTTP JSON 不出现该字段。**不得**从 `WORKER_ENDPOINT` 隐式猜端口 |

## 一条命令启动本地 Redis（仅 Redis）

前置：本机 Docker 可用（例如 `colima start` 或 Docker Desktop）。

```bash
# 在本目录（Docker Compose V2 插件或独立 docker-compose 二选一）
docker compose -f docker-compose.yml up -d
# 若本机无 compose 插件，改用：
# docker-compose -f docker-compose.yml up -d
```

验证 Redis：

```bash
docker compose -f docker-compose.yml exec -T redis redis-cli PING
# 或: docker-compose -f docker-compose.yml exec -T redis redis-cli PING
# 期望: PONG
```

清理：

```bash
docker compose -f docker-compose.yml down -v
# 或: docker-compose -f docker-compose.yml down -v
```

## E7-01 四服务测试拓扑（#255）

一条文档化命令启动**真实** Control Plane、Redis、faster-whisper STT、至少一个 Godot Headless Worker（Linux 容器）。宿主端口默认绑定 `127.0.0.1`；容器间经 Compose 网络互联。

**本机主命令**（已确认部分环境无 `docker compose` 插件，可用独立 `docker-compose`）：

```bash
cd services/control-plane
# 可选：cp .env.example .env 后编辑；勿提交真实密钥
# 成功退出即四服务 healthy（Redis PING / CP readyz / STT PONG / Worker 协议探活）
docker-compose -f docker-compose.e7.yml --env-file .env.example up -d --build --wait --wait-timeout 900
# Compose V2 等价：
# docker compose -f docker-compose.e7.yml --env-file .env.example up -d --build --wait --wait-timeout 900
```

| 服务 | 宿主端口 | 健康语义 |
|---|---|---|
| Redis | `127.0.0.1:6379` | `redis-cli PING` → `PONG` |
| Control Plane | `127.0.0.1:8081` | `GET /healthz` + Redis-backed `GET /readyz` |
| STT | `127.0.0.1:9100` | WebSocket `PING` → `PONG`（`primary.ok`；不含 token） |
| Headless Worker | `127.0.0.1:9000`（牌局）、`9001`（语音） | 真实 WebSocket 握手 + 协议探活（非日志 grep） |

静态 #239 过渡契约（**不**实现 #256 注册/租约/容量）：

- `WORKER_ENDPOINT=ws://127.0.0.1:9000`
- `VOICE_WORKER_ENDPOINT=ws://127.0.0.1:9001`
- Worker 容器内 `STT_SERVICE_URL=ws://stt:9100`

密钥与可选 new-api 备份**只经环境变量**注入（见 `.env.example`）。STT 模型二进制**不入 Git/镜像**，使用命名卷 `mahjong_e7_stt_model_cache`（`STT_MODEL_CACHE`）；默认仍为 multilingual `small` + CPU `int8`，可用 `STT_MODEL` / `STT_DEVICE` / `STT_COMPUTE_TYPE` 覆盖。

STT 冷启动会从 Hugging Face 拉模型（体积较大、依赖外网）。若宿主已有缓存，可先预热卷（`scripts/e7_255_topology_smoke.sh` 会自动尝试）：

```bash
docker volume create mahjong_e7_stt_model_cache
docker run --rm \
  -v mahjong_e7_stt_model_cache:/dest \
  -v "$HOME/.cache/huggingface/hub:/src:ro" \
  debian:bookworm-slim \
  bash -c 'cp -a /src/models--Systran--faster-whisper-small /dest/ && chmod -R a+rX /dest'
```

Godot 官方 Linux 发布物 zip 可放在 `godot/tools/godot_release_cache/`（已 gitignore `*.zip`）以离线构建 Worker 镜像；缺失时 Dockerfile 会从 GitHub Releases 下载。

一键 smoke（构建 + 启动 + 宿主侧真实探针 + 默认 `down -v` 清理）：

```bash
# 仓库根目录
scripts/e7_255_topology_smoke.sh
# 契约（不启动重型服务）
scripts/e7_255_topology_contract_test.sh
```

安全关闭 / 清理：

```bash
cd services/control-plane
docker-compose -f docker-compose.e7.yml --env-file .env.example down -v --remove-orphans
# Compose V2：docker compose -f docker-compose.e7.yml --env-file .env.example down -v --remove-orphans
# -v 会删除 STT 模型缓存卷；若需保留缓存可去掉 -v
```

**网络端到端未验证**（无公网四客户端整场；本拓扑仅本地容器健康与协议探针）。

## 启动 Control Plane

```bash
export HTTP_ADDR=:8081
export REDIS_ADDR=127.0.0.1:6379
# 本地开发示例密钥（仅示例，生产请使用独立强随机密钥，切勿提交真实密钥）
export TOKEN_SIGNING_SECRET='dev-only-example-secret-32bytes!'
# #239 静态 Worker 过渡契约（示例；非真实牌局 Worker 协议）
export WORKER_ENDPOINT='ws://127.0.0.1:9000'
export VOICE_WORKER_ENDPOINT='ws://127.0.0.1:9001'
go run ./cmd/control-plane
```

进程启动后会自动运行 matcher 扫描（不依赖客户端 GET 触发 30 秒分配）；优雅关闭时停止 matcher。

探针：

```bash
curl -sS http://127.0.0.1:8081/healthz   # 进程存活，200 {"status":"ok"}
curl -sS http://127.0.0.1:8081/readyz    # Redis 可用时 200 {"status":"ready"}
# Redis 停止后 /readyz 返回 503 {"status":"not_ready","reason":"redis"}
```

游客会话：

```bash
curl -sS -X POST http://127.0.0.1:8081/v1/guest-sessions
# 201 JSON: guest_id, display_name, session_token, expires_at
# 请勿在日志或工单中粘贴真实 session_token
```

### 公共休闲队列（#238）与分配查询（#239）

鉴权：`Authorization: Bearer <session_token>`（#237 游客会话令牌）。缺失 / 篡改 / 过期 / 房间令牌 → `401` `UNAUTHORIZED`。

`round_kind` ∈ `EAST` \| `HANCHAN`；`game_mode` ∈ `STANDARD` \| `TRASH_TALK`（ADR 稳定值，大小写敏感）。非法值 → `400` `INVALID_REQUEST`。

```bash
# 先拿 session_token（勿记录到日志）
TOKEN=$(curl -sS -X POST http://127.0.0.1:8081/v1/guest-sessions | jq -r .session_token)

# 加入队列（同游客+同规则组合幂等返回同一 ticket）
curl -sS -X POST http://127.0.0.1:8081/v1/queues/casual \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"round_kind":"EAST","game_mode":"STANDARD"}'
# 200 JSON: ticket_id, round_kind, game_mode, status=waiting, queued_at, deadline_at
# deadline_at = queued_at + 30s

# 查询（仅 ticket 所属游客）
# status=waiting|cancelled|assigned
# assigned 时额外含: worker, room_id, seat, room_token
# TRASH_TALK assigned 另含: voice_worker（STANDARD 不返回该字段）
curl -sS "http://127.0.0.1:8081/v1/queues/casual/$TICKET_ID" \
  -H "Authorization: Bearer $TOKEN"

# 取消（幂等；与消费原子竞争）
# waiting → cancelled；已 assigned 时保持 assigned（不得再变 cancelled）
curl -sS -X DELETE "http://127.0.0.1:8081/v1/queues/casual/$TICKET_ID" \
  -H "Authorization: Bearer $TOKEN"
```

### 匹配规则（#239）

- 匹配池按 `round_kind + game_mode` 隔离；优先凑真人。
- 同池 **4** 个有效真人 waiting ticket 到齐 → **立即**创建唯一四座位房间；单次扫描持续消费直到池中无可立即匹配（有界）。
- 同池 **1–3** 个有效真人 → 以**最早有效** ticket 的 `queued_at`（毫秒精度）为准，未满 30 秒不补位；满 30 秒原子开房，AI 数 = `4 - human_count`，总席位恒为 4。
- **完整原子分配**：先预签发全部真人 `room_token`，再经 **单次 Redis Lua** 校验候选仍有效后，一次写入 room + 全部 ticket 的 `status=assigned` / `worker` / `room_id` / `seat` / `room_token`。提交前对外不可见不完整 assigned；issuer 失败不写 Redis。
- 多 Control Plane 实例通过真实 Redis 原子语义收敛；同一 ticket 只进一房。
- 座位种类 ADR 稳定值：`HUMAN` / `AI`。
- 房间令牌经 `tokens.Service.IssueRoomToken` 签发，绑定 `session_id(=guest_id) + room_id + seat + exp`，并签入不可篡改 **`round_kind` / `game_mode` / `participants`**（#240 bootstrap）；`session_token` 与 `room_token` 不可互冒。
- `WORKER_ENDPOINT` 原样写入分配结果的 `worker` 字段（无 Worker 注册/健康回收）。
- `VOICE_WORKER_ENDPOINT` 仅对 **TRASH_TALK** 原样写入分配结果的 `voice_worker`（显式配置；不从 worker URL 推导端口）。**STANDARD** room/ticket/HTTP assigned **不得**出现 `voice_worker`（硬隔离）。
- 本地牌局 smoke（真实 Redis+CP+Worker+多客户端，**非公网**）：`godot/tools/e3_240_multiproc_smoke.sh`；声明 **网络端到端未验证**。

HTTP 错误体（ADR 逻辑包络）：`{"code":"...","message":"...","request_id":"..."}`。

## 令牌说明（实现摘要）

- 算法：HMAC-SHA256，线格式 `v1.<g|r>.<payload_b64url>.<sig_b64url>`
- 游客 TTL：24h；房间 TTL：2h（代码常量）
- 房间 payload 字段：`typ,room_id,seat,session_id,exp,round_kind,game_mode,participants`
- 展示名：`游客-` + guest_id 去连字符前 4 位大写 hex
- 密钥仅来自环境变量；日志与错误不得输出密钥或完整 token
- 跨语言 fixture：`go test ./internal/tokens -run TestExportCrossLangRoomTokenFixture` → `godot/tests/_fixtures/room_token_crosslang.json`

## 队列 / 房间 Redis 键（实现摘要）

按 `round_kind + game_mode` 隔离四个匹配池；guest 索引保证同组合 waiting 幂等。

| 键 | 类型 | 用途 |
|---|---|---|
| `cp:v1:casual:ticket:{id}` | Hash | ticket 字段（status / timestamps / 分配结果） |
| `cp:v1:casual:guest:{guest_id}:{round_kind}:{game_mode}` | String | 当前 waiting ticket_id |
| `cp:v1:casual:pool:{round_kind}:{game_mode}` | ZSet | 可消费匹配池（score=`queued_at` unix_ms） |
| `cp:v1:casual:room:{room_id}` | Hash | 临时房间与座位（`HUMAN`/`AI`） |

取消：`status=cancelled` + `ZREM` 出池 + 清理 guest 索引。
消费：peek 候选 → 预签全部 `room_token` → 单次 Lua 原子提交完整 assigned（含 token）；失败则不落库。

## 测试

```bash
export TOKEN_SIGNING_SECRET='dev-only-example-secret-32bytes!'
export WORKER_ENDPOINT='ws://127.0.0.1:9000'
export VOICE_WORKER_ENDPOINT='ws://127.0.0.1:9001'
export REDIS_ADDR=127.0.0.1:6379
# 先 compose up 真实 Redis；队列/匹配集成测试在 Redis 不可用时直接失败（不 Skip 冒充 Green）
go test ./...
go test -race ./...
go vet ./...
```

**网络端到端未验证**（无 Godot 客户端联调、无公网部署验收、无真实 Headless Worker 牌局）。
