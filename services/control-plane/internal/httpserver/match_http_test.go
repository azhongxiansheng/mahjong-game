package httpserver

import (
	"context"
	"encoding/json"
	"net/http"
	"os"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/lov-team/mahjong-game/services/control-plane/internal/queue"
	"github.com/lov-team/mahjong-game/services/control-plane/internal/redisx"
	"github.com/lov-team/mahjong-game/services/control-plane/internal/tokens"
	"github.com/redis/go-redis/v9"
)

type httpMutableClock struct {
	mu sync.Mutex
	t  time.Time
}

func (c *httpMutableClock) Now() time.Time {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.t
}

func (c *httpMutableClock) Advance(d time.Duration) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.t = c.t.Add(d)
}

type matchHTTPFixture struct {
	baseURL string
	ts      *tokens.Service
	q       *queue.Service
	rdb     *redis.Client
	clk     *httpMutableClock
	worker  string
	prefix  string
}

func newMatchHTTPFixture(t *testing.T) *matchHTTPFixture {
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

	prefix := "test:http:match:" + t.Name() + ":"
	clk := &httpMutableClock{t: time.Date(2026, 7, 24, 12, 0, 0, 0, time.UTC)}
	q, err := queue.NewService(queue.Options{
		Redis:     c.Redis(),
		KeyPrefix: prefix,
		Clock:     clk,
	})
	if err != nil {
		t.Fatalf("queue: %v", err)
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

	ts, err := tokens.NewService(tokens.Options{
		Secret: httpTestSecret,
		Clock:  clk,
	})
	if err != nil {
		t.Fatalf("tokens: %v", err)
	}
	worker := "ws://worker.http.test:9000"
	srv := New(Config{
		Addr:         "127.0.0.1:0",
		Pinger:       stubPinger{},
		TokenService: ts,
		CasualQueue:  q,
	})
	baseURL := startServer(t, srv)
	t.Cleanup(func() { shutdownServer(t, srv) })
	return &matchHTTPFixture{
		baseURL: baseURL,
		ts:      ts,
		q:       q,
		rdb:     c.Redis(),
		clk:     clk,
		worker:  worker,
		prefix:  prefix,
	}
}

func (f *matchHTTPFixture) join(t *testing.T, token string) map[string]any {
	t.Helper()
	body := []byte(`{"round_kind":"EAST","game_mode":"STANDARD"}`)
	resp, raw := doJSON(t, http.MethodPost, f.baseURL+"/v1/queues/casual", token, body)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("join status=%d body=%s", resp.StatusCode, redactSecrets(raw))
	}
	var m map[string]any
	if err := json.Unmarshal([]byte(raw), &m); err != nil {
		t.Fatalf("json: %v", err)
	}
	return m
}

func (f *matchHTTPFixture) getTicket(t *testing.T, token, ticketID string) (int, map[string]any, string) {
	t.Helper()
	resp, raw := doJSON(t, http.MethodGet, f.baseURL+"/v1/queues/casual/"+ticketID, token, nil)
	var m map[string]any
	_ = json.Unmarshal([]byte(raw), &m)
	return resp.StatusCode, m, raw
}

