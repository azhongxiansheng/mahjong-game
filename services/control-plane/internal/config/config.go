package config

import (
	"fmt"
	"os"
	"strconv"
)

// Config 为 Control Plane 进程配置（仅环境变量入口）。
type Config struct {
	HTTPAddr      string
	RedisAddr     string
	RedisPassword string
	RedisDB       int
}

// Load 从环境变量读取配置；空值使用计划冻结的默认值。
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

	return cfg, nil
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
