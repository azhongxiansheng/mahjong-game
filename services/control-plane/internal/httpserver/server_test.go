package httpserver

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net"
	"net/http"
	"testing"
	"time"
)

type stubPinger struct {
	err error
}

func (s stubPinger) Ping(ctx context.Context) error {
	return s.err
}

func TestHealthz_OKWithoutRedis(t *testing.T) {
	srv := New(Config{
		Addr:   "127.0.0.1:0",
		Pinger: stubPinger{err: errors.New("redis down")},
	})
	baseURL := startServer(t, srv)
	defer shutdownServer(t, srv)

	resp, body := doGET(t, baseURL+"/healthz")
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, want 200; body=%s", resp.StatusCode, body)
	}
	assertJSONStatus(t, body, "ok")
}

func TestReadyz_OKWhenRedisPings(t *testing.T) {
	srv := New(Config{
		Addr:   "127.0.0.1:0",
		Pinger: stubPinger{err: nil},
	})
	baseURL := startServer(t, srv)
	defer shutdownServer(t, srv)

	resp, body := doGET(t, baseURL+"/readyz")
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, want 200; body=%s", resp.StatusCode, body)
	}
	assertJSONStatus(t, body, "ready")
}

func TestReadyz_NotReadyWhenRedisFails(t *testing.T) {
	srv := New(Config{
		Addr:   "127.0.0.1:0",
		Pinger: stubPinger{err: errors.New("connection refused")},
	})
	baseURL := startServer(t, srv)
	defer shutdownServer(t, srv)

	resp, body := doGET(t, baseURL+"/readyz")
	defer resp.Body.Close()

	if resp.StatusCode < 400 || resp.StatusCode > 599 {
		t.Fatalf("status = %d, want non-2xx; body=%s", resp.StatusCode, body)
	}
	if resp.StatusCode == http.StatusOK {
		t.Fatalf("status must not be 200 when redis fails; body=%s", body)
	}

	var payload map[string]string
	if err := json.Unmarshal([]byte(body), &payload); err != nil {
		t.Fatalf("json decode: %v body=%s", err, body)
	}
	if payload["status"] != "not_ready" {
		t.Fatalf("status field = %q, want not_ready", payload["status"])
	}
	if payload["reason"] != "redis" {
		t.Fatalf("reason = %q, want redis", payload["reason"])
	}
}

func TestGracefulShutdown(t *testing.T) {
	srv := New(Config{
		Addr:   "127.0.0.1:0",
		Pinger: stubPinger{},
	})
	baseURL := startServer(t, srv)

	resp, _ := doGET(t, baseURL+"/healthz")
	resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("pre-shutdown health status = %d", resp.StatusCode)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		t.Fatalf("Shutdown: %v", err)
	}

	// 关闭后请求应失败（连接拒绝或无法建立）
	client := &http.Client{Timeout: 500 * time.Millisecond}
	_, err := client.Get(baseURL + "/healthz")
	if err == nil {
		t.Fatal("expected error after shutdown, got nil")
	}
}

func startServer(t *testing.T, srv *Server) string {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	addr := ln.Addr().String()
	errCh := make(chan error, 1)
	go func() {
		errCh <- srv.Serve(ln)
	}()
	t.Cleanup(func() {
		// 若测试未显式 Shutdown，清理时关闭
		_ = srv.Shutdown(context.Background())
		if err := <-errCh; err != nil && !errors.Is(err, http.ErrServerClosed) {
			t.Logf("Serve exit: %v", err)
		}
	})

	// 等待可连
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		conn, err := net.DialTimeout("tcp", addr, 50*time.Millisecond)
		if err == nil {
			_ = conn.Close()
			return "http://" + addr
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatalf("server did not become ready on %s", addr)
	return ""
}

func shutdownServer(t *testing.T, srv *Server) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		t.Fatalf("Shutdown: %v", err)
	}
}

func doGET(t *testing.T, url string) (*http.Response, string) {
	t.Helper()
	resp, err := http.Get(url)
	if err != nil {
		t.Fatalf("GET %s: %v", url, err)
	}
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatalf("read body: %v", err)
	}
	return resp, string(body)
}

func assertJSONStatus(t *testing.T, body, want string) {
	t.Helper()
	var payload map[string]string
	if err := json.Unmarshal([]byte(body), &payload); err != nil {
		t.Fatalf("json decode: %v body=%s", err, body)
	}
	if payload["status"] != want {
		t.Fatalf("status = %q, want %q; body=%s", payload["status"], want, body)
	}
}
