package queue

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/redis/go-redis/v9"
)

// injectStalePoolMembers 向池插入低 score、无对应 waiting ticket 的 stale member。
func injectStalePoolMembers(t *testing.T, f *matchFixture, rk RoundKind, gm GameMode, n int, baseScore int64) {
	t.Helper()
	ctx := context.Background()
	pkey := f.prefix + "pool:" + string(rk) + ":" + string(gm)
	for i := 0; i < n; i++ {
		// 不写 ticket 哈希 → load 为 missing → stale
		member := fmt.Sprintf("stale-missing-%d", i)
		if err := f.rdb.ZAdd(ctx, pkey, redis.Z{Score: float64(baseScore + int64(i)), Member: member}).Err(); err != nil {
			t.Fatalf("ZAdd stale: %v", err)
		}
	}
}

// TestRework3_P1_StaleHeadMustNotAIFillWhenFourthHumanExists
// 29 stale + 3 已满 30s 有效 + 第 33 项第 4 真人 → 必须 4 HUMAN / 0 AI。
func TestRework3_P1_StaleHeadMustNotAIFillWhenFourthHumanExists(t *testing.T) {
	f := newMatchFixture(t)
	ctx := context.Background()
	base := f.clk.Now().UTC().UnixMilli()

	// 先插 29 个更低 score 的 stale
	injectStalePoolMembers(t, f, RoundKindEast, GameModeStandard, 29, base-100000)

	// 3 个有效（score 高于 stale）
	humans := make([]Ticket, 0, 4)
	for i := 0; i < 3; i++ {
		tk, err := f.svc.Enqueue(ctx, fmt.Sprintf("h-%d", i), RoundKindEast, GameModeStandard)
		if err != nil {
			t.Fatalf("enqueue: %v", err)
		}
		humans = append(humans, tk)
	}
	// 第 4 真人（将成为清 stale 后的第 4 有效）
	tk4, err := f.svc.Enqueue(ctx, "h-3", RoundKindEast, GameModeStandard)
	if err != nil {
		t.Fatalf("enqueue4: %v", err)
	}
	humans = append(humans, tk4)

	// 满 30s 使 1–3 人路径在错误实现下可能 AI 补位
	f.clk.Advance(30 * time.Second)

	res, err := f.svc.MatchPool(ctx, RoundKindEast, GameModeStandard, MatchParams{
		WorkerEndpoint:      f.worker,
		VoiceWorkerEndpoint: f.voiceWorker,
		TokenIssuer:         f.issuer,
	})
	if err != nil {
		t.Fatalf("MatchPool: %v", err)
	}
	if !res.Matched {
		t.Fatal("expected match")
	}
	if res.HumanCount != 4 || res.AICount != 0 {
		t.Fatalf("want 4 HUMAN / 0 AI, got humans=%d ai=%d (stale head must not hide 4th human)", res.HumanCount, res.AICount)
	}
	room, err := f.svc.GetRoom(ctx, res.RoomID)
	if err != nil {
		t.Fatalf("GetRoom: %v", err)
	}
	if room.HumanCount != 4 || room.AICount != 0 {
		t.Fatalf("room humans=%d ai=%d", room.HumanCount, room.AICount)
	}
	for _, occ := range room.Seats {
		if occ.Kind != SeatKindHuman {
			t.Fatalf("seat kind=%q want HUMAN", occ.Kind)
		}
	}
	for _, h := range humans {
		tk, err := f.svc.Get(ctx, h.GuestID, h.TicketID)
		if err != nil || tk.Status != StatusAssigned || tk.RoomToken == "" {
			t.Fatalf("human incomplete: %+v err=%v", tk, err)
		}
	}
}

// TestRework3_P1_FullStaleWindowThenFourHumans
// 32 stale + 4 有效：MatchPool 或同次 MatchAll 必须开 4 真人房，不能永久 NONE。
func TestRework3_P1_FullStaleWindowThenFourHumans(t *testing.T) {
	f := newMatchFixture(t)
	ctx := context.Background()
	base := f.clk.Now().UTC().UnixMilli()
	injectStalePoolMembers(t, f, RoundKindEast, GameModeStandard, 32, base-100000)

	tickets := enqueueN(t, f.svc, 4, RoundKindEast, GameModeStandard)

	res, err := f.svc.MatchPool(ctx, RoundKindEast, GameModeStandard, MatchParams{
		WorkerEndpoint:      f.worker,
		VoiceWorkerEndpoint: f.voiceWorker,
		TokenIssuer:         f.issuer,
	})
	if err != nil {
		t.Fatalf("MatchPool: %v", err)
	}
	if !res.Matched {
		// 允许更严格有界：同一 MatchAll 扫描完成
		m, err := NewMatcher(MatcherOptions{
			Service:             f.svc,
			TokenIssuer:         f.issuer,
			WorkerEndpoint:      f.worker,
			VoiceWorkerEndpoint: f.voiceWorker,
		})
		if err != nil {
			t.Fatalf("NewMatcher: %v", err)
		}
		if err := m.MatchAll(ctx); err != nil {
			t.Fatalf("MatchAll: %v", err)
		}
	}
	roomIDs := map[string]bool{}
	for _, tk0 := range tickets {
		tk, err := f.svc.Get(ctx, tk0.GuestID, tk0.TicketID)
		if err != nil {
			t.Fatalf("Get: %v", err)
		}
		if tk.Status != StatusAssigned || tk.RoomToken == "" {
			t.Fatalf("must assign after stale clean, got %+v", tk)
		}
		roomIDs[tk.RoomID] = true
	}
	if len(roomIDs) != 1 {
		t.Fatalf("want 1 room, got %d", len(roomIDs))
	}
}

