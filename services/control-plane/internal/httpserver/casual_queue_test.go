package httpserver

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"os"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/lov-team/mahjong-game/services/control-plane/internal/queue"
	"github.com/lov-team/mahjong-game/services/control-plane/internal/redisx"
	"github.com/lov-team/mahjong-game/services/control-plane/internal/tokens"
)

func requireHTTPRedisQueue(t *testing.T) *queue.Service {
	t.Helper()
	addr := os.Getenv("REDIS_ADDR")
	if addr == "" {
		addr = "127.0.0.1:6379"
	}
	c, err := redisx.New(redisx.Options{
		Addr:     addr,
		Password: os.Getenv("REDIS_PASSWORD"),
		DB:       httpRedisDB(),
	})
	if err != nil {
		t.Fatalf("redisx.New: %v", err)
	}
	t.Cleanup(func() { _ = c.Close() })
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	if err := c.Ping(ctx); err != nil {
		t.Fatalf("真实 Redis 不可用（addr=%s）: %v", addr, err)
	}
	prefix := "test:http:casual:" + t.Name() + ":"
	svc, err := queue.NewService(queue.Options{
		Redis:     c.Redis(),
		KeyPrefix: prefix,
		Clock:     fixedNow{t: time.Date(2026, 7, 24, 12, 0, 0, 0, time.UTC)},
	})
	if err != nil {
		t.Fatalf("queue.NewService: %v", err)
	}
	t.Cleanup(func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		rdb := c.Redis()
		iter := rdb.Scan(ctx, 0, prefix+"*", 100).Iterator()
		var keys []string
		for iter.Next(ctx) {
			keys = append(keys, iter.Val())
		}
		if len(keys) > 0 {
			_ = rdb.Del(ctx, keys...).Err()
		}
	})
	return svc
}

func httpRedisDB() int {
	raw := os.Getenv("REDIS_DB")
	if raw == "" {
		return 0
	}
	n, err := strconv.Atoi(raw)
	if err != nil {
		return 0
	}
	return n
}

func newQueueServer(t *testing.T) (baseURL string, tokenSvc *tokens.Service, q *queue.Service) {
	t.Helper()
	tokenSvc = newTokenService(t)
	q = requireHTTPRedisQueue(t)
	srv := New(Config{
		Addr:         "127.0.0.1:0",
		Pinger:       stubPinger{},
		TokenService: tokenSvc,
		CasualQueue:  q,
	})
	baseURL = startServer(t, srv)
	t.Cleanup(func() { shutdownServer(t, srv) })
	return baseURL, tokenSvc, q
}

func issueGuestToken(t *testing.T, ts *tokens.Service) (guestID, token string) {
	t.Helper()
	sess, err := ts.IssueGuestSession()
	if err != nil {
		t.Fatalf("IssueGuestSession: %v", err)
	}
	return sess.GuestID, sess.SessionToken
}

func doJSON(t *testing.T, method, url, bearer string, body []byte) (*http.Response, string) {
	t.Helper()
	var rdr io.Reader
	if body != nil {
		rdr = bytes.NewReader(body)
	}
	req, err := http.NewRequest(method, url, rdr)
	if err != nil {
		t.Fatalf("NewRequest: %v", err)
	}
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	if bearer != "" {
		req.Header.Set("Authorization", "Bearer "+bearer)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("%s %s: %v", method, url, err)
	}
	b, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatalf("read body: %v", err)
	}
	resp.Body.Close()
	return resp, string(b)
}

