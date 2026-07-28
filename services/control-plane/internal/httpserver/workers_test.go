package httpserver

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/lov-team/mahjong-game/services/control-plane/internal/queue"
	"github.com/lov-team/mahjong-game/services/control-plane/internal/redisx"
	"github.com/lov-team/mahjong-game/services/control-plane/internal/tokens"
	"github.com/lov-team/mahjong-game/services/control-plane/internal/workers"
	"github.com/redis/go-redis/v9"
)

const workerHTTPRegToken = "worker-reg-token-http-test"

func newWorkerHTTPFixture(t *testing.T) (baseURL string, reg *workers.Registry, clk *httpMutableClock, rdb *redis.Client) {
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
		t.Fatalf("真实 Redis 不可用: %v", err)
	}
	prefix := "test:http:workers:" + t.Name() + ":"
	clk = &httpMutableClock{t: time.Date(2026, 7, 26, 12, 0, 0, 0, time.UTC)}
	reg, err = workers.NewRegistry(workers.Options{
		Redis:        c.Redis(),
		KeyPrefix:    prefix + "reg:",
		CasualPrefix: prefix + "casual:",
		Clock:        clk,
		LeaseTTL:     10 * time.Second,
	})
	if err != nil {
		t.Fatalf("registry: %v", err)
	}
	q, err := queue.NewService(queue.Options{
		Redis:     c.Redis(),
		KeyPrefix: prefix + "casual:",
		Clock:     clk,
		Workers:   reg,
	})
	if err != nil {
		t.Fatalf("queue: %v", err)
	}
	ts, err := tokens.NewService(tokens.Options{Secret: httpTestSecret, Clock: clk})
	if err != nil {
		t.Fatalf("tokens: %v", err)
	}
	srv := New(Config{
		Addr:                    "127.0.0.1:0",
		Pinger:                  stubPinger{},
		TokenService:            ts,
		CasualQueue:             q,
		WorkerRegistry:          reg,
		WorkerRegistrationToken: workerHTTPRegToken,
	})
	baseURL = startServer(t, srv)
	t.Cleanup(func() { shutdownServer(t, srv) })
	t.Cleanup(func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		iter := c.Redis().Scan(ctx, 0, prefix+"*", 100).Iterator()
		var keys []string
		for iter.Next(ctx) {
			keys = append(keys, iter.Val())
		}
		if len(keys) > 0 {
			_ = c.Redis().Del(ctx, keys...).Err()
		}
	})
	return baseURL, reg, clk, c.Redis()
}