// TestRework3_P1_ConcurrentIndependentClientsCleanStale
// 至少 4 个独立 redis.Client + Service 并发消费；单房、完整 token。
func TestRework3_P1_ConcurrentIndependentClientsCleanStale(t *testing.T) {
	addr := "127.0.0.1:6379"
	if v := getenvRedisAddr(); v != "" {
		addr = v
	}
	// 先确认 Redis
	probe := requireRealRedis(t)
	_ = probe

	prefix := "test:match:r3indep:" + t.Name() + ":"
	start := time.Date(2026, 7, 24, 12, 0, 0, 0, time.UTC)
	clk := &mutableClock{t: start}

	const nClients = 4
	clients := make([]*redis.Client, nClients)
	svcs := make([]*Service, nClients)
	for i := 0; i < nClients; i++ {
		c := redis.NewClient(&redis.Options{Addr: addr, Password: getenvRedisPassword(), DB: redisDBFromEnv()})
		t.Cleanup(func() { _ = c.Close() })
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		if err := c.Ping(ctx).Err(); err != nil {
			cancel()
			t.Fatalf("independent redis client %d ping: %v", i, err)
		}
		cancel()
		clients[i] = c
		svc, err := NewService(Options{
			Redis:     c,
			KeyPrefix: prefix,
			Clock:     clk,
			IDGen:     &seqIDGenVal{n: i * 1000},
		})
		if err != nil {
			t.Fatalf("NewService %d: %v", i, err)
		}
		svcs[i] = svc
	}
	t.Cleanup(func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		iter := clients[0].Scan(ctx, 0, prefix+"*", 100).Iterator()
		var keys []string
		for iter.Next(ctx) {
			keys = append(keys, iter.Val())
		}
		if len(keys) > 0 {
			_ = clients[0].Del(ctx, keys...).Err()
		}
	})

	issuer := newRecordingIssuer(t, clk)
	worker := "ws://worker.indep.test:9000"
	voiceWorker := "ws://voice.indep.test:9001"
	ctx := context.Background()

	// stale + 4 humans via client 0
	base := clk.Now().UTC().UnixMilli()
	for i := 0; i < 20; i++ {
		_ = clients[0].ZAdd(ctx, prefix+"pool:EAST:STANDARD", redis.Z{
			Score:  float64(base - 50000 + int64(i)),
			Member: fmt.Sprintf("stale-indep-%d", i),
		}).Err()
	}
	tickets := make([]Ticket, 0, 4)
	for i := 0; i < 4; i++ {
		tk, err := svcs[0].Enqueue(ctx, fmt.Sprintf("indep-g-%d", i), RoundKindEast, GameModeStandard)
		if err != nil {
			t.Fatalf("enqueue: %v", err)
		}
		tickets = append(tickets, tk)
	}

	var wg sync.WaitGroup
	results := make([]MatchResult, nClients)
	errs := make([]error, nClients)
	wg.Add(nClients)
	for i := 0; i < nClients; i++ {
		go func(i int) {
			defer wg.Done()
			results[i], errs[i] = svcs[i].MatchPool(ctx, RoundKindEast, GameModeStandard, MatchParams{
				WorkerEndpoint:      worker,
				VoiceWorkerEndpoint: voiceWorker,
				TokenIssuer:         issuer,
			})
		}(i)
	}
	wg.Wait()

	matched := 0
	var roomID string
	for i, err := range errs {
		if err != nil {
			t.Fatalf("client %d: %v", i, err)
		}
		if results[i].Matched {
			matched++
			if roomID == "" {
				roomID = results[i].RoomID
			} else if results[i].RoomID != roomID {
				t.Fatalf("multiple rooms: %s vs %s", roomID, results[i].RoomID)
			}
		}
	}
	if matched != 1 {
		t.Fatalf("matched count=%d want 1", matched)
	}
	// 用独立 client 读完整分配
	for _, tk0 := range tickets {
		tk, err := svcs[nClients-1].Get(ctx, tk0.GuestID, tk0.TicketID)
		if err != nil {
			t.Fatalf("Get: %v", err)
		}
		if tk.Status != StatusAssigned || tk.RoomID != roomID || tk.RoomToken == "" || tk.Worker != worker {
			t.Fatalf("incomplete cross-client: %+v", tk)
		}
		if _, err := issuer.VerifyRoomToken(tk.RoomToken, tk.RoomID, tk.Seat); err != nil {
			t.Fatalf("verify: %v", err)
		}
	}
}

