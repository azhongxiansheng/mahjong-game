package config

import (
	"strings"
	"testing"
	"time"
)

const validSigningSecret = "0123456789abcdef0123456789abcdef" // 32 bytes
const validWorkerRegToken = "worker-reg-token-16"             // 19 bytes

func TestLoad_Defaults(t *testing.T) {
	t.Setenv("HTTP_ADDR", "")
	t.Setenv("REDIS_ADDR", "")
	t.Setenv("REDIS_PASSWORD", "")
	t.Setenv("REDIS_DB", "")
	t.Setenv("TOKEN_SIGNING_SECRET", validSigningSecret)
	t.Setenv("WORKER_REGISTRATION_TOKEN", validWorkerRegToken)
	t.Setenv("WORKER_ENDPOINT", "")
	t.Setenv("VOICE_WORKER_ENDPOINT", "")
	t.Setenv("WORKER_LEASE_TTL_SEC", "")
	t.Setenv("WORKER_REAP_INTERVAL_MS", "")

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
	if cfg.TokenSigningSecret != validSigningSecret {
		t.Fatalf("TokenSigningSecret mismatch")
	}
	if cfg.WorkerRegistrationToken != validWorkerRegToken {
		t.Fatalf("WorkerRegistrationToken mismatch")
	}
	if cfg.WorkerLeaseTTL != 15*time.Second {
		t.Fatalf("WorkerLeaseTTL=%v", cfg.WorkerLeaseTTL)
	}
	if cfg.WorkerReapInterval != time.Second {
		t.Fatalf("WorkerReapInterval=%v", cfg.WorkerReapInterval)
	}
	if cfg.WorkerEndpoint != "" || cfg.VoiceWorkerEndpoint != "" {
		t.Fatalf("optional static endpoints should be empty by default")
	}
}

func TestLoad_FromEnv(t *testing.T) {
	t.Setenv("HTTP_ADDR", ":9090")
	t.Setenv("REDIS_ADDR", "10.0.0.2:6380")
	t.Setenv("REDIS_PASSWORD", "secret")
	t.Setenv("REDIS_DB", "3")
	t.Setenv("TOKEN_SIGNING_SECRET", validSigningSecret)
	t.Setenv("WORKER_REGISTRATION_TOKEN", validWorkerRegToken)
	t.Setenv("WORKER_ENDPOINT", "  ws://worker.example:9000  ")
	t.Setenv("VOICE_WORKER_ENDPOINT", "  ws://voice.example:9001  ")
	t.Setenv("WORKER_LEASE_TTL_SEC", "20")
	t.Setenv("WORKER_REAP_INTERVAL_MS", "500")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load() unexpected error: %v", err)
	}
	if cfg.HTTPAddr != ":9090" {
		t.Fatalf("HTTPAddr = %q, want :9090", cfg.HTTPAddr)
	}
	if cfg.WorkerEndpoint != "ws://worker.example:9000" {
		t.Fatalf("WorkerEndpoint = %q (should be trimmed)", cfg.WorkerEndpoint)
	}
	if cfg.VoiceWorkerEndpoint != "ws://voice.example:9001" {
		t.Fatalf("VoiceWorkerEndpoint = %q (should be trimmed)", cfg.VoiceWorkerEndpoint)
	}
	if cfg.WorkerLeaseTTL != 20*time.Second {
		t.Fatalf("lease ttl=%v", cfg.WorkerLeaseTTL)
	}
	if cfg.WorkerReapInterval != 500*time.Millisecond {
		t.Fatalf("reap interval=%v", cfg.WorkerReapInterval)
	}
}

func TestLoad_MissingWorkerRegistrationToken(t *testing.T) {
	t.Setenv("TOKEN_SIGNING_SECRET", validSigningSecret)
	t.Setenv("WORKER_REGISTRATION_TOKEN", "")
	_, err := Load()
	if err == nil {
		t.Fatal("expected error for missing WORKER_REGISTRATION_TOKEN")
	}
	if !strings.Contains(err.Error(), "WORKER_REGISTRATION_TOKEN") {
		t.Fatalf("error should mention WORKER_REGISTRATION_TOKEN: %v", err)
	}
	if strings.Contains(err.Error(), validSigningSecret) {
		t.Fatal("error must not contain signing secret")
	}
}

func TestLoad_WorkerTokenMustNotEqualSigningSecret(t *testing.T) {
	t.Setenv("TOKEN_SIGNING_SECRET", validSigningSecret)
	t.Setenv("WORKER_REGISTRATION_TOKEN", validSigningSecret)
	_, err := Load()
	if err == nil {
		t.Fatal("expected error when registration token equals signing secret")
	}
	if strings.Contains(err.Error(), validSigningSecret) {
		t.Fatal("error must not echo secrets")
	}
}

func TestLoad_MissingTokenSigningSecret(t *testing.T) {
	t.Setenv("TOKEN_SIGNING_SECRET", "")
	t.Setenv("WORKER_REGISTRATION_TOKEN", validWorkerRegToken)
	_, err := Load()
	if err == nil {
		t.Fatal("Load() expected error for missing TOKEN_SIGNING_SECRET")
	}
}

func TestLoad_ShortTokenSigningSecret(t *testing.T) {
	t.Setenv("TOKEN_SIGNING_SECRET", "too-short-secret-value!!")
	t.Setenv("WORKER_REGISTRATION_TOKEN", validWorkerRegToken)
	_, err := Load()
	if err == nil {
		t.Fatal("Load() expected error for short TOKEN_SIGNING_SECRET")
	}
	if strings.Contains(err.Error(), "too-short-secret-value!!") {
		t.Fatal("error must not echo the provided secret")
	}
}

func TestLoad_InvalidRedisDB(t *testing.T) {
	t.Setenv("TOKEN_SIGNING_SECRET", validSigningSecret)
	t.Setenv("WORKER_REGISTRATION_TOKEN", validWorkerRegToken)
	t.Setenv("REDIS_DB", "not-a-number")
	_, err := Load()
	if err == nil {
		t.Fatal("Load() expected error for invalid REDIS_DB, got nil")
	}
}

func TestLoad_StaticWorkerEndpointsOptional(t *testing.T) {
	t.Setenv("TOKEN_SIGNING_SECRET", validSigningSecret)
	t.Setenv("WORKER_REGISTRATION_TOKEN", validWorkerRegToken)
	t.Setenv("WORKER_ENDPOINT", "")
	t.Setenv("VOICE_WORKER_ENDPOINT", "")
	if _, err := Load(); err != nil {
		t.Fatalf("static endpoints must be optional: %v", err)
	}
}
