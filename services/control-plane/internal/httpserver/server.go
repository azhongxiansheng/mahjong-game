package httpserver

import (
	"context"
	"crypto/rand"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"time"

	"github.com/lov-team/mahjong-game/services/control-plane/internal/tokens"
)

// Pinger 抽象 Redis 依赖探测，便于单测注入。
type Pinger interface {
	Ping(ctx context.Context) error
}

// TokenService 游客会话与房间令牌能力（房间签发/校验供 #238/#240 使用，本 Issue 仅 HTTP 暴露 guest）。
type TokenService interface {
	IssueGuestSession() (tokens.GuestSession, error)
	VerifyGuestToken(token string) (tokens.GuestClaims, error)
	IssueRoomToken(sessionID, roomID string, seat int, roundKind, gameMode string, participants, characterIDs []string) (string, time.Time, error)
	VerifyRoomToken(token, expectedRoomID string, expectedSeat int) (tokens.RoomClaims, error)
}

// Config 构造 HTTP 服务器。
type Config struct {
	Addr         string
	Pinger       Pinger
	TokenService TokenService
	CasualQueue  CasualQueue
	// WorkerRegistry #256 内部注册/续租。
	WorkerRegistry WorkerRegistrar
	// WorkerRegistrationToken 独立注册 token；不得等于 TOKEN_SIGNING_SECRET。
	WorkerRegistrationToken string
}

// Server 提供探针、游客会话与公共休闲队列 HTTP，并支持优雅关闭。
type Server struct {
	httpServer     *http.Server
	pinger         Pinger
	tokenService   TokenService
	casualQueue    CasualQueue
	workerRegistry WorkerRegistrar
	workerRegToken string
}

// New 创建服务器（尚未监听）。
func New(cfg Config) *Server {
	s := &Server{
		pinger:         cfg.Pinger,
		tokenService:   cfg.TokenService,
		casualQueue:    cfg.CasualQueue,
		workerRegistry: cfg.WorkerRegistry,
		workerRegToken: cfg.WorkerRegistrationToken,
	}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", s.handleHealthz)
	mux.HandleFunc("GET /readyz", s.handleReadyz)
	mux.HandleFunc("POST /v1/guest-sessions", s.handleCreateGuestSession)
	mux.HandleFunc("/v1/guest-sessions", s.handleGuestSessionsFallback)
	mux.HandleFunc("POST /v1/queues/casual", s.handleEnqueueCasual)
	mux.HandleFunc("/v1/queues/casual", s.handleCasualQueueCollectionFallback)
	mux.HandleFunc("GET /v1/queues/casual/{ticket_id}", s.handleGetCasualTicket)
	mux.HandleFunc("DELETE /v1/queues/casual/{ticket_id}", s.handleCancelCasualTicket)
	mux.HandleFunc("/v1/queues/casual/{ticket_id}", s.handleCasualTicketFallback)
	mux.HandleFunc("POST /v1/internal/workers/register", s.handleRegisterWorker)
	mux.HandleFunc("/v1/internal/workers/register", s.handleWorkersFallback)
	mux.HandleFunc("POST /v1/internal/workers/rooms/complete", s.handleCompleteWorkerRoom)
	mux.HandleFunc("/v1/internal/workers/rooms/complete", s.handleCompleteRoomFallback)
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

func (s *Server) handleCreateGuestSession(w http.ResponseWriter, r *http.Request) {
	if s.tokenService == nil {
		writeError(w, r, http.StatusInternalServerError, "INTERNAL", "token service unavailable")
		return
	}
	sess, err := s.tokenService.IssueGuestSession()
	if err != nil {
		writeError(w, r, http.StatusInternalServerError, "INTERNAL", "failed to issue guest session")
		return
	}
	writeJSON(w, http.StatusCreated, guestSessionBody{
		GuestID:      sess.GuestID,
		DisplayName:  sess.DisplayName,
		SessionToken: sess.SessionToken,
		ExpiresAt:    sess.ExpiresAt.UTC().Format(time.RFC3339),
	})
}

// handleGuestSessionsFallback 捕获非 POST 方法，返回 ADR 风格错误包络。
func (s *Server) handleGuestSessionsFallback(w http.ResponseWriter, r *http.Request) {
	if r.Method == http.MethodPost {
		// 已由方法路由处理；兜底不应到达。
		s.handleCreateGuestSession(w, r)
		return
	}
	w.Header().Set("Allow", http.MethodPost)
	writeError(w, r, http.StatusMethodNotAllowed, "METHOD_NOT_ALLOWED", "method not allowed")
}

type healthBody struct {
	Status string `json:"status"`
}

type readyBody struct {
	Status string `json:"status"`
	Reason string `json:"reason,omitempty"`
}

type guestSessionBody struct {
	GuestID      string `json:"guest_id"`
	DisplayName  string `json:"display_name"`
	SessionToken string `json:"session_token"`
	ExpiresAt    string `json:"expires_at"`
}

type errorBody struct {
	Code      string `json:"code"`
	Message   string `json:"message"`
	RequestID string `json:"request_id"`
}

func writeJSON(w http.ResponseWriter, code int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(payload)
}

func writeError(w http.ResponseWriter, r *http.Request, status int, code, message string) {
	reqID := r.Header.Get("X-Request-ID")
	if reqID == "" {
		reqID = newRequestID()
	}
	writeJSON(w, status, errorBody{
		Code:      code,
		Message:   message,
		RequestID: reqID,
	})
}

func newRequestID() string {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		return fmt.Sprintf("req_%d", time.Now().UnixNano())
	}
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	return fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:16])
}
