package config

import (
	"testing"
)

func TestLoad_Defaults(t *testing.T) {
	t.Setenv("HTTP_ADDR", "")
	t.Setenv("REDIS_ADDR", "")
	t.Setenv("REDIS_PASSWORD", "")
	t.Setenv("REDIS_DB", "")

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
}

func TestLoad_FromEnv(t *testing.T) {
	t.Setenv("HTTP_ADDR", ":9090")
	t.Setenv("REDIS_ADDR", "10.0.0.2:6380")
	t.Setenv("REDIS_PASSWORD", "secret")
	t.Setenv("REDIS_DB", "3")

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
}

func TestLoad_InvalidRedisDB(t *testing.T) {
	t.Setenv("REDIS_DB", "not-a-number")

	_, err := Load()
	if err == nil {
		t.Fatal("Load() expected error for invalid REDIS_DB, got nil")
	}
}
