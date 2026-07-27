extends GutTest

# Claim window / self-kan / chankan — Action + instance_id 路径（E2-02 第二轮）
# Green：fixture 一律从同一 Wall 的 canonical 136 实体 take/swap，禁止墙外复制/覆盖


func _canonical_tile_id_for_serial(serial: int) -> int:
	@warning_ignore("integer_division")
	return TileId.ALL[serial / 4]


## wall 136 实体 + active zones 与 wall canonical 逐字段一致且 active iid 全局唯一。
## 类型/size 错误安全 return false，避免后续下标噪音。
func _assert_wall_and_active_entities_canonical_unique(bc, tag: String) -> bool:
	if bc == null or bc.state == null:
		assert_true(false, "%s: bc/state 须非 null" % tag)
		return false
	var wall: Wall = bc.state.wall
	if wall == null:
		assert_true(false, "%s: wall 须非 null" % tag)
		return false
	if typeof(wall.authority_tiles()) != TYPE_ARRAY:
		assert_true(false, "%s: wall.authority_tiles() 须为 Array" % tag)
		return false
	if wall.authority_tiles().size() != 136:
		assert_eq(wall.authority_tiles().size(), 136, "%s: wall.authority_tiles() 须恰 136" % tag)
		return false
	var hand_seq: int = bc.state.hand_seq
	var wall_by_iid: Dictionary = {}
	for i in range(wall.authority_tiles().size()):
		var raw = wall.authority_tiles()[i]
		if raw == null or not (raw is Tile):
			assert_true(false, "%s: wall[%d] 须为真实 Tile" % [tag, i])
			return false
		var wt: Tile = raw
		var iid: int = wt.instance_id
		if not Tile.is_instance_id_in_hand_seq(iid, hand_seq):
			assert_true(false,
				"%s: wall[%d] iid=%d 须在 hand_seq=%d namespace" % [tag, i, iid, hand_seq])
			return false
		var serial: int = iid - hand_seq * 136
		if serial < 0 or serial >= 136:
			assert_true(false, "%s: wall[%d] serial=%d 越界" % [tag, i, serial])
			return false
		var expect_id: int = _canonical_tile_id_for_serial(serial)
		var copy: int = serial % 4
		var expect_red: bool = (
			copy == 0
			and (expect_id == TileId.W5 or expect_id == TileId.T5 or expect_id == TileId.S5)
		)
		assert_eq(wt.id, expect_id, "%s: wall serial=%d id" % [tag, serial])
		if wt.id != expect_id:
			return false
		assert_eq(wt.owner_seat, copy, "%s: wall serial=%d owner_seat(=copy)" % [tag, serial])
		if wt.owner_seat != copy:
			return false
		assert_eq(wt.is_red_dora, expect_red, "%s: wall serial=%d red" % [tag, serial])
		if wt.is_red_dora != expect_red:
			return false
		if wall_by_iid.has(iid):
			assert_true(false, "%s: wall iid 重复 %d" % [tag, iid])
			return false
		wall_by_iid[iid] = wt
	assert_eq(wall_by_iid.size(), 136, "%s: wall iid 全局 unique 恰 136" % tag)
	if wall_by_iid.size() != 136:
		return false

	# active：仅四席 hand / 四河 / 四席 meld.tiles（_last_discarded_tile 为河别名不重复计；dora 不入）
	var seen_active: Dictionary = {}
	var locs: Array = []  # [tile, loc_tag]
	if bc.state.seats == null or bc.state.seats.size() != 4:
		assert_true(false, "%s: seats 须恰 4" % tag)
		return false
	for seat_i in range(4):
		var seat: Seat = bc.state.seats[seat_i]
		if seat == null or seat.hand == null or typeof(seat.hand.tiles()) != TYPE_ARRAY:
			assert_true(false, "%s: seat%d hand.tiles() 不可用" % [tag, seat_i])
			return false
		for t in seat.hand.tiles():
			locs.append([t, "hand@%d" % seat_i])
		if typeof(seat.melds.all()) != TYPE_ARRAY:
			assert_true(false, "%s: seat%d melds 须为 Array" % [tag, seat_i])
			return false
		for mi in range(seat.melds.size()):
			var meld = seat.melds.all()[mi]
			if meld == null or typeof(meld.tiles) != TYPE_ARRAY:
				assert_true(false, "%s: seat%d meld[%d].tiles 不可用" % [tag, seat_i, mi])
				return false
			for t in meld.tiles:
				locs.append([t, "meld@%d[%d]" % [seat_i, mi]])
	for seat_i in range(4):
		var river: DiscardRiver = bc.state.seats[seat_i].river
		if river == null:
			assert_true(false, "%s: river seat%d 须存在" % [tag, seat_i])
			return false
		for t in river.tiles():
			locs.append([t, "river@%d" % seat_i])

	for entry in locs:
		var raw = entry[0]
		var loc: String = entry[1]
		if raw == null or not (raw is Tile):
			assert_true(false, "%s: active %s 须为真实 Tile" % [tag, loc])
			return false
		var at: Tile = raw
		var iid: int = at.instance_id
		if not wall_by_iid.has(iid):
			assert_true(false, "%s: active %s iid=%d 不在 wall map" % [tag, loc, iid])
			return false
		var canon: Tile = wall_by_iid[iid]
		assert_eq(at.id, canon.id, "%s: active %s iid=%d id" % [tag, loc, iid])
		if at.id != canon.id:
			return false
		assert_eq(at.is_red_dora, canon.is_red_dora, "%s: active %s iid=%d red" % [tag, loc, iid])
		if at.is_red_dora != canon.is_red_dora:
			return false
		assert_eq(at.owner_seat, canon.owner_seat, "%s: active %s iid=%d owner" % [tag, loc, iid])
		if at.owner_seat != canon.owner_seat:
			return false
		assert_eq(at.instance_id, canon.instance_id, "%s: active %s iid 字段" % [tag, loc])
		if at.instance_id != canon.instance_id:
			return false
		if seen_active.has(iid):
			assert_true(false, "%s: active iid=%d 全局重复于 %s" % [tag, iid, loc])
			return false
		seen_active[iid] = true
	return true


