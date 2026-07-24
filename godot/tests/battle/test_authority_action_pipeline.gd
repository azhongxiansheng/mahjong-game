extends GutTest
## E2-02 / #232 第二轮：权威 Action 管线真实领域 Red → Green。
## 禁止源码字符串扫描、恒真断言、mock 顶替核心规则。

const ROOM := "local"
const IAUTH_PATH := "res://battle/i_authoritative_battle_controller.gd"
const BC_PATH := "res://battle/battle_controller.gd"
const RESOLVER_PATH := "res://battle/battle_action_resolver.gd"
const TILES_PER_HAND := 136
const UUID := "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
const UUID2 := "11111111-2222-4333-8444-555555555555"
const CMD_PREFIX := "550e8400-e29b-41d4-a716-"

const FACADE_METHODS := [
	"run_to_end", "apply_action", "decision_context_for_seat",
	"action_journal", "load_replay_journal", "replay_status",
]
const FORBIDDEN_PUBLIC := ["apply_ron"]


func _ns(hs: int, serial: int) -> int:
	return hs * TILES_PER_HAND + serial


func _script_method_names(path: String) -> Array:
	var scr: GDScript = load(path) as GDScript
	if scr == null:
		return []
	var names: Array = []
	for m in scr.get_script_method_list():
		names.append(str(m.get("name", "")))
	return names


func _count_name(names: Array, want: String) -> int:
	var n := 0
	for x in names:
		if str(x) == want:
			n += 1
	return n


func _cmd(n: int) -> String:
	return "%s%012d" % [CMD_PREFIX, n]


func _act(
	kind: String, seat: int, hs: int, did: String, payload: Dictionary, seq: int = 1
) -> Action:
	return Action.from_dict({
		"protocol_version": 1,
		"command_id": _cmd(seq),
		"room_id": ROOM,
		"seat": seat,
		"hand_seq": hs,
		"decision_id": did,
		"kind": kind,
		"payload": payload.duplicate(true),
		"client_seq": seq,
	})


func _make_bc(p_seed: int = 42, dealer: int = 0, hand_seq: int = 0) -> BattleController:
	return BattleController.new(p_seed, dealer, false, TileId.E, hand_seq)


# 本文件 fixture 一律从同一 Wall 的 canonical 136 实体取牌，禁止手写墙外/重复 iid。
var _used_wall_iids: Dictionary = {}


func _reset_wall_usage() -> void:
	_used_wall_iids.clear()


func _take_wall_tile(bc: BattleController, tid: int) -> Tile:
	assert_not_null(bc)
	assert_not_null(bc.state)
	assert_not_null(bc.state.wall)
	for t in bc.state.wall._tiles:
		if t == null or int(t.id) != int(tid):
			continue
		var iid: int = int(t.instance_id)
		if _used_wall_iids.has(iid):
			continue
		_used_wall_iids[iid] = true
		assert_true(Tile.is_instance_id_in_hand_seq(iid, bc.state.hand_seq),
			"wall tile 必须在本局 hand_seq 命名空间 iid=%d" % iid)
		return t
	assert_true(false, "Wall 中无剩余 id=%d 的 canonical 实体" % tid)
	return null


func _hand_from_wall(bc: BattleController, ids: Array) -> Hand:
	var h := Hand.new()
	for tid in ids:
		var t: Tile = _take_wall_tile(bc, int(tid))
		assert_not_null(t)
		assert_true(h.add(t), "hand 加入 wall 实体失败 iid=%d" % t.instance_id)
	return h


func _hand_from_ids(ids: Array, hand_seq: int, start_serial: int = 0) -> Hand:
	# 兼容旧调用点：无 bc 时退化为命名空间 serial（仅非领域污染单测）。
	# 领域 fixture 请用 _hand_from_wall。
	var h := Hand.new()
	var serial := start_serial
	for tid in ids:
		h.add(Tile.new(int(tid), false, Tile.NO_OWNER, _ns(hand_seq, serial)))
		serial += 1
	return h


func _tile(tid: int, hand_seq: int, serial: int) -> Tile:
	return Tile.new(tid, false, Tile.NO_OWNER, _ns(hand_seq, serial))


func _domain_snap(bc: BattleController, focus: int = -1) -> Dictionary:
	var seats_melds: Array = []
	var seats_hand_iids: Array = []
	for s in range(4):
		var mids: Array = []
		for m in bc.state.seats[s].melds:
			mids.append({
				"meld_id": (m as Meld).meld_id,
				"kind": int((m as Meld).kind),
				"size": (m as Meld).tiles.size(),
			})
		seats_melds.append(mids)
		var iids: Array = []
		for t in bc.state.seats[s].hand._tiles:
			iids.append(int(t.instance_id))
		seats_hand_iids.append(iids)
	return {
		"phase": int(bc.state.phase),
		"current_seat": int(bc.state.current_seat),
		"dora_n": bc.state.dora_indicators.visible.size(),
		"live_wall": bc.state.wall.live_wall_size(),
		"rinshan": bool(bc.state.seats[focus if focus >= 0 else 0].last_draw_is_rinshan) if focus >= 0 else false,
		"pending_empty": bc._pending_added_kan.is_empty(),
		"journal": bc.action_journal().size(),
		"events_n": bc.events.size(),
		"settled": bc._settled,
		"melds": seats_melds,
		"hands": seats_hand_iids,
		"applied": _count_events(bc.events, "ACTION_APPLIED"),
	}


func _offer_kinds(ctx: DecisionContext) -> Array:
	assert_not_null(ctx)
	if ctx == null:
		return []
	var out: Array = ctx.allowed_kinds.duplicate()
	out.sort()
	return out


func _has_offer_kind(ctx: DecisionContext, kind: String) -> bool:
	return ctx != null and ctx.has_kind(kind)


func _count_events(events: Array, type_name: String) -> int:
	var n := 0
	for ev in events:
		if ev is BattleEvent and str((ev as BattleEvent).type) == type_name:
			n += 1
	return n


func _enter_turn(bc: BattleController) -> void:
	assert_eq(bc.state.phase, BattlePhase.Kind.DRAW)
	var drawn: Tile = bc.engine.draw_for_current()
	assert_not_null(drawn)
	assert_eq(bc.state.phase, BattlePhase.Kind.DISCARD)


func test_pon_offer_enumerates_all_physical_companion_pairs() -> void:
	var bc := _make_bc(23212, 0, 0)
	_reset_wall_usage()
	var red_five: Tile = null
	var black_fives: Array[Tile] = []
	for tile in bc.state.wall._tiles:
		if tile.id != TileId.W5:
			continue
		if tile.is_red_dora:
			red_five = tile
		else:
			black_fives.append(tile)
	assert_not_null(red_five)
	assert_eq(black_fives.size(), 3)
	var discarded: Tile = black_fives[0]
	for used in [red_five, black_fives[0], black_fives[1], black_fives[2]]:
		_used_wall_iids[used.instance_id] = true

	var claimant_hand: Hand = _hand_from_wall(bc, [
		TileId.W1, TileId.W2, TileId.W3, TileId.W4, TileId.W6,
		TileId.W7, TileId.W8, TileId.W9, TileId.T1, TileId.T2,
	])
	assert_true(claimant_hand.add(red_five))
	assert_true(claimant_hand.add(black_fives[1]))
	assert_true(claimant_hand.add(black_fives[2]))
	bc.state.seats[2].hand = claimant_hand
	bc.state.current_seat = 0
	bc.state.phase = BattlePhase.Kind.CLAIM
	bc.state.discards_per_seat[0] = [discarded]
	bc._last_discarded_tile = discarded
	bc._last_discarder_seat = 0

	var offers: Array = bc._build_claim_offers(2, discarded, 0)
	var pon_options: Array = []
	for offer in offers:
		if str(offer.get("kind", "")) == "PON":
			pon_options = offer.get("payload_options", [])
			break
	var expected: Array = [
		{"companion_tile_instance_ids": [
			red_five.instance_id, black_fives[1].instance_id]},
		{"companion_tile_instance_ids": [
			red_five.instance_id, black_fives[2].instance_id]},
		{"companion_tile_instance_ids": [
			black_fives[1].instance_id, black_fives[2].instance_id]},
	]
	assert_eq(pon_options, expected,
		"三张同牌须冻结全部三种二选二实体组合，允许选择保留或使用赤五")


func test_chi_offer_enumerates_red_and_black_physical_choices() -> void:
	var bc := _make_bc(23213, 0, 0)
	_reset_wall_usage()
	var red_five: Tile = null
	var black_five: Tile = null
	for tile in bc.state.wall._tiles:
		if tile.id != TileId.W5:
			continue
		if tile.is_red_dora:
			red_five = tile
		elif black_five == null:
			black_five = tile
	assert_not_null(red_five)
	assert_not_null(black_five)
	_used_wall_iids[red_five.instance_id] = true
	_used_wall_iids[black_five.instance_id] = true
	var discarded: Tile = _take_wall_tile(bc, TileId.W4)
	var claimant_hand: Hand = _hand_from_wall(bc, [
		TileId.W6,
		TileId.T1, TileId.T2, TileId.T3, TileId.T4, TileId.T5,
		TileId.T6, TileId.T7, TileId.T8, TileId.T9,
		TileId.E,
	])
	assert_true(claimant_hand.add(red_five))
	assert_true(claimant_hand.add(black_five))
	bc.state.seats[1].hand = claimant_hand
	bc.state.current_seat = 0
	bc.state.phase = BattlePhase.Kind.CLAIM
	bc.state.discards_per_seat[0] = [discarded]
	bc._last_discarded_tile = discarded
	bc._last_discarder_seat = 0
	var w6: Tile = claimant_hand._tiles[0]
	assert_eq(w6.id, TileId.W6)

	var offers: Array = bc._build_claim_offers(1, discarded, 0)
	var chi_options: Array = []
	for offer in offers:
		if str(offer.get("kind", "")) == "CHI":
			chi_options = offer.get("payload_options", [])
			break
	var physical_pairs: Array = []
	for option in chi_options:
		var pair: Array = option.get("companion_tile_instance_ids", []).duplicate()
		pair.sort()
		physical_pairs.append(pair)
	var red_pair: Array = [red_five.instance_id, w6.instance_id]
	var black_pair: Array = [black_five.instance_id, w6.instance_id]
	red_pair.sort()
	black_pair.sort()
	assert_eq(physical_pairs.size(), 2,
		"同一吃牌牌型中的赤五与黑五须分别成为可提交的物理组合")
	assert_true(physical_pairs.has(red_pair))
	assert_true(physical_pairs.has(black_pair))