func TestHTTP_MatchAssignedQuery_WaitingCancelledAssigned(t *testing.T) {
	f := newMatchHTTPFixture(t)
	_, token := issueGuestToken(t, f.ts)

	join := f.join(t, token)
	ticketID, _ := join["ticket_id"].(string)
	if join["status"] != "waiting" {
		t.Fatalf("join status=%v", join["status"])
	}

	// waiting 查询稳定
	code, got, raw := f.getTicket(t, token, ticketID)
	if code != http.StatusOK || got["status"] != "waiting" {
		t.Fatalf("waiting GET %d %s", code, redactSecrets(raw))
	}
	if _, ok := got["worker"]; ok {
		t.Fatal("waiting must not include worker")
	}
	if _, ok := got["room_token"]; ok {
		t.Fatal("waiting must not include room_token")
	}
	assertNoSecretLeak(t, raw, token)

	// 满 30s 匹配（服务层 MatchPool，模拟 matcher 自动推进）
	f.clk.Advance(30 * time.Second)
	res, err := f.q.MatchPool(context.Background(), queue.RoundKindEast, queue.GameModeStandard, queue.MatchParams{
		WorkerEndpoint: f.worker,
		TokenIssuer:    f.ts,
	})
	if err != nil || !res.Matched {
		t.Fatalf("MatchPool: matched=%v err=%v", res.Matched, err)
	}

	code, got, raw = f.getTicket(t, token, ticketID)
	if code != http.StatusOK {
		t.Fatalf("assigned GET status=%d body=%s", code, redactSecrets(raw))
	}
	if got["status"] != "assigned" {
		t.Fatalf("status=%v want assigned; body=%s", got["status"], redactSecrets(raw))
	}
	for _, k := range []string{"worker", "room_id", "seat", "room_token"} {
		if _, ok := got[k]; !ok {
			t.Fatalf("missing %s in assigned body %s", k, redactSecrets(raw))
		}
	}
	if got["worker"] != f.worker {
		t.Fatalf("worker=%v", got["worker"])
	}
	if got["room_id"] != res.RoomID {
		t.Fatalf("room_id=%v want %s", got["room_id"], res.RoomID)
	}
	seatF, ok := got["seat"].(float64)
	if !ok {
		t.Fatalf("seat type %T", got["seat"])
	}
	seat := int(seatF)
	roomToken, _ := got["room_token"].(string)
	if roomToken == "" {
		t.Fatal("empty room_token")
	}
	// 错误/响应不得含签名密钥；room_token 本身是业务字段允许出现在成功体，但密钥不行
	if strings.Contains(raw, httpTestSecret) {
		t.Fatal("response contains signing secret")
	}
	claims, err := f.ts.VerifyRoomToken(roomToken, res.RoomID, seat)
	if err != nil {
		t.Fatalf("VerifyRoomToken: %v", err)
	}
	if claims.SessionID == "" {
		t.Fatal("empty session in room claims")
	}
	// 跨房跨座
	if _, err := f.ts.VerifyRoomToken(roomToken, res.RoomID, (seat+1)%4); err == nil {
		t.Fatal("cross-seat must fail")
	}
	// session token 不能冒充 room token
	if _, err := f.ts.VerifyRoomToken(token, res.RoomID, seat); err == nil {
		t.Fatal("session token must not verify as room")
	}
	// room token 不能当 guest 鉴权
	resp, rawAuth := doJSON(t, http.MethodGet, f.baseURL+"/v1/queues/casual/"+ticketID, roomToken, nil)
	if resp.StatusCode != http.StatusUnauthorized {
		t.Fatalf("room token as session status=%d body=%s", resp.StatusCode, redactSecrets(rawAuth))
	}
	assertErrorEnvelope(t, rawAuth, "UNAUTHORIZED")
	assertNoSecretLeak(t, rawAuth, roomToken, token)

	// 取消 assigned：终态保持 assigned
	respC, rawC := doJSON(t, http.MethodDelete, f.baseURL+"/v1/queues/casual/"+ticketID, token, nil)
	if respC.StatusCode != http.StatusOK {
		t.Fatalf("cancel assigned status=%d body=%s", respC.StatusCode, redactSecrets(rawC))
	}
	if !strings.Contains(rawC, `"status":"assigned"`) {
		t.Fatalf("cancel assigned body=%s", redactSecrets(rawC))
	}
}

func TestHTTP_MatchCancelledStable(t *testing.T) {
	f := newMatchHTTPFixture(t)
	_, token := issueGuestToken(t, f.ts)
	join := f.join(t, token)
	ticketID, _ := join["ticket_id"].(string)

	resp, raw := doJSON(t, http.MethodDelete, f.baseURL+"/v1/queues/casual/"+ticketID, token, nil)
	if resp.StatusCode != http.StatusOK || !strings.Contains(raw, `"status":"cancelled"`) {
		t.Fatalf("cancel: %d %s", resp.StatusCode, redactSecrets(raw))
	}
	code, got, rawG := f.getTicket(t, token, ticketID)
	if code != http.StatusOK || got["status"] != "cancelled" {
		t.Fatalf("get cancelled: %d %s", code, redactSecrets(rawG))
	}
	if _, ok := got["worker"]; ok {
		t.Fatal("cancelled must not include worker")
	}
	assertNoSecretLeak(t, rawG, token)

	// 取消后满 30s 不得再被消费
	f.clk.Advance(30 * time.Second)
	res, err := f.q.MatchPool(context.Background(), queue.RoundKindEast, queue.GameModeStandard, queue.MatchParams{
		WorkerEndpoint: f.worker,
		TokenIssuer:    f.ts,
	})
	if err != nil {
		t.Fatalf("MatchPool: %v", err)
	}
	if res.Matched {
		t.Fatal("cancelled ticket must never be consumed")
	}
}