# ── Entity fixture helpers（本文件专用；禁止 Tile.new / 墙覆盖） ──────────

func _sync_dora_from_wall(bc) -> void:
	var wall: Wall = bc.state.wall
	var dora := DoraIndicators.new()
	var ind: Tile = wall.peek_dora_indicator(0)
	var ura: Tile = wall.peek_uradora_indicator(0)
	if ind != null and ura != null:
		assert_true(dora.reveal_pair(ind, ura))
	bc.state.dora_indicators = dora


## 新 BC 后调用：重建 canonical wall + 清空四席/河/events/discard window，保持同一 bc/state/engine。
func _reset_entity_fixture(bc) -> void:
	assert_not_null(bc)
	assert_not_null(bc.state)
	var hs: int = bc.state.hand_seq
	bc.state.wall = Wall.new_full_set(hs)
	assert_not_null(bc.state.wall)
	bc.state.wall.reserve_dead_wall(14)
	for i in range(4):
		var seat: Seat = bc.state.seats[i]
		seat.hand = Hand.new()
		seat.melds.restore([], 0)
		seat.last_drawn_instance_id = Tile.INVALID_INSTANCE_ID
		seat.last_draw_is_rinshan = false
		bc.state.seats[i].river.restore([])
	bc.events.clear()
	bc._last_discarded_tile = null
	bc._last_discarder_seat = -1
	bc._active_window = null
	bc._active_window_phase = -1
	bc._pending_added_kan = {}
	bc._settled = false
	_sync_dora_from_wall(bc)


func _red_filter_matches(t: Tile, red_filter: int) -> bool:
	if red_filter < 0:
		return true
	if red_filter == 0:
		return not t.is_red_dora
	if red_filter == 1:
		return t.is_red_dora
	return false