# ── A) IAuthoritative facade ──────────────────────────────────────────────

func test_iauth_facade_complete_and_apply_ron_absent() -> void:
	var iauth_names: Array = _script_method_names(IAUTH_PATH)
	for m in FACADE_METHODS:
		assert_eq(_count_name(iauth_names, m), 1, "IAuth 公开 %s 恰好 1 次" % m)
	assert_eq(_count_name(iauth_names, "apply_ron"), 0, "IAuth 不得有公开 apply_ron")

	var bc_names: Array = _script_method_names(BC_PATH)
	# Godot get_script_method_list 含继承链：公开 apply_action 恰好 1 份（IAuth facade），
	# 不得因 BC 再声明而出现 2 份。
	assert_eq(_count_name(bc_names, "apply_action"), 1,
		"继承链上公开 apply_action 恰好 1 份（IAuth facade，BC 不重复声明）")
	assert_eq(_count_name(bc_names, "apply_ron"), 0, "BattleController 不得有公开 apply_ron")
	assert_gte(_count_name(bc_names, "_impl_apply_action"), 1, "BC 应覆写 protected impl")

	var bc := _make_bc()
	assert_not_null(bc)
	assert_true(bc.has_method("apply_action"))
	assert_true(bc.has_method("run_to_end"))
	assert_true(bc.has_method("decision_context_for_seat"))
	assert_true(bc.has_method("action_journal"))
	assert_true(bc.has_method("load_replay_journal"))
	assert_true(bc.has_method("replay_status"))
	assert_false(bc.has_method("apply_ron"), "实例也不得暴露 apply_ron")


# ── B) DecisionContext / Window hand_seq 命名空间 ─────────────────────────

func test_decision_context_window_reject_stale_hand_seq_iids() -> void:
	var hs := 1
	var good := _ns(hs, 10)
	var prev_stale := _ns(hs - 1, 10)
	var next_stale := _ns(hs + 1, 10)
	var turn_ok := [{"kind": "DISCARD", "payload_options": [{"tile_instance_id": good}]}]
	var ctx_ok: DecisionContext = DecisionContext.make(
		"TURN", hs, UUID, 0, turn_ok, -1, -1)
	assert_not_null(ctx_ok, "本局命名空间 iid 合法")

	var turn_prev := [{"kind": "DISCARD", "payload_options": [{"tile_instance_id": prev_stale}]}]
	assert_null(DecisionContext.make("TURN", hs, UUID, 0, turn_prev, -1, -1),
		"上一局 stale discard iid 拒")
	var turn_next := [{"kind": "DISCARD", "payload_options": [{"tile_instance_id": next_stale}]}]
	assert_null(DecisionContext.make("TURN", hs, UUID, 0, turn_next, -1, -1),
		"下一局 stale discard iid 拒")

	var claim_ok := [
		{"kind": "CHI", "payload_options": [{"companion_tile_instance_ids": [
			_ns(hs, 20), _ns(hs, 21)]}]},
		{"kind": "PASS", "payload_options": [{}]},
	]
	assert_not_null(DecisionContext.make(
		"CLAIM", hs, UUID, 1, claim_ok, good, 0), "CLAIM 本局 claimed 合法")
	assert_null(DecisionContext.make(
		"CLAIM", hs, UUID, 1, claim_ok, prev_stale, 0), "CLAIM 上一局 claimed 拒")
	assert_null(DecisionContext.make(
		"CLAIM", hs, UUID, 1, claim_ok, next_stale, 0), "CLAIM 下一局 claimed 拒")

	assert_not_null(DecisionWindow.make("TURN", hs, UUID, 0, -1, -1), "TURN subject=-1 合法")
	assert_not_null(DecisionWindow.make("TURN", hs, UUID, 0, good, -1), "TURN subject 本局合法")
	assert_null(DecisionWindow.make("TURN", hs, UUID, 0, prev_stale, -1), "TURN subject stale 拒")
	assert_null(DecisionWindow.make("CLAIM", hs, UUID, 0, -1, 0), "CLAIM subject 不可 -1")
	assert_null(DecisionWindow.make("ROB_KAN", hs, UUID, 1, -1, 1), "ROB_KAN subject 不可 -1")
	assert_not_null(DecisionWindow.make("CLAIM", hs, UUID, 0, good, 0), "CLAIM subject 本局合法")
	assert_null(DecisionWindow.make("CLAIM", hs, UUID, 0, next_stale, 0), "CLAIM subject stale 拒")


# ── C) TURN offers 真实领域 ───────────────────────────────────────────────

func test_turn_offers_include_tsumo_when_winning() -> void:
	var hs := 0
	var bc := _make_bc(7, 0, hs)
	# 天和型：庄家 14 张完整和牌（含刚摸），_check_tsumo 路径
	bc.state.current_seat = 0
	bc.state.phase = BattlePhase.Kind.DISCARD
	var seat: Seat = bc.state.seats[0]
	var ids := [
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.T1, TileId.T1,
	]
	seat.hand = _hand_from_ids(ids, hs, 0)
	var last: Tile = seat.hand._tiles[seat.hand._tiles.size() - 1]
	seat.last_drawn_instance_id = last.instance_id
	var win: Dictionary = bc._check_tsumo(last)
	assert_true(bool(win.get("is_winning", false)), "fixture 必须真实可自摸")
	var ctx: DecisionContext = bc.decision_context_for_seat(0)
	assert_not_null(ctx)
	assert_true(_has_offer_kind(ctx, "TSUMO"), "可和时必须 offer TSUMO")
	assert_true(_has_offer_kind(ctx, "DISCARD"), "仍须 DISCARD")


func test_turn_offers_include_ankan_when_four_in_hand() -> void:
	var hs := 0
	var bc := _make_bc(8, 0, hs)
	bc.state.current_seat = 1
	bc.state.phase = BattlePhase.Kind.DISCARD
	var seat: Seat = bc.state.seats[1]
	var ids := [
		TileId.E, TileId.E, TileId.E, TileId.E,
		TileId.W1, TileId.W2, TileId.W3,
		TileId.T1, TileId.T2, TileId.T3,
		TileId.S1, TileId.S2, TileId.S3, TileId.S5,
	]
	seat.hand = _hand_from_ids(ids, hs, 0)
	seat.last_drawn_instance_id = seat.hand._tiles[0].instance_id
	var ctx: DecisionContext = bc.decision_context_for_seat(1)
	assert_not_null(ctx)
	assert_true(_has_offer_kind(ctx, "KAN"), "四枚必须 offer KAN")
	var found_ankan := false
	for offer in ctx.allowed_actions:
		if str(offer.get("kind", "")) != "KAN":
			continue
		for opt in offer.get("payload_options", []):
			if str(opt.get("kan_kind", "")) == "ANKAN":
				found_ankan = true
				var iids: Array = opt.get("tile_instance_ids", [])
				assert_eq(iids.size(), 4)
				for iid in iids:
					assert_true(iid >= _ns(hs, 0) and iid <= _ns(hs, 135))
	assert_true(found_ankan, "必须含 ANKAN payload")


func test_turn_offers_include_added_kan_when_pon_plus_fourth() -> void:
	var hs := 0
	var bc := _make_bc(9, 0, hs)
	bc.state.current_seat = 2
	bc.state.phase = BattlePhase.Kind.DISCARD
	var seat: Seat = bc.state.seats[2]
	var ids := [
		TileId.W5,
		TileId.T1, TileId.T2, TileId.T3,
		TileId.S1, TileId.S2, TileId.S3,
		TileId.W7, TileId.W8, TileId.W9,
		TileId.S5, TileId.S6, TileId.S7, TileId.E,
	]
	seat.hand = _hand_from_ids(ids, hs, 10)
	var added: Tile = seat.hand._tiles[0]
	seat.last_drawn_instance_id = added.instance_id
	var pon_tiles: Array[Tile] = [
		_tile(TileId.W5, hs, 1), _tile(TileId.W5, hs, 2), _tile(TileId.W5, hs, 3),
	]
	var pon: Meld = Meld.make_pon(pon_tiles, 0, _ns(hs, 1))
	assert_not_null(pon)
	seat.melds = [pon]
	assert_true(ClaimValidator.can_added_kan(seat.melds, seat.hand, TileId.W5))
	var ctx: DecisionContext = bc.decision_context_for_seat(2)
	assert_not_null(ctx)
	assert_true(_has_offer_kind(ctx, "KAN"), "加杠条件必须 offer KAN")
	var found := false
	for offer in ctx.allowed_actions:
		if str(offer.get("kind", "")) != "KAN":
			continue
		for opt in offer.get("payload_options", []):
			if str(opt.get("kan_kind", "")) != "ADDED_KAN":
				continue
			found = true
			assert_eq(int(opt.get("meld_id", -1)), pon.meld_id)
			assert_eq(int(opt.get("added_tile_instance_id", -1)), added.instance_id)
	assert_true(found, "必须含 ADDED_KAN payload")


func test_turn_offers_declare_abortive_draw_on_kyuusyu() -> void:
	var hs := 0
	var bc := _make_bc(11, 0, hs)
	bc.state.current_seat = 0
	bc.state.phase = BattlePhase.Kind.DISCARD
	bc.state.first_round_active = true
	bc.state.turn_count = 0
	var seat: Seat = bc.state.seats[0]
	# 9 种幺九 + 填充（14 张）
	var ids := [
		TileId.W1, TileId.W9, TileId.T1, TileId.T9, TileId.S1, TileId.S9,
		TileId.E, TileId.S_WIND, TileId.W_WIND, TileId.N,
		TileId.W2, TileId.W3, TileId.T2, TileId.T3,
	]
	seat.hand = _hand_from_ids(ids, hs, 0)
	seat.last_drawn_instance_id = seat.hand._tiles[0].instance_id
	assert_true(AbortiveDraw.is_kyuusyu_kyuuhai(seat.hand.to_id_array()),
		"fixture 必须真实九种九牌")
	var ctx: DecisionContext = bc.decision_context_for_seat(0)
	assert_not_null(ctx)
	assert_true(_has_offer_kind(ctx, "DECLARE_ABORTIVE_DRAW"),
		"首巡九种九牌必须 offer DECLARE_ABORTIVE_DRAW")


# ── D) ADDED_KAN 两阶段 + 抢杠 ────────────────────────────────────────────

