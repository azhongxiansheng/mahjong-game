package config

import (
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"
)

const minTokenSigningSecretLen = 32
const minWorkerRegistrationTokenLen = 16

// Config 为 Control Plane 进程配置（仅环境变量入口）。
type Config struct {
	HTTPAddr           string
	RedisAddr          string
	RedisPassword      string
	RedisDB            int
	TokenSigningSecret string
	// WorkerRegistrationToken 内部 Worker 注册/续租专用；禁止复用 TokenSigningSecret。
	WorkerRegistrationToken string
	// WorkerLeaseTTL 注册租约时长（安全默认 15s）。
	WorkerLeaseTTL time.Duration
	// WorkerReapInterval 失联回收扫描间隔（安全默认 1s）。
	WorkerReapInterval time.Duration
	// WorkerEndpoint / VoiceWorkerEndpoint 为 #239 遗留可选配置，不再驱动匹配。
	// 生产匹配仅使用已注册且租约有效、有容量的 Worker。
	WorkerEndpoint      string
	VoiceWorkerEndpoint string
}

// Load 从环境变量读取配置；空值使用计划冻结的默认值。
// TOKEN_SIGNING_SECRET 必填且长度 >= 32。
// WORKER_REGISTRATION_TOKEN 必填且长度 >= 16，且不得与 TOKEN_SIGNING_SECRET 相同。
// WORKER_ENDPOINT / VOICE_WORKER_ENDPOINT 可选（兼容读入）；匹配不依赖它们。
// 错误文案不得回显密钥或 token。
func Load() (Config, error) {
	cfg := Config{
		HTTPAddr:           envOr("HTTP_ADDR", ":8081"),
		RedisAddr:          envOr("REDIS_ADDR", "127.0.0.1:6379"),
		RedisPassword:      os.Getenv("REDIS_PASSWORD"),
		RedisDB:            0,
		WorkerLeaseTTL:     15 * time.Second,
		WorkerReapInterval: 1 * time.Second,
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

	regTok := os.Getenv("WORKER_REGISTRATION_TOKEN")
	if regTok == "" {
		return Config{}, fmt.Errorf("WORKER_REGISTRATION_TOKEN is required")
	}
	if len(regTok) < minWorkerRegistrationTokenLen {
		return Config{}, fmt.Errorf("WORKER_REGISTRATION_TOKEN must be at least %d bytes", minWorkerRegistrationTokenLen)
	}
	if regTok == secret {
		return Config{}, fmt.Errorf("WORKER_REGISTRATION_TOKEN must not equal TOKEN_SIGNING_SECRET")
	}
	cfg.WorkerRegistrationToken = regTok

	if raw := strings.TrimSpace(os.Getenv("WORKER_LEASE_TTL_SEC")); raw != "" {
		sec, err := strconv.Atoi(raw)
		if err != nil || sec < 1 {
			return Config{}, fmt.Errorf("invalid WORKER_LEASE_TTL_SEC")
		}
		cfg.WorkerLeaseTTL = time.Duration(sec) * time.Second
	}
	if raw := strings.TrimSpace(os.Getenv("WORKER_REAP_INTERVAL_MS")); raw != "" {
		ms, err := strconv.Atoi(raw)
		if err != nil || ms < 50 {
			return Config{}, fmt.Errorf("invalid WORKER_REAP_INTERVAL_MS")
		}
		cfg.WorkerReapInterval = time.Duration(ms) * time.Millisecond
	}

	// 可选遗留：读入但不用于匹配权威路径。
	cfg.WorkerEndpoint = strings.TrimSpace(os.Getenv("WORKER_ENDPOINT"))
	cfg.VoiceWorkerEndpoint = strings.TrimSpace(os.Getenv("VOICE_WORKER_ENDPOINT"))

	return cfg, nil
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
