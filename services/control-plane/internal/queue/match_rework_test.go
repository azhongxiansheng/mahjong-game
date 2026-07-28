package queue

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

// ---- round-2 Red 目标：原子完整分配 / 毫秒边界 / HUMAN|AI / MatchAll 排空+错误报告 ----

// blockingIssuer 在第 blockAt 次（0-based）签发时阻塞，直到 release 关闭；
// 或在 failAt 次返回错误（-1 表示不失败）。
type blockingIssuer struct {
	inner   RoomTokenIssuer
	mu      sync.Mutex
	n       int
	blockAt int
	failAt  int
	blocked chan struct{} // 容量 1，进入阻塞时通知
	release chan struct{}
}

func (b *blockingIssuer) IssueRoomToken(sessionID, roomID string, seat int, roundKind, gameMode string, participants []string, characterIDs []string) (string, time.Time, error) {
	b.mu.Lock()
	idx := b.n
	b.n++
	b.mu.Unlock()
	if b.failAt >= 0 && idx == b.failAt {
		return "", time.Time{}, errors.New("issuer synthetic failure")
	}
	if b.blockAt >= 0 && idx == b.blockAt {
		select {
		case b.blocked <- struct{}{}:
		default:
		}
		<-b.release
	}
	return b.inner.IssueRoomToken(sessionID, roomID, seat, roundKind, gameMode, participants, characterIDs)
}

// TestRework_P1_BlockingIssuerNeverExposesPartialAssigned
// 签发阻塞期间，并发 GET 只能看到 waiting，绝不能看到缺 room_token 的 assigned。
func TestRework_P1_BlockingIssuerNeverExposesPartialAssigned(t *testing.T) {
	f := newMatchFixture(t)
	ctx := context.Background()
	tickets := enqueueN(t, f.svc, 4, RoundKindEast, GameModeStandard)

	blocked := make(chan struct{}, 1)
	release := make(chan struct{})
	issuer := &blockingIssuer{
		inner:   f.issuer,
		blockAt: 0,
		failAt:  -1,
		blocked: blocked,
		release: release,
	}

	var matchErr error
	var res MatchResult
	done := make(chan struct{})
	go func() {
		defer close(done)
		res, matchErr = f.svc.MatchPool(ctx, RoundKindEast, GameModeStandard, MatchParams{
			TokenIssuer: issuer,
		})
	}()

	select {
	case <-blocked:
	case <-time.After(2 * time.Second):
		t.Fatal("issuer did not block")
	}

	// 阻塞期间并发读：不得出现 assigned（含半分配）
	for _, tk0 := range tickets {
		tk, err := f.svc.Get(ctx, tk0.GuestID, tk0.TicketID)
		if err != nil {
			t.Fatalf("Get during block: %v", err)
		}
		if tk.Status != StatusWaiting {
			t.Fatalf("during issuer block status=%q want waiting (no partial assigned); ticket=%s token=%q",
				tk.Status, tk.TicketID, tk.RoomToken)
		}
		if tk.RoomToken != "" || tk.RoomID != "" {
			t.Fatalf("waiting ticket must not have assignment fields: %+v", tk)
		}
		if !f.svc.IsConsumable(ctx, tk.TicketID) {
			t.Fatal("still consumable while issuer blocked")
		}
	}

	close(release)
	<-done
	if matchErr != nil {
		t.Fatalf("MatchPool: %v", matchErr)
	}
	if !res.Matched {
		t.Fatal("expected match after release")
	}
	for _, tk0 := range tickets {
		tk, err := f.svc.Get(ctx, tk0.GuestID, tk0.TicketID)
		if err != nil {
			t.Fatalf("Get after: %v", err)
		}
		if tk.Status != StatusAssigned || tk.RoomToken == "" || tk.Worker == "" || !tk.HasSeat {
			t.Fatalf("incomplete assigned after success: %+v", tk)
		}
		if _, err := f.issuer.VerifyRoomToken(tk.RoomToken, tk.RoomID, tk.Seat); err != nil {
			t.Fatalf("token verify: %v", err)
		}
	}
}

