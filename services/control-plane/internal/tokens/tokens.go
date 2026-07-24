// Package tokens 提供游客会话与房间短期令牌的 HMAC-SHA256 签发/校验。
// 网络端到端未验证。
package tokens

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"
)

const (
	// GuestSessionTTL 游客会话默认存活时间（代码常量，不可配置）。
	GuestSessionTTL = 24 * time.Hour
	// RoomTokenTTL 房间令牌默认存活时间（代码常量，不可配置）。
	RoomTokenTTL = 2 * time.Hour

	minSecretLen = 32
	tokenVersion = "v1"
	typGuest     = "g"
	typRoom      = "r"
	claimGuest   = "guest"
	claimRoom    = "room"
)

// ErrUnauthorized 表示令牌无效、过期、类型错误或绑定不匹配。
// 对外映射为 code=UNAUTHORIZED；错误文案不得泄露签名细节。
var ErrUnauthorized = errors.New("unauthorized")

// Clock 可注入时钟，便于测试固定时间。
type Clock interface {
	Now() time.Time
}

type realClock struct{}

func (realClock) Now() time.Time { return time.Now().UTC() }

// IDGen 可注入 ID 生成器。
type IDGen interface {
	NewID() (string, error)
}

type cryptoIDGen struct{}

func (cryptoIDGen) NewID() (string, error) {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		return "", err
	}
	// UUID v4 layout
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	return fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:16]), nil
}

// Options 构造令牌服务。
type Options struct {
	Secret string
	Clock  Clock
	IDGen  IDGen
}

// Service 签发与校验 guest / room 令牌。
type Service struct {
	secret []byte
	clock  Clock
	idGen  IDGen
}

// NewService 创建服务；密钥长度必须 >= 32。
func NewService(opts Options) (*Service, error) {
	if len(opts.Secret) < minSecretLen {
		return nil, fmt.Errorf("token signing secret must be at least %d bytes", minSecretLen)
	}
	clk := opts.Clock
	if clk == nil {
		clk = realClock{}
	}
	idg := opts.IDGen
	if idg == nil {
		idg = cryptoIDGen{}
	}
	return &Service{
		secret: []byte(opts.Secret),
		clock:  clk,
		idGen:  idg,
	}, nil
}

// GuestSession 是 POST /v1/guest-sessions 成功结果。
type GuestSession struct {
	GuestID      string
	DisplayName  string
	SessionToken string
	ExpiresAt    time.Time
}

// GuestClaims 为游客令牌解析结果。
type GuestClaims struct {
	GuestID     string
	DisplayName string
	ExpiresAt   time.Time
}

// RoomClaims 为房间令牌解析结果。
type RoomClaims struct {
	RoomID    string
	Seat      int
	SessionID string
	ExpiresAt time.Time
}

type guestPayload struct {
	Typ         string `json:"typ"`
	GuestID     string `json:"guest_id"`
	DisplayName string `json:"display_name"`
	Exp         int64  `json:"exp"`
}

type roomPayload struct {
	Typ       string `json:"typ"`
	RoomID    string `json:"room_id"`
	Seat      int    `json:"seat"`
	SessionID string `json:"session_id"`
	Exp       int64  `json:"exp"`
}

// IssueGuestSession 签发游客会话。
func (s *Service) IssueGuestSession() (GuestSession, error) {
	id, err := s.idGen.NewID()
	if err != nil {
		return GuestSession{}, err
	}
	now := s.clock.Now().UTC()
	// 与 payload exp.Unix() / 校验 time.Unix(exp,0) 对齐到 UTC 秒，避免纳秒偏差。
	exp := time.Unix(now.Add(GuestSessionTTL).Unix(), 0).UTC()
	display := displayNameFromGuestID(id)
	token, err := s.sign(typGuest, guestPayload{
		Typ:         claimGuest,
		GuestID:     id,
		DisplayName: display,
		Exp:         exp.Unix(),
	})
	if err != nil {
		return GuestSession{}, err
	}
	return GuestSession{
		GuestID:      id,
		DisplayName:  display,
		SessionToken: token,
		ExpiresAt:    exp,
	}, nil
}

