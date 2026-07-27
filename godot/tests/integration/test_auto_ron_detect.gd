extends GutTest

# 麻将王 — M7 / E2-02：AI RON 统一 Action 端到端集成测试。
# 牌实体全部来自同一真实 Wall；AI 经 DecisionWindow → Action.ron → apply_action，
# 不使用旧自动荣和旁路、无 iid Tile.new 或物理上不可能的重复手牌。

# 确定性 AI：遇到目标 TileId 即弃，否则弃手牌第 0 张
class _ForcePickAi extends SimpleAi:
	var _target_id: int = -1
	func _init(target_id: int = -1) -> void:
		super(0)
		_target_id = target_id
	func decide_discard(seat: Seat) -> Tile:
		var hand_tiles: Array = seat.hand.tiles()
		if hand_tiles.is_empty():
			return null
		if _target_id >= 0:
			for t in hand_tiles:
				if t.id == _target_id:
					return t
		return hand_tiles[0]

var _bc: BattleController

func before_each() -> void:
	_bc = BattleController.new(42, 0)
	_prepare_live_fixture()
	# 4 家都倾向弃 W9；seat 0 下一摸固定为 W9。
	_bc.ai = _ForcePickAi.new(TileId.W9)

func _prepare_live_fixture() -> void:
	for seat_id in range(4):
		var seat: Seat = _bc.state.seats[seat_id]
		seat.hand = Hand.new()
		seat.melds.restore([], 0)
		seat.last_drawn_instance_id = Tile.INVALID_INSTANCE_ID
		seat.furiten = FuritenState.new()
		_bc.state.seats[seat_id].river.restore([])
	_bc.state.wall.set_draw_index(0)
	_bc.state.current_seat = 0
	_bc.state.phase = BattlePhase.Kind.DRAW
	_bc.state.first_round_active = false


func _live_end() -> int:
	return _bc.state.wall.authority_tiles().size() - _bc.state.wall.dead_wall_size()


func _take_live(tid: int) -> Tile:
	var wall: Wall = _bc.state.wall
	var found := -1
	for i in range(wall.draw_index(), _live_end()):
		if int((wall.authority_tiles()[i] as Tile).id) == tid:
			found = i
			break
	assert_gte(found, wall.draw_index(), "live 区须存在 tile_id=%d" % tid)
	if found < wall.draw_index():
		return null
	assert_true(wall.move_live_index_to_top(found))
	var tile: Tile = wall.draw()
	assert_not_null(tile)
	assert_true(Tile.is_instance_id_in_hand_seq(tile.instance_id, _bc.state.hand_seq))
	return tile


func _take_any_except(excluded_ids: Array) -> Tile:
	var wall: Wall = _bc.state.wall
	for i in range(wall.draw_index(), _live_end()):
		var tile: Tile = wall.authority_tiles()[i]
		if not excluded_ids.has(int(tile.id)):
			assert_true(wall.move_live_index_to_top(i))
			return wall.draw()
	return null


func _hand_from_live(ids: Array) -> Hand:
	var hand := Hand.new()
	for tid in ids:
		var tile: Tile = _take_live(int(tid))
		assert_not_null(tile)
		if tile != null:
			assert_true(hand.add(tile))
	return hand


func _fill_hand_without_w9() -> Hand:
	var hand := Hand.new()
	while hand.size() < 13:
		var tile: Tile = _take_any_except([TileId.W9])
		assert_not_null(tile)
		if tile == null:
			break
		assert_true(hand.add(tile))
	return hand


func _seat0_noise_ids() -> Array:
	return [
		TileId.S1, TileId.S2, TileId.S4, TileId.S5, TileId.S7, TileId.S8,
		TileId.T7, TileId.T8, TileId.E, TileId.S_WIND, TileId.W_WIND,
		TileId.N, TileId.CHUN,
	]


func _chiitoi_w_tenpai() -> Array:
	return [
		TileId.W1, TileId.W1, TileId.W2, TileId.W2, TileId.W3, TileId.W3,
		TileId.W4, TileId.W4, TileId.W5, TileId.W5, TileId.W6, TileId.W6,
		TileId.W9,
	]


func _chiitoi_t_tenpai() -> Array:
	return [
		TileId.T1, TileId.T1, TileId.T2, TileId.T2, TileId.T3, TileId.T3,
		TileId.T4, TileId.T4, TileId.T5, TileId.T5, TileId.T6, TileId.T6,
		TileId.W9,
	]


func _set_next_draw_w9() -> Tile:
	var wall: Wall = _bc.state.wall
	var found := -1
	for i in range(wall.draw_index(), _live_end()):
		if int((wall.authority_tiles()[i] as Tile).id) == TileId.W9:
			found = i
			break
	assert_gte(found, wall.draw_index(), "须保留一张真实 W9 供 seat0 下一摸")
	if found < wall.draw_index():
		return null
	assert_true(wall.move_live_index_to_top(found))
	return wall.authority_tiles()[wall.draw_index()]


## winners: seat → 13 张听牌 ids；其余对手设永久振听，避免 fixture 偶然抢胡。
func _setup_first_discard(winners: Dictionary) -> void:
	_bc.state.seats[0].hand = _hand_from_live(_seat0_noise_ids())
	for seat_id in range(1, 4):
		if winners.has(seat_id):
			_bc.state.seats[seat_id].hand = _hand_from_live(winners[seat_id])
		else:
			_bc.state.seats[seat_id].hand = _fill_hand_without_w9()
			_bc.state.seats[seat_id].furiten.permanent = true
	var next: Tile = _set_next_draw_w9()
	assert_not_null(next)
	if next != null:
		assert_eq(int(next.id), TileId.W9)


