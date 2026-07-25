package queue

import (
	"context"
	"fmt"
	"sync"
	"testing"
	"time"

	"github.com/lov-team/mahjong-game/services/control-plane/internal/workers"
)

// #256：真实 Redis 下容量边界与失联回收、恢复后只接新房。
func TestMatch_CapacityOneDoesNotOversell(t *testing.T) {
	f := newMatchFixture(t)
	ctx := context.Background()

	// 覆盖默认 worker：容量 1
	f.mustRegisterWorker(t, "cap-1", "ws://cap1:9000", "ws://cap1:9001", 1)

	// 两批各 4 人，最多只能开 1 房
	_ = enqueueN(t, f.svc, 4, RoundKindEast, GameModeStandard)
	res1 := f.matchOnce(t)
	if !res1.Matched {
		t.Fatal("first match should succeed with capacity 1")
	}
	if got := f.ticketWorker(t, res1); got != "ws://cap1:9000" {
		// 可能仍命中默认大容量 worker；强制只保留 cap-1
		t.Logf("worker=%s (may be default); re-testing with only cap-1", got)
	}

	// 重新夹具：仅一个 capacity=1 worker
	f2 := newMatchFixture(t)
	// 让默认 worker 无容量：报告占满
	_, err := f2.reg.Register(ctx, workers.Registration{
		WorkerID:      f2.workerID,
		GameEndpoint:  f2.worker,
		VoiceEndpoint: f2.voiceWorker,
		Capacity:      1,
		ActiveRooms:   0,
	})
	if err != nil {
		t.Fatalf("register: %v", err)
	}
	_ = enqueueN(t, f2.svc, 4, RoundKindEast, GameModeStandard)
	r1 := f2.matchOnce(t)
	if !r1.Matched {
		t.Fatal("expected first room")
	}
	_ = enqueueNGuests(t, f2.svc, 4, 10, RoundKindEast, GameModeStandard)
	r2 := f2.matchOnce(t)
	if r2.Matched {
		t.Fatal("capacity 1 must not oversell second room")
	}
	rec, ok, err := f2.reg.Get(ctx, f2.workerID)
	if err != nil || !ok {
		t.Fatalf("Get worker: %v %v", ok, err)
	}
	if rec.ReservedRooms != 1 {
		t.Fatalf("reserved=%d want 1", rec.ReservedRooms)
	}
}

func TestMatch_CapacityTwoConcurrentNoOversell(t *testing.T) {
	f := newMatchFixture(t)
	ctx := context.Background()
	_, err := f.reg.Register(ctx, workers.Registration{
		WorkerID:      f.workerID,
		GameEndpoint:  f.worker,
		VoiceEndpoint: f.voiceWorker,
		Capacity:      2,
		ActiveRooms:   0,
	})
	if err != nil {
		t.Fatalf("register: %v", err)
	}

	// 准备 3 批可立即匹配的 4 人（容量 2 → 最多 2 房）
	for batch := 0; batch < 3; batch++ {
		_ = enqueueNGuests(t, f.svc, 4, batch*10, RoundKindEast, GameModeStandard)
	}

	const n = 12
	var wg sync.WaitGroup
	results := make([]MatchResult, n)
	errs := make([]error, n)
	wg.Add(n)
	for i := 0; i < n; i++ {
		go func(i int) {
			defer wg.Done()
			svc2, err := NewService(Options{
				Redis:     f.rdb,
				KeyPrefix: f.prefix,
				Clock:     f.clk,
				IDGen:     &seqIDGenVal{n: 8000 + i*40},
				Workers:   f.reg,
			})
			if err != nil {
				errs[i] = err
				return
			}
			results[i], errs[i] = svc2.MatchPool(ctx, RoundKindEast, GameModeStandard, MatchParams{
				TokenIssuer: f.issuer,
			})
		}(i)
	}
	wg.Wait()

	matched := 0
	rooms := map[string]struct{}{}
	for i, err := range errs {
		if err != nil {
			t.Fatalf("match %d: %v", i, err)
		}
		if results[i].Matched {
			matched++
			rooms[results[i].RoomID] = struct{}{}
		}
	}
	if matched != 2 {
		t.Fatalf("matched=%d want 2 (capacity boundary)", matched)
	}
	if len(rooms) != 2 {
		t.Fatalf("unique rooms=%d want 2", len(rooms))
	}
	rec, ok, err := f.reg.Get(ctx, f.workerID)
	if err != nil || !ok {
		t.Fatalf("Get: %v", err)
	}
	if rec.ReservedRooms != 2 {
		t.Fatalf("reserved=%d want 2", rec.ReservedRooms)
	}
}