func TestCasualQueue_JoinGetCancel_HappyPath(t *testing.T) {
	baseURL, ts, q := newQueueServer(t)
	_, token := issueGuestToken(t, ts)

	body := []byte(`{"round_kind":"EAST","game_mode":"STANDARD","character_id":"lin_yeche"}`)
	resp, raw := doJSON(t, http.MethodPost, baseURL+"/v1/queues/casual", token, body)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("POST status=%d body=%s", resp.StatusCode, redactSecrets(raw))
	}
	var join map[string]any
	if err := json.Unmarshal([]byte(raw), &join); err != nil {
		t.Fatalf("json: %v", err)
	}
	for _, k := range []string{"ticket_id", "round_kind", "game_mode", "status", "queued_at", "deadline_at"} {
		if _, ok := join[k]; !ok {
			t.Fatalf("missing %s in %s", k, redactSecrets(raw))
		}
	}
	if join["status"] != "waiting" {
		t.Fatalf("status=%v", join["status"])
	}
	if join["round_kind"] != "EAST" || join["game_mode"] != "STANDARD" {
		t.Fatalf("rules=%v/%v", join["round_kind"], join["game_mode"])
	}
	ticketID, _ := join["ticket_id"].(string)
	if ticketID == "" {
		t.Fatal("empty ticket_id")
	}
	// deadline = queued + 30s
	queuedAt, _ := time.Parse(time.RFC3339, join["queued_at"].(string))
	deadlineAt, _ := time.Parse(time.RFC3339, join["deadline_at"].(string))
	if deadlineAt.Sub(queuedAt) != 30*time.Second {
		t.Fatalf("deadline-queued = %v, want 30s", deadlineAt.Sub(queuedAt))
	}
	if !q.IsConsumable(context.Background(), ticketID) {
		t.Fatal("joined ticket must be consumable")
	}

	// 幂等再加入
	resp2, raw2 := doJSON(t, http.MethodPost, baseURL+"/v1/queues/casual", token, body)
	if resp2.StatusCode != http.StatusOK {
		t.Fatalf("POST2 status=%d body=%s", resp2.StatusCode, redactSecrets(raw2))
	}
	var join2 map[string]any
	_ = json.Unmarshal([]byte(raw2), &join2)
	if join2["ticket_id"] != ticketID {
		t.Fatalf("idempotent ticket mismatch %v vs %v", join2["ticket_id"], ticketID)
	}

	// GET
	respG, rawG := doJSON(t, http.MethodGet, baseURL+"/v1/queues/casual/"+ticketID, token, nil)
	if respG.StatusCode != http.StatusOK {
		t.Fatalf("GET status=%d body=%s", respG.StatusCode, redactSecrets(rawG))
	}
	if !strings.Contains(rawG, `"status":"waiting"`) {
		t.Fatalf("GET body=%s", redactSecrets(rawG))
	}

	// DELETE
	respD, rawD := doJSON(t, http.MethodDelete, baseURL+"/v1/queues/casual/"+ticketID, token, nil)
	if respD.StatusCode != http.StatusOK {
		t.Fatalf("DELETE status=%d body=%s", respD.StatusCode, redactSecrets(rawD))
	}
	if !strings.Contains(rawD, `"status":"cancelled"`) {
		t.Fatalf("DELETE body=%s", redactSecrets(rawD))
	}
	if q.IsConsumable(context.Background(), ticketID) {
		t.Fatal("cancelled must not be consumable")
	}

	// 幂等再 DELETE
	respD2, rawD2 := doJSON(t, http.MethodDelete, baseURL+"/v1/queues/casual/"+ticketID, token, nil)
	if respD2.StatusCode != http.StatusOK {
		t.Fatalf("DELETE2 status=%d body=%s", respD2.StatusCode, redactSecrets(rawD2))
	}
	if !strings.Contains(rawD2, `"status":"cancelled"`) {
		t.Fatalf("DELETE2 body=%s", redactSecrets(rawD2))
	}

	// GET cancelled
	respG2, rawG2 := doJSON(t, http.MethodGet, baseURL+"/v1/queues/casual/"+ticketID, token, nil)
	if respG2.StatusCode != http.StatusOK {
		t.Fatalf("GET cancelled status=%d body=%s", respG2.StatusCode, redactSecrets(rawG2))
	}
	if !strings.Contains(rawG2, `"status":"cancelled"`) {
		t.Fatalf("GET cancelled body=%s", redactSecrets(rawG2))
	}
}