// VerifyGuestToken 校验游客会话令牌。
func (s *Service) VerifyGuestToken(token string) (GuestClaims, error) {
	raw, err := s.verifyRaw(token, typGuest)
	if err != nil {
		return GuestClaims{}, ErrUnauthorized
	}
	var p guestPayload
	if err := json.Unmarshal(raw, &p); err != nil {
		return GuestClaims{}, ErrUnauthorized
	}
	if p.Typ != claimGuest || p.GuestID == "" || p.DisplayName == "" || p.Exp == 0 {
		return GuestClaims{}, ErrUnauthorized
	}
	exp := time.Unix(p.Exp, 0).UTC()
	if !s.clock.Now().UTC().Before(exp) {
		return GuestClaims{}, ErrUnauthorized
	}
	return GuestClaims{
		GuestID:     p.GuestID,
		DisplayName: p.DisplayName,
		ExpiresAt:   exp,
	}, nil
}

// IssueRoomToken 签发绑定 room/seat/session 的短期房间令牌（内部 API，供 #238 调用）。
func (s *Service) IssueRoomToken(sessionID, roomID string, seat int) (token string, expiresAt time.Time, err error) {
	if sessionID == "" || roomID == "" {
		return "", time.Time{}, fmt.Errorf("session_id and room_id required")
	}
	if seat < 0 || seat > 3 {
		return "", time.Time{}, fmt.Errorf("seat must be 0..3")
	}
	now := s.clock.Now().UTC()
	// 与 payload exp.Unix() / 校验 time.Unix(exp,0) 对齐到 UTC 秒，避免纳秒偏差。
	exp := time.Unix(now.Add(RoomTokenTTL).Unix(), 0).UTC()
	tok, err := s.sign(typRoom, roomPayload{
		Typ:       claimRoom,
		RoomID:    roomID,
		Seat:      seat,
		SessionID: sessionID,
		Exp:       exp.Unix(),
	})
	if err != nil {
		return "", time.Time{}, err
	}
	return tok, exp, nil
}

// VerifyRoomToken 校验房间令牌，并要求 room_id 与 seat 匹配期望值。
func (s *Service) VerifyRoomToken(token, expectedRoomID string, expectedSeat int) (RoomClaims, error) {
	raw, err := s.verifyRaw(token, typRoom)
	if err != nil {
		return RoomClaims{}, ErrUnauthorized
	}
	var p roomPayload
	if err := json.Unmarshal(raw, &p); err != nil {
		return RoomClaims{}, ErrUnauthorized
	}
	if p.Typ != claimRoom || p.RoomID == "" || p.SessionID == "" {
		return RoomClaims{}, ErrUnauthorized
	}
	if p.Seat < 0 || p.Seat > 3 {
		return RoomClaims{}, ErrUnauthorized
	}
	exp := time.Unix(p.Exp, 0).UTC()
	if !s.clock.Now().UTC().Before(exp) {
		return RoomClaims{}, ErrUnauthorized
	}
	if p.RoomID != expectedRoomID || p.Seat != expectedSeat {
		return RoomClaims{}, ErrUnauthorized
	}
	return RoomClaims{
		RoomID:    p.RoomID,
		Seat:      p.Seat,
		SessionID: p.SessionID,
		ExpiresAt: exp,
	}, nil
}

func displayNameFromGuestID(guestID string) string {
	compact := strings.ReplaceAll(guestID, "-", "")
	if len(compact) < 4 {
		compact = (compact + "0000")[:4]
	}
	return "游客-" + strings.ToUpper(compact[:4])
}

func (s *Service) sign(typ string, payload any) (string, error) {
	body, err := json.Marshal(payload)
	if err != nil {
		return "", err
	}
	payloadB64 := base64.RawURLEncoding.EncodeToString(body)
	signingInput := tokenVersion + "." + typ + "." + payloadB64
	mac := hmac.New(sha256.New, s.secret)
	_, _ = mac.Write([]byte(signingInput))
	sig := base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
	return signingInput + "." + sig, nil
}

func (s *Service) verifyRaw(token, wantTyp string) ([]byte, error) {
	parts := strings.Split(token, ".")
	if len(parts) != 4 {
		return nil, ErrUnauthorized
	}
	if parts[0] != tokenVersion || parts[1] != wantTyp {
		return nil, ErrUnauthorized
	}
	signingInput := parts[0] + "." + parts[1] + "." + parts[2]
	mac := hmac.New(sha256.New, s.secret)
	_, _ = mac.Write([]byte(signingInput))
	expected := mac.Sum(nil)
	got, err := base64.RawURLEncoding.DecodeString(parts[3])
	if err != nil {
		return nil, ErrUnauthorized
	}
	if !hmac.Equal(expected, got) {
		return nil, ErrUnauthorized
	}
	raw, err := base64.RawURLEncoding.DecodeString(parts[2])
	if err != nil {
		return nil, ErrUnauthorized
	}
	return raw, nil
}
