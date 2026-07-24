package queue

import (
	"context"
	"fmt"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/lov-team/mahjong-game/services/control-plane/internal/tokens"
	"github.com/redis/go-redis/v9"
)

const matchTestSecret = "0123456789abcdef0123456789abcdef"

type mutableClock struct {
	mu sync.Mutex
	t  time.Time
}

func (c *mutableClock) Now() time.Time {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.t
}

func (c *mutableClock) Set(t time.Time) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.t = t.UTC()
}

func (c *mutableClock) Advance(d time.Duration) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.t = c.t.Add(d)
}

type recordingIssuer struct {
	inner *tokens.Service
	mu    sync.Mutex
	n     int
}

func newRecordingIssuer(t *testing.T, clk Clock) *recordingIssuer {
	t.Helper()
	svc, err := tokens.NewService(tokens.Options{
		Secret: matchTestSecret,
		Clock:  clk,
	})
	if err != nil {
		t.Fatalf("tokens.NewService: %v", err)
	}
	return &recordingIssuer{inner: svc}
}

func (r *recordingIssuer) IssueRoomToken(sessionID, roomID string, seat int) (string, time.Time, error) {
	r.mu.Lock()
	r.n++
	r.mu.Unlock()
	return r.inner.IssueRoomToken(sessionID, roomID, seat)
}

func (r *recordingIssuer) VerifyRoomToken(token, roomID string, seat int) (tokens.RoomClaims, error) {
	return r.inner.VerifyRoomToken(token, roomID, seat)
}

func (r *recordingIssuer) VerifyGuestToken(token string) (tokens.GuestClaims, error) {
	return r.inner.VerifyGuestToken(token)
}

func (r *recordingIssuer) IssueGuestSession() (tokens.GuestSession, error) {
	return r.inner.IssueGuestSession()
}

type matchFixture struct {
	svc    *Service
	rdb    *redis.Client
	clk    *mutableClock
	issuer *recordingIssuer
	worker string
	prefix string
}

func newMatchFixture(t *testing.T) *matchFixture {
	t.Helper()
	rdb := requireRealRedis(t)
	prefix := "test:match:" + t.Name() + ":"
	start := time.Date(2026, 7, 24, 12, 0, 0, 0, time.UTC)
	clk := &mutableClock{t: start}
	svc, err := NewService(Options{
		Redis:     rdb,
		KeyPrefix: prefix,
		Clock:     clk,
		IDGen:     &seqIDGenVal{},
	})
	if err != nil {
		t.Fatalf("NewService: %v", err)
	}
	t.Cleanup(func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		iter := rdb.Scan(ctx, 0, prefix+"*", 100).Iterator()
		var keys []string
		for iter.Next(ctx) {
			keys = append(keys, iter.Val())
		}
		if len(keys) > 0 {
			_ = rdb.Del(ctx, keys...).Err()
		}
	})
	return &matchFixture{
		svc:    svc,
		rdb:    rdb,
		clk:    clk,
		issuer: newRecordingIssuer(t, clk),
		worker: "ws://worker.test:9000",
		prefix: prefix,
	}
}

func (f *matchFixture) matchOnce(t *testing.T) MatchResult {
	t.Helper()
	res, err := f.svc.MatchPool(context.Background(), RoundKindEast, GameModeStandard, MatchParams{
		WorkerEndpoint: f.worker,
		TokenIssuer:    f.issuer,
	})
	if err != nil {
		t.Fatalf("MatchPool: %v", err)
	}
	return res
}

func enqueueN(t *testing.T, svc *Service, n int, rk RoundKind, gm GameMode) []Ticket {
	t.Helper()
	ctx := context.Background()
	out := make([]Ticket, 0, n)
	for i := 0; i < n; i++ {
		tk, err := svc.Enqueue(ctx, fmt.Sprintf("guest-%d", i+1), rk, gm)
		if err != nil {
			t.Fatalf("Enqueue %d: %v", i+1, err)
		}
		out = append(out, tk)
	}
	return out
}

