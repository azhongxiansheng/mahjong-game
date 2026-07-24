package httpserver

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/lov-team/mahjong-game/services/control-plane/internal/queue"
	"github.com/lov-team/mahjong-game/services/control-plane/internal/tokens"
)

const maxQueueBodyBytes = 1 << 20 // 1 MiB

// CasualQueue 公共休闲队列能力。
type CasualQueue interface {
	Enqueue(ctx context.Context, guestID string, rk queue.RoundKind, gm queue.GameMode) (queue.Ticket, error)
	Get(ctx context.Context, guestID, ticketID string) (queue.Ticket, error)
	Cancel(ctx context.Context, guestID, ticketID string) (queue.Ticket, error)
}

type enqueueRequest struct {
	RoundKind string `json:"round_kind"`
	GameMode  string `json:"game_mode"`
}

type ticketResponse struct {
	TicketID   string `json:"ticket_id"`
	RoundKind  string `json:"round_kind"`
	GameMode   string `json:"game_mode"`
	Status     string `json:"status"`
	QueuedAt   string `json:"queued_at"`
	DeadlineAt string `json:"deadline_at"`
	// assigned 时填充（ADR：Worker / room / seat / token）
	Worker    string `json:"worker,omitempty"`
	RoomID    string `json:"room_id,omitempty"`
	Seat      *int   `json:"seat,omitempty"`
	RoomToken string `json:"room_token,omitempty"`
}

func formatAPITime(t time.Time) string {
	t = t.UTC()
	if t.Nanosecond() == 0 {
		return t.Format("2006-01-02T15:04:05Z")
	}
	return t.Format("2006-01-02T15:04:05.000Z")
}

func ticketToResponse(tk queue.Ticket) ticketResponse {
	resp := ticketResponse{
		TicketID:   tk.TicketID,
		RoundKind:  string(tk.RoundKind),
		GameMode:   string(tk.GameMode),
		Status:     tk.Status,
		QueuedAt:   formatAPITime(tk.QueuedAt.Time()),
		DeadlineAt: formatAPITime(tk.DeadlineAt.Time()),
	}
	if tk.Status == queue.StatusAssigned {
		resp.Worker = tk.Worker
		resp.RoomID = tk.RoomID
		resp.RoomToken = tk.RoomToken
		if tk.HasSeat {
			seat := tk.Seat
			resp.Seat = &seat
		}
	}
	return resp
}

// handleCasualQueueCollectionFallback 捕获集合路径非 POST 方法，返回 ADR JSON 405。
func (s *Server) handleCasualQueueCollectionFallback(w http.ResponseWriter, r *http.Request) {
	if r.Method == http.MethodPost {
		s.handleEnqueueCasual(w, r)
		return
	}
	w.Header().Set("Allow", http.MethodPost)
	writeError(w, r, http.StatusMethodNotAllowed, "METHOD_NOT_ALLOWED", "method not allowed")
}

// handleCasualTicketFallback 捕获票据路径非 GET/DELETE 方法，返回 ADR JSON 405。
// Allow 字面量锁定为 "GET, DELETE"（单 Header.Set，与测试契约一致）。
func (s *Server) handleCasualTicketFallback(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		s.handleGetCasualTicket(w, r)
		return
	case http.MethodDelete:
		s.handleCancelCasualTicket(w, r)
		return
	}
	w.Header().Set("Allow", "GET, DELETE")
	writeError(w, r, http.StatusMethodNotAllowed, "METHOD_NOT_ALLOWED", "method not allowed")
}

func (s *Server) handleEnqueueCasual(w http.ResponseWriter, r *http.Request) {
	claims, ok := s.requireGuestAuth(w, r)
	if !ok {
		return
	}
	if s.casualQueue == nil {
		writeError(w, r, http.StatusInternalServerError, "INTERNAL", "queue service unavailable")
		return
	}

	var req enqueueRequest
	if err := decodeJSONBody(r, &req); err != nil {
		writeError(w, r, http.StatusBadRequest, "INVALID_REQUEST", "invalid request body")
		return
	}
	rk := queue.RoundKind(req.RoundKind)
	gm := queue.GameMode(req.GameMode)
	if err := queue.ValidateRules(rk, gm); err != nil {
		writeError(w, r, http.StatusBadRequest, "INVALID_REQUEST", "invalid round_kind or game_mode")
		return
	}

	tk, err := s.casualQueue.Enqueue(r.Context(), claims.GuestID, rk, gm)
	if err != nil {
		if errors.Is(err, queue.ErrInvalidRules) {
			writeError(w, r, http.StatusBadRequest, "INVALID_REQUEST", "invalid round_kind or game_mode")
			return
		}
		writeError(w, r, http.StatusInternalServerError, "INTERNAL", "failed to enqueue")
		return
	}
	writeJSON(w, http.StatusOK, ticketToResponse(tk))
}

