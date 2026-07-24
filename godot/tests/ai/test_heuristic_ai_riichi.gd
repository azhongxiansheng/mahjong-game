extends GutTest

# 麻将王 — M7 平衡：HeuristicAi.decide_riichi 单测 + BC 集成（E2-02 公开 apply_action）。
# 集成 fixture：清四席活动区 → draw_index=0 → live 区 swap + 真实 wall.draw() 消费。

const _CMD_UUID := "550e8400-e29b-41d4-a716-000000000001"
const _ROOM := "local"

var _used_wall_iids: Dictionary = {}


func _make_seat_with_hand(ids: Array, points: int = 25000) -> Seat:
	var s := Seat.new(0, TileId.E, points)
	s.hand._tiles.clear()
	for tid in ids:
		s.hand.add(Tile.new(tid))
	return s


# 七対子听 W9 单骑（13 tiles）
func _chiitoi_tenpai_hand() -> Array:
	return [
		TileId.W1, TileId.W1, TileId.W2, TileId.W2, TileId.W3, TileId.W3,
		TileId.W5, TileId.W5, TileId.W6, TileId.W6, TileId.W7, TileId.W7,
		TileId.W9,
	]


func _live_end(w: Wall) -> int:
	return w._tiles.size() - w._dead_wall_size


## 清空四席 hand/meld/river/last_drawn/furiten，draw_index 回 0；不改 dead wall。
func _prepare_live_fixture(bc: BattleController) -> void:
	for s in range(4):
		var seat: Seat = bc.state.seats[s]
		seat.hand = Hand.new()
		seat.melds = []
		seat.last_drawn_instance_id = Tile.INVALID_INSTANCE_ID
		seat.last_draw_is_rinshan = false
		seat.furiten = FuritenState.new()
		bc.state.discards_per_seat[s] = []
	bc.state.wall._draw_index = 0
	_used_wall_iids.clear()


func _assert_iid_absent_from_active_zones(
	bc: BattleController, iid: int, except_seat: int = -1
) -> void:
	for s in range(4):
		if s == except_seat:
			continue
		var seat: Seat = bc.state.seats[s]
		for t in seat.hand._tiles:
			if t == null:
				continue
			assert_ne(int(t.instance_id), iid,
				"iid=%d 不得仍在 seat%d hand" % [iid, s])
		for m in seat.melds:
			if m == null:
				continue
			for t2 in m.tiles:
				if t2 == null:
					continue
				assert_ne(int(t2.instance_id), iid,
					"iid=%d 不得仍在 seat%d meld" % [iid, s])
		for t3 in bc.state.discards_per_seat[s]:
			if t3 == null:
				continue
			assert_ne(int(t3.instance_id), iid,
				"iid=%d 不得仍在 seat%d river" % [iid, s])


func _find_live_index(w: Wall, tid: int) -> int:
	var end_i: int = _live_end(w)
	for i in range(w._draw_index, end_i):
		var t: Tile = w._tiles[i]
		if t == null or int(t.id) != int(tid):
			continue
		var iid: int = int(t.instance_id)
		if _used_wall_iids.has(iid):
			continue
		return i
	return -1


func _swap_live_to_draw_index(w: Wall, live_idx: int) -> void:
	assert_gte(live_idx, w._draw_index)
	assert_lt(live_idx, _live_end(w))
	if live_idx == w._draw_index:
		return
	var tmp: Tile = w._tiles[w._draw_index]
	w._tiles[w._draw_index] = w._tiles[live_idx]
	w._tiles[live_idx] = tmp


## live 未摸区找 tid → swap 到 draw_index → 真实 wall.draw() 消费。
func _draw_from_live(bc: BattleController, tid: int) -> Tile:
	assert_not_null(bc)
	assert_not_null(bc.state)
	var w: Wall = bc.state.wall
	assert_not_null(w)
	var live_idx: int = _find_live_index(w, tid)
	assert_true(live_idx >= 0, "live 未摸区无剩余 id=%d 的 canonical 实体" % tid)
	_swap_live_to_draw_index(w, live_idx)
	var selected: Tile = w._tiles[w._draw_index]
	assert_not_null(selected)
	var iid: int = int(selected.instance_id)
	assert_true(Tile.is_instance_id_in_hand_seq(iid, bc.state.hand_seq),
		"wall tile 必须在本局 hand_seq 命名空间 iid=%d" % iid)
	_assert_iid_absent_from_active_zones(bc, iid)
	var drawn: Tile = w.draw()
	assert_not_null(drawn, "wall.draw() 必须消耗 live 顶")
	assert_true(drawn == selected, "draw 必须返回 swap 后的同一实体对象")
	assert_eq(int(drawn.instance_id), iid)
	_used_wall_iids[iid] = true
	_assert_iid_absent_from_active_zones(bc, iid)
	return drawn


func _hand_from_live(bc: BattleController, ids: Array) -> Hand:
	var h := Hand.new()
	for tid in ids:
		var t: Tile = _draw_from_live(bc, int(tid))
		assert_not_null(t)
		assert_true(h.add(t), "hand 加入 live draw 实体失败 iid=%d" % t.instance_id)
	return h