// TestRework_P1_IssuerFailLeavesPoolUntouched
// 第 1 个或中间 token 失败时：无 room、全员仍 waiting 可消费；换正常 issuer 后只开一完整房。
func TestRework_P1_IssuerFailLeavesPoolUntouched(t *testing.T) {
	for _, failAt := range []int{0, 2} {
		t.Run(fmt.Sprintf("failAt_%d", failAt), func(t *testing.T) {
			f := newMatchFixture(t)
			ctx := context.Background()
			tickets := enqueueN(t, f.svc, 4, RoundKindEast, GameModeStandard)

			bad := &blockingIssuer{inner: f.issuer, blockAt: -1, failAt: failAt}
			res, err := f.svc.MatchPool(ctx, RoundKindEast, GameModeStandard, MatchParams{
				TokenIssuer: bad,
			})
			if err == nil {
				t.Fatal("expected issuer error")
			}
			if res.Matched {
				t.Fatal("must not report matched on issuer failure")
			}
			if strings.Contains(err.Error(), matchTestSecret) {
				t.Fatal("error must not contain signing secret")
			}

			for _, tk0 := range tickets {
				tk, err := f.svc.Get(ctx, tk0.GuestID, tk0.TicketID)
				if err != nil {
					t.Fatalf("Get: %v", err)
				}
				if tk.Status != StatusWaiting {
					t.Fatalf("status=%q want waiting after issuer fail", tk.Status)
				}
				if !f.svc.IsConsumable(ctx, tk.TicketID) {
					t.Fatal("must remain consumable")
				}
			}
			// 不得残留 room 键
			iter := f.rdb.Scan(ctx, 0, f.prefix+"room:*", 100).Iterator()
			for iter.Next(ctx) {
				t.Fatalf("unexpected room key after failed match: %s", iter.Val())
			}

			// 正常 issuer 一次完整成功
			res2, err := f.svc.MatchPool(ctx, RoundKindEast, GameModeStandard, MatchParams{
				TokenIssuer: f.issuer,
			})
			if err != nil || !res2.Matched {
				t.Fatalf("retry match: %+v err=%v", res2, err)
			}
			rooms := 0
			iter = f.rdb.Scan(ctx, 0, f.prefix+"room:*", 100).Iterator()
			for iter.Next(ctx) {
				rooms++
			}
			if rooms != 1 {
				t.Fatalf("want exactly 1 room, got %d", rooms)
			}
			for _, tk0 := range tickets {
				tk, err := f.svc.Get(ctx, tk0.GuestID, tk0.TicketID)
				if err != nil {
					t.Fatalf("Get: %v", err)
				}
				if tk.Status != StatusAssigned || tk.RoomToken == "" {
					t.Fatalf("incomplete: %+v", tk)
				}
			}
		})
	}
}