func (s *Server) handleGetCasualTicket(w http.ResponseWriter, r *http.Request) {
	claims, ok := s.requireGuestAuth(w, r)
	if !ok {
		return
	}
	if s.casualQueue == nil {
		writeError(w, r, http.StatusInternalServerError, "INTERNAL", "queue service unavailable")
		return
	}
	ticketID := r.PathValue("ticket_id")
	if ticketID == "" {
		writeError(w, r, http.StatusBadRequest, "INVALID_REQUEST", "ticket_id required")
		return
	}
	tk, err := s.casualQueue.Get(r.Context(), claims.GuestID, ticketID)
	if err != nil {
		writeQueueAccessError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, ticketToResponse(tk))
}

func (s *Server) handleCancelCasualTicket(w http.ResponseWriter, r *http.Request) {
	claims, ok := s.requireGuestAuth(w, r)
	if !ok {
		return
	}
	if s.casualQueue == nil {
		writeError(w, r, http.StatusInternalServerError, "INTERNAL", "queue service unavailable")
		return
	}
	ticketID := r.PathValue("ticket_id")
	if ticketID == "" {
		writeError(w, r, http.StatusBadRequest, "INVALID_REQUEST", "ticket_id required")
		return
	}
	tk, err := s.casualQueue.Cancel(r.Context(), claims.GuestID, ticketID)
	if err != nil {
		writeQueueAccessError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, ticketToResponse(tk))
}

func writeQueueAccessError(w http.ResponseWriter, r *http.Request, err error) {
	switch {
	case errors.Is(err, queue.ErrNotFound):
		writeError(w, r, http.StatusNotFound, "NOT_FOUND", "ticket not found")
	case errors.Is(err, queue.ErrForbidden):
		writeError(w, r, http.StatusForbidden, "FORBIDDEN", "ticket not owned by caller")
	default:
		writeError(w, r, http.StatusInternalServerError, "INTERNAL", "queue operation failed")
	}
}

// requireGuestAuth 校验 Authorization: Bearer <session_token>。
// 缺失、篡改、过期、房间 token 一律 UNAUTHORIZED；错误体不得含 token/密钥。
func (s *Server) requireGuestAuth(w http.ResponseWriter, r *http.Request) (tokens.GuestClaims, bool) {
	if s.tokenService == nil {
		writeError(w, r, http.StatusInternalServerError, "INTERNAL", "token service unavailable")
		return tokens.GuestClaims{}, false
	}
	raw := r.Header.Get("Authorization")
	if raw == "" {
		writeError(w, r, http.StatusUnauthorized, "UNAUTHORIZED", "missing authorization")
		return tokens.GuestClaims{}, false
	}
	const prefix = "Bearer "
	if !strings.HasPrefix(raw, prefix) || len(raw) <= len(prefix) {
		writeError(w, r, http.StatusUnauthorized, "UNAUTHORIZED", "invalid authorization")
		return tokens.GuestClaims{}, false
	}
	token := strings.TrimSpace(raw[len(prefix):])
	if token == "" {
		writeError(w, r, http.StatusUnauthorized, "UNAUTHORIZED", "invalid authorization")
		return tokens.GuestClaims{}, false
	}
	claims, err := s.tokenService.VerifyGuestToken(token)
	if err != nil {
		writeError(w, r, http.StatusUnauthorized, "UNAUTHORIZED", "unauthorized")
		return tokens.GuestClaims{}, false
	}
	return claims, true
}

func decodeJSONBody(r *http.Request, dst any) error {
	defer r.Body.Close()
	limited := io.LimitReader(r.Body, maxQueueBodyBytes)
	dec := json.NewDecoder(limited)
	dec.DisallowUnknownFields()
	if err := dec.Decode(dst); err != nil {
		return err
	}
	// 拒绝尾随垃圾
	if err := dec.Decode(&struct{}{}); err != io.EOF {
		return errors.New("trailing data")
	}
	return nil
}
