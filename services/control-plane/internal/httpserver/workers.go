package httpserver

import (
	"context"
	"crypto/subtle"
	"net/http"
	"strings"
	"time"

	"github.com/lov-team/mahjong-game/services/control-plane/internal/workers"
)

// WorkerRegistrar 内部 Worker 注册/续租/房间完成/失败能力。
type WorkerRegistrar interface {
	Register(ctx context.Context, reg workers.Registration) (workers.LeaseResult, error)
	LeaseTTL() time.Duration
	CompleteRoom(ctx context.Context, workerID, roomID string) (string, error)
	FailRoom(ctx context.Context, workerID, roomID, failCode string) (string, error)
}

type workerRegisterRequest struct {
	WorkerID      string `json:"worker_id"`
	GameEndpoint  string `json:"game_endpoint"`
	VoiceEndpoint string `json:"voice_endpoint"`
	Capacity      int    `json:"capacity"`
	ActiveRooms   int    `json:"active_rooms"`
}

type workerRegisterResponse struct {
	WorkerID       string `json:"worker_id"`
	LeaseExpiresAt string `json:"lease_expires_at"`
	LeaseTTLMs     int64  `json:"lease_ttl_ms"`
}

type workerCompleteRequest struct {
	WorkerID string `json:"worker_id"`
	RoomID   string `json:"room_id"`
}

type workerCompleteResponse struct {
	WorkerID string `json:"worker_id"`
	RoomID   string `json:"room_id"`
	Status   string `json:"status"`
}

type workerFailRequest struct {
	WorkerID string `json:"worker_id"`
	RoomID   string `json:"room_id"`
	FailCode string `json:"fail_code"`
}

type workerFailResponse struct {
	WorkerID string `json:"worker_id"`
	RoomID   string `json:"room_id"`
	Status   string `json:"status"`
	FailCode string `json:"fail_code"`
}

func (s *Server) handleRegisterWorker(w http.ResponseWriter, r *http.Request) {
	if !s.requireWorkerRegistrationAuth(w, r) {
		return
	}
	if s.workerRegistry == nil {
		writeError(w, r, http.StatusInternalServerError, "INTERNAL", "worker registry unavailable")
		return
	}
	var req workerRegisterRequest
	if err := decodeJSONBody(r, &req); err != nil {
		writeError(w, r, http.StatusBadRequest, "INVALID_REQUEST", "invalid request body")
		return
	}
	res, err := s.workerRegistry.Register(r.Context(), workers.Registration{
		WorkerID:      req.WorkerID,
		GameEndpoint:  req.GameEndpoint,
		VoiceEndpoint: req.VoiceEndpoint,
		Capacity:      req.Capacity,
		ActiveRooms:   req.ActiveRooms,
	})
	if err != nil {
		// 校验类错误 → 400；不回显 token/secret。
		msg := err.Error()
		if strings.Contains(msg, "required") || strings.Contains(msg, "must be") {
			writeError(w, r, http.StatusBadRequest, "INVALID_REQUEST", "invalid worker registration")
			return
		}
		writeError(w, r, http.StatusInternalServerError, "INTERNAL", "worker registration failed")
		return
	}
	writeJSON(w, http.StatusOK, workerRegisterResponse{
		WorkerID:       res.WorkerID,
		LeaseExpiresAt: time.UnixMilli(res.LeaseExpiresAtMs).UTC().Format(time.RFC3339),
		LeaseTTLMs:     res.LeaseTTL.Milliseconds(),
	})
}

func (s *Server) handleCompleteWorkerRoom(w http.ResponseWriter, r *http.Request) {
	if !s.requireWorkerRegistrationAuth(w, r) {
		return
	}
	if s.workerRegistry == nil {
		writeError(w, r, http.StatusInternalServerError, "INTERNAL", "worker registry unavailable")
		return
	}
	var req workerCompleteRequest
	if err := decodeJSONBody(r, &req); err != nil {
		writeError(w, r, http.StatusBadRequest, "INVALID_REQUEST", "invalid request body")
		return
	}
	kind, err := s.workerRegistry.CompleteRoom(r.Context(), req.WorkerID, req.RoomID)
	if err != nil {
		writeError(w, r, http.StatusBadRequest, "INVALID_REQUEST", "invalid room complete")
		return
	}
	switch kind {
	case workers.CompleteOK, workers.CompleteIdempotent:
		writeJSON(w, http.StatusOK, workerCompleteResponse{
			WorkerID: strings.TrimSpace(req.WorkerID),
			RoomID:   strings.TrimSpace(req.RoomID),
			Status:   workers.StatusCompleted,
		})
	case workers.CompleteNotFound:
		writeError(w, r, http.StatusNotFound, "NOT_FOUND", "room not found")
	case workers.CompleteWrongWorker:
		writeError(w, r, http.StatusForbidden, "FORBIDDEN", "room not owned by worker")
	case workers.CompleteAlreadyFailed:
		writeError(w, r, http.StatusConflict, "ROOM_FAILED", "room already failed")
	default:
		writeError(w, r, http.StatusConflict, "INVALID_REQUEST", "room not completable")
	}
}