func _setup_added_kan_ready(bc: BattleController, actor: int = 1) -> Dictionary:
	var hs: int = bc.state.hand_seq
	bc.state.current_seat = actor
	bc.state.phase = BattlePhase.Kind.DISCARD
	var seat: Seat = bc.state.seats[actor]
	var ids := [
		TileId.W5,
		TileId.T1, TileId.T2, TileId.T3,
		TileId.S1, TileId.S2, TileId.S3,
		TileId.W7, TileId.W8, TileId.W9,
		TileId.S5, TileId.S6, TileId.S7, TileId.E,
	]
	seat.hand = _hand_from_ids(ids, hs, 20)
	var added: Tile = seat.hand.find_by_instance_id(seat.hand._tiles[0].instance_id)
	seat.last_drawn_instance_id = added.instance_id
	var pon: Meld = Meld.make_pon([
		_tile(TileId.W5, hs, 1), _tile(TileId.W5, hs, 2), _tile(TileId.W5, hs, 3),
	], 0, _ns(hs, 1))
	seat.melds = [pon]
	return {
		"actor": actor, "added": added, "meld_id": pon.meld_id, "hs": hs,
	}


func test_added_kan_accepted_opens_rob_kan_without_domain_upgrade() -> void:
	var bc := _make_bc(21, 0, 0)
	var fx: Dictionary = _setup_added_kan_ready(bc, 1)
	var ctx: DecisionContext = bc.decision_context_for_seat(1)
	assert_not_null(ctx)
	var act: Action = _act("KAN", 1, fx["hs"], ctx.decision_id, {
		"kan_kind": "ADDED_KAN",
		"meld_id": fx["meld_id"],
		"added_tile_instance_id": (fx["added"] as Tile).instance_id,
	}, 1)
	var dora_before: int = bc.state.dora_indicators.visible.size()
	var meld_kind_before: int = (bc.state.seats[1].melds[0] as Meld).kind
	var hand_size_before: int = bc.state.seats[1].hand.size()
	var wall_before: int = bc.state.wall.live_wall_size()
	var resp: ActionResolution = bc.apply_action(act, ActionSource.HUMAN)
	assert_true(resp.accepted, "ADDED_KAN 应 accepted")
	assert_eq(_count_events(resp.events, "ACTION_APPLIED"), 1)
	assert_eq(bc.action_journal().size(), 1)
	# domain 零升级
	assert_eq((bc.state.seats[1].melds[0] as Meld).kind, meld_kind_before, "仍为 PON")
	assert_eq((bc.state.seats[1].melds[0] as Meld).kind, Meld.Kind.PON)
	assert_eq(bc.state.seats[1].hand.size(), hand_size_before, "加杠牌仍在手")
	assert_not_null(bc.state.seats[1].hand.find_by_instance_id((fx["added"] as Tile).instance_id))
	assert_eq(bc.state.dora_indicators.visible.size(), dora_before, "不翻 dora")
	assert_eq(bc.state.wall.live_wall_size(), wall_before, "不摸岭上")
	# ROB_KAN 窗
	var rob0: DecisionContext = bc.decision_context_for_seat(0)
	var rob2: DecisionContext = bc.decision_context_for_seat(2)
	var rob3: DecisionContext = bc.decision_context_for_seat(3)
	assert_not_null(rob0)
	assert_not_null(rob2)
	assert_not_null(rob3)
	assert_eq(rob0.window_kind, "ROB_KAN")
	assert_true(rob0.has_kind("PASS"), "ROB_KAN 至少 PASS")
	assert_false(rob0.has_kind("CHI"))
	assert_false(rob0.has_kind("PON"))
	assert_false(rob0.has_kind("KAN"))


func test_added_kan_all_pass_then_upgrades_domain() -> void:
	var bc := _make_bc(22, 0, 0)
	var fx: Dictionary = _setup_added_kan_ready(bc, 1)
	# 清空对家听牌，确保只能 PASS
	for s in [0, 2, 3]:
		bc.state.seats[s].hand = _hand_from_ids([
			TileId.W2, TileId.W3, TileId.W4, TileId.T2, TileId.T3, TileId.T4,
			TileId.S2, TileId.S3, TileId.S4, TileId.E, TileId.E, TileId.S_WIND, TileId.W_WIND,
		], 0, 40 + s * 13)
	var ctx: DecisionContext = bc.decision_context_for_seat(1)
	var act: Action = _act("KAN", 1, 0, ctx.decision_id, {
		"kan_kind": "ADDED_KAN",
		"meld_id": fx["meld_id"],
		"added_tile_instance_id": (fx["added"] as Tile).instance_id,
	}, 1)
	assert_true(bc.apply_action(act, ActionSource.HUMAN).accepted)
	var dora_before: int = bc.state.dora_indicators.visible.size()
	var seq := 2
	for seat_id in [0, 2, 3]:
		var rctx: DecisionContext = bc.decision_context_for_seat(seat_id)
		assert_not_null(rctx)
		var pass_act: Action = _act("PASS", seat_id, 0, rctx.decision_id, {}, seq)
		seq += 1
		var r: ActionResolution = bc.apply_action(pass_act, ActionSource.HUMAN)
		assert_true(r.accepted, "PASS seat %d" % seat_id)
	# 全 PASS 后升级
	assert_eq((bc.state.seats[1].melds[0] as Meld).kind, Meld.Kind.ADDED_KAN,
		"全 PASS 后才 promote 加杠")
	assert_null(bc.state.seats[1].hand.find_by_instance_id((fx["added"] as Tile).instance_id),
		"加杠牌离手")
	assert_gt(bc.state.dora_indicators.visible.size(), dora_before - 1)
	# 至少 dora 翻了或岭上摸了（实现可先翻 dora 再摸）
	assert_true(
		bc.state.dora_indicators.visible.size() >= dora_before
		or bc.state.seats[1].last_draw_is_rinshan,
		"全 PASS 后应翻 dora 或摸岭上"
	)


func test_chankan_ron_never_upgrades_added_kan() -> void:
	var bc := _make_bc(23, 0, 0)
	var fx: Dictionary = _setup_added_kan_ready(bc, 1)
	# seat 2 听 W5 单骑（断幺九役）
	bc.state.seats[2].hand = _hand_from_ids([
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.W6, TileId.W7, TileId.W8,
		TileId.W5,
	], 0, 70)
	bc.state.seats[2].furiten = FuritenState.new()
	# 其他对家无听
	for s in [0, 3]:
		bc.state.seats[s].hand = _hand_from_ids([
			TileId.W1, TileId.W1, TileId.W9, TileId.T1, TileId.T1, TileId.T9,
			TileId.S1, TileId.S1, TileId.S9, TileId.E, TileId.E, TileId.S_WIND, TileId.W_WIND,
		], 0, 90 + s * 13)
	var ron_tile: Tile = fx["added"] as Tile
	var can: bool = ClaimValidator.can_ron(
		bc.state.seats[2].hand, bc.state.seats[2].melds, ron_tile, bc.state.seats[2].furiten)
	assert_true(can, "seat2 必须真实可抢杠")
	var ctx: DecisionContext = bc.decision_context_for_seat(1)
	var act: Action = _act("KAN", 1, 0, ctx.decision_id, {
		"kan_kind": "ADDED_KAN",
		"meld_id": fx["meld_id"],
		"added_tile_instance_id": ron_tile.instance_id,
	}, 1)
	assert_true(bc.apply_action(act, ActionSource.HUMAN).accepted)
	assert_eq((bc.state.seats[1].melds[0] as Meld).kind, Meld.Kind.PON, "抢杠前不升级")
	# seat2 RON，其余 PASS
	var seq := 2
	for seat_id in [0, 2, 3]:
		var rctx: DecisionContext = bc.decision_context_for_seat(seat_id)
		assert_not_null(rctx)
		var a: Action
		if seat_id == 2:
			assert_true(rctx.has_kind("RON"), "听牌座必须 offer RON")
			a = _act("RON", 2, 0, rctx.decision_id, {}, seq)
		else:
			a = _act("PASS", seat_id, 0, rctx.decision_id, {}, seq)
		seq += 1
		assert_true(bc.apply_action(a, ActionSource.HUMAN).accepted)
	assert_eq((bc.state.seats[1].melds[0] as Meld).kind, Meld.Kind.PON,
		"抢杠成立后永不升级")
	assert_not_null(bc.state.seats[1].hand.find_by_instance_id(ron_tile.instance_id),
		"抢杠后加杠牌仍在杠家手（未 upgrade）或已结算；meld 不得变 KAN")
	var won := false
	for ev in bc.events:
		if ev is BattleEvent and str((ev as BattleEvent).type) == "WIN_DECLARED":
			won = true
			assert_true(bool((ev as BattleEvent).extra.get("is_chankan", false)),
				"WIN 必须 is_chankan")
	assert_true(won, "抢杠必须 WIN_DECLARED")


# ── E) BattleActionResolver 头跳 / sancha ─────────────────────────────────

func test_resolver_exists_and_is_pure() -> void:
	var scr: GDScript = load(RESOLVER_PATH) as GDScript
	assert_not_null(scr, "必须存在 BattleActionResolver")
	if scr == null:
		return
	assert_true(scr.can_instantiate())


func test_two_ron_head_jump_by_clockwise_distance_not_seat_number() -> void:
	# discarder=3：seat0 距离 1，seat2 距离 3 → seat0 胜（若按 seat 数字 seat0 也会赢，
	# 但这里同时断言 seat2 在 seat 序更小？seat0 < seat2 会混淆。
	# 关键：再造 discarder=1 时 seat2 距1、seat0 距3 → seat2 胜（seat 数字更大）。
	var scr: GDScript = load(RESOLVER_PATH) as GDScript
	assert_not_null(scr)
	if scr == null:
		return
	var intents_a: Array = [
		_act("RON", 0, 0, UUID, {}, 1),
		_act("RON", 2, 0, UUID, {}, 2),
		_act("PASS", 1, 0, UUID, {}, 3),
	]
	var out_a: Dictionary = scr.call("resolve", intents_a, 3)
	assert_eq(str(out_a.get("outcome", "")), "WINNER")
	var w_a: Action = out_a.get("winner", null) as Action
	assert_not_null(w_a)
	assert_eq(w_a.seat, 0, "discarder=3 时 seat0(距1) 胜 seat2(距3)")

	var intents_b: Array = [
		_act("RON", 0, 0, UUID, {}, 1),
		_act("RON", 2, 0, UUID, {}, 2),
		_act("PASS", 3, 0, UUID, {}, 3),
	]
	var out_b: Dictionary = scr.call("resolve", intents_b, 1)
	assert_eq(str(out_b.get("outcome", "")), "WINNER")
	var w_b: Action = out_b.get("winner", null) as Action
	assert_not_null(w_b)
	assert_eq(w_b.seat, 2, "discarder=1 时 seat2(距1) 胜 seat0(距3)，证明非 seat 数字排序")


