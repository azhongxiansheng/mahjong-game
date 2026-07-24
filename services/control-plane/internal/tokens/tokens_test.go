package tokens

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

const testSecret = "0123456789abcdef0123456789abcdef" // 32 bytes

// 测试默认 bootstrap（1 真人 + 3 AI，EAST/STANDARD）。
func testBootstrap() RoomBootstrap {
	return RoomBootstrap{
		RoundKind:    "EAST",
		GameMode:     "STANDARD",
		Participants: []string{"HUMAN", "AI", "AI", "AI"},
	}
}

type fixedClock struct {
	t time.Time
}

func (c fixedClock) Now() time.Time { return c.t }

type seqIDGen struct {
	ids []string
	i   int
}

func (g *seqIDGen) NewID() (string, error) {
	if g.i >= len(g.ids) {
		return "", errors.New("id exhausted")
	}
	id := g.ids[g.i]
	g.i++
	return id, nil
}

func newTestService(t *testing.T, now time.Time, ids ...string) *Service {
	t.Helper()
	svc, err := NewService(Options{
		Secret: testSecret,
		Clock:  fixedClock{t: now},
		IDGen:  &seqIDGen{ids: ids},
	})
	if err != nil {
		t.Fatalf("NewService: %v", err)
	}
	return svc
}

func TestIssueGuestSession_Success(t *testing.T) {
	now := time.Date(2026, 7, 24, 12, 0, 0, 0, time.UTC)
	svc := newTestService(t, now, "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")

	sess, err := svc.IssueGuestSession()
	if err != nil {
		t.Fatalf("IssueGuestSession: %v", err)
	}
	if sess.GuestID != "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" {
		t.Fatalf("GuestID = %q", sess.GuestID)
	}
	if sess.DisplayName != "游客-AAAA" {
		t.Fatalf("DisplayName = %q, want 游客-AAAA", sess.DisplayName)
	}
	wantExp := now.Add(GuestSessionTTL)
	if !sess.ExpiresAt.Equal(wantExp) {
		t.Fatalf("ExpiresAt = %v, want %v", sess.ExpiresAt, wantExp)
	}
	if sess.SessionToken == "" {
		t.Fatal("SessionToken empty")
	}
	if strings.Contains(sess.SessionToken, testSecret) {
		t.Fatal("token must not embed secret")
	}

	claims, err := svc.VerifyGuestToken(sess.SessionToken)
	if err != nil {
		t.Fatalf("VerifyGuestToken: %v", err)
	}
	if claims.GuestID != sess.GuestID {
		t.Fatalf("claims.GuestID = %q", claims.GuestID)
	}
	if claims.DisplayName != sess.DisplayName {
		t.Fatalf("claims.DisplayName = %q", claims.DisplayName)
	}
	if !claims.ExpiresAt.Equal(wantExp) {
		t.Fatalf("claims.ExpiresAt = %v", claims.ExpiresAt)
	}
}

func TestVerifyGuestToken_Tampered(t *testing.T) {
	now := time.Date(2026, 7, 24, 12, 0, 0, 0, time.UTC)
	svc := newTestService(t, now, "11111111-2222-3333-4444-555555555555")
	sess, err := svc.IssueGuestSession()
	if err != nil {
		t.Fatalf("IssueGuestSession: %v", err)
	}

	// Flip last character of token (signature region).
	raw := []byte(sess.SessionToken)
	if len(raw) < 2 {
		t.Fatal("token too short")
	}
	if raw[len(raw)-1] == 'A' {
		raw[len(raw)-1] = 'B'
	} else {
		raw[len(raw)-1] = 'A'
	}
	tampered := string(raw)

	_, err = svc.VerifyGuestToken(tampered)
	if err == nil {
		t.Fatal("expected error for tampered token")
	}
	if !errors.Is(err, ErrUnauthorized) {
		t.Fatalf("err = %v, want ErrUnauthorized", err)
	}
	if strings.Contains(err.Error(), testSecret) {
		t.Fatal("error must not leak secret")
	}
}

