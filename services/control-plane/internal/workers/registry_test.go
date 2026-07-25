package workers

import (
	"context"
	"fmt"
	"os"
	"strconv"
	"sync"
	"testing"
	"time"

	"github.com/lov-team/mahjong-game/services/control-plane/internal/redisx"
	"github.com/redis/go-redis/v9"
)

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

type regFixture struct {
	reg    *Registry
	rdb    *redis.Client
	clk    *mutableClock
	prefix string
	casual string
}

func newRegFixture(t *testing.T) *regFixture {
	t.Helper()
	rdb := requireRealRedis(t)
	prefix := "test:workers:" + t.Name() + ":"
	casual := prefix + "casual:"
	clk := &mutableClock{t: time.Date(2026, 7, 26, 12, 0, 0, 0, time.UTC)}
	reg, err := NewRegistry(Options{
		Redis:        rdb,
		KeyPrefix:    prefix,
		CasualPrefix: casual,
		Clock:        clk,
		LeaseTTL:     10 * time.Second,
	})
	if err != nil {
		t.Fatalf("NewRegistry: %v", err)
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
	return &regFixture{reg: reg, rdb: rdb, clk: clk, prefix: prefix, casual: casual}
}

func TestRegister_Renew_Expire_SameWorkerIDRecover(t *testing.T) {
	f := newRegFixture(t)
	ctx := context.Background()

	res, err := f.reg.Register(ctx, Registration{
		WorkerID:      "w1",
		GameEndpoint:  "ws://127.0.0.1:9000",
		VoiceEndpoint: "ws://127.0.0.1:9001",
		Capacity:      2,
		ActiveRooms:   0,
	})
	if err != nil {
		t.Fatalf("Register: %v", err)
	}
	if res.WorkerID != "w1" {
		t.Fatalf("worker_id=%q", res.WorkerID)
	}
	wantExp := f.clk.Now().UnixMilli() + 10_000
	if res.LeaseExpiresAtMs != wantExp {
		t.Fatalf("lease expires=%d want %d", res.LeaseExpiresAtMs, wantExp)
	}

	ok, err := f.reg.IsSelectable(ctx, "w1")
	if err != nil || !ok {
		t.Fatalf("expected selectable after register: ok=%v err=%v", ok, err)
	}

	// 人为设置 reserved=1，续租报告 active=0 不得把 reserved 打成 0。
	if err := f.rdb.HSet(ctx, f.reg.WorkerKey("w1"), "reserved_rooms", "1").Err(); err != nil {
		t.Fatalf("HSET reserved: %v", err)
	}
	f.clk.Advance(3 * time.Second)
	res2, err := f.reg.Register(ctx, Registration{
		WorkerID:      "w1",
		GameEndpoint:  "ws://127.0.0.1:9000",
		VoiceEndpoint: "ws://127.0.0.1:9001",
		Capacity:      2,
		ActiveRooms:   0,
	})
	if err != nil {
		t.Fatalf("renew: %v", err)
	}
	wantExp2 := f.clk.Now().UnixMilli() + 10_000
	if res2.LeaseExpiresAtMs != wantExp2 {
		t.Fatalf("renew lease expires=%d want %d", res2.LeaseExpiresAtMs, wantExp2)
	}
	rec, found, err := f.reg.Get(ctx, "w1")
	if err != nil || !found {
		t.Fatalf("Get after renew: found=%v err=%v", found, err)
	}
	if rec.ReservedRooms != 1 {
		t.Fatalf("reserved after renew with active=0: got %d want 1 (must not lower reserved)", rec.ReservedRooms)
	}
	if rec.ReportedRooms != 0 {
		t.Fatalf("reported=%d", rec.ReportedRooms)
	}

	// 租约过期：不再可选
	f.clk.Advance(11 * time.Second)
	ok, err = f.reg.IsSelectable(ctx, "w1")
	if err != nil {
		t.Fatalf("IsSelectable: %v", err)
	}
	if ok {
		t.Fatal("expired worker must not be selectable")
	}

	// 同一 worker_id 恢复注册
	res3, err := f.reg.Register(ctx, Registration{
		WorkerID:      "w1",
		GameEndpoint:  "ws://127.0.0.1:9100",
		VoiceEndpoint: "ws://127.0.0.1:9101",
		Capacity:      3,
		ActiveRooms:   0,
	})
	if err != nil {
		t.Fatalf("recover register: %v", err)
	}
	if res3.LeaseExpiresAtMs <= f.clk.Now().UnixMilli() {
		t.Fatal("recovered lease must be in future")
	}
	rec, found, err = f.reg.Get(ctx, "w1")
	if err != nil || !found {
		t.Fatalf("Get after recover: found=%v err=%v", found, err)
	}
	if rec.GameEndpoint != "ws://127.0.0.1:9100" {
		t.Fatalf("game endpoint after recover=%q", rec.GameEndpoint)
	}
	if rec.Capacity != 3 {
		t.Fatalf("capacity=%d", rec.Capacity)
	}
	ok, err = f.reg.IsSelectable(ctx, "w1")
	if err != nil || !ok {
		t.Fatalf("expected selectable after recover: ok=%v err=%v", ok, err)
	}
}

func TestReap_MarksAssignedTicketsAndRoomsFailed(t *testing.T) {
	f := newRegFixture(t)
	ctx := context.Background()

	_, err := f.reg.Register(ctx, Registration{
		WorkerID:      "w-dead",
		GameEndpoint:  "ws://127.0.0.1:9000",
		VoiceEndpoint: "ws://127.0.0.1:9001",
		Capacity:      2,
		ActiveRooms:   0,
	})
	if err != nil {
		t.Fatalf("Register: %v", err)
	}

	roomID := "room-fail-1"
	ticketID := "ticket-fail-1"
	// 模拟已分配房间与 ticket（与 queue 键布局一致）
	rkey := f.casual + "room:" + roomID
	tkey := f.casual + "ticket:" + ticketID
	if err := f.rdb.HSet(ctx, rkey, map[string]interface{}{
		"room_id":          roomID,
		"worker":           "ws://127.0.0.1:9000",
		"worker_id":        "w-dead",
		"status":           StatusActive,
		"human_count":      "1",
		"ai_count":         "3",
		"seat_0_kind":      "HUMAN",
		"seat_0_ticket_id": ticketID,
		"seat_0_guest_id":  "guest-1",
		"seat_1_kind":      "AI",
		"seat_2_kind":      "AI",
		"seat_3_kind":      "AI",
	}).Err(); err != nil {
		t.Fatalf("seed room: %v", err)
	}
	if err := f.rdb.HSet(ctx, tkey, map[string]interface{}{
		"ticket_id":  ticketID,
		"guest_id":   "guest-1",
		"status":     StatusAssigned,
		"room_id":    roomID,
		"worker":     "ws://127.0.0.1:9000",
		"seat":       "0",
		"room_token": "tok-secret-must-not-leak-in-logs",
	}).Err(); err != nil {
		t.Fatalf("seed ticket: %v", err)
	}
	if err := f.rdb.SAdd(ctx, f.reg.RoomsKey("w-dead"), roomID).Err(); err != nil {
		t.Fatalf("SADD rooms: %v", err)
	}
	if err := f.rdb.HSet(ctx, f.reg.WorkerKey("w-dead"), "reserved_rooms", "1").Err(); err != nil {
		t.Fatalf("reserved: %v", err)
	}

	// 租约过期
	f.clk.Advance(11 * time.Second)
	n, err := f.reg.ReapExpired(ctx)
	if err != nil {
		t.Fatalf("ReapExpired: %v", err)
	}
	if n != 1 {
		t.Fatalf("failed rooms=%d want 1", n)
	}

	rst, err := f.rdb.HGet(ctx, rkey, "status").Result()
	if err != nil || rst != StatusFailed {
		t.Fatalf("room status=%q err=%v", rst, err)
	}
	rcode, _ := f.rdb.HGet(ctx, rkey, "fail_code").Result()
	if rcode != FailCodeRoomFailed {
		t.Fatalf("room fail_code=%q", rcode)
	}
	tst, err := f.rdb.HGet(ctx, tkey, "status").Result()
	if err != nil || tst != StatusFailed {
		t.Fatalf("ticket status=%q err=%v", tst, err)
	}
	tcode, _ := f.rdb.HGet(ctx, tkey, "fail_code").Result()
	if tcode != FailCodeRoomFailed {
		t.Fatalf("ticket fail_code=%q", tcode)
	}

	// 过期后不可分配
	ok, err := f.reg.IsSelectable(ctx, "w-dead")
	if err != nil || ok {
		t.Fatalf("dead worker selectable=%v err=%v", ok, err)
	}

	// 同一 id 恢复：旧失败保持
	_, err = f.reg.Register(ctx, Registration{
		WorkerID:      "w-dead",
		GameEndpoint:  "ws://127.0.0.1:9000",
		VoiceEndpoint: "ws://127.0.0.1:9001",
		Capacity:      2,
		ActiveRooms:   0,
	})
	if err != nil {
		t.Fatalf("recover: %v", err)
	}
	tst, _ = f.rdb.HGet(ctx, tkey, "status").Result()
	if tst != StatusFailed {
		t.Fatalf("old ticket must stay failed, got %q", tst)
	}
	rst, _ = f.rdb.HGet(ctx, rkey, "status").Result()
	if rst != StatusFailed {
		t.Fatalf("old room must stay failed, got %q", rst)
	}
	// 恢复后 reserved 应已在 reap 时清零，可重新接新房
	rec, found, err := f.reg.Get(ctx, "w-dead")
	if err != nil || !found {
		t.Fatalf("Get: found=%v err=%v", found, err)
	}
	if rec.ReservedRooms != 0 {
		t.Fatalf("reserved after recover path=%d want 0", rec.ReservedRooms)
	}
	ok, err = f.reg.IsSelectable(ctx, "w-dead")
	if err != nil || !ok {
		t.Fatalf("recovered worker should be selectable: ok=%v err=%v", ok, err)
	}
}

func TestRegister_RejectsInvalid(t *testing.T) {
	f := newRegFixture(t)
	ctx := context.Background()
	cases := []Registration{
		{WorkerID: "", GameEndpoint: "ws://x", VoiceEndpoint: "ws://y", Capacity: 1},
		{WorkerID: "w", GameEndpoint: "", VoiceEndpoint: "ws://y", Capacity: 1},
		{WorkerID: "w", GameEndpoint: "ws://x", VoiceEndpoint: "", Capacity: 1},
		{WorkerID: "w", GameEndpoint: "ws://x", VoiceEndpoint: "ws://y", Capacity: 0},
		{WorkerID: "w", GameEndpoint: "ws://x", VoiceEndpoint: "ws://y", Capacity: 1, ActiveRooms: -1},
	}
	for i, c := range cases {
		if _, err := f.reg.Register(ctx, c); err == nil {
			t.Fatalf("case %d: expected error", i)
		}
	}
}

func TestReaper_StopWithoutStart(t *testing.T) {
	f := newRegFixture(t)
	rp, err := NewReaper(ReaperOptions{Registry: f.reg, Interval: 50 * time.Millisecond})
	if err != nil {
		t.Fatalf("NewReaper: %v", err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	if err := rp.Stop(ctx); err != nil {
		t.Fatalf("Stop without Start: %v", err)
	}
}

func TestCompleteRoom_ReleasesCapacityIdempotent_NoNegativeReserved(t *testing.T) {
	f := newRegFixture(t)
	ctx := context.Background()
	_, err := f.reg.Register(ctx, workersRegistration("w-cap1", 1))
	if err != nil {
		t.Fatalf("Register: %v", err)
	}
	// 模拟 match 预留
	if err := f.rdb.HSet(ctx, f.reg.WorkerKey("w-cap1"), "reserved_rooms", "1").Err(); err != nil {
		t.Fatalf("reserved: %v", err)
	}
	roomID := "room-done-1"
	rkey := f.casual + "room:" + roomID
	if err := f.rdb.HSet(ctx, rkey, map[string]interface{}{
		"room_id": roomID, "worker_id": "w-cap1", "status": StatusActive, "human_count": "1",
	}).Err(); err != nil {
		t.Fatalf("seed room: %v", err)
	}
	if err := f.rdb.SAdd(ctx, f.reg.RoomsKey("w-cap1"), roomID).Err(); err != nil {
		t.Fatalf("sadd: %v", err)
	}

	kind, err := f.reg.CompleteRoom(ctx, "w-cap1", roomID)
	if err != nil || kind != CompleteOK {
		t.Fatalf("CompleteRoom: kind=%s err=%v", kind, err)
	}
	rec, ok, err := f.reg.Get(ctx, "w-cap1")
	if err != nil || !ok {
		t.Fatalf("Get: %v", err)
	}
	if rec.ReservedRooms != 0 {
		t.Fatalf("reserved after complete=%d want 0", rec.ReservedRooms)
	}
	st, _ := f.rdb.HGet(ctx, rkey, "status").Result()
	if st != StatusCompleted {
		t.Fatalf("status=%q want completed", st)
	}
	// 幂等再 complete
	kind2, err := f.reg.CompleteRoom(ctx, "w-cap1", roomID)
	if err != nil || kind2 != CompleteIdempotent {
		t.Fatalf("idempotent: kind=%s err=%v", kind2, err)
	}
	rec, _, _ = f.reg.Get(ctx, "w-cap1")
	if rec.ReservedRooms != 0 {
		t.Fatalf("reserved after idempotent complete=%d (must not go negative)", rec.ReservedRooms)
	}
	// 错 worker
	if err := f.rdb.HSet(ctx, rkey, "status", StatusActive, "worker_id", "other").Err(); err != nil {
		t.Fatalf("reset: %v", err)
	}
	if err := f.rdb.HSet(ctx, f.reg.WorkerKey("w-cap1"), "reserved_rooms", "1").Err(); err != nil {
		t.Fatalf("reserved: %v", err)
	}
	kind3, err := f.reg.CompleteRoom(ctx, "w-cap1", roomID)
	if err != nil || kind3 != CompleteWrongWorker {
		t.Fatalf("wrong worker kind=%s err=%v", kind3, err)
	}
	// failed 不复活
	if err := f.rdb.HSet(ctx, rkey, "status", StatusFailed, "worker_id", "w-cap1", "fail_code", FailCodeRoomFailed).Err(); err != nil {
		t.Fatalf("fail seed: %v", err)
	}
	kind4, err := f.reg.CompleteRoom(ctx, "w-cap1", roomID)
	if err != nil || kind4 != CompleteAlreadyFailed {
		t.Fatalf("already failed kind=%s err=%v", kind4, err)
	}
	st, _ = f.rdb.HGet(ctx, rkey, "status").Result()
	if st != StatusFailed {
		t.Fatalf("failed must stay failed, got %q", st)
	}
}

func workersRegistration(id string, cap int) Registration {
	return Registration{
		WorkerID: id, GameEndpoint: "ws://127.0.0.1:9000", VoiceEndpoint: "ws://127.0.0.1:9001",
		Capacity: cap, ActiveRooms: 0,
	}
}

func TestReap_RemovesFromIndex_IdempotentZero_RecoverReadds(t *testing.T) {
	f := newRegFixture(t)
	ctx := context.Background()
	_, err := f.reg.Register(ctx, workersRegistration("w-idx", 2))
	if err != nil {
		t.Fatalf("Register: %v", err)
	}
	members, err := f.reg.IndexMembers(ctx)
	if err != nil {
		t.Fatalf("IndexMembers: %v", err)
	}
	found := false
	for _, m := range members {
		if m == "w-idx" {
			found = true
		}
	}
	if !found {
		t.Fatal("expected worker in index after register")
	}
	f.clk.Advance(11 * time.Second)
	n, err := f.reg.ReapExpired(ctx)
	if err != nil {
		t.Fatalf("reap: %v", err)
	}
	if n != 0 {
		// no rooms seeded — still remove from index
		t.Logf("failed_rooms=%d (ok if 0)", n)
	}
	members, err = f.reg.IndexMembers(ctx)
	if err != nil {
		t.Fatalf("IndexMembers2: %v", err)
	}
	for _, m := range members {
		if m == "w-idx" {
			t.Fatal("expired worker must be removed from selection index")
		}
	}
	n2, err := f.reg.ReapExpired(ctx)
	if err != nil || n2 != 0 {
		t.Fatalf("second reap rooms=%d err=%v want 0", n2, err)
	}
	// 恢复重新加入索引
	_, err = f.reg.Register(ctx, workersRegistration("w-idx", 2))
	if err != nil {
		t.Fatalf("recover: %v", err)
	}
	members, _ = f.reg.IndexMembers(ctx)
	found = false
	for _, m := range members {
		if m == "w-idx" {
			found = true
		}
	}
	if !found {
		t.Fatal("recovered worker must re-enter index")
	}
}

func TestReap_DoesNotFailCompletedRooms(t *testing.T) {
	f := newRegFixture(t)
	ctx := context.Background()
	_, err := f.reg.Register(ctx, workersRegistration("w-c", 2))
	if err != nil {
		t.Fatalf("Register: %v", err)
	}
	roomID := "room-completed-keep"
	rkey := f.casual + "room:" + roomID
	if err := f.rdb.HSet(ctx, rkey, map[string]interface{}{
		"room_id": roomID, "worker_id": "w-c", "status": StatusCompleted, "human_count": "1",
		"seat_0_ticket_id": "t-keep",
	}).Err(); err != nil {
		t.Fatalf("seed: %v", err)
	}
	tkey := f.casual + "ticket:t-keep"
	if err := f.rdb.HSet(ctx, tkey, map[string]interface{}{
		"ticket_id": "t-keep", "status": StatusAssigned, "guest_id": "g1",
	}).Err(); err != nil {
		t.Fatalf("ticket: %v", err)
	}
	if err := f.rdb.SAdd(ctx, f.reg.RoomsKey("w-c"), roomID).Err(); err != nil {
		t.Fatalf("sadd: %v", err)
	}
	f.clk.Advance(11 * time.Second)
	if _, err := f.reg.ReapExpired(ctx); err != nil {
		t.Fatalf("reap: %v", err)
	}
	st, _ := f.rdb.HGet(ctx, rkey, "status").Result()
	if st != StatusCompleted {
		t.Fatalf("completed room must not become failed, got %q", st)
	}
	tst, _ := f.rdb.HGet(ctx, tkey, "status").Result()
	if tst != StatusAssigned {
		t.Fatalf("ticket of completed room must stay assigned, got %q", tst)
	}
}

func TestComplete_Vs_Reap_SingleTerminalState(t *testing.T) {
	// 并发 complete 与 reap：只允许 completed 或 failed 之一
	f := newRegFixture(t)
	ctx := context.Background()
	_, err := f.reg.Register(ctx, workersRegistration("w-race", 2))
	if err != nil {
		t.Fatalf("Register: %v", err)
	}
	roomID := "room-race"
	rkey := f.casual + "room:" + roomID
	if err := f.rdb.HSet(ctx, rkey, map[string]interface{}{
		"room_id": roomID, "worker_id": "w-race", "status": StatusActive, "human_count": "0",
	}).Err(); err != nil {
		t.Fatalf("seed: %v", err)
	}
	_ = f.rdb.SAdd(ctx, f.reg.RoomsKey("w-race"), roomID).Err()
	_ = f.rdb.HSet(ctx, f.reg.WorkerKey("w-race"), "reserved_rooms", "1").Err()
	f.clk.Advance(11 * time.Second)

	var wg sync.WaitGroup
	wg.Add(2)
	var completeKind string
	var completeErr, reapErr error
	go func() {
		defer wg.Done()
		completeKind, completeErr = f.reg.CompleteRoom(ctx, "w-race", roomID)
	}()
	go func() {
		defer wg.Done()
		_, reapErr = f.reg.ReapExpired(ctx)
	}()
	wg.Wait()
	if completeErr != nil {
		t.Fatalf("complete err: %v", completeErr)
	}
	if reapErr != nil {
		t.Fatalf("reap err: %v", reapErr)
	}
	st, _ := f.rdb.HGet(ctx, rkey, "status").Result()
	if st != StatusCompleted && st != StatusFailed {
		t.Fatalf("terminal status=%q", st)
	}
	// complete 若赢 → completed；reap 若赢 → failed；complete 后到 failed 会 ALREADY_FAILED
	_ = completeKind
}

func TestReportedRoomsMakesOccupancyConservative(t *testing.T) {
	f := newRegFixture(t)
	ctx := context.Background()
	_, err := f.reg.Register(ctx, Registration{
		WorkerID:      "w-cap",
		GameEndpoint:  "ws://127.0.0.1:9000",
		VoiceEndpoint: "ws://127.0.0.1:9001",
		Capacity:      1,
		ActiveRooms:   1, // 报告已满；reserved=0 时仍不可选
	})
	if err != nil {
		t.Fatalf("Register: %v", err)
	}
	ok, err := f.reg.IsSelectable(ctx, "w-cap")
	if err != nil {
		t.Fatalf("IsSelectable: %v", err)
	}
	if ok {
		t.Fatal("reported_rooms=capacity must not be selectable")
	}
	//  sanity
	_ = fmt.Sprintf("ok")
}