## 未消费区 [draw_index, size) 找匹配 canonical 实体下标；允许落在 dead wall。
func _find_unconsumed_wall_index(bc, tid: int, red_filter: int = -1) -> int:
	var wall: Wall = bc.state.wall
	for i in range(wall.draw_index(), wall.authority_tiles().size()):
		var t: Tile = wall.authority_tiles()[i]
		if t == null:
			continue
		if int(t.id) != int(tid):
			continue
		if not _red_filter_matches(t, red_filter):
			continue
		return i
	return -1


## 交换两侧 `_tiles[index]=...`（非覆盖外来 tile）。
func _swap_wall_to_draw_index(wall: Wall, target_index: int) -> void:
	assert_true(wall.move_unconsumed_index_to_top(target_index))


## 从 wall 未消费区 take 匹配实体：swap → 真实 draw()；绝 new/clone/remove wall。
func _take_entity_from_wall(bc, tid: int, red_filter: int = -1) -> Tile:
	assert_not_null(bc)
	assert_not_null(bc.state)
	assert_not_null(bc.state.wall)
	var wall: Wall = bc.state.wall
	var idx: int = _find_unconsumed_wall_index(bc, tid, red_filter)
	assert_true(idx >= 0, "wall 未消费区无 id=%d red_filter=%d" % [tid, red_filter])
	if idx < 0:
		return null
	var target: Tile = wall.authority_tiles()[idx]
	_swap_wall_to_draw_index(wall, idx)
	var drawn: Tile = wall.draw()
	assert_not_null(drawn, "wall.draw 须返回实体")
	assert_eq(drawn, target, "draw 须为 swap 后同一 instance")
	assert_eq(drawn.instance_id, target.instance_id)
	assert_true(Tile.is_instance_id_in_hand_seq(drawn.instance_id, bc.state.hand_seq),
		"take iid 须在 hand_seq namespace")
	var serial: int = drawn.instance_id - bc.state.hand_seq * 136
	assert_eq(drawn.id, _canonical_tile_id_for_serial(serial), "take 实体须 canonical id")
	_sync_dora_from_wall(bc)
	return drawn


## 逐项 take 真实实体加入 Hand；失败安全。
func _hand_from_wall(bc, ids: Array) -> Hand:
	var h := Hand.new()
	for tid in ids:
		var t: Tile = _take_entity_from_wall(bc, int(tid))
		assert_not_null(t, "hand_from_wall 取 id=%d 失败" % int(tid))
		if t == null:
			return h
		assert_true(h.add(t), "hand 加入 wall 实体失败 iid=%d" % t.instance_id)
	return h


## 只把未消费目标 swap 到 draw_index；不 draw、不覆盖复制。
func _force_next_draw_from_wall(bc, tid: int, red_filter: int = -1) -> Tile:
	assert_not_null(bc)
	assert_not_null(bc.state)
	assert_not_null(bc.state.wall)
	var wall: Wall = bc.state.wall
	var idx: int = _find_unconsumed_wall_index(bc, tid, red_filter)
	assert_true(idx >= 0, "force next draw：wall 无 id=%d red_filter=%d" % [tid, red_filter])
	if idx < 0:
		return null
	var target: Tile = wall.authority_tiles()[idx]
	_swap_wall_to_draw_index(wall, idx)
	assert_eq(wall.authority_tiles()[wall.draw_index()], target)
	_sync_dora_from_wall(bc)
	return target


