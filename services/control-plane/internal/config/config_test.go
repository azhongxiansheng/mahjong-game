package config

import (
	"strings"
	"testing"
)

const validSigningSecret = "0123456789abcdef0123456789abcdef" // 32 bytes

func TestLoad_Defaults(t *testing.T) {
	t.Setenv("HTTP_ADDR", "")
	t.Setenv("REDIS_ADDR", "")
	t.Setenv("REDIS_PASSWORD", "")
	t.Setenv("REDIS_DB", "")
	t.Setenv("TOKEN_SIGNING_SECRET", validSigningSecret)
	t.Setenv("WORKER_ENDPOINT", "ws://127.0.0.1:9000")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load() unexpected error: %v", err)
	}
	if cfg.HTTPAddr != ":8081" {
		t.Fatalf("HTTPAddr = %q, want :8081", cfg.HTTPAddr)
	}
	if cfg.RedisAddr != "127.0.0.1:6379" {
		t.Fatalf("RedisAddr = %q, want 127.0.0.1:6379", cfg.RedisAddr)
	}
	if cfg.RedisPassword != "" {
		t.Fatalf("RedisPassword = %q, want empty", cfg.RedisPassword)
	}
	if cfg.RedisDB != 0 {
		t.Fatalf("RedisDB = %d, want 0", cfg.RedisDB)
	}
	if cfg.TokenSigningSecret != validSigningSecret {
		t.Fatalf("TokenSigningSecret mismatch")
	}
	if cfg.WorkerEndpoint != "ws://127.0.0.1:9000" {
		t.Fatalf("WorkerEndpoint = %q", cfg.WorkerEndpoint)
	}
}

func TestLoad_FromEnv(t *testing.T) {
	t.Setenv("HTTP_ADDR", ":9090")
	t.Setenv("REDIS_ADDR", "10.0.0.2:6380")
	t.Setenv("REDIS_PASSWORD", "secret")
	t.Setenv("REDIS_DB", "3")
	t.Setenv("TOKEN_SIGNING_SECRET", validSigningSecret)
	t.Setenv("WORKER_ENDPOINT", "  ws://worker.example:9000  ")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load() unexpected error: %v", err)
	}
	if cfg.HTTPAddr != ":9090" {
		t.Fatalf("HTTPAddr = %q, want :9090", cfg.HTTPAddr)
	}
	if cfg.RedisAddr != "10.0.0.2:6380" {
		t.Fatalf("RedisAddr = %q, want 10.0.0.2:6380", cfg.RedisAddr)
	}
	if cfg.RedisPassword != "secret" {
		t.Fatalf("RedisPassword = %q, want secret", cfg.RedisPassword)
	}
	if cfg.RedisDB != 3 {
		t.Fatalf("RedisDB = %d, want 3", cfg.RedisDB)
	}
	if cfg.TokenSigningSecret != validSigningSecret {
		t.Fatalf("TokenSigningSecret mismatch")
	}
	if cfg.WorkerEndpoint != "ws://worker.example:9000" {
		t.Fatalf("WorkerEndpoint = %q (should be trimmed)", cfg.WorkerEndpoint)
	}
}

func TestLoad_InvalidRedisDB(t *testing.T) {
	t.Setenv("TOKEN_SIGNING_SECRET", validSigningSecret)
	t.Setenv("WORKER_ENDPOINT", "ws://127.0.0.1:9000")
	t.Setenv("REDIS_DB", "not-a-number")

	_, err := Load()
	if err == nil {
		t.Fatal("Load() expected error for invalid REDIS_DB, got nil")
	}
}

func TestLoad_MissingTokenSigningSecret(t *testing.T) {
	t.Setenv("TOKEN_SIGNING_SECRET", "")
	t.Setenv("WORKER_ENDPOINT", "ws://127.0.0.1:9000")
	_, err := Load()
	if err == nil {
		t.Fatal("Load() expected error for missing TOKEN_SIGNING_SECRET")
	}
	if !strings.Contains(err.Error(), "TOKEN_SIGNING_SECRET") {
		t.Fatalf("error should mention TOKEN_SIGNING_SECRET: %v", err)
	}
	// Must not echo a real secret value (empty path has nothing to leak).
	if strings.Contains(err.Error(), validSigningSecret) {
		t.Fatal("error must not contain a signing secret value")
	}
}

func TestLoad_ShortTokenSigningSecret(t *testing.T) {
	t.Setenv("TOKEN_SIGNING_SECRET", "too-short-secret-value!!") // 24 chars
	t.Setenv("WORKER_ENDPOINT", "ws://127.0.0.1:9000")
	_, err := Load()
	if err == nil {
		t.Fatal("Load() expected error for short TOKEN_SIGNING_SECRET")
	}
	if strings.Contains(err.Error(), "too-short-secret-value!!") {
		t.Fatal("error must not echo the provided secret")
	}
}

func TestLoad_MissingWorkerEndpoint(t *testing.T) {
	t.Setenv("TOKEN_SIGNING_SECRET", validSigningSecret)
	t.Setenv("WORKER_ENDPOINT", "")
	_, err := Load()
	if err == nil {
		t.Fatal("Load() expected error for missing WORKER_ENDPOINT")
	}
	if !strings.Contains(err.Error(), "WORKER_ENDPOINT") {
		t.Fatalf("error should mention WORKER_ENDPOINT: %v", err)
	}
	if strings.Contains(err.Error(), validSigningSecret) {
		t.Fatal("error must not contain signing secret")
	}
}

func TestLoad_BlankWorkerEndpoint(t *testing.T) {
	t.Setenv("TOKEN_SIGNING_SECRET", validSigningSecret)
	t.Setenv("WORKER_ENDPOINT", "   \t  ")
	_, err := Load()
	if err == nil {
		t.Fatal("Load() expected error for blank WORKER_ENDPOINT")
	}
	if !strings.Contains(err.Error(), "WORKER_ENDPOINT") {
		t.Fatalf("error should mention WORKER_ENDPOINT: %v", err)
	}
	if strings.Contains(err.Error(), validSigningSecret) {
		t.Fatal("error must not contain signing secret")
	}
}
