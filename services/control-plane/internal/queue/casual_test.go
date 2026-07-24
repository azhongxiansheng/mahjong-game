package queue

import (
	"context"
	"os"
	"strconv"
	"sync"
	"testing"
	"time"

	"github.com/lov-team/mahjong-game/services/control-plane/internal/redisx"
	"github.com/redis/go-redis/v9"
)

// 真实 Redis 集成测试。Redis 不可用时直接失败（不算 Skip / 不算 Green）。
func requireRealRedis(t *testing.T) *redis.Client {
	t.Helper()
	addr := os.Getenv("REDIS_ADDR")
	if addr == "" {
		addr = "127.0.0.1:6379"
	}
	c, err := redisx.New(redisx.Options{
		Addr:     addr,
		Password: os.Getenv("REDIS_PASSWORD"),
		DB:       redisDBFromEnv(),
	})
	if err != nil {
		t.Fatalf("redisx.New: %v", err)
	}
	t.Cleanup(func() { _ = c.Close() })

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	if err := c.Ping(ctx); err != nil {
		t.Fatalf("真实 Redis 不可用（addr=%s）: %v；请先 docker compose up", addr, err)
	}
	return c.Redis()
}

func redisDBFromEnv() int {
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

func newTestService(t *testing.T) *Service {
	t.Helper()
	rdb := requireRealRedis(t)
	// 隔离：每个测试用独立 key 前缀 + 清理
	prefix := "test:casual:" + t.Name() + ":"
	svc, err := NewService(Options{
		Redis:     rdb,
		KeyPrefix: prefix,
		Clock:     fixedClock{t: time.Date(2026, 7, 24, 12, 0, 0, 0, time.UTC)},
		IDGen:     &seqIDGen{n: 0},
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
	return svc
}

type fixedClock struct{ t time.Time }

func (c fixedClock) Now() time.Time { return c.t }

type seqIDGen struct{ n int }

func (g *seqIDGen) NewID() (string, error) {
	g.n++
	return "ticket-" + strconv.Itoa(g.n), nil
}

// 适配值接收：NewService 需要 IDGen 接口
type seqIDGenVal struct {
	mu sync.Mutex
	n  int
}

func (g *seqIDGenVal) NewID() (string, error) {
	g.mu.Lock()
	defer g.mu.Unlock()
	g.n++
	return "ticket-" + strconv.Itoa(g.n), nil
}

func TestEnqueue_CreatesWaitingTicketWithDeadline(t *testing.T) {
	svc := newTestService(t)
	ctx := context.Background()

	ticket, err := svc.Enqueue(ctx, "guest-a", RoundKindEast, GameModeStandard)
	if err != nil {
		t.Fatalf("Enqueue: %v", err)
	}
	if ticket.TicketID == "" {
		t.Fatal("empty ticket_id")
	}
	if ticket.GuestID != "guest-a" {
		t.Fatalf("guest_id = %q", ticket.GuestID)
	}
	if ticket.RoundKind != RoundKindEast || ticket.GameMode != GameModeStandard {
		t.Fatalf("rules = %s/%s", ticket.RoundKind, ticket.GameMode)
	}
	if ticket.Status != StatusWaiting {
		t.Fatalf("status = %q, want waiting", ticket.Status)
	}
	wantQueued := time.Date(2026, 7, 24, 12, 0, 0, 0, time.UTC)
	if ticket.QueuedAt.Time().Unix() != wantQueued.Unix() {
		t.Fatalf("queued_at = %v, want %v", ticket.QueuedAt.Time(), wantQueued)
	}
	wantDeadline := wantQueued.Add(QueueWaitDeadline)
	if ticket.DeadlineAt.Time().Unix() != wantDeadline.Unix() {
		t.Fatalf("deadline_at = %v, want %v", ticket.DeadlineAt.Time(), wantDeadline)
	}
	if !svc.IsInPool(ctx, ticket) {
		t.Fatal("ticket must be in match pool after enqueue")
	}
	if !svc.IsConsumable(ctx, ticket.TicketID) {
		t.Fatal("waiting ticket must be consumable")
	}
}

func TestEnqueue_IdempotentSameGuestSameRules(t *testing.T) {
	svc := newTestService(t)
	ctx := context.Background()

	a, err := svc.Enqueue(ctx, "guest-a", RoundKindEast, GameModeStandard)
	if err != nil {
		t.Fatalf("first: %v", err)
	}
	b, err := svc.Enqueue(ctx, "guest-a", RoundKindEast, GameModeStandard)
	if err != nil {
		t.Fatalf("second: %v", err)
	}
	if a.TicketID != b.TicketID {
		t.Fatalf("expected same ticket, got %s vs %s", a.TicketID, b.TicketID)
	}
	if !a.QueuedAt.Time().Equal(b.QueuedAt.Time()) || !a.DeadlineAt.Time().Equal(b.DeadlineAt.Time()) {
		t.Fatalf("idempotent rejoin must preserve timestamps: %+v vs %+v", a, b)
	}
}

func TestEnqueue_ConcurrentIdempotent(t *testing.T) {
	rdb := requireRealRedis(t)
	prefix := "test:casual:" + t.Name() + ":"
	svc, err := NewService(Options{
		Redis:     rdb,
		KeyPrefix: prefix,
		Clock:     fixedClock{t: time.Date(2026, 7, 24, 12, 0, 0, 0, time.UTC)},
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

	const n = 20
	var wg sync.WaitGroup
	ids := make([]string, n)
	errs := make([]error, n)
	wg.Add(n)
	for i := 0; i < n; i++ {
		go func(i int) {
			defer wg.Done()
			ticket, err := svc.Enqueue(context.Background(), "guest-concurrent", RoundKindHanchan, GameModeTrashTalk)
			errs[i] = err
			if err == nil {
				ids[i] = ticket.TicketID
			}
		}(i)
	}
	wg.Wait()
	for i, err := range errs {
		if err != nil {
			t.Fatalf("goroutine %d: %v", i, err)
		}
	}
	first := ids[0]
	for i, id := range ids {
		if id != first {
			t.Fatalf("concurrent enqueue not idempotent: idx0=%s idx%d=%s", first, i, id)
		}
	}
}

func TestEnqueue_DifferentRuleCombosIsolatedPools(t *testing.T) {
	svc := newTestService(t)
	ctx := context.Background()

	combos := []struct {
		rk RoundKind
		gm GameMode
	}{
		{RoundKindEast, GameModeStandard},
		{RoundKindEast, GameModeTrashTalk},
		{RoundKindHanchan, GameModeStandard},
		{RoundKindHanchan, GameModeTrashTalk},
	}
	tickets := make([]Ticket, 0, 4)
	for _, c := range combos {
		// 同一 guest 不同组合应得到不同 ticket 并进入不同池
		tk, err := svc.Enqueue(ctx, "guest-pool", c.rk, c.gm)
		if err != nil {
			t.Fatalf("Enqueue %s/%s: %v", c.rk, c.gm, err)
		}
		tickets = append(tickets, tk)
	}
	seen := map[string]bool{}
	for _, tk := range tickets {
		if seen[tk.TicketID] {
			t.Fatalf("duplicate ticket across pools: %s", tk.TicketID)
		}
		seen[tk.TicketID] = true
		if !svc.IsInPool(ctx, tk) {
			t.Fatalf("ticket %s not in its pool", tk.TicketID)
		}
		// 不在其他三池
		for _, other := range tickets {
			if other.TicketID == tk.TicketID {
				continue
			}
			if svc.IsMemberOfPool(ctx, other.RoundKind, other.GameMode, tk.TicketID) {
				t.Fatalf("ticket %s leaked into pool %s/%s", tk.TicketID, other.RoundKind, other.GameMode)
			}
		}
	}
}

func TestGet_AndCancel_OwnerOnly_Idempotent(t *testing.T) {
	svc := newTestService(t)
	ctx := context.Background()

	tk, err := svc.Enqueue(ctx, "guest-owner", RoundKindEast, GameModeStandard)
	if err != nil {
		t.Fatalf("Enqueue: %v", err)
	}

	got, err := svc.Get(ctx, "guest-owner", tk.TicketID)
	if err != nil {
		t.Fatalf("Get owner: %v", err)
	}
	if got.Status != StatusWaiting {
		t.Fatalf("status = %q", got.Status)
	}

	_, err = svc.Get(ctx, "other-guest", tk.TicketID)
	if err == nil {
		t.Fatal("other guest Get expected error")
	}
	if err != ErrNotFound && err != ErrForbidden {
		// 允许 NotFound 或 Forbidden，但必须拒绝
		t.Fatalf("other guest Get err = %v", err)
	}

	cancelled, err := svc.Cancel(ctx, "guest-owner", tk.TicketID)
	if err != nil {
		t.Fatalf("Cancel: %v", err)
	}
	if cancelled.Status != StatusCancelled {
		t.Fatalf("status = %q, want cancelled", cancelled.Status)
	}
	if svc.IsInPool(ctx, tk) {
		t.Fatal("cancelled ticket must be removed from pool")
	}
	if svc.IsConsumable(ctx, tk.TicketID) {
		t.Fatal("cancelled ticket must not be consumable")
	}

	// 重复取消幂等
	again, err := svc.Cancel(ctx, "guest-owner", tk.TicketID)
	if err != nil {
		t.Fatalf("Cancel again: %v", err)
	}
	if again.Status != StatusCancelled {
		t.Fatalf("status after re-cancel = %q", again.Status)
	}

	// 仍可查询 cancelled
	query, err := svc.Get(ctx, "guest-owner", tk.TicketID)
	if err != nil {
		t.Fatalf("Get after cancel: %v", err)
	}
	if query.Status != StatusCancelled {
		t.Fatalf("query status = %q", query.Status)
	}

	// 取消后同组合可重新入队得到新 ticket
	newTk, err := svc.Enqueue(ctx, "guest-owner", RoundKindEast, GameModeStandard)
	if err != nil {
		t.Fatalf("re-enqueue: %v", err)
	}
	if newTk.TicketID == tk.TicketID {
		t.Fatal("re-enqueue after cancel must issue new ticket")
	}
	if newTk.Status != StatusWaiting {
		t.Fatalf("new status = %q", newTk.Status)
	}
}

func TestCancel_OtherGuestRejected(t *testing.T) {
	svc := newTestService(t)
	ctx := context.Background()
	tk, err := svc.Enqueue(ctx, "guest-a", RoundKindEast, GameModeStandard)
	if err != nil {
		t.Fatalf("Enqueue: %v", err)
	}
	_, err = svc.Cancel(ctx, "guest-b", tk.TicketID)
	if err == nil {
		t.Fatal("expected cancel reject for other guest")
	}
	// 仍在池中
	if !svc.IsInPool(ctx, tk) {
		t.Fatal("ticket must remain in pool after failed cancel")
	}
}

func TestValidateRules(t *testing.T) {
	if err := ValidateRules(RoundKindEast, GameModeStandard); err != nil {
		t.Fatalf("valid combo rejected: %v", err)
	}
	if err := ValidateRules("east", GameModeStandard); err == nil {
		t.Fatal("lowercase round_kind must be rejected")
	}
	if err := ValidateRules(RoundKindEast, "standard"); err == nil {
		t.Fatal("lowercase game_mode must be rejected")
	}
	if err := ValidateRules("SOUTH", GameModeStandard); err == nil {
		t.Fatal("invalid round_kind must be rejected")
	}
	if err := ValidateRules(RoundKindEast, "RANKED"); err == nil {
		t.Fatal("invalid game_mode must be rejected")
	}
}