func TestMatch_ExpiredWorkerNoNewRooms_AndReapROOM_FAILED(t *testing.T) {
	f := newMatchFixture(t)
	ctx := context.Background()
	_, err := f.reg.Register(ctx, workers.Registration{
		WorkerID:      f.workerID,
		GameEndpoint:  f.worker,
		VoiceEndpoint: f.voiceWorker,
		Capacity:      4,
		ActiveRooms:   0,
	})
	if err != nil {
		t.Fatalf("register: %v", err)
	}

	tickets := enqueueN(t, f.svc, 4, RoundKindEast, GameModeStandard)
	res := f.matchOnce(t)
	if !res.Matched {
		t.Fatal("expected match before expire")
	}

	// 租约过期（夹具 LeaseTTL=24h）
	f.clk.Advance(25 * time.Hour)
	_ = enqueueNGuests(t, f.svc, 4, 20, RoundKindEast, GameModeStandard)
	res2 := f.matchOnce(t)
	if res2.Matched {
		t.Fatal("expired worker must not receive new rooms")
	}

	n, err := f.reg.ReapExpired(ctx)
	if err != nil {
		t.Fatalf("ReapExpired: %v", err)
	}
	if n < 1 {
		t.Fatalf("reaped rooms=%d want >=1", n)
	}

	for _, tk0 := range tickets {
		tk, err := f.svc.Get(ctx, tk0.GuestID, tk0.TicketID)
		if err != nil {
			t.Fatalf("Get: %v", err)
		}
		if tk.Status != StatusFailed {
			t.Fatalf("ticket status=%q want failed", tk.Status)
		}
		if tk.FailCode != FailCodeRoomFailed {
			t.Fatalf("fail_code=%q want %s", tk.FailCode, FailCodeRoomFailed)
		}
	}
	room, err := f.svc.GetRoom(ctx, res.RoomID)
	if err != nil {
		t.Fatalf("GetRoom: %v", err)
	}
	if room.Status != StatusFailed || room.FailCode != FailCodeRoomFailed {
		t.Fatalf("room status=%q code=%q", room.Status, room.FailCode)
	}

	// 同一 worker_id 恢复后只接新房，旧失败保持
	_, err = f.reg.Register(ctx, workers.Registration{
		WorkerID:      f.workerID,
		GameEndpoint:  f.worker,
		VoiceEndpoint: f.voiceWorker,
		Capacity:      4,
		ActiveRooms:   0,
	})
	if err != nil {
		t.Fatalf("recover: %v", err)
	}
	newTickets := enqueueNGuests(t, f.svc, 4, 40, RoundKindEast, GameModeStandard)
	res3 := f.matchOnce(t)
	if !res3.Matched {
		t.Fatal("recovered worker should accept new rooms")
	}
	if res3.RoomID == res.RoomID {
		t.Fatal("must not resurrect old failed room")
	}
	for _, tk0 := range tickets {
		tk, err := f.svc.Get(ctx, tk0.GuestID, tk0.TicketID)
		if err != nil {
			t.Fatalf("old Get: %v", err)
		}
		if tk.Status != StatusFailed {
			t.Fatalf("old ticket must stay failed, got %s", tk.Status)
		}
	}
	for _, tk0 := range newTickets {
		tk, err := f.svc.Get(ctx, tk0.GuestID, tk0.TicketID)
		if err != nil {
			t.Fatalf("new Get: %v", err)
		}
		if tk.Status != StatusAssigned {
			t.Fatalf("new ticket status=%s", tk.Status)
		}
	}
}