func TestVerifyGuestToken_Expired(t *testing.T) {
	now := time.Date(2026, 7, 24, 12, 0, 0, 0, time.UTC)
	clock := &mutableClock{t: now}
	svc, err := NewService(Options{
		Secret: testSecret,
		Clock:  clock,
		IDGen:  &seqIDGen{ids: []string{"aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"}},
	})
	if err != nil {
		t.Fatalf("NewService: %v", err)
	}
	sess, err := svc.IssueGuestSession()
	if err != nil {
		t.Fatalf("IssueGuestSession: %v", err)
	}

	// Boundary: now == exp is expired.
	clock.t = now.Add(GuestSessionTTL)
	_, err = svc.VerifyGuestToken(sess.SessionToken)
	if !errors.Is(err, ErrUnauthorized) {
		t.Fatalf("at exp: err = %v, want ErrUnauthorized", err)
	}

	clock.t = now.Add(GuestSessionTTL + time.Second)
	_, err = svc.VerifyGuestToken(sess.SessionToken)
	if !errors.Is(err, ErrUnauthorized) {
		t.Fatalf("after exp: err = %v, want ErrUnauthorized", err)
	}
}

type mutableClock struct {
	t time.Time
}

func (c *mutableClock) Now() time.Time { return c.t }

func TestIssueAndVerifyRoomToken_Bound(t *testing.T) {
	now := time.Date(2026, 7, 24, 12, 0, 0, 0, time.UTC)
	svc := newTestService(t, now)

	boot := RoomBootstrap{
		RoundKind:    "HANCHAN",
		GameMode:     "TRASH_TALK",
		Participants: []string{"HUMAN", "HUMAN", "AI", "AI"},
	}
	token, exp, err := svc.IssueRoomTokenBootstrap("sess-1", "room-a", 2, boot)
	if err != nil {
		t.Fatalf("IssueRoomToken: %v", err)
	}
	wantExp := now.Add(RoomTokenTTL)
	if !exp.Equal(wantExp) {
		t.Fatalf("exp = %v, want %v", exp, wantExp)
	}

	claims, err := svc.VerifyRoomToken(token, "room-a", 2)
	if err != nil {
		t.Fatalf("VerifyRoomToken: %v", err)
	}
	if claims.RoomID != "room-a" || claims.Seat != 2 || claims.SessionID != "sess-1" {
		t.Fatalf("claims = %+v", claims)
	}
	if claims.RoundKind != "HANCHAN" || claims.GameMode != "TRASH_TALK" {
		t.Fatalf("bootstrap round/mode = %s/%s", claims.RoundKind, claims.GameMode)
	}
	if len(claims.Participants) != 4 || claims.Participants[0] != "HUMAN" || claims.Participants[2] != "AI" {
		t.Fatalf("participants = %#v", claims.Participants)
	}
	if !claims.ExpiresAt.Equal(wantExp) {
		t.Fatalf("claims.ExpiresAt = %v", claims.ExpiresAt)
	}
}

