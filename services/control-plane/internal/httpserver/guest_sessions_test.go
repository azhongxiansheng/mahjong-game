package httpserver

import (
	"bytes"
	"encoding/json"
	"io"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/lov-team/mahjong-game/services/control-plane/internal/tokens"
)

const httpTestSecret = "0123456789abcdef0123456789abcdef"

func newTokenService(t *testing.T) *tokens.Service {
	t.Helper()
	svc, err := tokens.NewService(tokens.Options{
		Secret: httpTestSecret,
		Clock:  fixedNow{t: time.Date(2026, 7, 24, 12, 0, 0, 0, time.UTC)},
	})
	if err != nil {
		t.Fatalf("tokens.NewService: %v", err)
	}
	return svc
}

type fixedNow struct {
	t time.Time
}

func (c fixedNow) Now() time.Time { return c.t }

func TestPostGuestSessions_Success(t *testing.T) {
	ts := newTokenService(t)
	srv := New(Config{
		Addr:         "127.0.0.1:0",
		Pinger:       stubPinger{},
		TokenService: ts,
	})
	baseURL := startServer(t, srv)
	defer shutdownServer(t, srv)

	resp, body := doPOST(t, baseURL+"/v1/guest-sessions", nil)
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusCreated {
		t.Fatalf("status = %d, want 201; body=%s", resp.StatusCode, redactSecrets(body))
	}
	if ct := resp.Header.Get("Content-Type"); !strings.Contains(ct, "application/json") {
		t.Fatalf("Content-Type = %q", ct)
	}

	var payload map[string]any
	if err := json.Unmarshal([]byte(body), &payload); err != nil {
		t.Fatalf("json: %v body=%s", err, redactSecrets(body))
	}
	for _, key := range []string{"guest_id", "display_name", "session_token", "expires_at"} {
		if _, ok := payload[key]; !ok {
			t.Fatalf("missing key %q in %s", key, redactSecrets(body))
		}
	}
	guestID, _ := payload["guest_id"].(string)
	displayName, _ := payload["display_name"].(string)
	sessionToken, _ := payload["session_token"].(string)
	expiresAt, _ := payload["expires_at"].(string)
	if guestID == "" || displayName == "" || sessionToken == "" || expiresAt == "" {
		t.Fatalf("empty fields: %s", redactSecrets(body))
	}
	if !strings.HasPrefix(displayName, "游客-") {
		t.Fatalf("display_name = %q", displayName)
	}
	if strings.Contains(body, httpTestSecret) {
		t.Fatal("response must not contain signing secret")
	}

	claims, err := ts.VerifyGuestToken(sessionToken)
	if err != nil {
		t.Fatalf("VerifyGuestToken: %v", err)
	}
	if claims.GuestID != guestID || claims.DisplayName != displayName {
		t.Fatalf("claims mismatch: %+v vs payload", claims)
	}
}

func TestPostGuestSessions_MethodNotAllowed(t *testing.T) {
	srv := New(Config{
		Addr:         "127.0.0.1:0",
		Pinger:       stubPinger{},
		TokenService: newTokenService(t),
	})
	baseURL := startServer(t, srv)
	defer shutdownServer(t, srv)

	resp, body := doGET(t, baseURL+"/v1/guest-sessions")
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusMethodNotAllowed {
		t.Fatalf("status = %d, want 405; body=%s", resp.StatusCode, redactSecrets(body))
	}
	assertErrorEnvelope(t, body, "METHOD_NOT_ALLOWED")
	if strings.Contains(body, httpTestSecret) {
		t.Fatal("error body must not contain secret")
	}
}

func TestPostGuestSessions_ErrorEnvelopeShape(t *testing.T) {
	// Nil token service should produce stable error envelope (internal).
	srv := New(Config{
		Addr:         "127.0.0.1:0",
		Pinger:       stubPinger{},
		TokenService: nil,
	})
	baseURL := startServer(t, srv)
	defer shutdownServer(t, srv)

	resp, body := doPOST(t, baseURL+"/v1/guest-sessions", nil)
	defer resp.Body.Close()
	if resp.StatusCode < 400 {
		t.Fatalf("status = %d, want error; body=%s", resp.StatusCode, redactSecrets(body))
	}
	assertErrorEnvelopeHasKeys(t, body)
	if strings.Contains(body, httpTestSecret) {
		t.Fatal("error body must not contain secret")
	}
}

func doPOST(t *testing.T, url string, body []byte) (*http.Response, string) {
	t.Helper()
	var rdr io.Reader
	if body != nil {
		rdr = bytes.NewReader(body)
	}
	resp, err := http.Post(url, "application/json", rdr)
	if err != nil {
		t.Fatalf("POST %s: %v", url, err)
	}
	b, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatalf("read body: %v", err)
	}
	return resp, string(b)
}

func assertErrorEnvelope(t *testing.T, body, wantCode string) {
	t.Helper()
	var payload map[string]any
	if err := json.Unmarshal([]byte(body), &payload); err != nil {
		t.Fatalf("json: %v body=%s", err, redactSecrets(body))
	}
	if payload["code"] != wantCode {
		t.Fatalf("code = %v, want %s; body=%s", payload["code"], wantCode, redactSecrets(body))
	}
	if _, ok := payload["message"]; !ok {
		t.Fatalf("missing message: %s", redactSecrets(body))
	}
	if _, ok := payload["request_id"]; !ok {
		t.Fatalf("missing request_id: %s", redactSecrets(body))
	}
}

func assertErrorEnvelopeHasKeys(t *testing.T, body string) {
	t.Helper()
	var payload map[string]any
	if err := json.Unmarshal([]byte(body), &payload); err != nil {
		t.Fatalf("json: %v body=%s", err, redactSecrets(body))
	}
	for _, k := range []string{"code", "message", "request_id"} {
		if _, ok := payload[k]; !ok {
			t.Fatalf("missing %s in %s", k, redactSecrets(body))
		}
	}
	if code, _ := payload["code"].(string); code == "" {
		t.Fatalf("empty code in %s", redactSecrets(body))
	}
}

func redactSecrets(s string) string {
	return strings.ReplaceAll(s, httpTestSecret, "***")
}