func test_three_ron_intents_sancha_but_pass_blocks() -> void:
	var scr: GDScript = load(RESOLVER_PATH) as GDScript
	assert_not_null(scr)
	if scr == null:
		return
	var three_ron: Array = [
		_act("RON", 1, 0, UUID, {}, 1),
		_act("RON", 2, 0, UUID, {}, 2),
		_act("RON", 3, 0, UUID, {}, 3),
	]
	var out3: Dictionary = scr.call("resolve", three_ron, 0)
	assert_eq(str(out3.get("outcome", "")), "SANCHA_HOURA")

	var two_ron_one_pass: Array = [
		_act("RON", 1, 0, UUID, {}, 1),
		_act("RON", 2, 0, UUID, {}, 2),
		_act("PASS", 3, 0, UUID, {}, 3),
	]
	var out2: Dictionary = scr.call("resolve", two_ron_one_pass, 0)
	assert_ne(str(out2.get("outcome", "")), "SANCHA_HOURA",
		"一人 PASS 绝不能 sancha")
	assert_eq(str(out2.get("outcome", "")), "WINNER")
	var w: Action = out2.get("winner", null) as Action
	assert_not_null(w)
	assert_eq(w.seat, 1, "两家 RON 取相对最近")


func test_integration_two_ron_discarder_3_seat0_beats_seat2() -> void:
	# 领域集成：discarder=3 打出 W5，seat0 与 seat2 均真实 RON intent
	var hs := 0
	var bc := _make_bc(30, 0, hs)
	bc.state.current_seat = 3
	bc.state.phase = BattlePhase.Kind.CLAIM
	var discarded := _tile(TileId.W5, hs, 50)
	bc._last_discarded_tile = discarded
	bc._last_discarder_seat = 3
	bc.state.discards_per_seat[3] = [discarded]
	# 两家 tanyao tanki W5
	for s in [0, 2]:
		bc.state.seats[s].hand = _hand_from_ids([
			TileId.W2, TileId.W3, TileId.W4,
			TileId.T2, TileId.T3, TileId.T4,
			TileId.S2, TileId.S3, TileId.S4,
			TileId.W6, TileId.W7, TileId.W8,
			TileId.W5,
		], hs, 10 + s * 20)
		bc.state.seats[s].furiten = FuritenState.new()
	bc.state.seats[1].hand = _hand_from_ids([
		TileId.W1, TileId.W1, TileId.W9, TileId.T1, TileId.T9, TileId.S1,
		TileId.S9, TileId.E, TileId.E, TileId.S_WIND, TileId.W_WIND, TileId.N, TileId.HAKU,
	], hs, 100)
	for s in [0, 2]:
		assert_true(ClaimValidator.can_ron(
			bc.state.seats[s].hand, bc.state.seats[s].melds, discarded, bc.state.seats[s].furiten),
			"seat%d 必须可荣" % s)
	# 提交 intents：0 RON, 1 PASS, 2 RON
	for s in [0, 1, 2]:
		var ctx: DecisionContext = bc.decision_context_for_seat(s)
		assert_not_null(ctx)
		var a: Action
		if s == 1:
			a = _act("PASS", s, hs, ctx.decision_id, {}, s + 1)
		else:
			assert_true(ctx.has_kind("RON"), "seat%d 必须 offer RON" % s)
			a = _act("RON", s, hs, ctx.decision_id, {}, s + 1)
		assert_true(bc.apply_action(a, ActionSource.HUMAN).accepted)
	var winner_seat := -1
	for ev in bc.events:
		if ev is BattleEvent and str((ev as BattleEvent).type) == "WIN_DECLARED":
			winner_seat = int((ev as BattleEvent).actor_seat)
	assert_eq(winner_seat, 0, "discarder=3 时 seat0(距1) 胜 seat2(距3)")
	# #232：成功 RON 不得再 emit 遗留 PLAYER_ACTION kind=ron_accept（仅 ACTION_APPLIED + 领域 WIN）
	for ev in bc.events:
		if not (ev is BattleEvent):
			continue
		var be: BattleEvent = ev as BattleEvent
		if str(be.type) != "PLAYER_ACTION":
			continue
		var k: String = str(be.extra.get("kind", ""))
		assert_ne(k, "ron_accept", "成功 RON 不得双发 PLAYER_ACTION ron_accept")
		assert_ne(k, "tsumo_accept", "成功 RON 路径不得出现 tsumo_accept")


func test_integration_three_can_win_but_one_pass_not_sancha() -> void:
	var hs := 0
	var bc := _make_bc(31, 0, hs)
	bc.state.current_seat = 0
	bc.state.phase = BattlePhase.Kind.CLAIM
	var discarded := _tile(TileId.W5, hs, 60)
	bc._last_discarded_tile = discarded
	bc._last_discarder_seat = 0
	bc.state.discards_per_seat[0] = [discarded]
	for s in [1, 2, 3]:
		bc.state.seats[s].hand = _hand_from_ids([
			TileId.W2, TileId.W3, TileId.W4,
			TileId.T2, TileId.T3, TileId.T4,
			TileId.S2, TileId.S3, TileId.S4,
			TileId.W6, TileId.W7, TileId.W8,
			TileId.W5,
		], hs, 10 + s * 20)
		bc.state.seats[s].furiten = FuritenState.new()
		assert_true(ClaimValidator.can_ron(
			bc.state.seats[s].hand, bc.state.seats[s].melds, discarded, bc.state.seats[s].furiten))
	# 1 RON, 2 RON, 3 PASS → 非 sancha
	for s in [1, 2, 3]:
		var ctx: DecisionContext = bc.decision_context_for_seat(s)
		var a: Action = _act(
			"PASS" if s == 3 else "RON", s, hs, ctx.decision_id, {}, s)
		assert_true(bc.apply_action(a, ActionSource.HUMAN).accepted)
	for ev in bc.events:
		if ev is BattleEvent and str((ev as BattleEvent).type) == "ABORTIVE_DRAW":
			assert_ne(str((ev as BattleEvent).extra.get("reason", "")), "sancha_houra",
				"一人 PASS 不得 sancha")
	var win_count := 0
	for ev in bc.events:
		if ev is BattleEvent and str((ev as BattleEvent).type) == "WIN_DECLARED":
			win_count += 1
	assert_eq(win_count, 1, "两家 RON 应头跳一家")


func test_integration_three_actual_ron_intents_sancha() -> void:
	var hs := 0
	var bc := _make_bc(32, 0, hs)
	bc.state.current_seat = 0
	bc.state.phase = BattlePhase.Kind.CLAIM
	var discarded := _tile(TileId.W5, hs, 61)
	bc._last_discarded_tile = discarded
	bc._last_discarder_seat = 0
	bc.state.discards_per_seat[0] = [discarded]
	for s in [1, 2, 3]:
		bc.state.seats[s].hand = _hand_from_ids([
			TileId.W2, TileId.W3, TileId.W4,
			TileId.T2, TileId.T3, TileId.T4,
			TileId.S2, TileId.S3, TileId.S4,
			TileId.W6, TileId.W7, TileId.W8,
			TileId.W5,
		], hs, 10 + s * 20)
		bc.state.seats[s].furiten = FuritenState.new()
	for s in [1, 2, 3]:
		var ctx: DecisionContext = bc.decision_context_for_seat(s)
		assert_true(ctx.has_kind("RON"))
		assert_true(bc.apply_action(
			_act("RON", s, hs, ctx.decision_id, {}, s), ActionSource.HUMAN).accepted)
	var found := false
	for ev in bc.events:
		if ev is BattleEvent and str((ev as BattleEvent).type) == "ABORTIVE_DRAW":
			if str((ev as BattleEvent).extra.get("reason", "")) == "sancha_houra":
				found = true
	assert_true(found, "三条实际 RON intent 必须 sancha_houra")
	assert_true(bc._settled)


# ── F) journal / ACTION_APPLIED 一一对应 ──────────────────────────────────

func test_driver_journal_matches_action_applied_one_to_one() -> void:
	var bc := _make_bc(40, 0, 0)
	# 固定短路径：摸 → 弃（AI）直到若干 accepted，检查对应
	var result: Dictionary = bc.run_to_end()
	assert_true(result.has("events"))
	var journal: Array = bc.action_journal()
	var applied := 0
	for ev in bc.events:
		if ev is BattleEvent and str((ev as BattleEvent).type) == "ACTION_APPLIED":
			applied += 1
	assert_eq(journal.size(), applied,
		"每个 accepted Action 恰好一个 ACTION_APPLIED；journal=%d applied=%d"
		% [journal.size(), applied])
	# 简化：至少有 discard 进 journal
	assert_gt(journal.size(), 0, "AI 局应有 accepted discard 等")
	for a in journal:
		assert_true(a is Action)
		assert_true((a as Action).kind in [
			"DISCARD", "RIICHI", "TSUMO", "RON", "PASS", "CHI", "PON", "KAN",
			"DECLARE_ABORTIVE_DRAW",
		])


func test_tsumo_only_via_apply_action_not_draw_bypass() -> void:
	var hs := 0
	var bc := _make_bc(41, 0, hs)
	bc.state.current_seat = 0
	bc.state.phase = BattlePhase.Kind.DISCARD
	var seat: Seat = bc.state.seats[0]
	var ids := [
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.T1, TileId.T1,
	]
	seat.hand = _hand_from_ids(ids, hs, 0)
	var last: Tile = seat.hand._tiles[seat.hand._tiles.size() - 1]
	seat.last_drawn_instance_id = last.instance_id
	assert_true(bool(bc._check_tsumo(last).get("is_winning", false)))
	# 直接 draw 路径不应在未 apply TSUMO 时 settle
	assert_false(bc._settled)
	var ctx: DecisionContext = bc.decision_context_for_seat(0)
	assert_true(ctx.has_kind("TSUMO"))
	var j0: int = bc.action_journal().size()
	var resp: ActionResolution = bc.apply_action(
		_act("TSUMO", 0, hs, ctx.decision_id, {}, 1), ActionSource.HUMAN)
	assert_true(resp.accepted)
	assert_eq(bc.action_journal().size(), j0 + 1)
	assert_eq(_count_events(resp.events, "ACTION_APPLIED"), 1)
	assert_true(bc._settled)
	var found_win := false
	for ev in bc.events:
		if ev is BattleEvent and str((ev as BattleEvent).type) == "WIN_DECLARED":
			found_win = true
			assert_true(bool((ev as BattleEvent).extra.get("is_tsumo", false)))
	assert_true(found_win)
	# #232：成功 TSUMO 不得再 emit 遗留 PLAYER_ACTION kind=tsumo_accept（仅 ACTION_APPLIED + 领域 WIN）
	for ev in bc.events:
		if not (ev is BattleEvent):
			continue
		var be: BattleEvent = ev as BattleEvent
		if str(be.type) != "PLAYER_ACTION":
			continue
		var k: String = str(be.extra.get("kind", ""))
		assert_ne(k, "tsumo_accept", "成功 TSUMO 不得双发 PLAYER_ACTION tsumo_accept")
		assert_ne(k, "ron_accept", "成功 TSUMO 路径不得出现 ron_accept")