func TestHTTP_WorkerRegister_AuthAndRenew(t *testing.T) {
	base, reg, clk, _ := newWorkerHTTPFixture(t)
	body := []byte(`{
		"worker_id":"w-http-1",
		"game_endpoint":"ws://127.0.0.1:9000",
		"voice_endpoint":"ws://127.0.0.1:9001",
		"capacity":2,
		"active_rooms":0
	}`)

	// 匿名拒绝
	resp, raw := doJSON(t, http.MethodPost, base+"/v1/internal/workers/register", "", body)
	if resp.StatusCode != http.StatusUnauthorized {
		t.Fatalf("anon status=%d body=%s", resp.StatusCode, redactSecrets(raw))
	}
	if strings.Contains(raw, workerHTTPRegToken) || strings.Contains(raw, httpTestSecret) {
		t.Fatal("auth error must not leak tokens")
	}
	// 错误 token 拒绝且不写状态
	req, _ := http.NewRequest(http.MethodPost, base+"/v1/internal/workers/register", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer wrong-token-value-xxxx")
	req.Header.Set("Content-Type", "application/json")
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("do: %v", err)
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusUnauthorized {
		t.Fatalf("bad token status=%d", res.StatusCode)
	}
	_, found, err := reg.Get(context.Background(), "w-http-1")
	if err != nil || found {
		t.Fatalf("must not register on auth failure: found=%v err=%v", found, err)
	}

	// 正确注册
	req2, _ := http.NewRequest(http.MethodPost, base+"/v1/internal/workers/register", bytes.NewReader(body))
	req2.Header.Set("Authorization", "Bearer "+workerHTTPRegToken)
	req2.Header.Set("Content-Type", "application/json")
	res2, err := http.DefaultClient.Do(req2)
	if err != nil {
		t.Fatalf("register: %v", err)
	}
	defer res2.Body.Close()
	var regBody map[string]any
	_ = json.NewDecoder(res2.Body).Decode(&regBody)
	if res2.StatusCode != http.StatusOK {
		t.Fatalf("register status=%d body=%v", res2.StatusCode, regBody)
	}
	if regBody["worker_id"] != "w-http-1" {
		t.Fatalf("body=%v", regBody)
	}
	if strings.Contains(raw, workerHTTPRegToken) {
		t.Fatal("must not leak reg token")
	}

	clk.Advance(3 * time.Second)
	// 续租
	bodyRenew := []byte(`{
		"worker_id":"w-http-1",
		"game_endpoint":"ws://127.0.0.1:9000",
		"voice_endpoint":"ws://127.0.0.1:9001",
		"capacity":2,
		"active_rooms":1
	}`)
	req3, _ := http.NewRequest(http.MethodPost, base+"/v1/internal/workers/register", bytes.NewReader(bodyRenew))
	req3.Header.Set("Authorization", "Bearer "+workerHTTPRegToken)
	req3.Header.Set("Content-Type", "application/json")
	res3, err := http.DefaultClient.Do(req3)
	if err != nil {
		t.Fatalf("renew: %v", err)
	}
	defer res3.Body.Close()
	if res3.StatusCode != http.StatusOK {
		t.Fatalf("renew status=%d", res3.StatusCode)
	}
	rec, ok, err := reg.Get(context.Background(), "w-http-1")
	if err != nil || !ok {
		t.Fatalf("Get: %v", err)
	}
	if rec.ReportedRooms != 1 {
		t.Fatalf("reported=%d", rec.ReportedRooms)
	}
}

func TestHTTP_WorkerAuth_RejectsWrongLengthWithoutLeak(t *testing.T) {
	base, reg, _, _ := newWorkerHTTPFixture(t)
	body := []byte(`{"worker_id":"w-x","game_endpoint":"ws://x","voice_endpoint":"ws://y","capacity":1,"active_rooms":0}`)
	// 不同长度 token
	req, _ := http.NewRequest(http.MethodPost, base+"/v1/internal/workers/register", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer short")
	req.Header.Set("Content-Type", "application/json")
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("do: %v", err)
	}
	defer res.Body.Close()
	raw, _ := io.ReadAll(res.Body)
	if res.StatusCode != http.StatusUnauthorized {
		t.Fatalf("status=%d", res.StatusCode)
	}
	if strings.Contains(string(raw), workerHTTPRegToken) || strings.Contains(string(raw), "short") {
		t.Fatal("must not echo tokens")
	}
	_, found, _ := reg.Get(context.Background(), "w-x")
	if found {
		t.Fatal("must not register on auth fail")
	}
}

func TestHTTP_CompleteRoom_ReleasesAndIdempotent(t *testing.T) {
	base, reg, _, rdb := newWorkerHTTPFixture(t)
	ctx := context.Background()
	body := []byte(`{"worker_id":"w-c1","game_endpoint":"ws://127.0.0.1:9000","voice_endpoint":"ws://127.0.0.1:9001","capacity":1,"active_rooms":0}`)
	req, _ := http.NewRequest(http.MethodPost, base+"/v1/internal/workers/register", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+workerHTTPRegToken)
	req.Header.Set("Content-Type", "application/json")
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("register: %v", err)
	}
	res.Body.Close()
	if res.StatusCode != http.StatusOK {
		t.Fatalf("register status=%d", res.StatusCode)
	}
	roomID := "room-http-done"
	rkey := reg.CasualPrefix() + "room:" + roomID
	if err := rdb.HSet(ctx, rkey, map[string]interface{}{
		"room_id": roomID, "worker_id": "w-c1", "status": workers.StatusActive, "human_count": "1",
	}).Err(); err != nil {
		t.Fatalf("seed room: %v", err)
	}
	if err := rdb.SAdd(ctx, reg.RoomsKey("w-c1"), roomID).Err(); err != nil {
		t.Fatalf("sadd: %v", err)
	}
	if err := rdb.HSet(ctx, reg.WorkerKey("w-c1"), "reserved_rooms", "1").Err(); err != nil {
		t.Fatalf("reserved: %v", err)
	}
	cbody := []byte(`{"worker_id":"w-c1","room_id":"` + roomID + `"}`)
	req2, _ := http.NewRequest(http.MethodPost, base+"/v1/internal/workers/rooms/complete", bytes.NewReader(cbody))
	req2.Header.Set("Authorization", "Bearer "+workerHTTPRegToken)
	req2.Header.Set("Content-Type", "application/json")
	res2, err := http.DefaultClient.Do(req2)
	if err != nil {
		t.Fatalf("complete: %v", err)
	}
	res2.Body.Close()
	if res2.StatusCode != http.StatusOK {
		t.Fatalf("complete status=%d", res2.StatusCode)
	}
	rec, ok, err := reg.Get(ctx, "w-c1")
	if err != nil || !ok || rec.ReservedRooms != 0 {
		t.Fatalf("reserved after complete=%v ok=%v err=%v", rec.ReservedRooms, ok, err)
	}
	req3, _ := http.NewRequest(http.MethodPost, base+"/v1/internal/workers/rooms/complete", bytes.NewReader(cbody))
	req3.Header.Set("Authorization", "Bearer "+workerHTTPRegToken)
	req3.Header.Set("Content-Type", "application/json")
	res3, err := http.DefaultClient.Do(req3)
	if err != nil {
		t.Fatalf("complete2: %v", err)
	}
	res3.Body.Close()
	if res3.StatusCode != http.StatusOK {
		t.Fatalf("idempotent complete status=%d", res3.StatusCode)
	}
	rec, _, _ = reg.Get(ctx, "w-c1")
	if rec.ReservedRooms != 0 {
		t.Fatalf("reserved must stay 0, got %d", rec.ReservedRooms)
	}
}