func TestMatch_FourHumansImmediateUniqueRoom(t *testing.T) {
	f := newMatchFixture(t)
	ctx := context.Background()
	tickets := enqueueN(t, f.svc, 4, RoundKindEast, GameModeStandard)

	res := f.matchOnce(t)
	if !res.Matched {
		t.Fatal("expected immediate match for 4 humans")
	}
	if res.HumanCount != 4 || res.AICount != 0 {
		t.Fatalf("humans=%d ai=%d, want 4/0", res.HumanCount, res.AICount)
	}
	if res.RoomID == "" {
		t.Fatal("empty room_id")
	}

	roomIDs := map[string]bool{}
	seats := map[int]bool{}
	for _, tk0 := range tickets {
		tk, err := f.svc.Get(ctx, tk0.GuestID, tk0.TicketID)
		if err != nil {
			t.Fatalf("Get: %v", err)
		}
		if tk.Status != StatusAssigned {
			t.Fatalf("status=%q want assigned", tk.Status)
		}
		if tk.RoomID != res.RoomID {
			t.Fatalf("room_id=%q want %q", tk.RoomID, res.RoomID)
		}
		if tk.Worker != f.worker {
			t.Fatalf("worker=%q want %q", tk.Worker, f.worker)
		}
		if tk.RoomToken == "" {
			t.Fatal("missing room_token")
		}
		if tk.Seat < 0 || tk.Seat > 3 {
			t.Fatalf("seat=%d", tk.Seat)
		}
		if seats[tk.Seat] {
			t.Fatalf("duplicate seat %d", tk.Seat)
		}
		seats[tk.Seat] = true
		roomIDs[tk.RoomID] = true
		if f.svc.IsConsumable(ctx, tk.TicketID) {
			t.Fatal("assigned ticket must not be consumable")
		}
		if f.svc.IsInPool(ctx, tk) {
			t.Fatal("assigned ticket must leave pool")
		}
		// room_token 可按 room/seat 验证；绑定 guest/session
		claims, err := f.issuer.VerifyRoomToken(tk.RoomToken, tk.RoomID, tk.Seat)
		if err != nil {
			t.Fatalf("VerifyRoomToken: %v", err)
		}
		if claims.SessionID != tk.GuestID {
			t.Fatalf("session_id=%q want guest %q", claims.SessionID, tk.GuestID)
		}
		// 跨座/跨房失败
		if _, err := f.issuer.VerifyRoomToken(tk.RoomToken, tk.RoomID, (tk.Seat+1)%4); err == nil {
			t.Fatal("cross-seat verify must fail")
		}
		if _, err := f.issuer.VerifyRoomToken(tk.RoomToken, "other-room", tk.Seat); err == nil {
			t.Fatal("cross-room verify must fail")
		}
	}
	if len(roomIDs) != 1 {
		t.Fatalf("want single room, got %d", len(roomIDs))
	}
	if len(seats) != 4 {
		t.Fatalf("want 4 seats, got %d", len(seats))
	}

	// 第二次 match 不得再开房（池已空）
	res2 := f.matchOnce(t)
	if res2.Matched {
		t.Fatal("second match must not create another room")
	}
}