## #232 Red：seat0 真实可自摸；TSUMO_DECLARED hook 不 cancel，只把 phase→DRAW。
## 正确：engine 领域失败 → ActionResolution RULE_REJECTED，
## 事务回滚（phase/DISCARD、窗/decision_id、events/journal/ACTION_APPLIED 与 before 相同），
## 无 TSUMO_DECLARED/WIN 残留、未 settled。
func test_tsumo_engine_reject_never_settles_or_emits_win() -> void:
	var hs := 0
	_reset_wall_usage()
	var bc := _make_bc(23205, 0, hs)
	bc.state.current_seat = 0
	bc.state.phase = BattlePhase.Kind.DISCARD

	# seat0 ability：TSUMO_DECLARED 上仅破坏 phase，不 cancel
	var sk := SkillResource.new()
	sk.id = &"_test_break_tsumo_domain_v1"
	sk.is_ability = true
	var ot: Array[StringName] = [&"TSUMO_DECLARED"]
	sk.owner_triggers = ot
	sk.hook_script = _BreakTsumoDomainWithoutCancelHook
	bc.registry.register(sk, 0)

	# seat0 14 张：W234 T567 S678 S234 T1T1，最后一张 last_drawn
	var seat: Seat = bc.state.seats[0]
	seat.hand = _hand_from_wall(bc, [
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.T1, TileId.T1,
	])
	var last: Tile = seat.hand._tiles[seat.hand._tiles.size() - 1]
	seat.last_drawn_instance_id = last.instance_id
	assert_true(bool(bc._check_tsumo(last).get("is_winning", false)),
		"seat0 必须真实可自摸")

	# 真实 TURN decision + TSUMO offer
	var ctx: DecisionContext = bc.decision_context_for_seat(0)
	assert_not_null(ctx)
	assert_true(ctx.has_kind("TSUMO"), "seat0 必须 offer TSUMO")
	var decision_id: String = ctx.decision_id

	# 提交前基线
	var phase_before: int = int(bc.state.phase)
	var current_before: int = int(bc.state.current_seat)
	var events_before: int = bc.events.size()
	var journal_before: int = bc.action_journal().size()
	var applied_before: int = _count_events(bc.events, "ACTION_APPLIED")
	var last_event_before: StringName = bc._last_event_type
	var chain_id_before: int = int(bc.scheduler._next_chain_id)
	var settled_before: bool = bool(bc._settled)
	var win_before = bc.get("_active_window")
	assert_eq(phase_before, BattlePhase.Kind.DISCARD)
	assert_eq(current_before, 0)
	assert_false(settled_before)
	assert_not_null(win_before, "提交前 active_window 必须存活")
	if win_before != null:
		var win_b: DecisionWindow = win_before as DecisionWindow
		assert_eq(win_b.decision_id, decision_id)

	# 真实 apply TSUMO → hook 把 phase→DRAW → engine 领域必须失败
	var resp: ActionResolution = bc.apply_action(
		_act("TSUMO", 0, hs, decision_id, {}, 1), ActionSource.HUMAN)

	assert_false(resp.accepted,
		"engine 领域失败必须 accepted=false；error=%s" % str(resp.error_code))
	assert_eq(resp.error_code, ActionResolution.RULE_REJECTED,
		"reason/error_code 必须 RULE_REJECTED，实际=%s" % str(resp.error_code))

	# 领域失败事务回滚
	assert_eq(int(bc.state.phase), BattlePhase.Kind.DISCARD, "phase 必须回滚 DISCARD")
	assert_eq(int(bc.state.current_seat), 0, "current_seat 仍为 0")
	assert_false(bc._settled, "不得 settled")
	assert_eq(bc._last_event_type, last_event_before,
		"失败后 _last_event_type 必须完全恢复")
	assert_eq(int(bc.scheduler._next_chain_id), chain_id_before,
		"失败后 scheduler._next_chain_id 必须完全恢复")
	var win_after = bc.get("_active_window")
	assert_not_null(win_after, "失败后原 active_window 必须保留")
	assert_same(win_after, win_before, "失败后必须保留原 TURN window 对象，不得重建同 ID 窗")
	if win_after != null:
		var win_a: DecisionWindow = win_after as DecisionWindow
		assert_eq(win_a.decision_id, decision_id, "decision_id 不得因失败换窗")

	assert_eq(bc.events.size(), events_before, "events 与 before 完全相同（条数）")
	assert_eq(bc.action_journal().size(), journal_before, "journal 与 before 完全相同")
	assert_eq(_count_events(bc.events, "ACTION_APPLIED"), applied_before,
		"ACTION_APPLIED 与 before 完全相同")
	assert_eq(_count_events(bc.events, "TSUMO_DECLARED"), 0, "不得残留 TSUMO_DECLARED")
	assert_eq(_count_events(bc.events, "WIN_DECLARED"), 0, "不得残留 WIN_DECLARED")


# ── G) CLAIM 收窗 domain 预检失败不得先 register / ACTION_APPLIED ──────────

func _river_iids(bc: BattleController) -> Array:
	var out: Array = []
	for s in range(4):
		var row: Array = []
		for t in bc.state.discards_per_seat[s]:
			if t is Tile:
				row.append(int((t as Tile).instance_id))
			else:
				row.append(-1)
		out.append(row)
	return out


