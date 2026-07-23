extends GutTest

# 麻将王 — M5 第 3 步：Run 流程 + 抽卡集成测试
#
# 模拟 RunFlow 的"战斗节点 → 抽卡 → 加进 deck"循环（不实例化 UI 控件，
# 直接调 Gacha.draw_node_single），验证：
#   1. Run 跑完后玩家 deck 被填充（≥1 张）
#   2. PityState 触发后下一抽必 EPIC+
#   3. MetaProgress 累计声望正确

const HARD_NODE_LIMIT: int = 100
const MetaProgressScript: GDScript = preload("res://meta/meta_progress.gd")
const SaveSystemScript: GDScript = preload("res://meta/save_system.gd")

var _mp_instance: Node = null


func _mp() -> Node:
	return _mp_instance


func before_each() -> void:
	_mp_instance = MetaProgressScript.new()
	add_child_autofree(_mp_instance)
	_mp_instance.reset()


func after_each() -> void:
	if is_instance_valid(_mp_instance) and _mp_instance.has_method("reset"):
		_mp_instance.reset()
	_mp_instance = null

# RunFlow 战斗节点结算后的核心逻辑：抽 1 张 → 记保底 → 加进 deck
func _hook_node_gacha(rs: RunState) -> GachaResult:
	var node_ref: NodeRef = rs.current_node_ref()
	var draw_seed: int = rs.run_seed * 1000 + (node_ref.index if node_ref else 0)
	var result: GachaResult = Gacha.draw_node_single(rs.pity_state, draw_seed)
	rs.pity_state.record_draw(result.rarity)
	if result.kind == GachaResult.KIND_TILE and result.tile_variant:
		rs.player_deck.add_tile_variant(result.tile_variant)
	elif result.kind == GachaResult.KIND_ABILITY and result.ability:
		rs.player_deck.add_ability(result.ability)
	return result

# 完整 Run：战斗节点用 BattleNodeRunner，占位用 from_placeholder；
# 战斗节点结算后自动给 1 抽（与 RunFlow._show_node_pack_open 同款逻辑）。
func _run_to_end_with_gacha(rs: RunState) -> Dictionary:
	var node_count := 0
	var draws := 0
	while not rs.finished and node_count < HARD_NODE_LIMIT:
		node_count += 1
		var opts: Array = rs.next_node_options()
		assert_gt(opts.size(), 0)
		var chosen: NodeRef = opts[0]
		rs.choose_next_node(chosen.index)
		var result: NodeResult
		if NodeKind.is_battle(chosen.kind):
			result = BattleNodeRunner.run_battle_to_node_result(rs.run_seed * 100 + chosen.index)
		else:
			result = NodeResult.from_placeholder()
		# 完成节点前先抽（与 RunFlow 顺序：complete_node → 战斗时 hook 抽卡）
		rs.complete_node(result)
		if NodeKind.is_battle(chosen.kind):
			_hook_node_gacha(rs)
			draws += 1
	return {"node_count": node_count, "draws": draws}

# ---- 完整 Run 跑通 + deck 被填充 ----

func test_run_completes_and_deck_grows():
	var rs := RunState.new(42)
	StarterPacks.apply_to(rs, &"starter_control")
	var stats := _run_to_end_with_gacha(rs)
	assert_true(rs.finished, "Run 应在节点上限内结束")
	# 至少打过 1 个战斗节点 → 至少 1 次抽卡
	assert_gt(stats.draws, 0, "至少 1 次战斗节点抽卡")
	# Deck 至少有 1 张牌或 1 个 ability（节点单抽 90% 牌 / 10% ability）
	var total: int = rs.player_deck.tile_variant_count() + rs.player_deck.ability_count()
	assert_gt(total, 0, "Run 跑完玩家 deck 应至少 1 项")

func test_run_with_multiple_seeds_each_grows_deck():
	for seed in [42, 7, 123]:
		var rs := RunState.new(seed)
		StarterPacks.apply_to(rs, &"starter_control")
		_run_to_end_with_gacha(rs)
		assert_true(rs.finished, "seed=%d 应结束" % seed)
		var total: int = rs.player_deck.tile_variant_count() + rs.player_deck.ability_count()
		assert_gt(total, 0, "seed=%d deck 应非空" % seed)

# ---- MetaProgress 累计 ----

func test_meta_progress_accumulates_after_run():
	var mp := _mp()
	assert_eq(mp.renown, 0)
	assert_eq(mp.runs_completed, 0)

	var rs := RunState.new(42)
	StarterPacks.apply_to(rs, &"starter_control")
	_run_to_end_with_gacha(rs)
	# Run 结束后调用 MetaProgress（模拟 RunFlow._on_run_*）
	mp.add_renown_for_run(rs.won)
	assert_eq(mp.runs_completed, 1)
	assert_gt(mp.renown, 0, "至少 +5 声望")
	if rs.won:
		assert_eq(mp.runs_won, 1)

func test_meta_progress_two_runs_compound():
	var mp := _mp()
	# Run 1
	mp.add_renown_for_run(false)  # +5
	# Run 2
	mp.add_renown_for_run(true)   # +50
	assert_eq(mp.runs_completed, 2)
	assert_eq(mp.runs_won, 1)
	assert_eq(mp.renown, MetaProgressScript.RENOWN_RUN_FAILED + MetaProgressScript.RENOWN_RUN_WON)

# ---- PityState 持久化 ----

func test_pity_state_persists_across_node_draws():
	var rs := RunState.new(42)
	# 8 次 COMMON record → 保底激活
	for i in range(8):
		rs.pity_state.record_draw(Rarity.Kind.COMMON)
	assert_true(rs.pity_state.node_single_pity_active())
	# 下次 draw_node_single 必 EPIC+
	var r: GachaResult = Gacha.draw_node_single(rs.pity_state, 999)
	assert_true(Rarity.is_epic_or_above(r.rarity), "保底激活时应出 EPIC+")

# ---- RunState save/load 保留 player_deck + pity_state ----

func test_save_load_preserves_player_deck_and_pity():
	var rs := RunState.new(42)
	# 注入一些数据
	var v := TileVariant.new(&"test_v", TileId.W5, Rarity.Kind.UNCOMMON)
	v.display_name = "测试牌"
	rs.player_deck.add_tile_variant(v)
	rs.pity_state.record_draw(Rarity.Kind.COMMON)
	rs.pity_state.record_draw(Rarity.Kind.UNCOMMON)

	var ss: Node = SaveSystemScript.new()
	add_child_autofree(ss)
	ss.clear_run()
	ss.save_run(rs)
	var loaded = ss.load_run()
	ss.clear_run()

	assert_not_null(loaded)
	assert_eq(loaded.player_deck.tile_variant_count(), 1)
	assert_eq(loaded.player_deck.get_tile_variant(TileId.W5).display_name, "测试牌")
	assert_eq(loaded.pity_state.node_single_no_epic_streak, 2)