func TestCasualQueue_AuthNegatives(t *testing.T) {
	baseURL, ts, _ := newQueueServer(t)
	_, goodToken := issueGuestToken(t, ts)

	body := []byte(`{"round_kind":"EAST","game_mode":"STANDARD","character_id":"lin_yeche"}`)
	url := baseURL + "/v1/queues/casual"

	// 缺失
	resp, raw := doJSON(t, http.MethodPost, url, "", body)
	if resp.StatusCode != http.StatusUnauthorized {
		t.Fatalf("missing auth status=%d body=%s", resp.StatusCode, redactSecrets(raw))
	}
	assertErrorEnvelope(t, raw, "UNAUTHORIZED")
	assertNoSecretLeak(t, raw, goodToken)

	// 篡改
	resp, raw = doJSON(t, http.MethodPost, url, goodToken+"x", body)
	if resp.StatusCode != http.StatusUnauthorized {
		t.Fatalf("tampered status=%d", resp.StatusCode)
	}
	assertErrorEnvelope(t, raw, "UNAUTHORIZED")
	assertNoSecretLeak(t, raw, goodToken)

	// 房间 token 不得当 session
	roomTok, _, err := ts.IssueRoomToken("sess-1", "room-1", 0, "EAST", "STANDARD", []string{"HUMAN", "AI", "AI", "AI"}, []string{"lin_yeche", "an_cheng", "bai_touli", "hua_ling"})
	if err != nil {
		t.Fatalf("IssueRoomToken: %v", err)
	}
	resp, raw = doJSON(t, http.MethodPost, url, roomTok, body)
	if resp.StatusCode != http.StatusUnauthorized {
		t.Fatalf("room token status=%d body=%s", resp.StatusCode, redactSecrets(raw))
	}
	assertErrorEnvelope(t, raw, "UNAUTHORIZED")
	assertNoSecretLeak(t, raw, roomTok)
	assertNoSecretLeak(t, raw, goodToken)

	// 过期 guest token
	expiredSvc, err := tokens.NewService(tokens.Options{
		Secret: httpTestSecret,
		Clock:  fixedNow{t: time.Date(2020, 1, 1, 0, 0, 0, 0, time.UTC)},
	})
	if err != nil {
		t.Fatalf("expired svc: %v", err)
	}
	expiredSess, err := expiredSvc.IssueGuestSession()
	if err != nil {
		t.Fatalf("issue expired: %v", err)
	}
	// 用「现在」时钟的服务校验 → 过期
	resp, raw = doJSON(t, http.MethodPost, url, expiredSess.SessionToken, body)
	if resp.StatusCode != http.StatusUnauthorized {
		t.Fatalf("expired status=%d body=%s", resp.StatusCode, redactSecrets(raw))
	}
	assertErrorEnvelope(t, raw, "UNAUTHORIZED")
	assertNoSecretLeak(t, raw, expiredSess.SessionToken)
}

func TestCasualQueue_InvalidRules(t *testing.T) {
	baseURL, ts, _ := newQueueServer(t)
	_, token := issueGuestToken(t, ts)
	url := baseURL + "/v1/queues/casual"

	cases := []string{
		`{"round_kind":"east","game_mode":"STANDARD"}`,
		`{"round_kind":"EAST","game_mode":"standard"}`,
		`{"round_kind":"SOUTH","game_mode":"STANDARD"}`,
		`{"round_kind":"EAST","game_mode":"RANKED"}`,
		`{"round_kind":"EAST"}`,
		`{}`,
		`not-json`,
	}
	for _, body := range cases {
		resp, raw := doJSON(t, http.MethodPost, url, token, []byte(body))
		if resp.StatusCode != http.StatusBadRequest {
			t.Fatalf("body=%s status=%d want 400; resp=%s", body, resp.StatusCode, redactSecrets(raw))
		}
		assertErrorEnvelope(t, raw, "INVALID_REQUEST")
		assertNoSecretLeak(t, raw, token)
	}
}