func TestHTTP_MatchFourHumansAssigned(t *testing.T) {
	f := newMatchHTTPFixture(t)
	type player struct {
		token    string
		ticketID string
	}
	players := make([]player, 4)
	for i := 0; i < 4; i++ {
		_, tok := issueGuestToken(t, f.ts)
		join := f.join(t, tok)
		players[i] = player{token: tok, ticketID: join["ticket_id"].(string)}
	}
	res, err := f.q.MatchPool(context.Background(), queue.RoundKindEast, queue.GameModeStandard, queue.MatchParams{
		WorkerEndpoint: f.worker,
		TokenIssuer:    f.ts,
	})
	if err != nil || !res.Matched || res.HumanCount != 4 {
		t.Fatalf("match: %+v err=%v", res, err)
	}
	seats := map[int]bool{}
	for _, p := range players {
		code, got, raw := f.getTicket(t, p.token, p.ticketID)
		if code != http.StatusOK || got["status"] != "assigned" {
			t.Fatalf("GET: %d %s", code, redactSecrets(raw))
		}
		if got["room_id"] != res.RoomID {
			t.Fatalf("room mismatch")
		}
		seat := int(got["seat"].(float64))
		if seats[seat] {
			t.Fatalf("dup seat %d", seat)
		}
		seats[seat] = true
		// 非所属 guest 拒绝
		_, otherTok := issueGuestToken(t, f.ts)
		codeF, _, rawF := f.getTicket(t, otherTok, p.ticketID)
		if codeF != http.StatusForbidden {
			t.Fatalf("foreign GET status=%d body=%s", codeF, redactSecrets(rawF))
		}
		assertErrorEnvelope(t, rawF, "FORBIDDEN")
		assertNoSecretLeak(t, rawF, p.token, otherTok, got["room_token"].(string))
	}
	if len(seats) != 4 {
		t.Fatalf("seats=%d", len(seats))
	}
}

func TestHTTP_MatchCrossInstanceVisible(t *testing.T) {
	f := newMatchHTTPFixture(t)
	_, token := issueGuestToken(t, f.ts)
	join := f.join(t, token)
	ticketID := join["ticket_id"].(string)
	f.clk.Advance(30 * time.Second)
	res, err := f.q.MatchPool(context.Background(), queue.RoundKindEast, queue.GameModeStandard, queue.MatchParams{
		WorkerEndpoint: f.worker,
		TokenIssuer:    f.ts,
	})
	if err != nil || !res.Matched {
		t.Fatalf("match: %+v %v", res, err)
	}

	// 第二套 HTTP 服务 + 同 Redis 前缀，模拟另一 CP 实例查询
	q2, err := queue.NewService(queue.Options{
		Redis:     f.rdb,
		KeyPrefix: f.prefix,
		Clock:     f.clk,
	})
	if err != nil {
		t.Fatalf("q2: %v", err)
	}
	srv2 := New(Config{
		Addr:         "127.0.0.1:0",
		Pinger:       stubPinger{},
		TokenService: f.ts,
		CasualQueue:  q2,
	})
	base2 := startServer(t, srv2)
	t.Cleanup(func() { shutdownServer(t, srv2) })

	resp, raw := doJSON(t, http.MethodGet, base2+"/v1/queues/casual/"+ticketID, token, nil)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("cross GET status=%d body=%s", resp.StatusCode, redactSecrets(raw))
	}
	var got map[string]any
	_ = json.Unmarshal([]byte(raw), &got)
	if got["status"] != "assigned" || got["room_id"] != res.RoomID || got["worker"] != f.worker {
		t.Fatalf("cross body=%s", redactSecrets(raw))
	}
	if got["room_token"] == "" {
		t.Fatal("cross missing room_token")
	}
}

func TestHTTP_MatcherAutoAssignWithoutClientGET(t *testing.T) {
	// 证明匹配由 matcher 生命周期推进，不依赖客户端 GET
	f := newMatchHTTPFixture(t)
	_, token := issueGuestToken(t, f.ts)
	join := f.join(t, token)
	ticketID := join["ticket_id"].(string)
	claims, err := f.ts.VerifyGuestToken(token)
	if err != nil {
		t.Fatalf("verify guest: %v", err)
	}
	f.clk.Advance(30 * time.Second)

	m, err := queue.NewMatcher(queue.MatcherOptions{
		Service:        f.q,
		TokenIssuer:    f.ts,
		WorkerEndpoint: f.worker,
		ScanInterval:   15 * time.Millisecond,
	})
	if err != nil {
		t.Fatalf("NewMatcher: %v", err)
	}
	m.Start()
	t.Cleanup(func() { _ = m.Stop(context.Background()) })

	assigned := false
	for i := 0; i < 100; i++ {
		// 直接读队列服务（不发 GET），确认后台 matcher 已分配
		tk, err := f.q.Get(context.Background(), claims.GuestID, ticketID)
		if err == nil && tk.Status == queue.StatusAssigned {
			assigned = true
			break
		}
		time.Sleep(20 * time.Millisecond)
	}
	if !assigned {
		t.Fatal("matcher must assign without client GET")
	}
}