func test_ai_ankan_after_draw():
	var bc := BattleController.new(100, 0, true)
	_reset_entity_fixture(bc)
	var seat1: Seat = bc.state.seats[1]
	seat1.hand = _hand_from_wall(bc, [
		TileId.E, TileId.E, TileId.E,
		TileId.W1, TileId.W2, TileId.W3,
		TileId.T1, TileId.T2, TileId.T3,
		TileId.S1, TileId.S2, TileId.S3, TileId.S5,
	])
	assert_eq(seat1.hand.size(), 13)
	var next_draw: Tile = _force_next_draw_from_wall(bc, TileId.E)
	assert_not_null(next_draw)
	bc.state.current_seat = 1
	bc.state.phase = BattlePhase.Kind.DRAW
	bc._step_draw()
	assert_eq(seat1.hand.size(), 14)
	assert_true(
		_assert_wall_and_active_entities_canonical_unique(bc, "test_ai_ankan_after_draw"),
		"test_ai_ankan_after_draw: fixture 实体审计")
	# TURN 选 ANKAN Action
	assert_eq(bc.state.phase, BattlePhase.Kind.DISCARD)
	var ctx: DecisionContext = bc.decision_context_for_seat(1)
	assert_not_null(ctx)
	assert_true(ctx.has_kind("KAN"), "四枚应 offer ANKAN")
	var payload: Dictionary = {}
	for offer in ctx.allowed_actions:
		if str(offer.get("kind", "")) != "KAN":
			continue
		for opt in offer.get("payload_options", []):
			if str(opt.get("kan_kind", "")) == "ANKAN":
				payload = opt
				break
	assert_false(payload.is_empty())
	var act: Action = Action.kan(
		1, payload, "local", "550e8400-e29b-41d4-a716-000000000001",
		ctx.decision_id, 0, 1
	)
	assert_true(bc.apply_action(act, ActionSource.AI).accepted)
	var has_ankan := false
	for m in seat1.melds.all():
		if m.kind == Meld.Kind.ANKAN and m.tiles[0].id == TileId.E:
			has_ankan = true
	assert_true(has_ankan, "AI should declare ankan with 4 copies of E")


func test_no_ankan_during_riichi():
	var bc := BattleController.new(100, 0, true)
	_reset_entity_fixture(bc)
	var seat1: Seat = bc.state.seats[1]
	seat1.hand = _hand_from_wall(bc, [
		TileId.E, TileId.E, TileId.E,
		TileId.W1, TileId.W2, TileId.W3,
		TileId.T1, TileId.T2, TileId.T3,
		TileId.S1, TileId.S2, TileId.S3, TileId.S5,
	])
	assert_eq(seat1.hand.size(), 13)
	seat1.riichi.declare(0, false)
	var next_draw: Tile = _force_next_draw_from_wall(bc, TileId.E)
	assert_not_null(next_draw)
	bc.state.current_seat = 1
	bc.state.phase = BattlePhase.Kind.DRAW
	bc._step_draw()
	assert_eq(seat1.hand.size(), 14)
	assert_true(
		_assert_wall_and_active_entities_canonical_unique(bc, "test_no_ankan_during_riichi"),
		"test_no_ankan_during_riichi: fixture 实体审计")
	var ctx: DecisionContext = bc.decision_context_for_seat(1)
	assert_not_null(ctx)
	assert_false(ctx.has_kind("KAN"), "riichi blocks ankan offer")


func test_ai_pon_during_claim_phase():
	var bc := BattleController.new(100, 0, true)
	_reset_entity_fixture(bc)
	var seat2: Seat = bc.state.seats[2]
	seat2.hand = _hand_from_wall(bc, [
		TileId.W5, TileId.W5,
		TileId.T1, TileId.T2, TileId.T3,
		TileId.S1, TileId.S2, TileId.S3,
		TileId.W1, TileId.W2, TileId.W3,
		TileId.E, TileId.E,
	])
	bc.state.current_seat = 0
	bc.state.phase = BattlePhase.Kind.CLAIM
	var discarded: Tile = _take_entity_from_wall(bc, TileId.W5)
	assert_not_null(discarded)
	bc._last_discarded_tile = discarded
	bc._last_discarder_seat = 0
	bc.state.seats[0].river.restore([discarded])
	bc.events.append(BattleEvent.make(&"TILE_DISCARDED", 0, TileSkillAnchor.make(discarded, 0, null), {}))
	assert_true(
		_assert_wall_and_active_entities_canonical_unique(bc, "test_ai_pon_during_claim_phase"),
		"test_ai_pon_during_claim_phase: fixture 实体审计")
	# 显式提交 intents：seat2 PON，其余 PASS（不依赖 AI 策略）
	for s in [1, 2, 3]:
		var ctx: DecisionContext = bc.decision_context_for_seat(s)
		assert_not_null(ctx)
		var act: Action
		if s == 2 and ctx.has_kind("PON"):
			var pay: Dictionary = {}
			for offer in ctx.allowed_actions:
				if str(offer.get("kind", "")) == "PON":
					pay = (offer.get("payload_options", [{}]) as Array)[0]
			act = Action.pon(2, pay.get("companion_tile_instance_ids", []), "local",
				"550e8400-e29b-41d4-a716-00000000010%d" % s, ctx.decision_id, 0, s)
		else:
			act = Action.make_pass(s, "local",
				"550e8400-e29b-41d4-a716-00000000010%d" % s, ctx.decision_id, 0, s)
		assert_true(bc.apply_action(act, ActionSource.HUMAN).accepted)
	var has_pon := false
	for m in seat2.melds.all():
		if m.kind == Meld.Kind.PON and m.tiles[0].id == TileId.W5:
			has_pon = true
	assert_true(has_pon, "seat 2 should pon W5")
	assert_eq(bc.state.current_seat, 2, "current_seat = claimant")
	assert_eq(bc.state.phase, BattlePhase.Kind.DISCARD, "phase = DISCARD after pon")