// TestRework_P1_AssignedAlwaysHasCompleteTokenFields
// 多 matcher + 取消竞态后：凡 assigned 必有可验证完整字段；无半分配。
func TestRework_P1_AssignedAlwaysHasCompleteTokenFields(t *testing.T) {
	for round := 0; round < 12; round++ {
		// 每轮独立 subtest 前缀，避免 ticket id 复用污染
		t.Run(fmt.Sprintf("round_%d", round), func(t *testing.T) {
			f := newMatchFixture(t)
			ctx := context.Background()
			tickets := enqueueN(t, f.svc, 4, RoundKindEast, GameModeStandard)

			var wg sync.WaitGroup
			const n = 8
			wg.Add(n + 1)
			for i := 0; i < n; i++ {
				go func(i int) {
					defer wg.Done()
					svc2, err := NewService(Options{
						Redis:     f.rdb,
						KeyPrefix: f.prefix,
						Clock:     f.clk,
						IDGen:     &seqIDGenVal{n: 5000 + i*50},
						Workers:   f.reg,
					})
					if err != nil {
						return
					}
					_, _ = svc2.MatchPool(ctx, RoundKindEast, GameModeStandard, MatchParams{
						TokenIssuer: f.issuer,
					})
				}(i)
			}
			go func() {
				defer wg.Done()
				_, _ = f.svc.Cancel(ctx, tickets[0].GuestID, tickets[0].TicketID)
			}()
			wg.Wait()

			f.clk.Advance(30 * time.Second)
			_, _ = f.svc.MatchPool(ctx, RoundKindEast, GameModeStandard, MatchParams{
				TokenIssuer: f.issuer,
			})

			for _, tk0 := range tickets {
				tk, err := f.svc.Get(ctx, tk0.GuestID, tk0.TicketID)
				if err != nil {
					t.Fatalf("Get: %v", err)
				}
				switch tk.Status {
				case StatusCancelled:
					if tk.RoomToken != "" || tk.RoomID != "" {
						t.Fatalf("cancelled must not have assignment fields: %+v", tk)
					}
				case StatusAssigned:
					if tk.RoomToken == "" || tk.RoomID == "" || tk.Worker == "" || !tk.HasSeat {
						t.Fatalf("partial assigned forbidden: %+v", tk)
					}
					if _, err := f.issuer.VerifyRoomToken(tk.RoomToken, tk.RoomID, tk.Seat); err != nil {
						t.Fatalf("verify: %v", err)
					}
				case StatusWaiting:
					if tk.RoomToken != "" || tk.RoomID != "" {
						t.Fatalf("waiting with assignment fields: %+v", tk)
					}
				default:
					t.Fatalf("unexpected status %q", tk.Status)
				}
			}
		})
	}
}

// TestRework_P2_MillisecondDeadlineBoundary
// 从 12:00:00.900 入队；+29.999s 仍 waiting；+1ms 到恰好 30s 才 assigned。
func TestRework_P2_MillisecondDeadlineBoundary(t *testing.T) {
	f := newMatchFixture(t)
	start := time.Date(2026, 7, 24, 12, 0, 0, 900*int(time.Millisecond), time.UTC)
	f.clk.Set(start)
	ctx := context.Background()

	tk, err := f.svc.Enqueue(ctx, "guest-ms", RoundKindEast, GameModeStandard, "lin_yeche")
	if err != nil {
		t.Fatalf("Enqueue: %v", err)
	}
	// 持久化 queued_at 必须保留亚秒
	if tk.QueuedAt.Time().Nanosecond() == 0 {
		t.Fatalf("queued_at truncated to whole second: %v (need sub-second precision)", tk.QueuedAt.Time())
	}
	if !tk.QueuedAt.Time().Equal(start.Truncate(time.Millisecond)) && !tk.QueuedAt.Time().Equal(start) {
		// 允许截断到毫秒
		got := tk.QueuedAt.Time()
		if got.UnixMilli() != start.UnixMilli() {
			t.Fatalf("queued_at=%v want ms of %v", got, start)
		}
	}

	// 29.999s 仍 waiting
	f.clk.Set(start.Add(30*time.Second - time.Millisecond))
	res := f.matchOnce(t)
	if res.Matched {
		t.Fatal("must NOT match at queued_at+29.999s")
	}
	got, err := f.svc.Get(ctx, "guest-ms", tk.TicketID)
	if err != nil || got.Status != StatusWaiting {
		t.Fatalf("want waiting at +29.999s: %+v err=%v", got, err)
	}

	// 恰好 +30.000s
	f.clk.Set(start.Add(30 * time.Second))
	res = f.matchOnce(t)
	if !res.Matched || res.HumanCount != 1 || res.AICount != 3 {
		t.Fatalf("must match at exactly +30s: %+v", res)
	}
	got, err = f.svc.Get(ctx, "guest-ms", tk.TicketID)
	if err != nil || got.Status != StatusAssigned || got.RoomToken == "" {
		t.Fatalf("assigned incomplete: %+v err=%v", got, err)
	}
}