func TestMatch_PartialHumansWaitUntilExactly30s(t *testing.T) {
	cases := []struct {
		humans int
		ai     int
	}{
		{1, 3},
		{2, 2},
		{3, 1},
	}
	for _, tc := range cases {
		t.Run(fmt.Sprintf("%dhuman_%dai", tc.humans, tc.ai), func(t *testing.T) {
			f := newMatchFixture(t)
			ctx := context.Background()
			tickets := enqueueN(t, f.svc, tc.humans, RoundKindEast, GameModeStandard)

			// 29.999s 仍 waiting
			f.clk.Advance(30*time.Second - time.Nanosecond)
			res := f.matchOnce(t)
			if res.Matched {
				t.Fatal("must not match before full 30s")
			}
			for _, tk0 := range tickets {
				tk, err := f.svc.Get(ctx, tk0.GuestID, tk0.TicketID)
				if err != nil {
					t.Fatalf("Get: %v", err)
				}
				if tk.Status != StatusWaiting {
					t.Fatalf("status=%q want waiting", tk.Status)
				}
			}

			// 恰好 30s 补位
			f.clk.Advance(time.Nanosecond)
			res = f.matchOnce(t)
			if !res.Matched {
				t.Fatal("must match at exactly 30s")
			}
			if res.HumanCount != tc.humans || res.AICount != tc.ai {
				t.Fatalf("humans=%d ai=%d want %d/%d", res.HumanCount, res.AICount, tc.humans, tc.ai)
			}
			if res.HumanCount+res.AICount != 4 {
				t.Fatalf("total seats=%d want 4", res.HumanCount+res.AICount)
			}

			room, err := f.svc.GetRoom(ctx, res.RoomID)
			if err != nil {
				t.Fatalf("GetRoom: %v", err)
			}
			if room.HumanCount != tc.humans || room.AICount != tc.ai {
				t.Fatalf("room humans=%d ai=%d", room.HumanCount, room.AICount)
			}
			humanSeats := 0
			aiSeats := 0
			for seat, occ := range room.Seats {
				if seat < 0 || seat > 3 {
					t.Fatalf("invalid seat key %d", seat)
				}
				switch occ.Kind {
				case SeatKindHuman:
					humanSeats++
					if occ.TicketID == "" || occ.GuestID == "" {
						t.Fatalf("human seat %d missing identity", seat)
					}
				case SeatKindAI:
					aiSeats++
					if occ.TicketID != "" {
						t.Fatalf("AI seat %d must not have ticket", seat)
					}
				default:
					t.Fatalf("unknown kind %q want HUMAN|AI", occ.Kind)
				}
			}
			if humanSeats != tc.humans || aiSeats != tc.ai {
				t.Fatalf("seat kinds human=%d ai=%d", humanSeats, aiSeats)
			}
		})
	}
}

func TestMatch_DeadlineFollowsEarliestValidTicket(t *testing.T) {
	f := newMatchFixture(t)
	ctx := context.Background()

	// t0: guest-early
	early, err := f.svc.Enqueue(ctx, "guest-early", RoundKindEast, GameModeStandard)
	if err != nil {
		t.Fatalf("early: %v", err)
	}
	// t0+10s: guest-late
	f.clk.Advance(10 * time.Second)
	late, err := f.svc.Enqueue(ctx, "guest-late", RoundKindEast, GameModeStandard)
	if err != nil {
		t.Fatalf("late: %v", err)
	}

	// 自 early 起 29.999s → 未满，不应开房
	f.clk.Set(early.QueuedAt.Time().Add(30*time.Second - time.Nanosecond))
	if f.matchOnce(t).Matched {
		t.Fatal("should wait on earliest ticket")
	}

	// 取消最早 ticket 后，deadline 改由 late 决定
	if _, err := f.svc.Cancel(ctx, "guest-early", early.TicketID); err != nil {
		t.Fatalf("cancel early: %v", err)
	}
	// 此时时钟仍接近 early+30，但对 late 仅约 20s → 仍 waiting
	if f.matchOnce(t).Matched {
		t.Fatal("after cancel earliest, must re-anchor to remaining earliest")
	}
	lateTk, err := f.svc.Get(ctx, "guest-late", late.TicketID)
	if err != nil || lateTk.Status != StatusWaiting {
		t.Fatalf("late should still wait: %+v %v", lateTk, err)
	}

	// late + 30s 才开房，AI=3
	f.clk.Set(late.QueuedAt.Time().Add(30 * time.Second))
	res := f.matchOnce(t)
	if !res.Matched || res.HumanCount != 1 || res.AICount != 3 {
		t.Fatalf("res=%+v", res)
	}
	got, err := f.svc.Get(ctx, "guest-late", late.TicketID)
	if err != nil || got.Status != StatusAssigned {
		t.Fatalf("late assigned: %+v %v", got, err)
	}
	// 已取消 early 不得被消费
	earlyGot, err := f.svc.Get(ctx, "guest-early", early.TicketID)
	if err != nil || earlyGot.Status != StatusCancelled {
		t.Fatalf("early must stay cancelled: %+v %v", earlyGot, err)
	}
}