func test_no_claims_advances():
	var bc := BattleController.new(100, 0, true)
	_reset_entity_fixture(bc)
	# 从 wall 真实 take canonical HAKU ≥1 放入 seat1（含 dead 交换路径）
	var haku_in_hand: Tile = _take_entity_from_wall(bc, TileId.HAKU)
	assert_not_null(haku_in_hand)
	assert_eq(haku_in_hand.id, TileId.HAKU)
	bc.state.seats[1].hand = Hand.new()
	assert_true(bc.state.seats[1].hand.add(haku_in_hand))
	var removed_count := 0
	for i in range(1, 4):
		var hand: Hand = bc.state.seats[i].hand
		while hand.count_of(TileId.HAKU) > 0:
			var iid: int = Tile.INVALID_INSTANCE_ID
			for t in hand.tiles():
				if t.id == TileId.HAKU:
					iid = t.instance_id
					break
			assert_true(Tile.is_valid_instance_id(iid), "HAKU 实体须有合法 instance_id")
			var found: Tile = hand.find_by_instance_id(iid)
			assert_not_null(found, "find_by_instance_id 须命中精确实体")
			assert_eq(found.instance_id, iid)
			var taken: Tile = hand.take_by_instance_id(iid)
			assert_not_null(taken, "take_by_instance_id 须删除精确实体")
			assert_eq(taken.instance_id, iid)
			removed_count += 1
		assert_eq(hand.count_of(TileId.HAKU), 0)
	assert_gte(removed_count, 1, "seed100 路径至少移除 1 张 HAKU")
	bc.state.current_seat = 0
	bc.state.phase = BattlePhase.Kind.CLAIM
	var discarded: Tile = _take_entity_from_wall(bc, TileId.HAKU)
	assert_not_null(discarded)
	assert_eq(discarded.id, TileId.HAKU)
	bc._last_discarded_tile = discarded
	bc._last_discarder_seat = 0
	bc.state.seats[0].river.restore([discarded])
	bc.events.append(BattleEvent.make(&"TILE_DISCARDED", 0,
		TileSkillAnchor.make(discarded, 0, null), {}))
	assert_true(
		_assert_wall_and_active_entities_canonical_unique(bc, "test_no_claims_advances"),
		"test_no_claims_advances: fixture 实体审计")
	bc._step_claim_collect()
	assert_eq(bc.state.current_seat, 1, "should advance to next seat")
	assert_eq(bc.state.phase, BattlePhase.Kind.DRAW)


