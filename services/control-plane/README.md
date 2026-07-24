# Control Plane（E3 匹配控制面）

独立 Go module：配置入口、探针、游客会话签发、房间令牌内部服务。

**网络端到端未验证。** 本目录尚未实现公共队列 / Worker / 业务 WebSocket（#238–#242）。

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

HTTP 错误体（ADR 逻辑包络）：`{"code":"...","message":"...","request_id":"..."}`。

房间令牌：仅 Control Plane **内部** API（`tokens.IssueRoomToken` / `VerifyRoomToken`），无独立 HTTP 端点；供 #238 队列分配调用。游客 `session_token` 不可直接当房间令牌。

## 令牌说明（实现摘要）

- 算法：HMAC-SHA256，线格式 `v1.<g|r>.<payload_b64url>.<sig_b64url>`
- 游客 TTL：24h；房间 TTL：2h（代码常量）
- 展示名：`游客-` + guest_id 去连字符前 4 位大写 hex
- 密钥仅来自环境变量；日志与错误不得输出密钥或完整 token

## 测试

```bash
export TOKEN_SIGNING_SECRET='dev-only-example-secret-32bytes!'
go test ./...
go test -race ./...
go vet ./...
# 真实 Redis 集成：先 compose up，再
REDIS_ADDR=127.0.0.1:6379 go test ./internal/redisx -count=1
```
