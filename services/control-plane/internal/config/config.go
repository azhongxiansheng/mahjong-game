package config

import (
	"fmt"
	"os"
	"strconv"
	"strings"
)

const minTokenSigningSecretLen = 32

// Config 为 Control Plane 进程配置（仅环境变量入口）。
type Config struct {
	HTTPAddr           string
	RedisAddr          string
	RedisPassword      string
	RedisDB            int
	TokenSigningSecret string
	// WorkerEndpoint 为 #239 最小静态过渡契约（匹配结果中的 Worker 地址）。
	// 不实现 Worker 注册/续租/容量（#256）。
	WorkerEndpoint string
}

// Load 从环境变量读取配置；空值使用计划冻结的默认值。
// TOKEN_SIGNING_SECRET 必填且长度 >= 32；缺失/空/过短时稳定失败。
// WORKER_ENDPOINT 必填且 trim 后非空；缺失/空白时稳定失败。
// 错误文案不得回显密钥或 token。
func Load() (Config, error) {
	cfg := Config{
		HTTPAddr:      envOr("HTTP_ADDR", ":8081"),
		RedisAddr:     envOr("REDIS_ADDR", "127.0.0.1:6379"),
		RedisPassword: os.Getenv("REDIS_PASSWORD"),
		RedisDB:       0,
	}

	if raw := os.Getenv("REDIS_DB"); raw != "" {
		db, err := strconv.Atoi(raw)
		if err != nil {
			return Config{}, fmt.Errorf("invalid REDIS_DB %q: %w", raw, err)
		}
		cfg.RedisDB = db
	}

	secret := os.Getenv("TOKEN_SIGNING_SECRET")
	if secret == "" {
		return Config{}, fmt.Errorf("TOKEN_SIGNING_SECRET is required")
	}
	if len(secret) < minTokenSigningSecretLen {
		return Config{}, fmt.Errorf("TOKEN_SIGNING_SECRET must be at least %d bytes", minTokenSigningSecretLen)
	}
	cfg.TokenSigningSecret = secret

	worker := strings.TrimSpace(os.Getenv("WORKER_ENDPOINT"))
	if worker == "" {
		return Config{}, fmt.Errorf("WORKER_ENDPOINT is required")
	}
	cfg.WorkerEndpoint = worker

	return cfg, nil
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