func TestHTTP_TicketFailedReturnsROOM_FAILED(t *testing.T) {
	f := newMatchHTTPFixture(t)
	_, token := issueGuestToken(t, f.ts)
	// 4 人立即匹配
	tokensList := make([]string, 0, 4)
	ticketIDs := make([]string, 0, 4)
	for i := 0; i < 4; i++ {
		_, tok := issueGuestToken(t, f.ts)
		tokensList = append(tokensList, tok)
		j := f.join(t, tok)
		ticketIDs = append(ticketIDs, j["ticket_id"].(string))
	}
	_ = token
	res, err := f.q.MatchPool(context.Background(), queue.RoundKindEast, queue.GameModeStandard, queue.MatchParams{
		TokenIssuer: f.ts,
	})
	if err != nil || !res.Matched {
		t.Fatalf("match: %+v %v", res, err)
	}

	// 仅使 worker 租约失效，不推进游客 token 时钟（避免 GET 401）。
	wkey := f.reg.WorkerKey("http-w1")
	if err := f.rdb.HSet(context.Background(), wkey, "lease_expires_at_ms", "0").Err(); err != nil {
		t.Fatalf("expire worker lease: %v", err)
	}
	if _, err := f.reg.ReapExpired(context.Background()); err != nil {
		t.Fatalf("reap: %v", err)
	}

	code, body, raw := f.getTicket(t, tokensList[0], ticketIDs[0])
	if code != http.StatusOK {
		t.Fatalf("GET status=%d body=%s", code, redactSecrets(raw))
	}
	if body["status"] != "failed" {
		t.Fatalf("status=%v want failed body=%s", body["status"], redactSecrets(raw))
	}
	if body["code"] != "ROOM_FAILED" {
		t.Fatalf("code=%v want ROOM_FAILED", body["code"])
	}
	// 不得伪装 assigned 完整字段（room_token 不应再作为成功分配出现）
	if tok, ok := body["room_token"]; ok && tok != "" {
		t.Fatalf("failed ticket must not present room_token as assigned success")
	}
}