## #232 Red：CLAIM 窗中 PON 为收窗最后 intent；offer 后故意从 claimant hand
## 移除 payload companion，使 TurnEngine.apply_pon 领域预检失败。
## 正确行为：apply_action accepted=false / RULE_REJECTED，且不得 register intent、
## 不得 ACTION_APPLIED、不得写 journal、领域状态与窗响应态零修改。
func test_claim_last_pon_domain_precheck_fail_rejects_without_register_or_action_applied() -> void:
	var hs := 0
	var discarder := 0
	var claimant := 2
	var passers: Array = [1, 3]
	_reset_wall_usage()
	var bc := _make_bc(23202, discarder, hs)
	bc.state.current_seat = discarder
	bc.state.phase = BattlePhase.Kind.CLAIM

	# 弃牌与各座手牌一律取自同一 wall 的 canonical 136 实体
	var discarded: Tile = _take_wall_tile(bc, TileId.W5)
	assert_not_null(discarded)
	bc._last_discarded_tile = discarded
	bc._last_discarder_seat = discarder
	bc.state.discards_per_seat[discarder] = [discarded]

	# claimant：对子 W5 可碰；万子序数填充（全局 W5≤3，无超 4 枚）
	bc.state.seats[claimant].hand = _hand_from_wall(bc, [
		TileId.W5, TileId.W5,
		TileId.W1, TileId.W2, TileId.W3, TileId.W4,
		TileId.W6, TileId.W7, TileId.W8, TileId.W9,
		TileId.T1, TileId.T2, TileId.T3,
	])
	# seat1（下家）：筒/索序数，无 W5、对 W5 无 CHI 组合
	bc.state.seats[1].hand = _hand_from_wall(bc, [
		TileId.T4, TileId.T5, TileId.T6, TileId.T7, TileId.T8, TileId.T9,
		TileId.S1, TileId.S2, TileId.S3, TileId.S4, TileId.S5, TileId.S6, TileId.S7,
	])
	bc.state.seats[1].furiten = FuritenState.new()
	# seat3：字牌/边张，无 W5、无听 W5
	bc.state.seats[3].hand = _hand_from_wall(bc, [
		TileId.S8, TileId.S9,
		TileId.E, TileId.E,
		TileId.S_WIND, TileId.S_WIND,
		TileId.W_WIND, TileId.W_WIND,
		TileId.N, TileId.N,
		TileId.HAKU, TileId.HAKU,
		TileId.HATSU,
	])
	bc.state.seats[3].furiten = FuritenState.new()
	# discarder 不重设 hand：构造器已有非 null Hand；CLAIM 窗跳过 discarder

	assert_true(ClaimValidator.can_pon(
		claimant, discarder, bc.state.seats[claimant].hand, discarded.id),
		"fixture 必须真实可碰")

	# 打开 CLAIM 窗并冻结 offer（payload 来自真实 DecisionContext，禁止手造）
	var ctx_c: DecisionContext = bc.decision_context_for_seat(claimant)
	assert_not_null(ctx_c)
	assert_eq(ctx_c.window_kind, "CLAIM")
	assert_true(ctx_c.has_kind("PON"), "claimant 必须 offer PON")
	var pon_payload: Dictionary = {}
	for offer in ctx_c.allowed_actions:
		if str(offer.get("kind", "")) != "PON":
			continue
		var opts: Array = offer.get("payload_options", [])
		assert_gt(opts.size(), 0, "PON payload_options 非空")
		pon_payload = (opts[0] as Dictionary).duplicate(true)
		break
	assert_false(pon_payload.is_empty(), "须从真实 offer 取 PON payload")
	var comps: Array = pon_payload.get("companion_tile_instance_ids", [])
	assert_eq(comps.size(), 2, "PON companion 须 2 枚")
	for iid in comps:
		assert_true(Tile.is_instance_id_in_hand_seq(int(iid), hs),
			"companion 必须本局 wall 命名空间 iid=%s" % str(iid))
		assert_not_null(bc.state.seats[claimant].hand.find_by_instance_id(int(iid)),
			"offer companion 提交前必须在 claimant hand")

	# 其他响应者先 PASS → PON 成为收窗最后 intent
	var seq := 1
	for s in passers:
		var pctx: DecisionContext = bc.decision_context_for_seat(int(s))
		assert_not_null(pctx)
		assert_eq(pctx.decision_id, ctx_c.decision_id, "同窗 decision_id")
		assert_true(pctx.has_kind("PASS"))
		var pass_act: Action = _act("PASS", int(s), hs, pctx.decision_id, {}, seq)
		seq += 1
		var pr: ActionResolution = bc.apply_action(pass_act, ActionSource.HUMAN)
		assert_true(pr.accepted, "PASS seat %d 应 accepted" % int(s))
	var win_mid = bc.get("_active_window")
	assert_not_null(win_mid, "两席 PASS 后 CLAIM 窗仍存活")
	assert_true((win_mid as DecisionWindow).has_responded(int(passers[0])))
	assert_true((win_mid as DecisionWindow).has_responded(int(passers[1])))
	assert_false((win_mid as DecisionWindow).has_responded(claimant),
		"claimant 尚未响应")
	assert_false((win_mid as DecisionWindow).is_complete(),
		"PON 未提交前窗未 complete")

	# offer 生成后 sabotage：从 hand 移除 payload 指定的一枚 companion
	var sabotage_iid: int = int(comps[0])
	var sab_tile: Tile = bc.state.seats[claimant].hand.take_by_instance_id(sabotage_iid)
	assert_not_null(sab_tile, "sabotage 必须取走 companion")
	assert_null(bc.state.seats[claimant].hand.find_by_instance_id(sabotage_iid),
		"companion 已离手")
	# 领域预检必失败（零修改路径）
	assert_false(
		bc.engine.apply_pon(claimant, discarded.instance_id, comps),
		"sabotage 后 TurnEngine.apply_pon 领域预检必须失败")

	# sabotage 后重新建立 before 基线（提交前）
	var before: Dictionary = _domain_snap(bc, claimant)
	var events_before: int = bc.events.size()
	var journal_before: int = bc.action_journal().size()
	var river_before: Array = _river_iids(bc)
	var applied_before: int = int(before["applied"])
	assert_eq(int(before["events_n"]), events_before)
	assert_eq(int(before["journal"]), journal_before)

	var pon_act: Action = _act("PON", claimant, hs, ctx_c.decision_id, pon_payload, seq)
	var resp: ActionResolution = bc.apply_action(pon_act, ActionSource.HUMAN)

	# 强断言：拒绝且 reason/error_code = RULE_REJECTED
	assert_false(resp.accepted, "domain 预检失败必须 accepted=false")
	assert_eq(resp.error_code, ActionResolution.RULE_REJECTED,
		"reason/error_code 必须 RULE_REJECTED，实际=%s" % str(resp.error_code))

	# ACTION_APPLIED / journal / events 与 before 相同
	var after: Dictionary = _domain_snap(bc, claimant)
	assert_eq(int(after["applied"]), applied_before,
		"不得新增 ACTION_APPLIED（先 register 再 domain 为 bug）")
	assert_eq(bc.action_journal().size(), journal_before,
		"journal 不得追加被拒 Action")
	assert_eq(bc.events.size(), events_before, "events 条数不得增加")
	assert_eq(int(after["events_n"]), events_before)
	assert_eq(int(after["journal"]), journal_before)

	# phase / current_seat / 河 / melds / hand iid / dora / live wall / rinshan / settled
	assert_eq(int(after["phase"]), int(before["phase"]))
	assert_eq(int(after["phase"]), BattlePhase.Kind.CLAIM)
	assert_eq(int(after["current_seat"]), int(before["current_seat"]))
	assert_eq(int(after["current_seat"]), discarder)
	assert_eq(_river_iids(bc), river_before, "河（discards_per_seat iid）零修改")
	assert_eq(after["melds"], before["melds"], "四座 melds 零修改")
	assert_eq(after["hands"], before["hands"], "四座 hand iid 零修改（含 sabotage 后状态）")
	assert_eq(int(after["dora_n"]), int(before["dora_n"]))
	assert_eq(int(after["live_wall"]), int(before["live_wall"]))
	assert_eq(bool(after["rinshan"]), bool(before["rinshan"]))
	assert_eq(bool(after["settled"]), bool(before["settled"]))
	assert_false(bool(after["settled"]))
	assert_eq(after["pending_empty"], before["pending_empty"])

	# 该 seat 不得标记 has_responded；窗口仍可确定响应
	var win_after = bc.get("_active_window")
	assert_not_null(win_after, "拒绝后 CLAIM 窗必须仍存活以便重试")
	var win_a: DecisionWindow = win_after as DecisionWindow
	assert_eq(win_a.decision_id, ctx_c.decision_id, "不得因失败重建/换窗")
	assert_false(win_a.has_responded(claimant),
		"domain 失败不得 register intent / has_responded")
	assert_false(win_a.is_complete(), "claimant 未成功响应则窗未 complete")
	var ctx_retry: DecisionContext = bc.decision_context_for_seat(claimant)
	assert_not_null(ctx_retry, "窗口仍可对 claimant 给出 DecisionContext")
	assert_eq(ctx_retry.decision_id, ctx_c.decision_id)
	assert_true(ctx_retry.has_kind("PON") or ctx_retry.has_kind("PASS"),
		"窗仍可确定响应（至少保留原 offer 或 PASS）")

# ── H) CLAIM 头跳 RON 被技能 cancel 后应 fallback，不得当 FAILED ──────────

## seat1 一次性 ability：仅取消 actor=seat1 的 RON_DECLARED，并 consume。
class _CancelOwnRonOnceHook extends SkillHook:
	func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
		if int(event.actor_seat) != int(ctx.beneficiary_seat):
			return
		ctx.cancel_ron(int(event.actor_seat))
		ctx.consume_self()


## offer 后、engine.apply_ron 前：不 cancel，只把 phase 改成 DRAW，使权威 apply_ron 领域必失败。
class _BreakRonDomainWithoutCancelHook extends SkillHook:
	func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
		if str(event.type) != "RON_DECLARED":
			return
		# 不 cancel；模拟 settle 中途领域条件失效
		ctx._state.phase = BattlePhase.Kind.DRAW


## TSUMO_DECLARED 时不 cancel，只把 phase 改成 DRAW，使权威 tsumo 领域必失败。
class _BreakTsumoDomainWithoutCancelHook extends SkillHook:
	func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
		if event.type != &"TSUMO_DECLARED":
			return
		# 不 cancel；模拟 settle 中途领域条件失效
		ctx._state.phase = BattlePhase.Kind.DRAW


## #232 Red：discarder=0 打 W5；seat1/2 真实可荣；seat1 ability cancel 自身 RON 一次。
## 期望：seat1 canceled 后 seat2 WIN；PASS accepted；窗关；3 条 journal/ACTION_APPLIED；
## ACTION_APPLIED 在 RON/WIN 前。当前实现把 cancel 当 RULE_REJECTED(FAILED) 故本测 Red。
func test_claim_ron_cancel_fallback_to_next_winner_not_failed() -> void:
	var hs := 0
	var discarder := 0
	_reset_wall_usage()
	var bc := _make_bc(23203, discarder, hs)
	bc.state.current_seat = discarder
	bc.state.phase = BattlePhase.Kind.CLAIM

	# seat1 一次性 ability：RON_DECLARED 上 cancel_ron + consume
	var sk := SkillResource.new()
	sk.id = &"_test_cancel_own_ron_v1"
	sk.is_ability = true
	var ot: Array[StringName] = [&"RON_DECLARED"]
	sk.owner_triggers = ot
	sk.hook_script = _CancelOwnRonOnceHook
	bc.registry.register(sk, 1)

	# discarder0 canonical W5
	var discarded: Tile = _take_wall_tile(bc, TileId.W5)
	assert_not_null(discarded)
	bc._last_discarded_tile = discarded
	bc._last_discarder_seat = discarder
	bc.state.discards_per_seat[discarder] = [discarded]

	# seat1/2：T234 S234 T678 W6W6 W3W4（听 W5 断幺九）
	var tenpai_ids: Array = [
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.T6, TileId.T7, TileId.T8,
		TileId.W6, TileId.W6,
		TileId.W3, TileId.W4,
	]
	for s in [1, 2]:
		bc.state.seats[s].hand = _hand_from_wall(bc, tenpai_ids)
		bc.state.seats[s].furiten = FuritenState.new()
		assert_true(ClaimValidator.can_ron(
			bc.state.seats[s].hand, bc.state.seats[s].melds, discarded, bc.state.seats[s].furiten),
			"seat%d 必须真实可荣" % s)

	# seat3：无听 W5，仅 PASS
	bc.state.seats[3].hand = _hand_from_wall(bc, [
		TileId.S8, TileId.S9,
		TileId.E, TileId.E,
		TileId.S_WIND, TileId.S_WIND,
		TileId.W_WIND, TileId.W_WIND,
		TileId.N, TileId.N,
		TileId.HAKU, TileId.HAKU,
		TileId.HATSU,
	])
	bc.state.seats[3].furiten = FuritenState.new()

	# 真实 offer RON
	for s in [1, 2]:
		var octx: DecisionContext = bc.decision_context_for_seat(s)
		assert_not_null(octx)
		assert_eq(octx.window_kind, "CLAIM")
		assert_true(octx.has_kind("RON"), "seat%d 必须 offer RON" % s)
	var pctx0: DecisionContext = bc.decision_context_for_seat(3)
	assert_not_null(pctx0)
	assert_false(pctx0.has_kind("RON"), "seat3 不得 offer RON")
	assert_true(pctx0.has_kind("PASS"))
	var decision_id: String = pctx0.decision_id

	# 依次 seat1 RON、seat2 RON、seat3 PASS
	var seq := 1
	var r1: ActionResolution = bc.apply_action(
		_act("RON", 1, hs, decision_id, {}, seq), ActionSource.HUMAN)
	seq += 1
	assert_true(r1.accepted, "seat1 RON intent 应 accepted（窗未 complete）")
	assert_false(sk.consumed, "收窗前 ability 尚未 fire")

	var r2: ActionResolution = bc.apply_action(
		_act("RON", 2, hs, decision_id, {}, seq), ActionSource.HUMAN)
	seq += 1
	assert_true(r2.accepted, "seat2 RON intent 应 accepted（窗未 complete）")

	var r3: ActionResolution = bc.apply_action(
		_act("PASS", 3, hs, decision_id, {}, seq), ActionSource.HUMAN)
	# 当前 bug：cancel 当 FAILED → PASS 被 RULE_REJECTED；正确：CANCELLED 后 seat2 WIN
	assert_true(r3.accepted,
		"PASS 收窗必须 accepted（cancel 不得当 FAILED/RULE_REJECTED）；error=%s"
		% str(r3.error_code))
	assert_eq(r3.error_code, &"", "accepted 时 error_code 空")

	assert_true(sk.consumed, "seat1 ability 必须 consume")
	assert_true(bool(bc.state.ron_cancelled[1]), "seat1 RON 必须被 cancel")
	assert_false(bool(bc.state.ron_cancelled[2]), "seat2 不得被 cancel")

	assert_true(bc._settled, "seat2 WIN 后 settled")
	assert_null(bc.get("_active_window"), "窗口必须关闭")

	var winner_seat := -1
	var win_n := 0
	for ev in bc.events:
		if ev is BattleEvent and str((ev as BattleEvent).type) == "WIN_DECLARED":
			win_n += 1
			winner_seat = int((ev as BattleEvent).actor_seat)
	assert_eq(win_n, 1, "恰好一家 WIN")
	assert_eq(winner_seat, 2, "seat1 canceled 后 seat2 头跳 WIN")

	assert_eq(bc.action_journal().size(), 3, "三条 journal（RON+RON+PASS）")
	assert_eq(_count_events(bc.events, "ACTION_APPLIED"), 3,
		"三条 ACTION_APPLIED")

	# ACTION_APPLIED 必须出现在任意 RON_DECLARED / WIN_DECLARED 之前（收窗段）
	var idx_applied_pass := -1
	var idx_first_ron_decl := -1
	var idx_win := -1
	for i in range(bc.events.size()):
		var ev2 = bc.events[i]
		if not (ev2 is BattleEvent):
			continue
		var t: String = str((ev2 as BattleEvent).type)
		var seat_e: int = int((ev2 as BattleEvent).actor_seat)
		if t == "ACTION_APPLIED" and seat_e == 3:
			idx_applied_pass = i
		if t == "RON_DECLARED" and idx_first_ron_decl < 0:
			idx_first_ron_decl = i
		if t == "WIN_DECLARED" and idx_win < 0:
			idx_win = i
	assert_gte(idx_applied_pass, 0, "须有 seat3 PASS 的 ACTION_APPLIED")
	assert_gte(idx_first_ron_decl, 0, "须有 RON_DECLARED")
	assert_gte(idx_win, 0, "须有 WIN_DECLARED")
	assert_lt(idx_applied_pass, idx_first_ron_decl,
		"收窗 ACTION_APPLIED 必须在 RON_DECLARED 前")
	assert_lt(idx_applied_pass, idx_win,
		"收窗 ACTION_APPLIED 必须在 WIN_DECLARED 前")


