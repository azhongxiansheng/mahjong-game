package httpserver

import (
	"context"
	"encoding/json"
	"net"
	"net/http"
	"time"
)

// Pinger 抽象 Redis 依赖探测，便于单测注入。
type Pinger interface {
	Ping(ctx context.Context) error
}

// Config 构造 HTTP 服务器。
type Config struct {
	Addr   string
	Pinger Pinger
}

// Server 提供 /healthz 与 /readyz，并支持优雅关闭。
type Server struct {
	httpServer *http.Server
	pinger     Pinger
}

// New 创建服务器（尚未监听）。
func New(cfg Config) *Server {
	s := &Server{pinger: cfg.Pinger}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", s.handleHealthz)
	mux.HandleFunc("GET /readyz", s.handleReadyz)
	s.httpServer = &http.Server{
		Addr:              cfg.Addr,
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
	}
	return s
}

// ListenAndServe 在 Config.Addr 上阻塞服务。
func (s *Server) ListenAndServe() error {
	return s.httpServer.ListenAndServe()
}

// Serve 在已有 listener 上服务（测试用）。
func (s *Server) Serve(ln net.Listener) error {
	return s.httpServer.Serve(ln)
}

// Shutdown 优雅关闭。
func (s *Server) Shutdown(ctx context.Context) error {
	return s.httpServer.Shutdown(ctx)
}

func (s *Server) handleHealthz(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, healthBody{Status: "ok"})
}

func (s *Server) handleReadyz(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()

	if s.pinger == nil || s.pinger.Ping(ctx) != nil {
		writeJSON(w, http.StatusServiceUnavailable, readyBody{
			Status: "not_ready",
			Reason: "redis",
		})
		return
	}
	writeJSON(w, http.StatusOK, readyBody{Status: "ready"})
}

type healthBody struct {
	Status string `json:"status"`
}

type readyBody struct {
	Status string `json:"status"`
	Reason string `json:"reason,omitempty"`
}

func writeJSON(w http.ResponseWriter, code int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(payload)
}