func TestVerifyRoomToken_CrossRoomSeatExpiredTampered(t *testing.T) {
	now := time.Date(2026, 7, 24, 12, 0, 0, 0, time.UTC)
	clock := &mutableClock{t: now}
	svc, err := NewService(Options{
		Secret: testSecret,
		Clock:  clock,
	})
	if err != nil {
		t.Fatalf("NewService: %v", err)
	}

	token, _, err := svc.IssueRoomTokenBootstrap("sess-1", "room-a", 1, testBootstrap())
	if err != nil {
		t.Fatalf("IssueRoomToken: %v", err)
	}

	if _, err := svc.VerifyRoomToken(token, "room-b", 1); !errors.Is(err, ErrUnauthorized) {
		t.Fatalf("cross room: %v", err)
	}
	if _, err := svc.VerifyRoomToken(token, "room-a", 0); !errors.Is(err, ErrUnauthorized) {
		t.Fatalf("cross seat: %v", err)
	}

	clock.t = now.Add(RoomTokenTTL)
	if _, err := svc.VerifyRoomToken(token, "room-a", 1); !errors.Is(err, ErrUnauthorized) {
		t.Fatalf("expired: %v", err)
	}

	// Restore clock for tamper check with a fresh token.
	clock.t = now
	token2, _, err := svc.IssueRoomTokenBootstrap("sess-1", "room-a", 1, testBootstrap())
	if err != nil {
		t.Fatalf("IssueRoomToken: %v", err)
	}
	raw := []byte(token2)
	raw[len(raw)-1] ^= 0x01
	if _, err := svc.VerifyRoomToken(string(raw), "room-a", 1); !errors.Is(err, ErrUnauthorized) {
		t.Fatalf("tampered: %v", err)
	}
}

func TestTokenTypeIsolation(t *testing.T) {
	now := time.Date(2026, 7, 24, 12, 0, 0, 0, time.UTC)
	svc := newTestService(t, now, "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")

	guest, err := svc.IssueGuestSession()
	if err != nil {
		t.Fatalf("IssueGuestSession: %v", err)
	}
	room, _, err := svc.IssueRoomTokenBootstrap(guest.GuestID, "room-x", 0, testBootstrap())
	if err != nil {
		t.Fatalf("IssueRoomToken: %v", err)
	}

	if _, err := svc.VerifyRoomToken(guest.SessionToken, "room-x", 0); !errors.Is(err, ErrUnauthorized) {
		t.Fatalf("guest as room: %v", err)
	}
	if _, err := svc.VerifyGuestToken(room); !errors.Is(err, ErrUnauthorized) {
		t.Fatalf("room as guest: %v", err)
	}
}

func TestIssueRoomToken_InvalidSeat(t *testing.T) {
	now := time.Date(2026, 7, 24, 12, 0, 0, 0, time.UTC)
	svc := newTestService(t, now)
	if _, _, err := svc.IssueRoomTokenBootstrap("s", "r", -1, testBootstrap()); err == nil {
		t.Fatal("expected error for seat -1")
	}
	if _, _, err := svc.IssueRoomTokenBootstrap("s", "r", 4, testBootstrap()); err == nil {
		t.Fatal("expected error for seat 4")
	}
}

func TestIssueRoomToken_InvalidBootstrap(t *testing.T) {
	now := time.Date(2026, 7, 24, 12, 0, 0, 0, time.UTC)
	svc := newTestService(t, now)
	cases := []RoomBootstrap{
		{RoundKind: "east", GameMode: "STANDARD", Participants: []string{"HUMAN", "AI", "AI", "AI"}},
		{RoundKind: "EAST", GameMode: "standard", Participants: []string{"HUMAN", "AI", "AI", "AI"}},
		{RoundKind: "EAST", GameMode: "STANDARD", Participants: []string{"HUMAN", "AI"}},
		{RoundKind: "EAST", GameMode: "STANDARD", Participants: []string{"BOT", "AI", "AI", "AI"}},
		{RoundKind: "EAST", GameMode: "STANDARD", Participants: []string{"AI", "AI", "AI", "AI"}},
	}
	for i, boot := range cases {
		if _, _, err := svc.IssueRoomTokenBootstrap("s", "r", 0, boot); err == nil {
			t.Fatalf("case %d: expected invalid bootstrap error", i)
		}
	}
}