func TestCasualQueue_OwnerIsolation(t *testing.T) {
	baseURL, ts, q := newQueueServer(t)
	_, tokenA := issueGuestToken(t, ts)
	_, tokenB := issueGuestToken(t, ts)

	body := []byte(`{"round_kind":"HANCHAN","game_mode":"TRASH_TALK","character_id":"lin_yeche"}`)
	resp, raw := doJSON(t, http.MethodPost, baseURL+"/v1/queues/casual", tokenA, body)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("join status=%d body=%s", resp.StatusCode, redactSecrets(raw))
	}
	var join map[string]any
	_ = json.Unmarshal([]byte(raw), &join)
	ticketID, _ := join["ticket_id"].(string)

	respG, rawG := doJSON(t, http.MethodGet, baseURL+"/v1/queues/casual/"+ticketID, tokenB, nil)
	if respG.StatusCode != http.StatusForbidden {
		t.Fatalf("other GET status=%d, want 403; body=%s", respG.StatusCode, redactSecrets(rawG))
	}
	assertErrorEnvelope(t, rawG, "FORBIDDEN")
	assertNoSecretLeak(t, rawG, tokenA, tokenB)

	respD, rawD := doJSON(t, http.MethodDelete, baseURL+"/v1/queues/casual/"+ticketID, tokenB, nil)
	if respD.StatusCode != http.StatusForbidden {
		t.Fatalf("other DELETE status=%d, want 403; body=%s", respD.StatusCode, redactSecrets(rawD))
	}
	assertErrorEnvelope(t, rawD, "FORBIDDEN")
	assertNoSecretLeak(t, rawD, tokenA, tokenB)

	// 失败取消后 owner ticket 仍 waiting 且可消费
	if !q.IsConsumable(context.Background(), ticketID) {
		t.Fatal("owner ticket must remain consumable after failed foreign cancel")
	}
	respG2, rawG2 := doJSON(t, http.MethodGet, baseURL+"/v1/queues/casual/"+ticketID, tokenA, nil)
	if respG2.StatusCode != http.StatusOK || !strings.Contains(rawG2, `"status":"waiting"`) {
		t.Fatalf("owner GET after other ops: %d %s", respG2.StatusCode, redactSecrets(rawG2))
	}
}