func TestMatch_ConcurrentMatchersSingleRoom(t *testing.T) {
	f := newMatchFixture(t)
	ctx := context.Background()
	tickets := enqueueN(t, f.svc, 4, RoundKindEast, GameModeStandard)

	const n = 16
	var wg sync.WaitGroup
	results := make([]MatchResult, n)
	errs := make([]error, n)
	wg.Add(n)
	for i := 0; i < n; i++ {
		go func(i int) {
			defer wg.Done()
			// 每个 goroutine 独立 Service 视图（同 Redis / 同 prefix）模拟多 CP 实例
			svc2, err := NewService(Options{
				Redis:     f.rdb,
				KeyPrefix: f.prefix,
				Clock:     f.clk,
				IDGen:     &seqIDGenVal{n: 1000 + i*100},
			})
			if err != nil {
				errs[i] = err
				return
			}
			results[i], errs[i] = svc2.MatchPool(ctx, RoundKindEast, GameModeStandard, MatchParams{
				WorkerEndpoint: f.worker,
				TokenIssuer:    f.issuer,
			})
		}(i)
	}
	wg.Wait()
	matched := 0
	var roomID string
	for i, err := range errs {
		if err != nil {
			t.Fatalf("matcher %d: %v", i, err)
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
	// 每个 ticket 仅一房
	for _, tk0 := range tickets {
		tk, err := f.svc.Get(ctx, tk0.GuestID, tk0.TicketID)
		if err != nil {
			t.Fatalf("Get: %v", err)
		}
		if tk.Status != StatusAssigned || tk.RoomID != roomID {
			t.Fatalf("ticket %+v", tk)
		}
	}
}

func TestMatch_CancelVsConsumeRace(t *testing.T) {
	// 两种合法赢家：取消成功则永不进房；消费成功则不可再 cancelled
	for round := 0; round < 20; round++ {
		f := newMatchFixture(t)
		ctx := context.Background()
		// 单人满 30s 可补位
		tk, err := f.svc.Enqueue(ctx, "guest-race", RoundKindEast, GameModeStandard)
		if err != nil {
			t.Fatalf("enqueue: %v", err)
		}
		f.clk.Advance(30 * time.Second)

		var cancelStatus atomic.Value
		var matchRes atomic.Value
		var cancelErr atomic.Value
		var matchErr atomic.Value
		cancelStatus.Store("")
		matchRes.Store(MatchResult{})
		var wg sync.WaitGroup
		wg.Add(2)
		go func() {
			defer wg.Done()
			got, err := f.svc.Cancel(ctx, "guest-race", tk.TicketID)
			if err != nil {
				cancelErr.Store(err)
				return
			}
			cancelStatus.Store(got.Status)
		}()
		go func() {
			defer wg.Done()
			res, err := f.svc.MatchPool(ctx, RoundKindEast, GameModeStandard, MatchParams{
				WorkerEndpoint: f.worker,
				TokenIssuer:    f.issuer,
			})
			if err != nil {
				matchErr.Store(err)
				return
			}
			matchRes.Store(res)
		}()
		wg.Wait()

		if v := cancelErr.Load(); v != nil {
			t.Fatalf("cancel err: %v", v)
		}
		if v := matchErr.Load(); v != nil {
			t.Fatalf("match err: %v", v)
		}
		st := cancelStatus.Load().(string)
		res := matchRes.Load().(MatchResult)
		final, err := f.svc.Get(ctx, "guest-race", tk.TicketID)
		if err != nil {
			t.Fatalf("final get: %v", err)
		}
		switch {
		case st == StatusCancelled && !res.Matched:
			if final.Status != StatusCancelled {
				t.Fatalf("cancel winner but final=%+v", final)
			}
			if f.svc.IsConsumable(ctx, tk.TicketID) {
				t.Fatal("cancelled must not be consumable")
			}
		case st == StatusAssigned && res.Matched:
			if final.Status != StatusAssigned {
				t.Fatalf("match winner but final=%+v", final)
			}
			// 再取消不得变 cancelled
			again, err := f.svc.Cancel(ctx, "guest-race", tk.TicketID)
			if err != nil {
				t.Fatalf("re-cancel: %v", err)
			}
			if again.Status != StatusAssigned {
				t.Fatalf("assigned cancel must stay assigned, got %q", again.Status)
			}
		case st == StatusAssigned && !res.Matched:
			// 取消观察到已分配（match 先赢，cancel 返回终态）
			if final.Status != StatusAssigned {
				t.Fatalf("unexpected final %+v st=%s matched=%v", final, st, res.Matched)
			}
		case st == StatusCancelled && res.Matched:
			t.Fatalf("invariant broken: cancelled and matched both won; final=%+v", final)
		default:
			t.Fatalf("unexpected pair cancel=%s matched=%v final=%+v", st, res.Matched, final)
		}
	}
}

func TestMatch_PoolsIsolated(t *testing.T) {
	f := newMatchFixture(t)
	ctx := context.Background()
	// 各池 1 人，满 30s 后应各自独立开房，互不混席
	combos := []struct {
		rk RoundKind
		gm GameMode
	}{
		{RoundKindEast, GameModeStandard},
		{RoundKindEast, GameModeTrashTalk},
		{RoundKindHanchan, GameModeStandard},
		{RoundKindHanchan, GameModeTrashTalk},
	}
	for i, c := range combos {
		if _, err := f.svc.Enqueue(ctx, fmt.Sprintf("g-%d", i), c.rk, c.gm); err != nil {
			t.Fatalf("enqueue: %v", err)
		}
	}
	f.clk.Advance(30 * time.Second)
	rooms := map[string]bool{}
	for _, c := range combos {
		res, err := f.svc.MatchPool(ctx, c.rk, c.gm, MatchParams{
			WorkerEndpoint: f.worker,
			TokenIssuer:    f.issuer,
		})
		if err != nil {
			t.Fatalf("match: %v", err)
		}
		if !res.Matched || res.HumanCount != 1 || res.AICount != 3 {
			t.Fatalf("combo %s/%s res=%+v", c.rk, c.gm, res)
		}
		if rooms[res.RoomID] {
			t.Fatalf("room id collision %s", res.RoomID)
		}
		rooms[res.RoomID] = true
	}
	if len(rooms) != 4 {
		t.Fatalf("want 4 rooms, got %d", len(rooms))
	}
}

func TestMatch_TokenTypeConfusion(t *testing.T) {
	f := newMatchFixture(t)
	ctx := context.Background()
	tickets := enqueueN(t, f.svc, 4, RoundKindEast, GameModeStandard)
	res := f.matchOnce(t)
	if !res.Matched {
		t.Fatal("expected match")
	}
	tk, err := f.svc.Get(ctx, tickets[0].GuestID, tickets[0].TicketID)
	if err != nil {
		t.Fatalf("Get: %v", err)
	}
	// room token 不能当 guest session
	if _, err := f.issuer.VerifyGuestToken(tk.RoomToken); err == nil {
		t.Fatal("room token must not verify as guest")
	}
	// guest session 不能当 room token
	sess, err := f.issuer.IssueGuestSession()
	if err != nil {
		t.Fatalf("guest: %v", err)
	}
	if _, err := f.issuer.VerifyRoomToken(sess.SessionToken, tk.RoomID, tk.Seat); err == nil {
		t.Fatal("session token must not verify as room")
	}
}

func TestMatcher_StartStopLifecycle(t *testing.T) {
	f := newMatchFixture(t)
	ctx := context.Background()
	tk, err := f.svc.Enqueue(ctx, "guest-life", RoundKindEast, GameModeStandard)
	if err != nil {
		t.Fatalf("enqueue: %v", err)
	}
	f.clk.Advance(30 * time.Second)

	m, err := NewMatcher(MatcherOptions{
		Service:        f.svc,
		TokenIssuer:    f.issuer,
		WorkerEndpoint: f.worker,
		ScanInterval:   15 * time.Millisecond,
	})
	if err != nil {
		t.Fatalf("NewMatcher: %v", err)
	}
	m.Start()
	assigned := false
	for i := 0; i < 100; i++ {
		got, err := f.svc.Get(ctx, "guest-life", tk.TicketID)
		if err == nil && got.Status == StatusAssigned {
			assigned = true
			break
		}
		time.Sleep(20 * time.Millisecond)
	}
	if !assigned {
		t.Fatal("matcher did not auto-assign within timeout")
	}
	if err := m.Stop(context.Background()); err != nil {
		t.Fatalf("Stop: %v", err)
	}
	// 再次 Stop 应安全
	if err := m.Stop(context.Background()); err != nil {
		t.Fatalf("Stop again: %v", err)
	}
}

func TestMatch_WorkerEndpointRequiredOnMatcher(t *testing.T) {
	f := newMatchFixture(t)
	_, err := NewMatcher(MatcherOptions{
		Service:        f.svc,
		TokenIssuer:    f.issuer,
		WorkerEndpoint: "   ",
	})
	if err == nil {
		t.Fatal("expected error for blank worker")
	}
	if strings.Contains(err.Error(), matchTestSecret) {
		t.Fatal("error must not leak secrets")
	}
}

func TestMatch_CrossInstanceAssignmentVisible(t *testing.T) {
	f := newMatchFixture(t)
	ctx := context.Background()
	tickets := enqueueN(t, f.svc, 4, RoundKindEast, GameModeStandard)
	res := f.matchOnce(t)
	if !res.Matched {
		t.Fatal("expected match")
	}
	// 另一 Service 实例读同一 Redis
	svc2, err := NewService(Options{
		Redis:     f.rdb,
		KeyPrefix: f.prefix,
		Clock:     f.clk,
	})
	if err != nil {
		t.Fatalf("svc2: %v", err)
	}
	for _, tk0 := range tickets {
		tk, err := svc2.Get(ctx, tk0.GuestID, tk0.TicketID)
		if err != nil {
			t.Fatalf("cross get: %v", err)
		}
		if tk.Status != StatusAssigned || tk.RoomID != res.RoomID || tk.RoomToken == "" {
			t.Fatalf("cross-instance incomplete: %+v", tk)
		}
		room, err := svc2.GetRoom(ctx, tk.RoomID)
		if err != nil {
			t.Fatalf("cross room: %v", err)
		}
		if room.Worker != f.worker {
			t.Fatalf("worker=%q", room.Worker)
		}
	}
}

func TestCancel_AssignedIdempotentReturnsAssigned(t *testing.T) {
	f := newMatchFixture(t)
	ctx := context.Background()
	tickets := enqueueN(t, f.svc, 4, RoundKindEast, GameModeStandard)
	if !f.matchOnce(t).Matched {
		t.Fatal("expected match")
	}
	tk, err := f.svc.Cancel(ctx, tickets[0].GuestID, tickets[0].TicketID)
	if err != nil {
		t.Fatalf("Cancel assigned: %v", err)
	}
	if tk.Status != StatusAssigned {
		t.Fatalf("status=%q want assigned", tk.Status)
	}
	tk2, err := f.svc.Cancel(ctx, tickets[0].GuestID, tickets[0].TicketID)
	if err != nil {
		t.Fatalf("Cancel again: %v", err)
	}
	if tk2.Status != StatusAssigned || tk2.RoomID == "" {
		t.Fatalf("idempotent assigned cancel: %+v", tk2)
	}
}
