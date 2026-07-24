package redisx

import (
	"context"
	"os"
	"testing"
	"time"
)

// 真实 Redis 集成测试：需要环境变量 REDIS_ADDR（或默认 127.0.0.1:6379）上有可连通实例。
// 无 Redis 时 Skip，不算 Green 证据；本地 smoke 必须在 compose 起 Redis 后跑通。
func TestClient_PingRealRedis(t *testing.T) {
	addr := os.Getenv("REDIS_ADDR")
	if addr == "" {
		addr = "127.0.0.1:6379"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	c, err := New(Options{
		Addr:     addr,
		Password: os.Getenv("REDIS_PASSWORD"),
		DB:       0,
	})
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	defer c.Close()

	if err := c.Ping(ctx); err != nil {
		t.Skipf("真实 Redis 不可用（addr=%s）: %v；请先 docker compose up 后再跑", addr, err)
	}
}

func TestClient_PingFailsOnBadAddr(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 500*time.Millisecond)
	defer cancel()

	c, err := New(Options{
		Addr: "127.0.0.1:1", // 几乎必然拒绝连接
	})
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	defer c.Close()

	if err := c.Ping(ctx); err == nil {
		t.Fatal("Ping expected error on bad addr, got nil")
	}
}
