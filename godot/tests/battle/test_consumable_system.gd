extends GutTest

# 麻将王 — 消耗品系统全链路 TDD（无 mock）


# ============================================================
# 第 1 组：ConsumableItem 数据类
# ============================================================

func test_consumable_item_creation():
	var c := ConsumableItem.new(&"test_item", ConsumableItem.Kind.BATTLE, Rarity.Kind.EPIC)
	assert_eq(c.id, &"test_item")
	assert_eq(c.kind, ConsumableItem.Kind.BATTLE)
	assert_true(c.is_battle())

func test_consumable_item_serialization():
	var c := ConsumableItem.new(&"test_item", ConsumableItem.Kind.BATTLE, Rarity.Kind.COMMON)
	c.display_name = "测试道具"
	c.description = "测试用"
	var d := c.to_dict()
	var restored := ConsumableItem.from_dict(d)
	assert_eq(restored.id, &"test_item")
	assert_eq(restored.kind, ConsumableItem.Kind.BATTLE)
	assert_eq(restored.display_name, "测试道具")


# ============================================================
# 第 2 组：CardPool consumable pool
# ============================================================

func test_card_pool_has_consumables():
	var pool := CardPool.all_consumables()
	assert_gt(pool.size(), 0, "CardPool 应有消耗品")

func test_card_pool_battle_consumables():
	var battle := CardPool.consumables_by_kind(ConsumableItem.Kind.BATTLE)
	assert_gt(battle.size(), 0, "应有战斗消耗品")
	for c in battle:
		assert_true(c.is_battle())

func test_each_battle_consumable_has_hook():
	for c in CardPool.consumables_by_kind(ConsumableItem.Kind.BATTLE):
		assert_ne(c.hook_resource_path, "", "%s 应有 hook 路径" % c.id)


# ============================================================
# 第 3 组：ConsumableFactory 注入
# ============================================================

func test_factory_build_iron_shield():
	var sk := ConsumableFactory.build(&"iron_shield_v1")
	assert_not_null(sk)
	assert_true(sk.is_ability)
	assert_true(sk.owner_triggers.has(&"RON_DECLARED"))

func test_factory_build_wall_peek():
	var sk := ConsumableFactory.build(&"wall_peek_v1")
	assert_not_null(sk)
	assert_true(sk.owner_triggers.has(&"GAME_BEGIN"))

func test_factory_build_double_payout():
	var sk := ConsumableFactory.build(&"double_payout_v1")
	assert_not_null(sk)
	assert_true(sk.owner_triggers.has(&"WIN_DECLARED_PRE"))

func test_factory_inject_registers():
	var reg := SkillRegistry.new()
	var ok := ConsumableFactory.inject(reg, &"iron_shield_v1", 0)
	assert_true(ok)
	assert_eq(reg.get_all_entries().size(), 1)

func test_factory_inject_all():
	var reg := SkillRegistry.new()
	var ids: Array = [&"iron_shield_v1", &"wall_peek_v1", &"double_payout_v1", &"dora_charm_v1"]
	var n := ConsumableFactory.inject_all(reg, ids, 0)
	assert_eq(n, 4)
	assert_eq(reg.get_all_entries().size(), 4)

func test_factory_unknown_id_returns_false():
	var reg := SkillRegistry.new()
	var ok := ConsumableFactory.inject(reg, &"nonexistent_v1", 0)
	assert_false(ok)
	assert_eq(reg.get_all_entries().size(), 0)


# ============================================================
# 第 4 组：消耗品在真实战斗中触发
# ============================================================

func _anchor(tid: int, serial: int) -> TileSkillAnchor:
	return TileSkillAnchor.make(Tile.new(tid, false, Tile.NO_OWNER, serial), 0)

func test_iron_shield_cancels_all_rons_on_same_discard_then_consumes():
	# spec 2026-07-28 §3.1 / §2.2：铁盾保护一次完整放铳事件——
	# 同一弃牌的多家荣和全部取消；CLAIM 窗结束（下一次摸牌）后消耗。
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	ConsumableFactory.inject(reg, &"iron_shield_v1", 0)
	var protected := _anchor(TileId.W5, 900)
	sched.emit_event(BattleEvent.make(&"RON_DECLARED", 1, protected, {"discarder_seat": 0}))
	assert_true(st.ron_cancelled[1], "铁盾应取消第一家荣和")
	sched.emit_event(BattleEvent.make(&"RON_DECLARED", 2, protected, {"discarder_seat": 0}))
	assert_true(st.ron_cancelled[2], "同一弃牌的第二家荣和也应取消")
	var sk: SkillResource = reg.get_all_entries()[0]["skill"]
	assert_false(sk.consumed, "CLAIM 窗内保持保护，不提前消耗")
	sched.emit_event(BattleEvent.make(&"TILE_DRAWN", 1))
	assert_true(sk.consumed, "保护窗结束（下一次摸牌）后消耗")