func getenvRedisAddr() string {
	return os.Getenv("REDIS_ADDR")
}

func getenvRedisPassword() string {
	return os.Getenv("REDIS_PASSWORD")
}

// TestRework3_P2_OnErrorNeverLeaksSecretOrToken
// 注入含 secret / v1.r. / raw-secret 的错误；后台回调可见载荷不得含三者。
func TestRework3_P2_OnErrorNeverLeaksSecretOrToken(t *testing.T) {
	f := newMatchFixture(t)
	ctx := context.Background()
	_ = enqueueN(t, f.svc, 4, RoundKindEast, GameModeStandard)

	const rawSecret = "raw-secret-value-should-never-log"
	const leakTok = "v1.r.eyJ0eXAiOiJyb29tIn0.signaturepart"
	leaky := RoomTokenIssuerFunc(func(sessionID, roomID string, seat int, roundKind, gameMode string, participants []string) (string, time.Time, error) {
		return "", time.Time{}, fmt.Errorf("issuer boom secret=%s token=%s extra=%s", matchTestSecret, leakTok, rawSecret)
	})

	var reports atomic.Int32
	var payloads []string
	var mu sync.Mutex

	m, err := NewMatcher(MatcherOptions{
		Service:             f.svc,
		TokenIssuer:         leaky,
		WorkerEndpoint:      f.worker,
		VoiceWorkerEndpoint: f.voiceWorker,
		ScanInterval:        15 * time.Millisecond,
		OnError: func(op string, safeMsg string) {
			reports.Add(1)
			mu.Lock()
			payloads = append(payloads, op+"|"+safeMsg)
			mu.Unlock()
			if strings.Contains(safeMsg, matchTestSecret) || strings.Contains(op, matchTestSecret) {
				t.Errorf("leaked signing secret in OnError")
			}
			if strings.Contains(safeMsg, leakTok) || strings.Contains(safeMsg, "v1.r.") {
				t.Errorf("leaked room token material in OnError: %q", safeMsg)
			}
			if strings.Contains(safeMsg, rawSecret) {
				t.Errorf("leaked raw-secret-value in OnError: %q", safeMsg)
			}
		},
	})
	if err != nil {
		t.Fatalf("NewMatcher: %v", err)
	}
	// MatchAll 内部仍可返回原 error（调用方），但后台 loop 必须去敏
	if err := m.MatchAll(ctx); err == nil {
		t.Fatal("MatchAll should surface error to caller")
	}
	// 调用方可见原 error（允许），但我们主要验证 OnError 后台路径
	m.Start()
	deadline := time.Now().Add(500 * time.Millisecond)
	for time.Now().Before(deadline) && reports.Load() == 0 {
		time.Sleep(10 * time.Millisecond)
	}
	_ = m.Stop(context.Background())
	if reports.Load() == 0 {
		t.Fatal("expected sanitized OnError reports from background loop")
	}
	mu.Lock()
	defer mu.Unlock()
	foundOp := false
	for _, p := range payloads {
		if strings.HasPrefix(p, "match_all|") || strings.Contains(p, "match_all") {
			foundOp = true
		}
		if strings.Contains(p, matchTestSecret) || strings.Contains(p, leakTok) || strings.Contains(p, rawSecret) {
			t.Fatalf("payload leaked secrets: %q", p)
		}
	}
	if !foundOp {
		t.Fatalf("expected stable op=match_all, payloads=%v", payloads)
	}

	// 恢复后仍可分配
	mOK, err := NewMatcher(MatcherOptions{
		Service:             f.svc,
		TokenIssuer:         f.issuer,
		WorkerEndpoint:      f.worker,
		VoiceWorkerEndpoint: f.voiceWorker,
	})
	if err != nil {
		t.Fatalf("mOK: %v", err)
	}
	if err := mOK.MatchAll(ctx); err != nil {
		t.Fatalf("recover: %v", err)
	}
}

// TestRework3_TicketTimeJSONPreservesMilliseconds
func TestRework3_TicketTimeJSONPreservesMilliseconds(t *testing.T) {
	ms := time.Date(2026, 7, 24, 12, 0, 0, 277*int(time.Millisecond), time.UTC)
	tt := TicketTime(ms)
	b, err := json.Marshal(tt)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	s := string(b)
	if !strings.Contains(s, ".277") {
		t.Fatalf("MarshalJSON dropped milliseconds: %s", s)
	}
	var back TicketTime
	if err := json.Unmarshal(b, &back); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if back.Time().UnixMilli() != ms.UnixMilli() {
		t.Fatalf("round-trip ms: got %v want %v", back.Time(), ms)
	}
	// 整秒兼容
	whole := TicketTime(time.Date(2026, 7, 24, 12, 0, 0, 0, time.UTC))
	bw, _ := json.Marshal(whole)
	if strings.Contains(string(bw), ".") {
		// 允许无小数
	}
	var w2 TicketTime
	if err := json.Unmarshal([]byte(`"2026-07-24T12:00:00Z"`), &w2); err != nil {
		t.Fatalf("whole second unmarshal: %v", err)
	}
}