func TestMatch_CapacityOne_CompleteThenMatchAgain(t *testing.T) {
	f := newMatchFixture(t)
	ctx := context.Background()
	_, err := f.reg.Register(ctx, workers.Registration{
		WorkerID: f.workerID, GameEndpoint: f.worker, VoiceEndpoint: f.voiceWorker,
		Capacity: 1, ActiveRooms: 0,
	})
	if err != nil {
		t.Fatalf("register: %v", err)
	}
	_ = enqueueN(t, f.svc, 4, RoundKindEast, GameModeStandard)
	r1 := f.matchOnce(t)
	if !r1.Matched {
		t.Fatal("first match")
	}
	// 未完成前第二房应失败
	_ = enqueueNGuests(t, f.svc, 4, 100, RoundKindEast, GameModeStandard)
	rBlocked := f.matchOnce(t)
	if rBlocked.Matched {
		t.Fatal("must not match while capacity reserved")
	}
	// 正常完成释放
	kind, err := f.reg.CompleteRoom(ctx, f.workerID, r1.RoomID)
	if err != nil || (kind != workers.CompleteOK && kind != workers.CompleteIdempotent) {
		t.Fatalf("CompleteRoom: %s %v", kind, err)
	}
	room, err := f.svc.GetRoom(ctx, r1.RoomID)
	if err != nil {
		t.Fatalf("GetRoom: %v", err)
	}
	if room.Status != "completed" {
		t.Fatalf("room status=%q want completed", room.Status)
	}
	// 再分配
	r2 := f.matchOnce(t)
	if !r2.Matched {
		t.Fatal("after complete, capacity=1 worker must accept new room")
	}
	if r2.RoomID == r1.RoomID {
		t.Fatal("must be a new room id")
	}
}

func TestMatch_ReportedRoomsConservativeOccupancy(t *testing.T) {
	f := newMatchFixture(t)
	ctx := context.Background()
	// capacity=2, reported=2 → 不可选，即使 reserved=0
	_, err := f.reg.Register(ctx, workers.Registration{
		WorkerID:      f.workerID,
		GameEndpoint:  f.worker,
		VoiceEndpoint: f.voiceWorker,
		Capacity:      2,
		ActiveRooms:   2,
	})
	if err != nil {
		t.Fatalf("register: %v", err)
	}
	_ = enqueueN(t, f.svc, 4, RoundKindEast, GameModeStandard)
	res := f.matchOnce(t)
	if res.Matched {
		t.Fatal("reported full occupancy must block match")
	}
}

func enqueueNGuests(t *testing.T, svc *Service, n, guestBase int, rk RoundKind, gm GameMode) []Ticket {
	t.Helper()
	ctx := context.Background()
	out := make([]Ticket, 0, n)
	for i := 0; i < n; i++ {
		tk, err := svc.Enqueue(ctx, fmt.Sprintf("guest-%d", guestBase+i+1), rk, gm)
		if err != nil {
			t.Fatalf("Enqueue: %v", err)
		}
		out = append(out, tk)
	}
	return out
}

func (f *matchFixture) ticketWorker(t *testing.T, res MatchResult) string {
	t.Helper()
	if !res.Matched || len(res.TicketIDs) == 0 {
		return ""
	}
	// guest id 约定 guest-1..
	tk, err := f.svc.Get(context.Background(), "guest-1", res.TicketIDs[0])
	if err != nil {
		return ""
	}
	return tk.Worker
}