func test_iron_shield_does_not_protect_later_discard():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	ConsumableFactory.inject(reg, &"iron_shield_v1", 0)
	sched.emit_event(BattleEvent.make(&"RON_DECLARED", 1, _anchor(TileId.W5, 900),
		{"discarder_seat": 0}))
	assert_true(st.ron_cancelled[1])
	# 之后另一张弃牌产生的荣和：保护已结束 → 不取消并消耗
	sched.emit_event(BattleEvent.make(&"RON_DECLARED", 2, _anchor(TileId.T3, 901),
		{"discarder_seat": 0}))
	assert_false(st.ron_cancelled[2], "另一弃牌的荣和不再受保护")
	var sk: SkillResource = reg.get_all_entries()[0]["skill"]
	assert_true(sk.consumed, "保护窗过后消耗")

func test_iron_shield_untriggered_stays_armed_and_ignores_others():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	ConsumableFactory.inject(reg, &"iron_shield_v1", 0)
	# 未触发前的摸牌 / 他家放铳不消耗
	sched.emit_event(BattleEvent.make(&"TILE_DRAWN", 0))
	sched.emit_event(BattleEvent.make(&"RON_DECLARED", 1, _anchor(TileId.W5, 900),
		{"discarder_seat": 2}))
	assert_false(st.ron_cancelled[1], "他家放铳不取消")
	var sk: SkillResource = reg.get_all_entries()[0]["skill"]
	assert_false(sk.consumed, "未触发时跨事件保持武装")
	# 触发保护后在本局结束（荒牌流局）时消耗
	sched.emit_event(BattleEvent.make(&"RON_DECLARED", 3, _anchor(TileId.S9, 902),
		{"discarder_seat": 0}))
	assert_true(st.ron_cancelled[3])
	sched.emit_event(BattleEvent.make(&"EXHAUSTIVE_DRAW", -1))
	assert_true(sk.consumed, "局末兜底消耗")

func test_wall_peek_reveals_on_game_begin():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	st.wall = Wall.new_full_set()
	st.wall.shuffle(42)
	st.wall.reserve_dead_wall(14)
	for i in range(4):
		st.seats.append(Seat.new(i, TileId.E))
	var sched := SkillScheduler.new(reg, st)
	ConsumableFactory.inject(reg, &"wall_peek_v1", 0)
	assert_eq(st.revealed_tiles.size(), 0)
	sched.emit_event(BattleEvent.make(&"GAME_BEGIN", 0))
	assert_eq(st.revealed_tiles.size(), 3, "千里眼应 reveal 3 张")

func test_double_payout_multiplies_han():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	ConsumableFactory.inject(reg, &"double_payout_v1", 0)
	var ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_eq(float(ctx.han_multipliers.get(0, 1.0)), 2.0, "倍率券应 ×2")
	# consumed 后不再触发
	var ctx2 := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_eq(float(ctx2.han_multipliers.get(0, 1.0)), 1.0, "consumed 后倍率回 1.0")

func test_dora_charm_adds_extra_dora():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	ConsumableFactory.inject(reg, &"dora_charm_v1", 0)
	sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_eq(st.extra_dora_count[0], 2, "宝牌护符应 +2 dora")


# ============================================================
# 第 5 组：道具 L0/L1 规则对齐批（2026-07-28 玩法设计 spec §3.1）
# ============================================================

func test_wall_collapse_removes_six_and_consumes():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	st.wall = Wall.new_full_set()
	st.wall.reserve_dead_wall(14)
	var sched := SkillScheduler.new(reg, st)
	ConsumableFactory.inject(reg, &"wall_collapse_v1", 0)
	var before := st.wall.live_wall_size()
	sched.emit_event(BattleEvent.make(&"GAME_BEGIN", 0))
	assert_eq(st.wall.live_wall_size(), before - 6, "牌墙崩塌应移除 6 张")
	var sk: SkillResource = reg.get_all_entries()[0]["skill"]
	assert_true(sk.consumed, "成功移除后应消耗")

func test_wall_collapse_rejects_when_wall_would_drop_below_14():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	st.wall = Wall.new_full_set()
	st.wall.reserve_dead_wall(14)
	while st.wall.live_wall_size() > 19:
		st.wall.draw()
	var sched := SkillScheduler.new(reg, st)
	ConsumableFactory.inject(reg, &"wall_collapse_v1", 0)
	sched.emit_event(BattleEvent.make(&"GAME_BEGIN", 0))
	assert_eq(st.wall.live_wall_size(), 19, "活牌墙将低于 14 张时应拒绝且不移除")
	var sk: SkillResource = reg.get_all_entries()[0]["skill"]
	assert_false(sk.consumed, "拒绝时不消耗")