func test_tile_claimed_event_emitted():
	var bc := BattleController.new(100, 0, true)
	_reset_entity_fixture(bc)
	var seat2: Seat = bc.state.seats[2]
	seat2.hand = _hand_from_wall(bc, [
		TileId.W5, TileId.W5,
		TileId.T1, TileId.T2, TileId.T3,
		TileId.S1, TileId.S2, TileId.S3,
		TileId.W1, TileId.W2, TileId.W3,
		TileId.E, TileId.E,
	])
	bc.state.current_seat = 0
	bc.state.phase = BattlePhase.Kind.CLAIM
	var discarded: Tile = _take_entity_from_wall(bc, TileId.W5)
	assert_not_null(discarded)
	bc._last_discarded_tile = discarded
	bc._last_discarder_seat = 0
	bc.state.seats[0].river.restore([discarded])
	assert_true(
		_assert_wall_and_active_entities_canonical_unique(bc, "test_tile_claimed_event_emitted"),
		"test_tile_claimed_event_emitted: fixture 实体审计")
	for s in [1, 2, 3]:
		var ctx: DecisionContext = bc.decision_context_for_seat(s)
		assert_not_null(ctx)
		var act: Action
		if s == 2 and ctx.has_kind("PON"):
			var pay: Dictionary = {}
			for offer in ctx.allowed_actions:
				if str(offer.get("kind", "")) == "PON":
					pay = (offer.get("payload_options", [{}]) as Array)[0]
			act = Action.pon(2, pay.get("companion_tile_instance_ids", []), "local",
				"550e8400-e29b-41d4-a716-00000000000%d" % s, ctx.decision_id, 0, s)
		else:
			act = Action.make_pass(s, "local",
				"550e8400-e29b-41d4-a716-00000000000%d" % s, ctx.decision_id, 0, s)
		assert_true(bc.apply_action(act, ActionSource.HUMAN).accepted)
	var found_claim := false
	for ev in bc.events:
		if ev.type == &"TILE_CLAIMED":
			found_claim = true
	assert_true(found_claim, "TILE_CLAIMED event should be emitted")


func test_chankan_ron_on_added_kan():
	var bc := BattleController.new(100, 0, true)
	_reset_entity_fixture(bc)
	bc.state.seats[2].hand = _hand_from_wall(bc, [
		TileId.W4, TileId.W6,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.W1, TileId.W2, TileId.W3,
		TileId.E, TileId.E,
	])
	bc.state.seats[2].furiten = FuritenState.new()
	# seat1：1 张 W5 在 hand + PON 三张 W5，合计四 copy 均自 wall
	bc.state.seats[1].hand = _hand_from_wall(bc, [
		TileId.W5,
		TileId.T1, TileId.T2, TileId.T3,
		TileId.S1, TileId.S2, TileId.S3,
		TileId.W7, TileId.W8, TileId.W9,
		TileId.S5, TileId.S5, TileId.S5,
	])
	var pon_a: Tile = _take_entity_from_wall(bc, TileId.W5)
	var pon_b: Tile = _take_entity_from_wall(bc, TileId.W5)
	var pon_c: Tile = _take_entity_from_wall(bc, TileId.W5)
	assert_not_null(pon_a)
	assert_not_null(pon_b)
	assert_not_null(pon_c)
	var pon_tiles: Array[Tile] = [pon_a, pon_b, pon_c]
	var pon := Meld.make_pon(pon_tiles, 0, 1)
	bc.state.seats[1].melds.restore([pon], 1)
	bc.state.current_seat = 1
	bc.state.phase = BattlePhase.Kind.DISCARD
	bc.state.seats[1].last_drawn_instance_id = bc.state.seats[1].hand.tiles()[0].instance_id
	assert_true(
		_assert_wall_and_active_entities_canonical_unique(bc, "test_chankan_ron_on_added_kan"),
		"test_chankan_ron_on_added_kan: fixture 实体审计")
	var ctx: DecisionContext = bc.decision_context_for_seat(1)
	assert_not_null(ctx)
	assert_true(ctx.has_kind("KAN"))
	var pay: Dictionary = {}
	for offer in ctx.allowed_actions:
		if str(offer.get("kind", "")) != "KAN":
			continue
		for opt in offer.get("payload_options", []):
			if str(opt.get("kan_kind", "")) == "ADDED_KAN":
				pay = opt
	assert_false(pay.is_empty())
	var kan_act := Action.kan(1, pay, "local", "550e8400-e29b-41d4-a716-000000000010",
		ctx.decision_id, 0, 1)
	assert_true(bc.apply_action(kan_act, ActionSource.HUMAN).accepted)
	# ROB_KAN: seat2 RON
	var rctx2: DecisionContext = bc.decision_context_for_seat(2)
	assert_not_null(rctx2)
	assert_true(rctx2.has_kind("RON"), "seat2 should rob kan")
	for s in [0, 2, 3]:
		var rctx: DecisionContext = bc.decision_context_for_seat(s)
		var a: Action
		if s == 2:
			a = Action.ron(2, "local", "550e8400-e29b-41d4-a716-00000000002%d" % s,
				rctx.decision_id, 0, s + 2)
		else:
			a = Action.make_pass(s, "local", "550e8400-e29b-41d4-a716-00000000002%d" % s,
				rctx.decision_id, 0, s + 2)
		assert_true(bc.apply_action(a, ActionSource.HUMAN).accepted)
	var won := false
	for ev in bc.events:
		if ev.type == &"WIN_DECLARED":
			won = true
			assert_true(bool(ev.extra.get("is_chankan", false)))
	assert_true(won, "seat 2 should ron via chankan")
	assert_eq((bc.state.seats[1].melds.all()[0] as Meld).kind, Meld.Kind.PON,
		"chankan never upgrades")