// TestCasualQueue_UnsupportedMethods_JSONEnvelope 锁定 ADR 统一错误包络（非 ServeMux 纯文本 405）。
func TestCasualQueue_UnsupportedMethods_JSONEnvelope(t *testing.T) {
	baseURL, ts, _ := newQueueServer(t)
	_, token := issueGuestToken(t, ts)

	// 集合路径：仅允许 POST；GET 必须 405 + Allow: POST + METHOD_NOT_ALLOWED JSON
	resp, raw := doJSON(t, http.MethodGet, baseURL+"/v1/queues/casual", token, nil)
	if resp.StatusCode != http.StatusMethodNotAllowed {
		t.Fatalf("GET /v1/queues/casual status=%d, want 405; body=%s", resp.StatusCode, redactSecrets(raw))
	}
	if allow := resp.Header.Get("Allow"); allow != http.MethodPost {
		t.Fatalf("GET collection Allow=%q, want %q; body=%s", allow, http.MethodPost, redactSecrets(raw))
	}
	if ct := resp.Header.Get("Content-Type"); !strings.Contains(ct, "application/json") {
		t.Fatalf("GET collection Content-Type=%q, want application/json; body=%s", ct, redactSecrets(raw))
	}
	assertErrorEnvelope(t, raw, "METHOD_NOT_ALLOWED")
	assertNoSecretLeak(t, raw, token)

	// 票据路径：仅允许 GET, DELETE；POST 必须 405 + 锁定 Allow 多值表达 + METHOD_NOT_ALLOWED JSON
	ticketPath := baseURL + "/v1/queues/casual/not-a-real-ticket"
	resp2, raw2 := doJSON(t, http.MethodPost, ticketPath, token, []byte(`{}`))
	if resp2.StatusCode != http.StatusMethodNotAllowed {
		t.Fatalf("POST ticket status=%d, want 405; body=%s", resp2.StatusCode, redactSecrets(raw2))
	}
	// 锁定实现使用的 Allow 字面量（与 guest fallback 风格一致的 Header.Set 单值）
	const wantAllowTicket = "GET, DELETE"
	if allow := resp2.Header.Get("Allow"); allow != wantAllowTicket {
		t.Fatalf("POST ticket Allow=%q, want %q; body=%s", allow, wantAllowTicket, redactSecrets(raw2))
	}
	if ct := resp2.Header.Get("Content-Type"); !strings.Contains(ct, "application/json") {
		t.Fatalf("POST ticket Content-Type=%q, want application/json; body=%s", ct, redactSecrets(raw2))
	}
	assertErrorEnvelope(t, raw2, "METHOD_NOT_ALLOWED")
	assertNoSecretLeak(t, raw2, token)

	// 再覆盖 DELETE 集合路径（同样只允许 POST）
	resp3, raw3 := doJSON(t, http.MethodDelete, baseURL+"/v1/queues/casual", token, nil)
	if resp3.StatusCode != http.StatusMethodNotAllowed {
		t.Fatalf("DELETE collection status=%d, want 405; body=%s", resp3.StatusCode, redactSecrets(raw3))
	}
	if allow := resp3.Header.Get("Allow"); allow != http.MethodPost {
		t.Fatalf("DELETE collection Allow=%q, want POST; body=%s", allow, redactSecrets(raw3))
	}
	assertErrorEnvelope(t, raw3, "METHOD_NOT_ALLOWED")
	assertNoSecretLeak(t, raw3, token)
}

func TestCasualQueue_FourPoolsHTTP(t *testing.T) {
	baseURL, ts, q := newQueueServer(t)
	_, token := issueGuestToken(t, ts)
	combos := []string{
		`{"round_kind":"EAST","game_mode":"STANDARD","character_id":"lin_yeche"}`,
		`{"round_kind":"EAST","game_mode":"TRASH_TALK","character_id":"lin_yeche"}`,
		`{"round_kind":"HANCHAN","game_mode":"STANDARD","character_id":"lin_yeche"}`,
		`{"round_kind":"HANCHAN","game_mode":"TRASH_TALK","character_id":"lin_yeche"}`,
	}
	ids := map[string]bool{}
	for _, body := range combos {
		resp, raw := doJSON(t, http.MethodPost, baseURL+"/v1/queues/casual", token, []byte(body))
		if resp.StatusCode != http.StatusOK {
			t.Fatalf("join %s status=%d body=%s", body, resp.StatusCode, redactSecrets(raw))
		}
		var join map[string]any
		_ = json.Unmarshal([]byte(raw), &join)
		id, _ := join["ticket_id"].(string)
		if ids[id] {
			t.Fatalf("duplicate ticket across pools: %s", id)
		}
		ids[id] = true
		if !q.IsConsumable(context.Background(), id) {
			t.Fatalf("ticket %s not consumable", id)
		}
	}
	if len(ids) != 4 {
		t.Fatalf("want 4 tickets, got %d", len(ids))
	}
}

func assertNoSecretLeak(t *testing.T, body string, secrets ...string) {
	t.Helper()
	if strings.Contains(body, httpTestSecret) {
		t.Fatal("body contains signing secret")
	}
	for _, s := range secrets {
		if s != "" && strings.Contains(body, s) {
			t.Fatal("body contains token material")
		}
	}
}
