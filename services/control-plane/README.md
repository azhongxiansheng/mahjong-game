# Control Plane（E3-01 骨架）

独立 Go module：配置入口、`GET /healthz`、真实 Redis 依赖的 `GET /readyz`、优雅关闭。

**网络端到端未验证。** 本目录不实现游客/队列/Worker/业务 WebSocket（#237–#242）。

## 环境变量

| 变量 | 默认 | 说明 |
|---|---|---|
| `HTTP_ADDR` | `:8081` | HTTP 监听地址 |
| `REDIS_ADDR` | `127.0.0.1:6379` | Redis 地址 |
| `REDIS_PASSWORD` | （空） | Redis 密码 |
| `REDIS_DB` | `0` | Redis DB 编号 |

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
go run ./cmd/control-plane
```

探针：

```bash
curl -sS http://127.0.0.1:8081/healthz   # 进程存活，200 {"status":"ok"}
curl -sS http://127.0.0.1:8081/readyz    # Redis 可用时 200 {"status":"ready"}
# Redis 停止后 /readyz 返回 503 {"status":"not_ready","reason":"redis"}
```

## 测试

```bash
go test ./...
# 真实 Redis 集成：先 compose up，再
REDIS_ADDR=127.0.0.1:6379 go test ./internal/redisx -count=1
```