# ── I) ROB_KAN 抢杠 RON 被技能 cancel 后应完成加杠，不得当 FAILED ─────────

## #232 Red：actor=1 真实 ADDED_KAN；seat2 可抢杠但 ability cancel 自身 RON 一次。
## 期望：CANCELLED 后 fallback 完成加杠（非 settled）；PASS accepted；4 条 journal/ACTION_APPLIED；
## ACTION_APPLIED 在 RON_DECLARED / PLAYER_ACTION added_kan 前。
## 当前实现 ROB_KAN 把 cancel 当 false(FAILED) 故本测 Red。
func test_rob_kan_ron_cancel_completes_added_kan_not_failed() -> void:
	var hs := 0
	var actor := 1
	_reset_wall_usage()
	var bc := _make_bc(23204, actor, hs)
	bc.state.current_seat = actor
	bc.state.phase = BattlePhase.Kind.DISCARD

	# seat2 一次性 ability：仅 cancel 自身 RON_DECLARED 并 consume
	var sk := SkillResource.new()
	sk.id = &"_test_cancel_own_rob_kan_ron_v1"
	sk.is_ability = true
	var ot: Array[StringName] = [&"RON_DECLARED"]
	sk.owner_triggers = ot
	sk.hook_script = _CancelOwnRonOnceHook
	bc.registry.register(sk, 2)

	# actor：11 张手牌 + PON(W5×3)；added=手中 W5
	var seat_a: Seat = bc.state.seats[actor]
	seat_a.hand = _hand_from_wall(bc, [
		TileId.W5,
		TileId.T1, TileId.T2, TileId.T3,
		TileId.S1, TileId.S2, TileId.S3,
		TileId.W7, TileId.W8, TileId.W9,
		TileId.E,
	])
	var added: Tile = null
	for t in seat_a.hand._tiles:
		if int(t.id) == TileId.W5:
			added = t
			break
	assert_not_null(added, "actor 手中必须有 canonical W5")
	seat_a.last_drawn_instance_id = added.instance_id
	var pon_tiles: Array[Tile] = []
	for _i in range(3):
		var wt: Tile = _take_wall_tile(bc, TileId.W5)
		assert_not_null(wt)
		pon_tiles.append(wt)
	var pon: Meld = Meld.make_pon(pon_tiles, 0, _ns(0, 25))
	assert_not_null(pon)
	seat_a.melds = [pon]
	assert_true(ClaimValidator.can_added_kan(seat_a.melds, seat_a.hand, TileId.W5),
		"fixture 必须真实可加杠")

	# seat2：听 W5（断幺九），可抢杠
	bc.state.seats[2].hand = _hand_from_wall(bc, [
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.T6, TileId.T7, TileId.T8,
		TileId.W6, TileId.W6,
		TileId.W3, TileId.W4,
	])
	bc.state.seats[2].furiten = FuritenState.new()
	assert_true(ClaimValidator.can_ron(
		bc.state.seats[2].hand, bc.state.seats[2].melds, added, bc.state.seats[2].furiten),
		"seat2 必须真实可抢杠 added W5")

	# 下一岭上实体不得与 fixture 占用 iid 冲突（seed 冲突时换 seed）
	var next_rinshan_iid: int = -1
	if bc.state.wall._tiles.size() > 0:
		var ridx: int = bc.state.wall._tiles.size() - 1 - int(bc.state.wall._rinshan_taken)
		if ridx >= 0 and ridx < bc.state.wall._tiles.size():
			var rt: Tile = bc.state.wall._tiles[ridx]
			if rt != null:
				next_rinshan_iid = int(rt.instance_id)
	assert_true(next_rinshan_iid < 0 or not _used_wall_iids.has(next_rinshan_iid),
		"下一岭上 iid 不得已被 fixture 占用；seed 冲突请换 seed")

	# 真实 TURN DecisionContext 取 ADDED_KAN payload
	var turn_ctx: DecisionContext = bc.decision_context_for_seat(actor)
	assert_not_null(turn_ctx)
	assert_eq(turn_ctx.window_kind, "TURN")
	assert_true(turn_ctx.has_kind("KAN"), "必须 offer KAN")
	var kan_payload: Dictionary = {}
	var found_added := false
	for offer in turn_ctx.allowed_actions:
		if str(offer.get("kind", "")) != "KAN":
			continue
		for opt in offer.get("payload_options", []):
			if str(opt.get("kan_kind", "")) != "ADDED_KAN":
				continue
			kan_payload = (opt as Dictionary).duplicate(true)
			found_added = true
			break
		if found_added:
			break
	assert_true(found_added, "必须含 ADDED_KAN payload")
	assert_eq(int(kan_payload.get("meld_id", -1)), pon.meld_id)
	assert_eq(int(kan_payload.get("added_tile_instance_id", -1)), added.instance_id)

	var kan_act: Action = _act("KAN", actor, hs, turn_ctx.decision_id, kan_payload, 1)
	var r_kan: ActionResolution = bc.apply_action(kan_act, ActionSource.HUMAN)
	assert_true(r_kan.accepted, "ADDED_KAN 声明应 accepted")
	assert_false(bc._pending_added_kan.is_empty(), "pending 非空")
	assert_eq((bc.state.seats[actor].melds[0] as Meld).kind, Meld.Kind.PON, "声明后仍为 PON")
	assert_not_null(bc.state.seats[actor].hand.find_by_instance_id(added.instance_id),
		"added 仍在手")

	var dora_after_decl: int = bc.state.dora_indicators.visible.size()
	var rinshan_after_decl: int = int(bc.state.wall._rinshan_taken)
	var hand_size_after_decl: int = bc.state.seats[actor].hand.size()

	# 真实 ROB_KAN：seat0 PASS → seat2 RON → seat3 PASS 收窗
	var seq := 2
	var rctx0: DecisionContext = bc.decision_context_for_seat(0)
	assert_not_null(rctx0)
	assert_eq(rctx0.window_kind, "ROB_KAN")
	var decision_id: String = rctx0.decision_id
	var r0: ActionResolution = bc.apply_action(
		_act("PASS", 0, hs, decision_id, {}, seq), ActionSource.HUMAN)
	seq += 1
	assert_true(r0.accepted, "seat0 PASS intent 应 accepted")

	var rctx2: DecisionContext = bc.decision_context_for_seat(2)
	assert_not_null(rctx2)
	assert_eq(rctx2.decision_id, decision_id)
	assert_true(rctx2.has_kind("RON"), "seat2 必须 offer RON")
	var r2: ActionResolution = bc.apply_action(
		_act("RON", 2, hs, decision_id, {}, seq), ActionSource.HUMAN)
	seq += 1
	assert_true(r2.accepted, "seat2 RON intent 应 accepted（窗未 complete）")
	assert_false(sk.consumed, "收窗前 ability 尚未 fire")

	var rctx3: DecisionContext = bc.decision_context_for_seat(3)
	assert_not_null(rctx3)
	assert_eq(rctx3.decision_id, decision_id)
	assert_true(rctx3.has_kind("PASS"))
	var r3: ActionResolution = bc.apply_action(
		_act("PASS", 3, hs, decision_id, {}, seq), ActionSource.HUMAN)
	# 当前 bug：ROB_KAN 把 cancel 当 FAILED → PASS RULE_REJECTED；
	# 正确：CANCELLED 后完成 added kan
	assert_true(r3.accepted,
		"PASS 收窗必须 accepted（cancel 不得当 FAILED/RULE_REJECTED）；error=%s"
		% str(r3.error_code))
	assert_eq(r3.error_code, &"", "accepted 时 error_code 空")

	assert_true(sk.consumed, "seat2 ability 必须 consume")
	assert_true(bool(bc.state.ron_cancelled[2]), "seat2 RON 必须被 cancel")

	assert_true(bc._pending_added_kan.is_empty(), "cancel 后应完成加杠并清 pending")
	assert_null(bc.get("_active_window"), "窗口必须关闭")
	assert_false(bc._settled, "cancel 后不得 settled（应完成加杠非胡）")
	assert_eq(bc.state.current_seat, actor, "current_seat 回到杠家")
	assert_eq(bc.state.phase, BattlePhase.Kind.DISCARD, "加杠完成后 phase=DISCARD")
	assert_eq((bc.state.seats[actor].melds[0] as Meld).kind, Meld.Kind.ADDED_KAN,
		"cancel 后应 promote 为 ADDED_KAN")
	assert_null(bc.state.seats[actor].hand.find_by_instance_id(added.instance_id),
		"added 必须离手")
	assert_eq(bc.state.dora_indicators.visible.size(), dora_after_decl + 1,
		"加杠完成应翻 1 张 dora")
	assert_eq(int(bc.state.wall._rinshan_taken), rinshan_after_decl + 1,
		"加杠完成应摸 1 张岭上")
	assert_true(bc.state.seats[actor].last_draw_is_rinshan, "last_draw_is_rinshan")
	assert_eq(bc.state.seats[actor].hand.size(), hand_size_after_decl,
		"手牌 size：移 added + 摸岭上 → 与声明后相同")

	assert_eq(bc.action_journal().size(), 4, "KAN+三响应共 4 条 journal")
	assert_eq(_count_events(bc.events, "ACTION_APPLIED"), 4,
		"KAN+三响应共 4 条 ACTION_APPLIED")

	# 最终 PASS 的 ACTION_APPLIED 须早于 RON_DECLARED 与 PLAYER_ACTION added_kan
	var idx_applied_pass := -1
	var idx_ron_decl := -1
	var idx_added_kan_pa := -1
	for i in range(bc.events.size()):
		var ev = bc.events[i]
		if not (ev is BattleEvent):
			continue
		var be: BattleEvent = ev as BattleEvent
		var t: String = str(be.type)
		if t == "ACTION_APPLIED" and int(be.actor_seat) == 3:
			idx_applied_pass = i
		if t == "RON_DECLARED" and idx_ron_decl < 0:
			idx_ron_decl = i
		if t == "PLAYER_ACTION" and str(be.extra.get("kind", "")) == "added_kan" and idx_added_kan_pa < 0:
			idx_added_kan_pa = i
	assert_gte(idx_applied_pass, 0, "须有 seat3 PASS 的 ACTION_APPLIED")
	assert_gte(idx_ron_decl, 0, "须有 RON_DECLARED（cancel 前 emit）")
	assert_gte(idx_added_kan_pa, 0, "须有 PLAYER_ACTION added_kan（完成加杠）")
	assert_lt(idx_applied_pass, idx_ron_decl,
		"收窗 ACTION_APPLIED 必须在 RON_DECLARED 前")
	assert_lt(idx_applied_pass, idx_added_kan_pa,
		"收窗 ACTION_APPLIED 必须在 PLAYER_ACTION added_kan 前")