func test_chankan_blocked_by_furiten():
	var bc := BattleController.new(100, 0, true)
	_reset_entity_fixture(bc)
	bc.state.seats[2].hand = _hand_from_wall(bc, [
		TileId.W4, TileId.W6,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.W1, TileId.W2, TileId.W3,
		TileId.E, TileId.E,
	])
	bc.state.seats[2].furiten = FuritenState.new()
	bc.state.seats[2].furiten.temporary = true
	bc.state.seats[1].hand = _hand_from_wall(bc, [
		TileId.W5,
		TileId.T1, TileId.T2, TileId.T3,
		TileId.S1, TileId.S2, TileId.S3,
		TileId.W7, TileId.W8, TileId.W9,
		TileId.S5, TileId.S5, TileId.S5,
	])
	var pon_a: Tile = _take_entity_from_wall(bc, TileId.W5)
	var pon_b: Tile = _take_entity_from_wall(bc, TileId.W5)
	var pon_c: Tile = _take_entity_from_wall(bc, TileId.W5)
	assert_not_null(pon_a)
	assert_not_null(pon_b)
	assert_not_null(pon_c)
	var pon_tiles: Array[Tile] = [pon_a, pon_b, pon_c]
	bc.state.seats[1].melds.restore([Meld.make_pon(pon_tiles, 0, 1)], 1)
	bc.state.current_seat = 1
	bc.state.phase = BattlePhase.Kind.DISCARD
	bc.state.seats[1].last_drawn_instance_id = bc.state.seats[1].hand.tiles()[0].instance_id
	assert_true(
		_assert_wall_and_active_entities_canonical_unique(bc, "test_chankan_blocked_by_furiten"),
		"test_chankan_blocked_by_furiten: fixture 实体审计")
	var ctx: DecisionContext = bc.decision_context_for_seat(1)
	var pay: Dictionary = {}
	for offer in ctx.allowed_actions:
		if str(offer.get("kind", "")) != "KAN":
			continue
		for opt in offer.get("payload_options", []):
			if str(opt.get("kan_kind", "")) == "ADDED_KAN":
				pay = opt
	assert_true(bc.apply_action(Action.kan(1, pay, "local",
		"550e8400-e29b-41d4-a716-000000000030", ctx.decision_id, 0, 1), ActionSource.HUMAN).accepted)
	var rctx2: DecisionContext = bc.decision_context_for_seat(2)
	assert_not_null(rctx2)
	assert_false(rctx2.has_kind("RON"), "furiten blocks rob kan RON offer")
