extends GutTest

# 麻将王 — 遗物系统全链路 TDD

func test_relic_item_creation():
	var r := RelicItem.new(&"relic_lucky_cat_v1", Rarity.Kind.UNCOMMON)
	r.display_name = "招财猫"
	assert_eq(r.id, &"relic_lucky_cat_v1")
	assert_eq(r.rarity, Rarity.Kind.UNCOMMON)

func test_relic_serialization():
	var r := RelicItem.new(&"relic_test", Rarity.Kind.EPIC)
	r.display_name = "测试遗物"
	r.description = "测试用"
	var d := r.to_dict()
	var restored := RelicItem.from_dict(d)
	assert_eq(restored.id, &"relic_test")
	assert_eq(restored.display_name, "测试遗物")

func test_card_pool_has_relics():
	# 4 初版 + M12 8 个新遗物
	var pool: Array = CardPool.all_relics()
	assert_eq(pool.size(), 12, "应有 12 个遗物")

func test_relic_factory_build():
	var sk: SkillResource = RelicFactory.build(&"relic_lucky_cat_v1")
	assert_not_null(sk)
	assert_true(sk.is_ability)
	assert_true(sk.owner_triggers.has(&"WIN_DECLARED_PRE"))

func test_relic_factory_inject():
	var reg := SkillRegistry.new()
	var ok := RelicFactory.inject(reg, &"relic_lucky_cat_v1", 0)
	assert_true(ok)
	assert_eq(reg.get_all_entries().size(), 1)

func test_relic_lucky_cat_adds_dora():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	RelicFactory.inject(reg, &"relic_lucky_cat_v1", 0)
	sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_eq(st.extra_dora_count[0], 1, "招财猫应 +1 dora")
	# 遗物不消耗——第二次也触发
	sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_eq(st.extra_dora_count[0], 2, "遗物永久——再 +1")

func test_relic_iron_will_reduces_han():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	RelicFactory.inject(reg, &"relic_iron_will_v1", 0)
	var ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 1, null, {"discarder_seat": 0}))
	assert_eq(int(ctx.han_deltas.get(1, 0)), -1, "铁壁意志应给对手 -1 番")

func test_relic_soul_mirror_transfers_5_percent_of_points_won():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	RelicFactory.inject(reg, &"relic_soul_mirror_v1", 0)
	var before_0: int = st.scores[0]
	var before_1: int = st.scores[1]
	# 对手本次实际得点 8000 → 5% = 400（向下取整到 100）
	sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 1, null, {"points_won": 8000}))
	assert_eq(st.scores[0], before_0 + 400, "魂镜按本次得点 5% 转移")
	assert_eq(st.scores[1], before_1 - 400)
	# 取整：3900 * 5% = 195 → 100
	sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 1, null, {"points_won": 3900}))
	assert_eq(st.scores[0], before_0 + 400 + 100, "向下取整到 100 点")
	# owner 自己胡牌不转移
	var s0: int = st.scores[0]
	sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 0, null, {"points_won": 8000}))
	assert_eq(st.scores[0], s0, "owner 自己胡牌不触发")


# ============================================================
# 道具 L0/L1 规则对齐批（2026-07-28 玩法设计 spec §4.1 / §2.3）
# ============================================================

func _tile(tid: int, serial: int) -> Tile:
	return Tile.new(tid, false, Tile.NO_OWNER, serial)

func test_relic_red_string_requires_concealed_hand():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	for i in range(4):
		st.seats.append(Seat.new(i, TileId.E))
	var sched := SkillScheduler.new(reg, st)
	RelicFactory.inject(reg, &"relic_red_string_v1", 0)
	# 门清（无副露）→ +1 赤 Dora
	sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_eq(st.extra_red_dora_count[0], 1, "门清胡牌应 +1 赤 Dora")
	# 副露（碰）→ 不触发；meld_id 编码为 local_index*4+seat_id（seat 0 → 0）
	var pon_tiles: Array[Tile] = [
		_tile(TileId.W5, 1), _tile(TileId.W5, 2), _tile(TileId.W5, 3),
	]
	var pon: Meld = Meld.make_pon(pon_tiles, 1, 0)
	assert_true(st.seats[0].melds.restore([pon], 1), "测试副露必须成功装入")
	sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_eq(st.extra_red_dora_count[0], 1, "副露手不触发红线")

func test_relic_comeback_crown_strict_lowest_two_tied_one():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	RelicFactory.inject(reg, &"relic_comeback_crown_v1", 0)
	# 严格最低 → +2
	st.scores = [10000, 30000, 30000, 30000]
	var ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_eq(int(ctx.han_deltas.get(0, 0)), 2, "严格最低分 +2 番")
	# 并列最低 → +1
	st.scores = [10000, 10000, 40000, 40000]
	var ctx2 := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_eq(int(ctx2.han_deltas.get(0, 0)), 1, "并列最低分 +1 番")
	# 不是最低 → 0
	st.scores = [30000, 10000, 30000, 30000]
	var ctx3 := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_eq(int(ctx3.han_deltas.get(0, 0)), 0, "非最低不加番")

