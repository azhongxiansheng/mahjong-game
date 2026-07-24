package tokens

import (
	"errors"
	"strings"
	"testing"
	"time"
)

const testSecret = "0123456789abcdef0123456789abcdef" // 32 bytes

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

	token, exp, err := svc.IssueRoomToken("sess-1", "room-a", 2)
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

	token, _, err := svc.IssueRoomToken("sess-1", "room-a", 1)
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
	token2, _, err := svc.IssueRoomToken("sess-1", "room-a", 1)
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
	room, _, err := svc.IssueRoomToken(guest.GuestID, "room-x", 0)
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
	if _, _, err := svc.IssueRoomToken("s", "r", -1); err == nil {
		t.Fatal("expected error for seat -1")
	}
	if _, _, err := svc.IssueRoomToken("s", "r", 4); err == nil {
		t.Fatal("expected error for seat 4")
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

	token, exp, err := svc.IssueRoomToken("sess-1", "room-a", 2)
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
