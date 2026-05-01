extends GutTest

# 里程碑 2 — 端到端集成测试。
# 验证 BattleController 把 TurnEngine + SkillScheduler + 规则引擎串成可跑的一局。

var _bc: BattleController

func before_each() -> void:
	_bc = BattleController.new(42, 0)

# ---- 路径 A：跑到底不崩 ----
# 4 家随机 SimpleAI 弃牌；预期最末事件是流局或自摸（自摸概率极低，但允许）；
# 不应 crash；scores 总和守恒；event_chain_depth 在 emit 之间归零。
func test_path_a_runs_full_hand_without_crash() -> void:
	var result: Dictionary = _bc.run_to_end()

	var allowed: Array = [&"EXHAUSTIVE_DRAW", &"WIN_DECLARED"]
	assert_true(allowed.has(result.last_event),
		"最末事件应是流局或胡牌，实际：%s" % result.last_event)

	var total: int = 0
	for s in _bc.state.scores:
		total += s
	assert_eq(total, 100000, "scores 总和应守恒为 100000")

	assert_eq(_bc.state.event_chain_depth, 0,
		"事件链深度在 run_to_end 退出时应归零")

	assert_gt(result.events.size(), 0, "至少要有一个事件被 emit")
	assert_eq(result.events[0].type, &"GAME_BEGIN",
		"首事件必须是 GAME_BEGIN")

# ---- 路径 B：自摸结算 ----
# 构造确定 fixture：seat 0（庄）手 13 张是七対子听 W9 单骑；
# 把 wall 顶牌换成 W9 → seat 0 第一次摸即自摸。
# 验证最末事件 = WIN_DECLARED、winner_seat=0、han > 0、payout 不空。
func test_path_b_tsumo_settles_with_payout() -> void:
	# 七対子听 W9：m1m1 m2m2 m3m3 m5m5 m6m6 m7m7 m9
	var tenpai_ids: Array = [
		TileId.W1, TileId.W1, TileId.W2, TileId.W2, TileId.W3, TileId.W3,
		TileId.W5, TileId.W5, TileId.W6, TileId.W6, TileId.W7, TileId.W7,
		TileId.W9,
	]
	var seat0: Seat = _bc.state.seats[0]
	seat0.hand._tiles.clear()
	for tid in tenpai_ids:
		seat0.hand.add(Tile.new(tid))

	# 让 wall 下一张可摸 = W9
	var w: Wall = _bc.state.wall
	w._tiles[w._draw_index] = Tile.new(TileId.W9)

	# dealer = 0、current_seat = 0；第一次进入循环就是 seat 0 的 DRAW
	var result: Dictionary = _bc.run_to_end()

	assert_eq(result.last_event, &"WIN_DECLARED",
		"自摸命中后最末事件应为 WIN_DECLARED，实际：%s" % result.last_event)
	var win_event: BattleEvent = result.events[result.events.size() - 1]
	assert_eq(win_event.actor_seat, 0, "胡牌座位应为 0")
	var extra: Dictionary = win_event.extra
	assert_true(extra.has("payout"), "WIN_DECLARED.extra 必含 payout 字典")
	assert_true(extra.has("winner_seat"), "WIN_DECLARED.extra 必含 winner_seat")
	assert_eq(extra.winner_seat, 0)
	assert_gt(extra.han, 0, "han 应为正（七対子至少 2 番）")
	assert_gt(extra.payout.size(), 0, "payout 至少含 1 个支付者")

# ---- 路径 C：荣胡 — owner / holder 归属 ----
# 玩家 seat 0 听 W9（同 path B 七対子），但这次由 seat 1 弃出 W9 → 荣胡。
# 验证 BattleEvent.tile_instance.owner_seat = 弃牌人座（1） ≠ actor_seat（胡牌人=0）。
# 这条断言钉住「owner = 牌的来源 / actor = 这次事件的主体」语义区分。
func test_path_c_ron_owner_holder_distinction() -> void:
	var tenpai_ids: Array = [
		TileId.W1, TileId.W1, TileId.W2, TileId.W2, TileId.W3, TileId.W3,
		TileId.W5, TileId.W5, TileId.W6, TileId.W6, TileId.W7, TileId.W7,
		TileId.W9,
	]
	var seat0: Seat = _bc.state.seats[0]
	seat0.hand._tiles.clear()
	for tid in tenpai_ids:
		seat0.hand.add(Tile.new(tid))

	# seat 1 弃出 W9（构造 Tile 携带 owner=1）
	var ron_tile := Tile.new(TileId.W9)
	var ok: bool = _bc.apply_ron(0, ron_tile, 1)

	assert_true(ok, "apply_ron 应成立")
	assert_eq(_bc._last_event_type, &"WIN_DECLARED",
		"apply_ron 成功后最末事件应为 WIN_DECLARED")
	var win_event: BattleEvent = _bc.events[_bc.events.size() - 1]
	assert_eq(win_event.actor_seat, 0, "actor 是胡牌人")
	assert_ne(win_event.tile_instance.owner_seat, win_event.actor_seat,
		"owner（弃牌人 1）必须 ≠ actor（胡牌人 0）— 这是 spec §3.1 的 owner/holder 区分核心")
	assert_eq(win_event.tile_instance.owner_seat, 1, "owner 应等于弃牌人座 1")

	# 中间也应有一条 RON_DECLARED 事件（emit 在 settle 之前，给技能拦截窗口）
	var has_ron_event := false
	for ev in _bc.events:
		if ev.type == &"RON_DECLARED":
			assert_eq(ev.actor_seat, 0, "RON_DECLARED actor 也是胡牌人")
			assert_eq(ev.tile_instance.owner_seat, 1, "RON_DECLARED owner 也是弃牌人")
			has_ron_event = true
	assert_true(has_ron_event, "结算前必须 emit 一次 RON_DECLARED")