func test_negative_skill_han_delta_clamped_to_min_one_han():
	# spec §2.3：负番防御只减少计分番，最终计分番最低为 1
	var yl := YakuList.new()
	yl.add_yaku(&"riichi", 1)
	BattleController._apply_skill_han_delta(yl, -3)
	assert_eq(yl.total_han(), 1, "最终计分番最低为 1")
	var yl2 := YakuList.new()
	yl2.add_yaku(&"riichi", 1)
	yl2.add_yaku(&"tsumo", 1)
	yl2.add_yaku(&"pinfu", 1)
	BattleController._apply_skill_han_delta(yl2, -2)
	assert_eq(yl2.total_han(), 1, "3 番 -2 应剩 1 番")
	var yl3 := YakuList.new()
	yl3.add_yaku(&"riichi", 1)
	yl3.dora_count = 2
	BattleController._apply_skill_han_delta(yl3, -2)
	assert_eq(yl3.total_han(), 1, "含 Dora 也按总计分番钳制到 1")


func test_relic_dragon_seal_requires_dragon_triplet_yaku():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	RelicFactory.inject(reg, &"relic_dragon_seal_v1", 0)
	var ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0, null,
		{"yaku_ids": [YakuId.RIICHI, YakuId.YAKUHAI_HAKU]}))
	assert_eq(int(ctx.han_deltas.get(0, 0)), 1, "含白刻子役 +1 番")
	var ctx2 := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0, null,
		{"yaku_ids": [YakuId.YAKUHAI_HAKU, YakuId.YAKUHAI_HATSU, YakuId.YAKUHAI_CHUN]}))
	assert_eq(int(ctx2.han_deltas.get(0, 0)), 1, "多种三元牌单件仍只 +1")
	var ctx3 := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0, null,
		{"yaku_ids": [YakuId.RIICHI, YakuId.TANYAO]}))
	assert_eq(int(ctx3.han_deltas.get(0, 0)), 0, "无三元牌役不触发")

func test_relic_wind_charm_requires_wind_yaku_once():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	RelicFactory.inject(reg, &"relic_wind_charm_v1", 0)
	var ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0, null,
		{"yaku_ids": [YakuId.YAKUHAI_BAKAZE]}))
	assert_eq(int(ctx.han_deltas.get(0, 0)), 1, "场风役 +1 番")
	var ctx2 := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0, null,
		{"yaku_ids": [YakuId.YAKUHAI_BAKAZE, YakuId.YAKUHAI_JIKAZE]}))
	assert_eq(int(ctx2.han_deltas.get(0, 0)), 1, "连风牌单件仍只 +1")
	var ctx3 := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0, null,
		{"yaku_ids": [YakuId.RIICHI]}))
	assert_eq(int(ctx3.han_deltas.get(0, 0)), 0, "无风役不触发")

func _add_tiles(seat: Seat, ids: Array, base_serial: int) -> void:
	for i in range(ids.size()):
		seat.add_to_hand(Tile.new(ids[i], false, Tile.NO_OWNER, base_serial + i))

func test_relic_patience_stone_pays_1000_only_when_tenpai():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	for i in range(4):
		st.seats.append(Seat.new(i, TileId.E))
	var sched := SkillScheduler.new(reg, st)
	RelicFactory.inject(reg, &"relic_patience_stone_v1", 0)
	# owner 听牌：123m456m789m123s + 5p 单骑
	_add_tiles(st.seats[0], [
		TileId.W1, TileId.W2, TileId.W3, TileId.W4, TileId.W5, TileId.W6,
		TileId.W7, TileId.W8, TileId.W9, TileId.S1, TileId.S2, TileId.S3,
		TileId.T5,
	], 1)
	var before: int = st.scores[0]
	sched.emit_event(BattleEvent.make(&"EXHAUSTIVE_DRAW", -1))
	assert_eq(st.scores[0], before + 1000, "荒牌流局听牌 +1000")

func test_relic_patience_stone_noten_gets_nothing():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	for i in range(4):
		st.seats.append(Seat.new(i, TileId.E))
	var sched := SkillScheduler.new(reg, st)
	RelicFactory.inject(reg, &"relic_patience_stone_v1", 0)
	# owner 未听牌（散张 + 孤立字牌，向听数 ≥ 2；注意全幺九 13 张会构成国士听牌）
	_add_tiles(st.seats[0], [
		TileId.W2, TileId.W5, TileId.W8, TileId.T2, TileId.T5, TileId.T8,
		TileId.S2, TileId.S5, TileId.S8, TileId.E, TileId.S_WIND,
		TileId.W_WIND, TileId.HAKU,
	], 1)
	var before: int = st.scores[0]
	sched.emit_event(BattleEvent.make(&"EXHAUSTIVE_DRAW", -1))
	assert_eq(st.scores[0], before, "未听牌不获得忍石奖励")

func test_win_declared_pre_carries_yaku_ids_readonly_context():
	for seed_value in range(1, 41):
		var bc := BattleController.new(seed_value, 0, true)
		var result: Dictionary = bc.run_to_end()
		for value in result.events:
			var event := value as BattleEvent
			if event.type == &"WIN_DECLARED_PRE":
				assert_true(event.extra.has("yaku_ids"),
					"WIN_DECLARED_PRE 应携带 yaku_ids 只读上下文")
				var ids: Array = event.extra["yaku_ids"]
				assert_gt(ids.size(), 0, "胡牌至少 1 个役")
				return
	fail_test("40 个 seed 内应至少出现一次胡牌")