// TestRework_P2_DeadlineReanchorsWithMillisecondPrecision
func TestRework_P2_DeadlineReanchorsWithMillisecondPrecision(t *testing.T) {
	f := newMatchFixture(t)
	ctx := context.Background()
	t0 := time.Date(2026, 7, 24, 12, 0, 0, 500*int(time.Millisecond), time.UTC)
	f.clk.Set(t0)
	early, err := f.svc.Enqueue(ctx, "g-early", RoundKindEast, GameModeStandard, "lin_yeche")
	if err != nil {
		t.Fatalf("early: %v", err)
	}
	t1 := t0.Add(1500 * time.Millisecond)
	f.clk.Set(t1)
	late, err := f.svc.Enqueue(ctx, "g-late", RoundKindEast, GameModeStandard, "lin_yeche")
	if err != nil {
		t.Fatalf("late: %v", err)
	}

	// 取消 early 后，以 late 的精确 queued_at 锚定
	if _, err := f.svc.Cancel(ctx, "g-early", early.TicketID); err != nil {
		t.Fatalf("cancel: %v", err)
	}
	// late + 29.999s
	f.clk.Set(t1.Add(30*time.Second - time.Millisecond))
	if f.matchOnce(t).Matched {
		t.Fatal("should still wait on late's ms deadline")
	}
	f.clk.Set(t1.Add(30 * time.Second))
	res := f.matchOnce(t)
	if !res.Matched || res.HumanCount != 1 {
		t.Fatalf("res=%+v", res)
	}
	got, _ := f.svc.Get(ctx, "g-late", late.TicketID)
	if got.Status != StatusAssigned {
		t.Fatalf("late status=%s", got.Status)
	}
}

// TestRework_P2_ParticipantKindADRStable
func TestRework_P2_ParticipantKindADRStable(t *testing.T) {
	f := newMatchFixture(t)
	ctx := context.Background()
	_ = enqueueN(t, f.svc, 1, RoundKindEast, GameModeStandard)
	f.clk.Advance(30 * time.Second)
	res := f.matchOnce(t)
	if !res.Matched {
		t.Fatal("expected match")
	}
	room, err := f.svc.GetRoom(ctx, res.RoomID)
	if err != nil {
		t.Fatalf("GetRoom: %v", err)
	}
	human, ai := 0, 0
	for _, occ := range room.Seats {
		switch occ.Kind {
		case SeatKindHuman:
			human++
			if occ.Kind != "HUMAN" {
				t.Fatalf("kind=%q want HUMAN", occ.Kind)
			}
		case SeatKindAI:
			ai++
			if occ.Kind != "AI" {
				t.Fatalf("kind=%q want AI", occ.Kind)
			}
		default:
			t.Fatalf("unexpected kind %q (ADR requires HUMAN|AI)", occ.Kind)
		}
	}
	if human != 1 || ai != 3 {
		t.Fatalf("human=%d ai=%d", human, ai)
	}
}

// TestRework_P2_MatchAllDrainsEightHumansInOneScan
func TestRework_P2_MatchAllDrainsEightHumansInOneScan(t *testing.T) {
	f := newMatchFixture(t)
	ctx := context.Background()
	// 8 真人同池
	tickets := make([]Ticket, 0, 8)
	for i := 0; i < 8; i++ {
		tk, err := f.svc.Enqueue(ctx, fmt.Sprintf("guest-8-%d", i), RoundKindEast, GameModeStandard, "lin_yeche")
		if err != nil {
			t.Fatalf("enqueue: %v", err)
		}
		tickets = append(tickets, tk)
	}
	m, err := NewMatcher(MatcherOptions{
		Service:     f.svc,
		TokenIssuer: f.issuer,
	})
	if err != nil {
		t.Fatalf("NewMatcher: %v", err)
	}
	if err := m.MatchAll(ctx); err != nil {
		t.Fatalf("MatchAll: %v", err)
	}

	rooms := map[string]bool{}
	for _, tk0 := range tickets {
		tk, err := f.svc.Get(ctx, tk0.GuestID, tk0.TicketID)
		if err != nil {
			t.Fatalf("Get: %v", err)
		}
		if tk.Status != StatusAssigned || tk.RoomToken == "" {
			t.Fatalf("ticket not fully assigned after one MatchAll: %+v", tk)
		}
		rooms[tk.RoomID] = true
	}
	if len(rooms) != 2 {
		t.Fatalf("want exactly 2 rooms from 8 humans in one scan, got %d: %v", len(rooms), rooms)
	}
}

