extends GutTest

# 麻将王 — M7：主循环 RON 自动检测端到端集成测试。
#
# 验证 BattleController 在 TILE_DISCARDED 之后自动遍历对家，按 atama-hane
# 顺序检测 ron。（以前只在外部 apply_ron 入口可达，run_to_end 主循环内部
# 没有 ron 路径。）

# 确定性 AI：遇到目标 TileId 即弃，否则弃手牌第 0 张
class _ForcePickAi extends SimpleAi:
	var _target_id: int = -1
	func _init(target_id: int = -1) -> void:
		super(0)
		_target_id = target_id
	func decide_discard(seat: Seat) -> Tile:
		var hand_tiles: Array = seat.hand._tiles
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
	# 替换为确定性 AI：4 家都倾向弃 W9（discarder=0 案例下让 seat 0 必弃 W9）
	_bc.ai = _ForcePickAi.new(TileId.W9)

# ---- helper: 给 seat 装 7 对子听 W9 单骑 ----
func _set_chiitoi_tenpai_for(seat_idx: int) -> void:
	var tenpai_ids: Array = [
		TileId.W1, TileId.W1, TileId.W2, TileId.W2, TileId.W3, TileId.W3,
		TileId.W5, TileId.W5, TileId.W6, TileId.W6, TileId.W7, TileId.W7,
		TileId.W9,
	]
	var s: Seat = _bc.state.seats[seat_idx]
	s.hand._tiles.clear()
	for tid in tenpai_ids:
		s.hand.add(Tile.new(tid))

# helper: seat 0 hand = 13 random non-winning + 让它摸到 W9 后弃 W9
func _setup_seat0_to_discard_w9() -> void:
	# seat 0 hand = 13 张不能胡的杂牌（多 ID，避免成对／成顺）
	var noise: Array = [
		TileId.W2, TileId.W3, TileId.W4, TileId.W6, TileId.W8,
		TileId.T1, TileId.T2, TileId.T3, TileId.T4, TileId.T5,
		TileId.E, TileId.S_WIND, TileId.W_WIND,
	]
	var s0: Seat = _bc.state.seats[0]
	s0.hand._tiles.clear()
	for tid in noise:
		s0.hand.add(Tile.new(tid))
	# wall 顶牌 = W9，seat 0 摸到后 _ForcePickAi 会找 W9 弃出
	_bc.state.wall._tiles[_bc.state.wall._draw_index] = Tile.new(TileId.W9)

# ---- 路径 1: discarder=0 弃 W9，seat 1 自动 RON ----

func test_auto_ron_fires_on_tenpai_opponent():
	_set_chiitoi_tenpai_for(1)
	_setup_seat0_to_discard_w9()

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
	_set_chiitoi_tenpai_for(1)
	_set_chiitoi_tenpai_for(2)
	_setup_seat0_to_discard_w9()

	var result: Dictionary = _bc.run_to_end()
	var win_ev: BattleEvent = result.events[result.events.size() - 1]
	assert_eq(win_ev.actor_seat, 1, "atama-hane 优先 seat 1（discarder+1）")

# ---- 路径 3: 振听对家不能 ron ----

func test_auto_ron_skips_furiten_seat():
	_set_chiitoi_tenpai_for(1)
	_set_chiitoi_tenpai_for(2)
	_bc.state.seats[1].furiten.permanent = true
	_setup_seat0_to_discard_w9()

	var result: Dictionary = _bc.run_to_end()
	assert_eq(result.last_event, &"WIN_DECLARED")
	var win_ev: BattleEvent = result.events[result.events.size() - 1]
	assert_eq(win_ev.actor_seat, 2, "振听 seat 1 跳过；seat 2 取 ron")

# ---- 路径 4: 没人听 → 正常流转 ----

func test_no_auto_ron_when_no_tenpai_opponent():
	# 不设 tenpai；用默认 SimpleAi（保留 _ForcePickAi 也行，反正没人 ron）
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
	_set_chiitoi_tenpai_for(1)
	_set_chiitoi_tenpai_for(2)

	var sk := SkillResource.new()
	sk.id = &"_test_cancel_seat1_v1"
	sk.is_ability = true
	var ot: Array[StringName] = [&"RON_DECLARED"]
	sk.owner_triggers = ot
	sk.hook_script = _SelfCancelRonHook
	_bc.registry.register(sk, 1)

	_setup_seat0_to_discard_w9()

	var result: Dictionary = _bc.run_to_end()
	assert_eq(result.last_event, &"WIN_DECLARED")
	var win_ev: BattleEvent = result.events[result.events.size() - 1]
	assert_eq(win_ev.actor_seat, 2, "seat 1 ron 被 cancel → fallback seat 2")

# ---- 路径 6: HOUTEI 自动判定（wall 空时的 ron）----

func test_auto_ron_houtei_emit_when_wall_empty():
	_set_chiitoi_tenpai_for(1)
	# 把 wall draw_index 推到 size==1，下次 draw 是最后一张 live tile = W9
	_setup_seat0_to_discard_w9()
	var w: Wall = _bc.state.wall
	# 重写 draw_index 让 live_wall_size() = 1（仅剩 1 张可摸 = 即将 W9）
	var current_live: int = w.live_wall_size()
	w._draw_index += (current_live - 1)
	# 重新设置最后一张 = W9（之前 setup 已设但 index 移动后位置变了）
	w._tiles[w._draw_index] = Tile.new(TileId.W9)

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