func test_furiten_bomb_cancels_next_opponent_ron_then_consumes():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	ConsumableFactory.inject(reg, &"furiten_bomb_v1", 0)
	# 对手荣和不要求来自 owner 的舍牌
	sched.emit_event(BattleEvent.make(&"RON_DECLARED", 1, null, {"discarder_seat": 2}))
	assert_true(st.ron_cancelled[1], "振听炸弹应取消下一名对手的荣和")
	st.ron_cancelled[1] = false
	sched.emit_event(BattleEvent.make(&"RON_DECLARED", 1, null, {"discarder_seat": 2}))
	assert_false(st.ron_cancelled[1], "consumed 后不再触发")

func test_furiten_bomb_ignores_owner_ron_and_tsumo():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	ConsumableFactory.inject(reg, &"furiten_bomb_v1", 0)
	# owner 自己荣和不受影响
	sched.emit_event(BattleEvent.make(&"RON_DECLARED", 0, null, {"discarder_seat": 2}))
	assert_false(st.ron_cancelled[0], "owner 自己的荣和不取消")
	# 自摸（WIN_DECLARED_PRE）不触发、不消耗
	sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 1, null, {"is_tsumo": true}))
	var sk: SkillResource = reg.get_all_entries()[0]["skill"]
	assert_false(sk.consumed, "对自摸无效且不消耗")
	# 武装仍在：下一次对手荣和仍被取消
	sched.emit_event(BattleEvent.make(&"RON_DECLARED", 1, null, {"discarder_seat": 0}))
	assert_true(st.ron_cancelled[1], "武装保留到下一次对手荣和")


# ============================================================
# 第 6 组：道具 L2-score 计分上下文批（2026-07-28 spec §3.1 / §2.2 / §2.3）
# ============================================================

func test_double_payout_records_extra_han_cap_three():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	ConsumableFactory.inject(reg, &"double_payout_v1", 0)
	var ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_eq(float(ctx.han_multipliers.get(0, 1.0)), 2.0, "倍率仍 ×2")
	assert_eq(int(ctx.han_multiplier_extra_caps.get(0, -1)), 3, "额外番上限 3")

func test_apply_han_multiplier_caps_extra_and_skips_yakuman():
	var yl := YakuList.new()
	yl.add_yaku(&"riichi", 1)
	yl.add_yaku(&"chinitsu", 6)
	BattleController._apply_han_multiplier(yl, 2.0, 3)
	assert_eq(yl.total_han(), 10, "7 番 ×2 上限 +3 → 10 番")
	var yl2 := YakuList.new()
	yl2.add_yaku(&"riichi", 1)
	yl2.add_yaku(&"tsumo", 1)
	BattleController._apply_han_multiplier(yl2, 2.0, 3)
	assert_eq(yl2.total_han(), 4, "2 番 ×2 未触上限 → 4 番")
	var yl3 := YakuList.new()
	yl3.is_yakuman = true
	yl3.yakuman_multiplier = 1
	BattleController._apply_han_multiplier(yl3, 2.0, 3)
	assert_eq(yl3.total_han(), 0, "役满不放大")
	var yl4 := YakuList.new()
	yl4.add_yaku(&"riichi", 1)
	yl4.add_yaku(&"chinitsu", 6)
	BattleController._apply_han_multiplier(yl4, 2.0)
	assert_eq(yl4.total_han(), 14, "无上限调用保持原语义")

func test_point_shield_refunds_30_percent_of_ron_net_after_settle():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	ConsumableFactory.inject(reg, &"point_shield_v1", 0)
	var before_winner: int = st.scores[1]
	var before_owner: int = st.scores[0]
	# 荣和净得点 7700（payout 各付家正数之和，不含立直棒）→ 返还 2300（30% 向下取整到 100）
	sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 1, null, {
		"discarder_seat": 0, "is_tsumo": false,
		"payout": {0: 7700}, "points_won": 8700,
	}))
	assert_eq(st.scores[0], before_owner + 2300, "放铳者收回 30% 净得点")
	assert_eq(st.scores[1], before_winner - 2300, "从和牌者本次得点中转移")
	# consumed：第二次不再触发
	var w1: int = st.scores[1]
	sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 1, null, {
		"discarder_seat": 0, "is_tsumo": false, "payout": {0: 7700},
	}))
	assert_eq(st.scores[1], w1, "consumed 后不再触发")

func test_point_shield_ignores_other_discarder_and_tsumo():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	ConsumableFactory.inject(reg, &"point_shield_v1", 0)
	var snapshot: Array = st.scores.duplicate()
	# 他家放铳不触发
	sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 1, null, {
		"discarder_seat": 2, "is_tsumo": false, "payout": {2: 7700},
	}))
	# 自摸不触发（无放铳人）
	sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 1, null, {
		"is_tsumo": true, "payout": {0: 4000, 2: 2000, 3: 2000},
	}))
	assert_eq(st.scores, snapshot, "非 owner 放铳与自摸均不触发")
	var sk: SkillResource = reg.get_all_entries()[0]["skill"]
	assert_false(sk.consumed, "未触发不消耗")
