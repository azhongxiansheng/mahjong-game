# Control Plane（E3 匹配控制面）

独立 Go module：配置入口、探针、游客会话签发、房间令牌内部服务、**公共休闲队列**（加入 / 查询 / 取消）。

**网络端到端未验证。** 本目录尚未实现 30 秒 AI 补位消费、房间创建、Worker 注册或业务 WebSocket（#239–#242）。公共队列仅建立 ticket / 匹配池 / 取消与 `queued_at`/`deadline_at` 契约。

## 环境变量

| 变量 | 默认 | 说明 |
|---|---|---|
| `HTTP_ADDR` | `:8081` | HTTP 监听地址 |
| `REDIS_ADDR` | `127.0.0.1:6379` | Redis 地址 |
| `REDIS_PASSWORD` | （空） | Redis 密码 |
| `REDIS_DB` | `0` | Redis DB 编号 |
| `TOKEN_SIGNING_SECRET` | **必填** | HMAC 签名密钥，长度 ≥ 32；缺失/过短时进程拒绝启动。**勿提交真实密钥** |

## 一条命令启动本地 Redis

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

## 启动 Control Plane

```bash
export HTTP_ADDR=:8081
export REDIS_ADDR=127.0.0.1:6379
# 本地开发示例密钥（仅示例，生产请使用独立强随机密钥，切勿提交真实密钥）
export TOKEN_SIGNING_SECRET='dev-only-example-secret-32bytes!'
go run ./cmd/control-plane
```

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

### 公共休闲队列（#238）

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
# deadline_at = queued_at + 30s（契约字段；本 Issue 不消费）

# 查询（仅 ticket 所属游客；status=waiting|cancelled）
curl -sS "http://127.0.0.1:8081/v1/queues/casual/$TICKET_ID" \
  -H "Authorization: Bearer $TOKEN"

# 取消（幂等；原子移出匹配池，ticket 不再可被未来分配消费，仍可查 cancelled）
curl -sS -X DELETE "http://127.0.0.1:8081/v1/queues/casual/$TICKET_ID" \
  -H "Authorization: Bearer $TOKEN"
```

HTTP 错误体（ADR 逻辑包络）：`{"code":"...","message":"...","request_id":"..."}`。

房间令牌：仅 Control Plane **内部** API（`tokens.IssueRoomToken` / `VerifyRoomToken`），无独立 HTTP 端点；供后续 #239 队列分配调用。游客 `session_token` 不可直接当房间令牌。

## 令牌说明（实现摘要）

- 算法：HMAC-SHA256，线格式 `v1.<g|r>.<payload_b64url>.<sig_b64url>`
- 游客 TTL：24h；房间 TTL：2h（代码常量）
- 展示名：`游客-` + guest_id 去连字符前 4 位大写 hex
- 密钥仅来自环境变量；日志与错误不得输出密钥或完整 token

## 队列 Redis 键（实现摘要）

按 `round_kind + game_mode` 隔离四个匹配池；guest 索引保证同组合 waiting 幂等。

| 键 | 类型 | 用途 |
|---|---|---|
| `cp:v1:casual:ticket:{id}` | Hash | ticket 字段（含 status / timestamps） |
| `cp:v1:casual:guest:{guest_id}:{round_kind}:{game_mode}` | String | 当前 waiting ticket_id |
| `cp:v1:casual:pool:{round_kind}:{game_mode}` | ZSet | 可消费匹配池（score=`queued_at` unix） |

取消：`status=cancelled` + `ZREM` 出池 + 清理 guest 索引。本 Issue **不**实现池消费 / 开房。

## 测试

```bash
export TOKEN_SIGNING_SECRET='dev-only-example-secret-32bytes!'
export REDIS_ADDR=127.0.0.1:6379
# 先 compose up 真实 Redis；队列集成测试在 Redis 不可用时直接失败（不 Skip 冒充 Green）
go test ./...
go test -race ./...
go vet ./...
```

**网络端到端未验证**（无 Godot 客户端联调、无公网部署验收）。