func (s *Server) handleWorkersFallback(w http.ResponseWriter, r *http.Request) {
	if r.Method == http.MethodPost {
		s.handleRegisterWorker(w, r)
		return
	}
	w.Header().Set("Allow", http.MethodPost)
	writeError(w, r, http.StatusMethodNotAllowed, "METHOD_NOT_ALLOWED", "method not allowed")
}

func (s *Server) handleCompleteRoomFallback(w http.ResponseWriter, r *http.Request) {
	if r.Method == http.MethodPost {
		s.handleCompleteWorkerRoom(w, r)
		return
	}
	w.Header().Set("Allow", http.MethodPost)
	writeError(w, r, http.StatusMethodNotAllowed, "METHOD_NOT_ALLOWED", "method not allowed")
}

func (s *Server) handleFailWorkerRoom(w http.ResponseWriter, r *http.Request) {
	if !s.requireWorkerRegistrationAuth(w, r) {
		return
	}
	if s.workerRegistry == nil {
		writeError(w, r, http.StatusInternalServerError, "INTERNAL", "worker registry unavailable")
		return
	}
	var req workerFailRequest
	if err := decodeJSONBody(r, &req); err != nil {
		writeError(w, r, http.StatusBadRequest, "INVALID_REQUEST", "invalid request body")
		return
	}
	failCode := strings.TrimSpace(req.FailCode)
	if failCode == "" {
		failCode = workers.FailCodeRoomFailed
	}
	if failCode != workers.FailCodeRoomFailed {
		writeError(w, r, http.StatusBadRequest, "INVALID_REQUEST", "fail_code must be ROOM_FAILED")
		return
	}
	kind, err := s.workerRegistry.FailRoom(r.Context(), req.WorkerID, req.RoomID, failCode)
	if err != nil {
		writeError(w, r, http.StatusBadRequest, "INVALID_REQUEST", "invalid room fail")
		return
	}
	switch kind {
	case workers.FailOK, workers.FailIdempotent:
		writeJSON(w, http.StatusOK, workerFailResponse{
			WorkerID: strings.TrimSpace(req.WorkerID),
			RoomID:   strings.TrimSpace(req.RoomID),
			Status:   workers.StatusFailed,
			FailCode: failCode,
		})
	case workers.FailNotFound:
		writeError(w, r, http.StatusNotFound, "NOT_FOUND", "room not found")
	case workers.FailWrongWorker:
		writeError(w, r, http.StatusForbidden, "FORBIDDEN", "room not owned by worker")
	case workers.FailAlreadyDone:
		writeError(w, r, http.StatusConflict, "ALREADY_COMPLETED", "room already completed")
	default:
		writeError(w, r, http.StatusConflict, "INVALID_REQUEST", "room not failable")
	}
}

func (s *Server) handleFailRoomFallback(w http.ResponseWriter, r *http.Request) {
	if r.Method == http.MethodPost {
		s.handleFailWorkerRoom(w, r)
		return
	}
	w.Header().Set("Allow", http.MethodPost)
	writeError(w, r, http.StatusMethodNotAllowed, "METHOD_NOT_ALLOWED", "method not allowed")
}

// requireWorkerRegistrationAuth 校验独立注册 token（恒定时间比较）；失败不写注册状态。
// 响应体不得回显 token / TOKEN_SIGNING_SECRET。
func (s *Server) requireWorkerRegistrationAuth(w http.ResponseWriter, r *http.Request) bool {
	if s.workerRegToken == "" {
		writeError(w, r, http.StatusInternalServerError, "INTERNAL", "worker registration not configured")
		return false
	}
	raw := r.Header.Get("Authorization")
	const prefix = "Bearer "
	if !strings.HasPrefix(raw, prefix) {
		writeError(w, r, http.StatusUnauthorized, "UNAUTHORIZED", "unauthorized")
		return false
	}
	tok := strings.TrimSpace(strings.TrimPrefix(raw, prefix))
	if !secureTokenEqual(tok, s.workerRegToken) {
		writeError(w, r, http.StatusUnauthorized, "UNAUTHORIZED", "unauthorized")
		return false
	}
	return true
}

// secureTokenEqual 使用 crypto/subtle 恒定时间比较；长度不同也返回 false 且不泄漏期望长度细节到响应。
func secureTokenEqual(got, want string) bool {
	if len(got) != len(want) {
		// 仍做一次比较以降低计时侧信道；填充到相同长度的副本
		dummy := make([]byte, len(want))
		subtle.ConstantTimeCompare(dummy, []byte(want))
		return false
	}
	return subtle.ConstantTimeCompare([]byte(got), []byte(want)) == 1
}
