package queue

import (
	"context"
	"errors"
	"fmt"
	"testing"
	"time"
)

func TestEnqueue_RequiresCanonicalCharacterID(t *testing.T) {
	svc := newTestService(t)
	ctx := context.Background()
	_, err := svc.Enqueue(ctx, "guest-a", RoundKindEast, GameModeStandard, "")
	if !errors.Is(err, ErrInvalidCharacter) {
		t.Fatalf("empty: err=%v want ErrInvalidCharacter", err)
	}
	_, err = svc.Enqueue(ctx, "guest-a", RoundKindEast, GameModeStandard, "not_a_real_char")
	if !errors.Is(err, ErrInvalidCharacter) {
		t.Fatalf("unknown: err=%v want ErrInvalidCharacter", err)
	}
	tk, err := svc.Enqueue(ctx, "guest-a", RoundKindEast, GameModeStandard, "lin_yeche")
	if err != nil {
		t.Fatalf("valid: %v", err)
	}
	if tk.CharacterID != "lin_yeche" {
		t.Fatalf("character_id=%q", tk.CharacterID)
	}
}

func TestBuildCharacterRoster_HumanPreservedAIDeterministic(t *testing.T) {
	parts := []string{SeatKindHuman, SeatKindAI, SeatKindAI, SeatKindAI}
	roster, err := BuildCharacterRoster(parts, map[int]string{0: "qiu_jue"})
	if err != nil {
		t.Fatalf("Build: %v", err)
	}
	if roster[0] != "qiu_jue" {
		t.Fatalf("human seat0=%q", roster[0])
	}
	// AI 取字典序目录中尚未占用的首个
	if roster[1] != "an_cheng" || roster[2] != "bai_touli" || roster[3] != "bao_luo" {
		t.Fatalf("ai roster=%#v", roster)
	}
	// 再次调用必须相同（确定性）
	roster2, err := BuildCharacterRoster(parts, map[int]string{0: "qiu_jue"})
	if err != nil {
		t.Fatal(err)
	}
	for i := range roster {
		if roster[i] != roster2[i] {
			t.Fatalf("non-deterministic at %d: %q vs %q", i, roster[i], roster2[i])
		}
	}
}

func TestMatchPool_RoomTokenSignsFullCharacterRoster(t *testing.T) {
	f := newMatchFixture(t)
	ctx := context.Background()
	// 1 真人 + 30s AI 补位
	tk, err := f.svc.Enqueue(ctx, "guest-char", RoundKindEast, GameModeStandard, "hua_ling")
	if err != nil {
		t.Fatalf("Enqueue: %v", err)
	}
	f.clk.t = f.clk.t.Add(QueueWaitDeadline + time.Millisecond)
	res, err := f.svc.MatchPool(ctx, RoundKindEast, GameModeStandard, MatchParams{TokenIssuer: f.issuer})
	if err != nil {
		t.Fatalf("MatchPool: %v", err)
	}
	if !res.Matched {
		t.Fatal("expected match")
	}
	got, err := f.svc.Get(ctx, "guest-char", tk.TicketID)
	if err != nil {
		t.Fatalf("Get: %v", err)
	}
	if got.Status != StatusAssigned || got.RoomToken == "" {
		t.Fatalf("assigned ticket incomplete: %+v", got)
	}
	claims, err := f.issuer.VerifyRoomToken(got.RoomToken, got.RoomID, got.Seat)
	if err != nil {
		t.Fatalf("VerifyRoomToken: %v", err)
	}
	if len(claims.CharacterIDs) != 4 {
		t.Fatalf("character_ids len=%d", len(claims.CharacterIDs))
	}
	if claims.CharacterIDs[0] != "hua_ling" {
		t.Fatalf("human char not preserved: %#v", claims.CharacterIDs)
	}
	// AI 确定性补齐
	wantAI, err := BuildCharacterRoster(
		[]string{SeatKindHuman, SeatKindAI, SeatKindAI, SeatKindAI},
		map[int]string{0: "hua_ling"},
	)
	if err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 4; i++ {
		if claims.CharacterIDs[i] != wantAI[i] {
			t.Fatalf("seat %d char=%q want %q", i, claims.CharacterIDs[i], wantAI[i])
		}
	}
	room, err := f.svc.GetRoom(ctx, res.RoomID)
	if err != nil {
		t.Fatalf("GetRoom: %v", err)
	}
	if len(room.CharacterIDs) != 4 || room.CharacterIDs[0] != "hua_ling" {
		t.Fatalf("room roster=%#v", room.CharacterIDs)
	}
	// #374：room.character_ids 与 token claims 必须原子一致（非 post-commit 补写）
	for i := 0; i < 4; i++ {
		if room.CharacterIDs[i] != claims.CharacterIDs[i] {
			t.Fatalf("room/token roster diverge seat %d: room=%q token=%q",
				i, room.CharacterIDs[i], claims.CharacterIDs[i])
		}
	}
}

func TestMatchPool_FourHumansAtomicRoomRosterMatchesAllTokens(t *testing.T) {
	f := newMatchFixture(t)
	ctx := context.Background()
	chars := []string{"lin_yeche", "qiu_jue", "an_cheng", "bai_touli"}
	tickets := make([]Ticket, 0, 4)
	for i, c := range chars {
		tk, err := f.svc.Enqueue(ctx, fmt.Sprintf("guest-4h-%d", i), RoundKindEast, GameModeStandard, c)
		if err != nil {
			t.Fatalf("Enqueue %d: %v", i, err)
		}
		tickets = append(tickets, tk)
	}
	res, err := f.svc.MatchPool(ctx, RoundKindEast, GameModeStandard, MatchParams{TokenIssuer: f.issuer})
	if err != nil {
		t.Fatalf("MatchPool: %v", err)
	}
	if !res.Matched || res.HumanCount != 4 {
		t.Fatalf("match result=%+v", res)
	}
	room, err := f.svc.GetRoom(ctx, res.RoomID)
	if err != nil {
		t.Fatalf("GetRoom: %v", err)
	}
	if len(room.CharacterIDs) != 4 {
		t.Fatalf("room.CharacterIDs=%#v", room.CharacterIDs)
	}
	for i, want := range chars {
		if room.CharacterIDs[i] != want {
			t.Fatalf("room seat %d=%q want %q", i, room.CharacterIDs[i], want)
		}
	}
	for i, tk0 := range tickets {
		got, err := f.svc.Get(ctx, fmt.Sprintf("guest-4h-%d", i), tk0.TicketID)
		if err != nil {
			t.Fatalf("Get ticket %d: %v", i, err)
		}
		if got.Status != StatusAssigned || got.RoomToken == "" {
			t.Fatalf("ticket %d not fully assigned: %+v", i, got)
		}
		claims, err := f.issuer.VerifyRoomToken(got.RoomToken, got.RoomID, got.Seat)
		if err != nil {
			t.Fatalf("verify seat %d: %v", i, err)
		}
		if len(claims.CharacterIDs) != 4 {
			t.Fatalf("claims len=%d", len(claims.CharacterIDs))
		}
		for j := 0; j < 4; j++ {
			if claims.CharacterIDs[j] != room.CharacterIDs[j] {
				t.Fatalf("seat %d token roster[%d]=%q room=%q", i, j, claims.CharacterIDs[j], room.CharacterIDs[j])
			}
		}
	}
}