// TestRework_P2_MatcherReportsErrorsAndRecovers
func TestRework_P2_MatcherReportsErrorsAndRecovers(t *testing.T) {
	f := newMatchFixture(t)
	ctx := context.Background()
	tickets := enqueueN(t, f.svc, 4, RoundKindEast, GameModeStandard)

	var reports atomic.Int32
	var lastOp atomic.Value
	onErr := func(op string, safeDetail string) {
		reports.Add(1)
		lastOp.Store(op)
		if strings.Contains(op, matchTestSecret) || strings.Contains(safeDetail, matchTestSecret) {
			t.Errorf("OnError leaked secret")
		}
		if strings.Contains(safeDetail, "v1.r.") || strings.Contains(safeDetail, "v1.g.") {
			t.Errorf("OnError leaked token material: %q", safeDetail)
		}
	}

	// 直接 MatchAll 应返回错误
	failingDirect := &blockingIssuer{inner: f.issuer, blockAt: -1, failAt: 0}
	mFail, err := NewMatcher(MatcherOptions{
		Service:     f.svc,
		TokenIssuer: failingDirect,
		OnError:     onErr,
	})
	if err != nil {
		t.Fatalf("NewMatcher: %v", err)
	}
	if err := mFail.MatchAll(ctx); err == nil {
		t.Fatal("MatchAll expected error from failing issuer")
	}

	// 后台 loop 路径：始终失败的 issuer，验证 OnError 被调用
	alwaysFail := RoomTokenIssuer(RoomTokenIssuerFunc(func(sessionID, roomID string, seat int, roundKind, gameMode string, participants, characterIDs []string) (string, time.Time, error) {
		return "", time.Time{}, errors.New("issuer synthetic failure")
	}))
	m2, err := NewMatcher(MatcherOptions{
		Service:      f.svc,
		TokenIssuer:  alwaysFail,
		ScanInterval: 15 * time.Millisecond,
		OnError:      onErr,
	})
	if err != nil {
		t.Fatalf("m2: %v", err)
	}
	m2.Start()
	deadline := time.Now().Add(500 * time.Millisecond)
	for time.Now().Before(deadline) && reports.Load() == 0 {
		time.Sleep(10 * time.Millisecond)
	}
	_ = m2.Stop(context.Background())
	if reports.Load() == 0 {
		t.Fatal("expected OnError to be called for background match failure")
	}
	if op, _ := lastOp.Load().(string); op == "" {
		t.Fatal("empty op in OnError")
	}

	// 全员仍 waiting
	for _, tk0 := range tickets {
		tk, err := f.svc.Get(ctx, tk0.GuestID, tk0.TicketID)
		if err != nil || tk.Status != StatusWaiting {
			t.Fatalf("want waiting after errors: %+v err=%v", tk, err)
		}
	}

	// 恢复：正常 issuer MatchAll 成功
	mOK, err := NewMatcher(MatcherOptions{
		Service:     f.svc,
		TokenIssuer: f.issuer,
	})
	if err != nil {
		t.Fatalf("mOK: %v", err)
	}
	if err := mOK.MatchAll(ctx); err != nil {
		t.Fatalf("recover MatchAll: %v", err)
	}
	for _, tk0 := range tickets {
		tk, err := f.svc.Get(ctx, tk0.GuestID, tk0.TicketID)
		if err != nil || tk.Status != StatusAssigned || tk.RoomToken == "" {
			t.Fatalf("recover incomplete: %+v err=%v", tk, err)
		}
	}
}

// RoomTokenIssuerFunc 测试用函数适配器。
type RoomTokenIssuerFunc func(sessionID, roomID string, seat int, roundKind, gameMode string, participants, characterIDs []string) (string, time.Time, error)

func (f RoomTokenIssuerFunc) IssueRoomToken(sessionID, roomID string, seat int, roundKind, gameMode string, participants []string, characterIDs []string) (string, time.Time, error) {
	return f(sessionID, roomID, seat, roundKind, gameMode, participants, characterIDs)
}