func TestVerifyRoomToken_BootstrapClaimsTamperedFail(t *testing.T) {
	now := time.Date(2026, 7, 24, 12, 0, 0, 0, time.UTC)
	svc := newTestService(t, now)
	token, _, err := svc.IssueRoomTokenBootstrap("sess-1", "room-a", 0, testBootstrap())
	if err != nil {
		t.Fatalf("IssueRoomToken: %v", err)
	}
	// 改写 payload 中 game_mode 后签名必失败。
	parts := strings.Split(token, ".")
	if len(parts) != 4 {
		t.Fatalf("token parts = %d", len(parts))
	}
	raw, err := base64.RawURLEncoding.DecodeString(parts[2])
	if err != nil {
		t.Fatalf("decode payload: %v", err)
	}
	// 最小篡改：替换 STANDARD → TRASH_TALK 的字节会导致 JSON 变化
	tampered := strings.Replace(string(raw), `"STANDARD"`, `"TRASH_TALK"`, 1)
	if tampered == string(raw) {
		t.Fatal("fixture payload missing STANDARD")
	}
	parts[2] = base64.RawURLEncoding.EncodeToString([]byte(tampered))
	bad := strings.Join(parts, ".")
	if _, err := svc.VerifyRoomToken(bad, "room-a", 0); !errors.Is(err, ErrUnauthorized) {
		t.Fatalf("tampered bootstrap: %v", err)
	}
}

func TestNewService_RejectsWeakSecret(t *testing.T) {
	_, err := NewService(Options{Secret: "short"})
	if err == nil {
		t.Fatal("expected error for short secret")
	}
	_, err = NewService(Options{Secret: ""})
	if err == nil {
		t.Fatal("expected error for empty secret")
	}
}

// 签发返回的 ExpiresAt 必须与令牌 payload 秒精度边界一致（非零纳秒时钟）。
func TestIssueGuestSession_ExpiresAtMatchesTokenSecondPrecision(t *testing.T) {
	now := time.Date(2026, 7, 24, 12, 0, 0, 123456789, time.UTC)
	svc := newTestService(t, now, "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")

	sess, err := svc.IssueGuestSession()
	if err != nil {
		t.Fatalf("IssueGuestSession: %v", err)
	}
	claims, err := svc.VerifyGuestToken(sess.SessionToken)
	if err != nil {
		t.Fatalf("VerifyGuestToken: %v", err)
	}
	if !sess.ExpiresAt.Equal(claims.ExpiresAt) {
		t.Fatalf("returned ExpiresAt %v != claims.ExpiresAt %v (nanosecond/second mismatch)",
			sess.ExpiresAt, claims.ExpiresAt)
	}
	if sess.ExpiresAt.Nanosecond() != 0 {
		t.Fatalf("ExpiresAt must be second-aligned for token wire format, got ns=%d", sess.ExpiresAt.Nanosecond())
	}
}

func TestIssueRoomToken_ExpiresAtMatchesTokenSecondPrecision(t *testing.T) {
	now := time.Date(2026, 7, 24, 12, 0, 0, 987654321, time.UTC)
	svc := newTestService(t, now)

	token, exp, err := svc.IssueRoomTokenBootstrap("sess-1", "room-a", 2, testBootstrap())
	if err != nil {
		t.Fatalf("IssueRoomToken: %v", err)
	}
	claims, err := svc.VerifyRoomToken(token, "room-a", 2)
	if err != nil {
		t.Fatalf("VerifyRoomToken: %v", err)
	}
	if !exp.Equal(claims.ExpiresAt) {
		t.Fatalf("returned expiresAt %v != claims.ExpiresAt %v (nanosecond/second mismatch)",
			exp, claims.ExpiresAt)
	}
	if exp.Nanosecond() != 0 {
		t.Fatalf("expiresAt must be second-aligned for token wire format, got ns=%d", exp.Nanosecond())
	}
}

// crossLangFixturePath 指向仓库内已提交的 Go→GDScript 跨语言 fixture。
func crossLangFixturePath() string {
	return filepath.Join("..", "..", "..", "..", "godot", "tests", "_fixtures", "room_token_crosslang.json")
}