func _drain_live_until_only_next_w9() -> void:
	var wall: Wall = _bc.state.wall
	var next: Tile = _set_next_draw_w9()
	assert_not_null(next)
	if next == null:
		return
	var last_live := _live_end() - 1
	assert_true(wall.swap_live_indices(last_live, wall.draw_index()))
	while wall.live_wall_size() > 1:
		assert_not_null(wall.draw())
	assert_eq(wall.live_wall_size(), 1)
	assert_eq(int((wall.peek_next_draw() as Tile).id), TileId.W9)

# ---- 路径 1: discarder=0 弃 W9，seat 1 自动 RON ----

func test_auto_ron_fires_on_tenpai_opponent():
	_setup_first_discard({1: _chiitoi_w_tenpai()})

	var result: Dictionary = _bc.run_to_end()
	assert_eq(result.last_event, &"WIN_DECLARED",
		"对家 ron 后最末事件应为 WIN_DECLARED，实际：%s" % result.last_event)
	var win_ev: BattleEvent = result.events[result.events.size() - 1]
	assert_eq(win_ev.actor_seat, 1, "atama-hane: discarder=0 → 最近对家 = seat 1")

	# 中间应有 RON_DECLARED
	var has_ron := false
	for ev in result.events:
		if ev.type == &"RON_DECLARED":
			has_ron = true
			assert_eq(ev.actor_seat, 1)
			assert_eq(int(ev.extra.get("discarder_seat", -1)), 0)
	assert_true(has_ron, "应当 emit 至少一次 RON_DECLARED")

# ---- 路径 2: atama-hane 顺序（seat 1 在 seat 2 之前优先）----

func test_auto_ron_atama_hane_order_seat_1_priority_over_2():
	_setup_first_discard({1: _chiitoi_w_tenpai(), 2: _chiitoi_t_tenpai()})

	var result: Dictionary = _bc.run_to_end()
	var win_ev: BattleEvent = result.events[result.events.size() - 1]
	assert_eq(win_ev.actor_seat, 1, "atama-hane 优先 seat 1（discarder+1）")

# ---- 路径 3: 振听对家不能 ron ----

func test_auto_ron_skips_furiten_seat():
	_setup_first_discard({1: _chiitoi_w_tenpai(), 2: _chiitoi_t_tenpai()})
	_bc.state.seats[1].furiten.permanent = true

	var result: Dictionary = _bc.run_to_end()
	assert_eq(result.last_event, &"WIN_DECLARED")
	var win_ev: BattleEvent = result.events[result.events.size() - 1]
	assert_eq(win_ev.actor_seat, 2, "振听 seat 1 跳过；seat 2 取 ron")

# ---- 路径 4: 没人听 → 正常流转 ----

func test_no_auto_ron_when_no_tenpai_opponent():
	_setup_first_discard({})
	# 不设 tenpai；三家永久振听，第一弃无人可荣后继续到自然终局。
	var result: Dictionary = _bc.run_to_end()
	var allowed: Array = [&"EXHAUSTIVE_DRAW", &"WIN_DECLARED"]
	assert_true(allowed.has(result.last_event))

# ---- 路径 5: cancel_ron fallback 到下一候选 ----

class _SelfCancelRonHook extends SkillHook:
	# 当 actor=本 ability owner 时 cancel — 用于让 seat 1 ron 失败
	func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
		if event.actor_seat != ctx.beneficiary_seat:
			return
		ctx.cancel_ron(event.actor_seat)

func test_auto_ron_cancelled_falls_back_to_next_seat():
	_setup_first_discard({1: _chiitoi_w_tenpai(), 2: _chiitoi_t_tenpai()})

	var sk := SkillResource.new()
	sk.id = &"_test_cancel_seat1_v1"
	sk.is_ability = true
	var ot: Array[StringName] = [&"RON_DECLARED"]
	sk.owner_triggers = ot
	sk.hook_script = _SelfCancelRonHook
	_bc.registry.register(sk, 1)

	var result: Dictionary = _bc.run_to_end()
	assert_eq(result.last_event, &"WIN_DECLARED")
	var win_ev: BattleEvent = result.events[result.events.size() - 1]
	assert_eq(win_ev.actor_seat, 2, "seat 1 ron 被 cancel → fallback seat 2")

# ---- 路径 6: HOUTEI 自动判定（wall 空时的 ron）----

func test_auto_ron_houtei_emit_when_wall_empty():
	_setup_first_discard({1: _chiitoi_w_tenpai()})
	_drain_live_until_only_next_w9()

	var result: Dictionary = _bc.run_to_end()
	# seat 1 ron W9 → houtei；最末是 WIN_DECLARED
	assert_eq(result.last_event, &"WIN_DECLARED")
	# 应 emit HOUTEI（在 RON_DECLARED 之后、WIN_DECLARED_PRE 之前）
	var has_houtei := false
	for ev in result.events:
		if ev.type == &"HOUTEI":
			has_houtei = true
			assert_eq(ev.actor_seat, 1)
	assert_true(has_houtei, "wall 空时 ron 应 emit HOUTEI 事件")