# ── J) CLAIM 荣和 engine.apply_ron 领域失败不得 settled / WIN ─────────────

## #232 Red：seat1 真实 RON；RON_DECLARED hook 不 cancel，只把 phase→DRAW。
## 正确：收窗后 engine.apply_ron 必 false → ActionResolution RULE_REJECTED，
## 事务回滚（phase/CLAIM、窗/decision_id、events/journal/ACTION_APPLIED 与 before 相同），
## 无 RON_DECLARED/WIN 残留、未 settled。当前 _settle_ron 忽略 apply_ron bool 故本测 Red。
func test_claim_ron_engine_reject_never_settles_or_emits_win() -> void:
	var hs := 0
	var discarder := 0
	_reset_wall_usage()
	var bc := _make_bc(23204, discarder, hs)
	bc.state.current_seat = discarder
	bc.state.phase = BattlePhase.Kind.CLAIM

	# seat1 ability：RON_DECLARED 上仅破坏 phase，不 cancel
	var sk := SkillResource.new()
	sk.id = &"_test_break_ron_domain_v1"
	sk.is_ability = true
	var ot: Array[StringName] = [&"RON_DECLARED"]
	sk.owner_triggers = ot
	sk.hook_script = _BreakRonDomainWithoutCancelHook
	bc.registry.register(sk, 1)

	# discarder0 canonical W5 入河 / _last
	var discarded: Tile = _take_wall_tile(bc, TileId.W5)
	assert_not_null(discarded)
	bc._last_discarded_tile = discarded
	bc._last_discarder_seat = discarder
	bc.state.discards_per_seat[discarder] = [discarded]

	# seat1：T234 S234 T678 W6W6 W3W4（听 W5）
	bc.state.seats[1].hand = _hand_from_wall(bc, [
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.T6, TileId.T7, TileId.T8,
		TileId.W6, TileId.W6,
		TileId.W3, TileId.W4,
	])
	bc.state.seats[1].furiten = FuritenState.new()
	assert_true(ClaimValidator.can_ron(
		bc.state.seats[1].hand, bc.state.seats[1].melds, discarded, bc.state.seats[1].furiten),
		"seat1 必须真实可荣")

	# seat2/3：canonical 非听 hand，真实仅 PASS；禁止 new Tile
	bc.state.seats[2].hand = _hand_from_wall(bc, [
		TileId.T1, TileId.T1, TileId.T9, TileId.T9,
		TileId.S1, TileId.S1, TileId.S9, TileId.S9,
		TileId.W1, TileId.W1, TileId.W9, TileId.W9,
		TileId.CHUN,
	])
	bc.state.seats[2].furiten = FuritenState.new()
	bc.state.seats[3].hand = _hand_from_wall(bc, [
		TileId.S8, TileId.S9,
		TileId.E, TileId.E,
		TileId.S_WIND, TileId.S_WIND,
		TileId.W_WIND, TileId.W_WIND,
		TileId.N, TileId.N,
		TileId.HAKU, TileId.HAKU,
		TileId.HATSU,
	])
	bc.state.seats[3].furiten = FuritenState.new()

	# 真实 offer：seat1 RON；seat2/3 仅 PASS
	var octx1: DecisionContext = bc.decision_context_for_seat(1)
	assert_not_null(octx1)
	assert_eq(octx1.window_kind, "CLAIM")
	assert_true(octx1.has_kind("RON"), "seat1 必须 offer RON")
	var pctx2: DecisionContext = bc.decision_context_for_seat(2)
	assert_not_null(pctx2)
	assert_false(pctx2.has_kind("RON"), "seat2 不得 offer RON")
	assert_true(pctx2.has_kind("PASS"))
	var pctx3: DecisionContext = bc.decision_context_for_seat(3)
	assert_not_null(pctx3)
	assert_false(pctx3.has_kind("RON"), "seat3 不得 offer RON")
	assert_true(pctx3.has_kind("PASS"))
	var decision_id: String = octx1.decision_id
	assert_eq(pctx2.decision_id, decision_id)
	assert_eq(pctx3.decision_id, decision_id)

	# 前两 intent accepted（窗未 complete）
	var seq := 1
	var r1: ActionResolution = bc.apply_action(
		_act("RON", 1, hs, decision_id, {}, seq), ActionSource.HUMAN)
	seq += 1
	assert_true(r1.accepted, "seat1 RON intent 应 accepted（窗未 complete）")
	var r2: ActionResolution = bc.apply_action(
		_act("PASS", 2, hs, decision_id, {}, seq), ActionSource.HUMAN)
	seq += 1
	assert_true(r2.accepted, "seat2 PASS intent 应 accepted（窗未 complete）")

	# 最后提交前基线（seat3 尚未响应）
	var win_before = bc.get("_active_window")
	assert_not_null(win_before, "收窗前 CLAIM 窗必须存活")
	var win_b: DecisionWindow = win_before as DecisionWindow
	assert_eq(win_b.decision_id, decision_id)
	assert_true(win_b.has_responded(1))
	assert_true(win_b.has_responded(2))
	assert_false(win_b.has_responded(3), "seat3 提交前未 responded")
	assert_false(win_b.is_complete())
	var phase_before: int = int(bc.state.phase)
	var current_before: int = int(bc.state.current_seat)
	var events_before: int = bc.events.size()
	var journal_before: int = bc.action_journal().size()
	var applied_before: int = _count_events(bc.events, "ACTION_APPLIED")
	# 零污染强断言基线：失败后须完全恢复
	var last_event_before: StringName = bc._last_event_type
	var chain_id_before: int = int(bc.scheduler._next_chain_id)
	assert_eq(phase_before, BattlePhase.Kind.CLAIM)
	assert_eq(current_before, discarder)
	assert_eq(applied_before, 2, "前两 intent 各一条 ACTION_APPLIED")
	assert_eq(journal_before, 2)

	# seat3 PASS 收窗 → hook 把 phase→DRAW → engine.apply_ron 必须 false
	var r3: ActionResolution = bc.apply_action(
		_act("PASS", 3, hs, decision_id, {}, seq), ActionSource.HUMAN)

	# 当前 bug：_settle_ron 忽略 apply_ron bool → accepted/WIN/settled
	assert_false(r3.accepted,
		"engine.apply_ron 领域失败必须 accepted=false；error=%s" % str(r3.error_code))
	assert_eq(r3.error_code, ActionResolution.RULE_REJECTED,
		"reason/error_code 必须 RULE_REJECTED，实际=%s" % str(r3.error_code))

	# 领域失败事务回滚
	assert_eq(int(bc.state.phase), BattlePhase.Kind.CLAIM, "phase 必须回滚 CLAIM")
	assert_eq(int(bc.state.current_seat), discarder, "current_seat 仍为 discarder0")
	assert_false(bc._settled, "不得 settled")
	assert_eq(bc._last_event_type, last_event_before,
		"失败后 _last_event_type 必须完全恢复")
	assert_eq(int(bc.scheduler._next_chain_id), chain_id_before,
		"失败后 scheduler._next_chain_id 必须完全恢复")
	var win_after = bc.get("_active_window")
	assert_not_null(win_after, "失败后原 active_window 必须保留")
	if win_after != null:
		var win_a: DecisionWindow = win_after as DecisionWindow
		assert_eq(win_a.decision_id, decision_id, "decision_id 不得因失败换窗")
		assert_true(win_a.has_responded(1))
		assert_true(win_a.has_responded(2))
		assert_false(win_a.has_responded(3), "seat3 失败路径不得 has_responded")
		assert_false(win_a.is_complete())

	assert_eq(bc.events.size(), events_before, "events 与 before 完全相同（条数）")
	assert_eq(bc.action_journal().size(), journal_before, "journal 与 before 完全相同")
	assert_eq(_count_events(bc.events, "ACTION_APPLIED"), applied_before,
		"ACTION_APPLIED 与 before 完全相同")
	assert_eq(_count_events(bc.events, "RON_DECLARED"), 0, "不得残留 RON_DECLARED")
	assert_eq(_count_events(bc.events, "WIN_DECLARED"), 0, "不得残留 WIN_DECLARED")
	assert_false(bool(bc.state.ron_cancelled[1]), "不 cancel 路径 ron_cancelled[1] 必须 false")