func issueCrossLangFixtureToken(t *testing.T) (token string, issuedAt, expiresAt int64) {
	t.Helper()
	now := time.Date(2026, 7, 24, 12, 0, 0, 0, time.UTC)
	svc := newTestService(t, now)
	boot := RoomBootstrap{
		RoundKind:    "EAST",
		GameMode:     "STANDARD",
		Participants: []string{"HUMAN", "HUMAN", "AI", "AI"},
	}
	tok, exp, err := svc.IssueRoomTokenBootstrap("sess-fixture", "room-fixture", 1, boot)
	if err != nil {
		t.Fatalf("IssueRoomToken: %v", err)
	}
	return tok, now.Unix(), exp.Unix()
}

// TestCrossLangRoomTokenFixture_MatchesCommitted 默认无副作用：
// Go 真实签发后与已提交 fixture 字节级比对；禁止普通 go test 改写仓库。
func TestCrossLangRoomTokenFixture_MatchesCommitted(t *testing.T) {
	token, issuedAt, expiresAt := issueCrossLangFixtureToken(t)
	raw, err := os.ReadFile(crossLangFixturePath())
	if err != nil {
		t.Fatalf("read committed fixture: %v (若需重建请 UPDATE_CROSSLANG_FIXTURE=1)", err)
	}
	var doc map[string]any
	if err := json.Unmarshal(raw, &doc); err != nil {
		t.Fatalf("parse fixture: %v", err)
	}
	gotTok, _ := doc["token"].(string)
	if gotTok != token {
		t.Fatalf("committed fixture token mismatch Go re-issue; set UPDATE_CROSSLANG_FIXTURE=1 to refresh")
	}
	if int64(doc["issued_at_unix"].(float64)) != issuedAt {
		t.Fatalf("issued_at_unix mismatch")
	}
	if int64(doc["expires_at_unix"].(float64)) != expiresAt {
		t.Fatalf("expires_at_unix mismatch")
	}
	// 自洽：刚签发的 token 必须可验
	svc := newTestService(t, time.Unix(issuedAt, 0).UTC())
	if _, err := svc.VerifyRoomToken(token, "room-fixture", 1); err != nil {
		t.Fatalf("re-issued token verify: %v", err)
	}
}

// TestUpdateCrossLangRoomTokenFixture 仅在显式环境变量下写回 fixture（维护入口）。
func TestUpdateCrossLangRoomTokenFixture(t *testing.T) {
	if os.Getenv("UPDATE_CROSSLANG_FIXTURE") != "1" {
		t.Skip("set UPDATE_CROSSLANG_FIXTURE=1 to rewrite godot/tests/_fixtures/room_token_crosslang.json")
	}
	token, issuedAt, expiresAt := issueCrossLangFixtureToken(t)
	svc := newTestService(t, time.Unix(issuedAt, 0).UTC())
	claims, err := svc.VerifyRoomToken(token, "room-fixture", 1)
	if err != nil {
		t.Fatalf("VerifyRoomToken: %v", err)
	}
	doc := map[string]any{
		"secret":          testSecret,
		"token":           token,
		"issued_at_unix":  issuedAt,
		"expires_at_unix": expiresAt,
		"claims": map[string]any{
			"room_id":      claims.RoomID,
			"seat":         claims.Seat,
			"session_id":   claims.SessionID,
			"round_kind":   claims.RoundKind,
			"game_mode":    claims.GameMode,
			"participants": claims.Participants,
			"exp":          claims.ExpiresAt.Unix(),
		},
		"session_token_must_fail_as_room": true,
		"note":                           "Go tokens 真实签发；GDScript 只验不重签。UPDATE_CROSSLANG_FIXTURE=1 维护。网络端到端未验证。",
	}
	body, err := json.MarshalIndent(doc, "", "  ")
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	body = append(body, '\n')
	if err := os.WriteFile(crossLangFixturePath(), body, 0o600); err != nil {
		t.Fatalf("write fixture: %v", err)
	}
}