func TestHTTP_FailRoom_ReleasesAndIdempotent(t *testing.T) {
	base, reg, _, rdb := newWorkerHTTPFixture(t)
	ctx := context.Background()
	body := []byte(`{"worker_id":"w-f1","game_endpoint":"ws://127.0.0.1:9000","voice_endpoint":"ws://127.0.0.1:9001","capacity":1,"active_rooms":0}`)
	req, _ := http.NewRequest(http.MethodPost, base+"/v1/internal/workers/register", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+workerHTTPRegToken)
	req.Header.Set("Content-Type", "application/json")
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("register: %v", err)
	}
	res.Body.Close()
	if res.StatusCode != http.StatusOK {
		t.Fatalf("register status=%d", res.StatusCode)
	}
	roomID := "room-http-fail"
	rkey := reg.CasualPrefix() + "room:" + roomID
	tid := "ticket-http-fail-0"
	if err := rdb.HSet(ctx, rkey, map[string]interface{}{
		"room_id": roomID, "worker_id": "w-f1", "status": workers.StatusActive,
		"human_count": "1", "seat_0_ticket_id": tid,
	}).Err(); err != nil {
		t.Fatalf("seed room: %v", err)
	}
	tkey := reg.CasualPrefix() + "ticket:" + tid
	if err := rdb.HSet(ctx, tkey, map[string]interface{}{
		"ticket_id": tid, "status": workers.StatusAssigned, "room_id": roomID, "seat": "0",
	}).Err(); err != nil {
		t.Fatalf("seed ticket: %v", err)
	}
	if err := rdb.SAdd(ctx, reg.RoomsKey("w-f1"), roomID).Err(); err != nil {
		t.Fatalf("sadd: %v", err)
	}
	if err := rdb.HSet(ctx, reg.WorkerKey("w-f1"), "reserved_rooms", "1").Err(); err != nil {
		t.Fatalf("reserved: %v", err)
	}
	fbody := []byte(`{"worker_id":"w-f1","room_id":"` + roomID + `","fail_code":"ROOM_FAILED"}`)
	req2, _ := http.NewRequest(http.MethodPost, base+"/v1/internal/workers/rooms/fail", bytes.NewReader(fbody))
	req2.Header.Set("Authorization", "Bearer "+workerHTTPRegToken)
	req2.Header.Set("Content-Type", "application/json")
	res2, err := http.DefaultClient.Do(req2)
	if err != nil {
		t.Fatalf("fail: %v", err)
	}
	res2.Body.Close()
	if res2.StatusCode != http.StatusOK {
		t.Fatalf("fail status=%d", res2.StatusCode)
	}
	rec, ok, err := reg.Get(ctx, "w-f1")
	if err != nil || !ok || rec.ReservedRooms != 0 {
		t.Fatalf("reserved after fail=%v ok=%v err=%v", rec.ReservedRooms, ok, err)
	}
	st, _ := rdb.HGet(ctx, rkey, "status").Result()
	if st != workers.StatusFailed {
		t.Fatalf("room status=%q", st)
	}
	tst, _ := rdb.HGet(ctx, tkey, "status").Result()
	if tst != workers.StatusFailed {
		t.Fatalf("ticket status=%q", tst)
	}
	// 幂等
	req3, _ := http.NewRequest(http.MethodPost, base+"/v1/internal/workers/rooms/fail", bytes.NewReader(fbody))
	req3.Header.Set("Authorization", "Bearer "+workerHTTPRegToken)
	req3.Header.Set("Content-Type", "application/json")
	res3, err := http.DefaultClient.Do(req3)
	if err != nil {
		t.Fatalf("fail2: %v", err)
	}
	res3.Body.Close()
	if res3.StatusCode != http.StatusOK {
		t.Fatalf("idempotent fail status=%d", res3.StatusCode)
	}
	rec, _, _ = reg.Get(ctx, "w-f1")
	if rec.ReservedRooms != 0 {
		t.Fatalf("reserved must stay 0, got %d", rec.ReservedRooms)
	}
}

func TestHTTP_FailRoom_RejectsArbitraryFailCode(t *testing.T) {
	base, reg, _, rdb := newWorkerHTTPFixture(t)
	ctx := context.Background()
	body := []byte(`{"worker_id":"w-fc1","game_endpoint":"ws://127.0.0.1:9000","voice_endpoint":"ws://127.0.0.1:9001","capacity":1,"active_rooms":0}`)
	req, _ := http.NewRequest(http.MethodPost, base+"/v1/internal/workers/register", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+workerHTTPRegToken)
	req.Header.Set("Content-Type", "application/json")
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("register: %v", err)
	}
	res.Body.Close()
	roomID := "room-http-bad-code"
	rkey := reg.CasualPrefix() + "room:" + roomID
	if err := rdb.HSet(ctx, rkey, map[string]interface{}{
		"room_id": roomID, "worker_id": "w-fc1", "status": workers.StatusActive,
	}).Err(); err != nil {
		t.Fatalf("seed: %v", err)
	}
	fbody := []byte(`{"worker_id":"w-fc1","room_id":"` + roomID + `","fail_code":"NOT_A_STABLE_CODE"}`)
	req2, _ := http.NewRequest(http.MethodPost, base+"/v1/internal/workers/rooms/fail", bytes.NewReader(fbody))
	req2.Header.Set("Authorization", "Bearer "+workerHTTPRegToken)
	req2.Header.Set("Content-Type", "application/json")
	res2, err := http.DefaultClient.Do(req2)
	if err != nil {
		t.Fatalf("fail: %v", err)
	}
	defer res2.Body.Close()
	if res2.StatusCode != http.StatusBadRequest {
		t.Fatalf("status=%d want 400", res2.StatusCode)
	}
	st, _ := rdb.HGet(ctx, rkey, "status").Result()
	if st != workers.StatusActive {
		t.Fatalf("room must stay active, got %q", st)
	}
}