# ---- decide_riichi 行为 ----

func test_riichi_yes_when_tenpai_and_concealed():
	var ai := HeuristicAi.new(0)
	var seat := _make_seat_with_hand(_chiitoi_tenpai_hand())
	assert_true(ai.decide_riichi(seat, 20), "听牌门清 + wall 充足 → 立直")


func test_riichi_no_when_already_declared():
	var ai := HeuristicAi.new(0)
	var seat := _make_seat_with_hand(_chiitoi_tenpai_hand())
	seat.riichi.declared = true
	assert_false(ai.decide_riichi(seat, 20))


func test_riichi_no_when_wall_too_small():
	var ai := HeuristicAi.new(0)
	var seat := _make_seat_with_hand(_chiitoi_tenpai_hand())
	# 立直 spec：剩余 ≥ 4 张才可立直
	assert_false(ai.decide_riichi(seat, 3))


func test_riichi_no_when_below_min_points():
	var ai := HeuristicAi.new(0)
	var seat := _make_seat_with_hand(_chiitoi_tenpai_hand(), 500)
	assert_false(ai.decide_riichi(seat, 20), "< 1000 点不能立直")


func test_riichi_no_when_not_tenpai():
	var ai := HeuristicAi.new(0)
	# 13 张完全无序
	var seat := _make_seat_with_hand([
		TileId.W1, TileId.W2, TileId.W3, TileId.T1, TileId.T2,
		TileId.T3, TileId.S1, TileId.S2, TileId.S3, TileId.E,
		TileId.S_WIND, TileId.W_WIND, TileId.N,
	])
	assert_false(ai.decide_riichi(seat, 20))


# ---- BattleController 集成：公开 apply_action(Action.RIICHI) ----

func test_battle_controller_emits_riichi_declared_when_tenpai_and_heuristic():
	var bc := BattleController.new(42, 0, true)  # use_heuristic_ai
	assert_not_null(bc.state)
	_prepare_live_fixture(bc)

	# 13 张七対子听 + 1 张 E（立直弃牌目标）——live swap + wall.draw 消费
	var hand_ids: Array = [
		TileId.W1, TileId.W1, TileId.W2, TileId.W2, TileId.W3, TileId.W3,
		TileId.W5, TileId.W5, TileId.W6, TileId.W6, TileId.W7, TileId.W7,
		TileId.W9, TileId.E,
	]
	var seat0: Seat = bc.state.seats[0]
	seat0.hand = _hand_from_live(bc, hand_ids)
	assert_eq(seat0.hand._tiles.size(), 14)

	var e_iid: int = -1
	for t in seat0.hand._tiles:
		assert_true(Tile.is_instance_id_in_hand_seq(t.instance_id, bc.state.hand_seq),
			"hand iid 必须属于 hand_seq")
		# seat0 持有后，其它席 hand/river/meld 不得再持同 iid
		_assert_iid_absent_from_active_zones(bc, int(t.instance_id), 0)
		if t.id == TileId.E:
			e_iid = t.instance_id
	assert_true(e_iid >= 0, "fixture 必须含东风实体")

	bc.state.phase = BattlePhase.Kind.DISCARD
	var ctx: DecisionContext = bc.decision_context_for_seat(0)
	assert_not_null(ctx, "DISCARD 期应有 TURN DecisionContext")
	assert_eq(ctx.window_kind, DecisionContext.KIND_TURN)
	assert_eq(ctx.seat, 0)
	assert_eq(ctx.hand_seq, bc.state.hand_seq)
	assert_true(ctx.has_kind("RIICHI"), "听牌弃 E 后应 offer RIICHI")
	assert_true(ctx.allows("RIICHI", {"tile_instance_id": e_iid}),
		"RIICHI offer 必须覆盖目标 E iid=%d" % e_iid)

	var action: Action = Action.riichi(
		0, e_iid, _ROOM, _CMD_UUID, ctx.decision_id, bc.state.hand_seq, 1
	)
	assert_not_null(action)
	var resp: ActionResolution = bc.apply_action(action, ActionSource.AI)
	assert_not_null(resp)
	assert_true(resp.accepted, "apply_action RIICHI 应 accepted")

	var journal: Array = bc.action_journal()
	assert_eq(journal.size(), 1, "journal 应记录 1 条已接受 Action")
	assert_true(journal[0] is Action)
	var logged: Action = journal[0] as Action
	assert_eq(logged.kind, "RIICHI")
	assert_eq(int(logged.payload.get("tile_instance_id", -2)), e_iid)
	assert_eq(logged.decision_id, ctx.decision_id)
	assert_eq(logged.hand_seq, bc.state.hand_seq)

	var has_riichi := false
	for ev in bc.events:
		if ev.type == &"RIICHI_DECLARED":
			has_riichi = true
			assert_eq(ev.actor_seat, 0)
	assert_true(has_riichi, "立直应 emit RIICHI_DECLARED")
	assert_eq(bc.state.scores[0], 25000 - 1000, "立直扣 1000 点同步到 state.scores")
	assert_eq(bc.state.riichi_sticks, 1, "立直棒 +1")
	assert_true(seat0.riichi.declared)
