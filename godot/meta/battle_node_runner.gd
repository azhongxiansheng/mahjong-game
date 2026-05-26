class_name BattleNodeRunner

# 麻将王 — 里程碑 4 第 4 步：战斗节点纯逻辑封装
#
# 把 east_round_e2e_smoke 里的"驱动 GameDriver 跑完整场东风战 + 算 viewer
# 排名"逻辑提取成可复用的纯函数。RunFlow / GUT integration test 都能调。
#
# 不持 UI 引用，方便单测；显示层（4 人桌）由调用方决定是否实例化。
#
# v1 同步跑：调用阻塞直到东风战结束。M5/M6 想要"边跑边显示"时改 await + frame yield。

const HAND_LIMIT: int = 60  # M8: 半庄 8 局 × ~7.5 倍连庄余量；东风战 4 局通常远低于
const VIEWER_SEAT: int = 0  # 玩家固定 seat 0
const HANDS_PER_ROUND: int = 4  # M8: 一个风圈 4 局（东 1-4 / 南 1-4）

# 跑一整场东风战，返 NodeResult（已含 viewer 排名 / hp_delta / final_scores）。
# seed 决定洗牌；node_index 通常作为 seed 偏移避免同 Run 内不同节点重复牌局。
#
# boss_id（plan-6 C，M6 收尾）：传非空 StringName 时，每局开始把对应 Boss 能力
# inject 到 BattleController 的 SkillRegistry（默认 AI seat 1）。若 boss_id
# 未在 BossAbilityFactory 注册或 CardPool 找不到，本调用静默 fallback 到
# 普通对局（不 inject）。
static func run_battle_to_node_result(seed: int, boss_id: StringName = &"", player_ability_ids: Array = [], use_heuristic_ai: bool = false, player_tile_variants: Dictionary = {}, tiebreak_seed: int = 0, ai_abilities_seed: int = 0, session_kind: String = "east_round", use_shanten_ai: bool = false, player_consumable_ids: Array = [], player_relic_ids: Array = []) -> NodeResult:
	return run_battle_with_stats(seed, boss_id, player_ability_ids, use_heuristic_ai, player_tile_variants, tiebreak_seed, ai_abilities_seed, session_kind, use_shanten_ai, player_consumable_ids, player_relic_ids).node_result

# M7 D4：扩展版本，附带 hand-level 统计（plan-7 D6 simulation 假设 B 用）。
# 返：
#   {
#     node_result: NodeResult,
#     hand_outcomes: {tsumo: int, ron: int, exhaustive_draw: int},
#     final_scores: Array[int]（4 seats），
#     hand_count: int（实际跑了几局）
#   }
static func run_battle_with_stats(seed: int, boss_id: StringName = &"", player_ability_ids: Array = [], use_heuristic_ai: bool = false, player_tile_variants: Dictionary = {}, tiebreak_seed: int = 0, ai_abilities_seed: int = 0, session_kind: String = "east_round", use_shanten_ai: bool = false, player_consumable_ids: Array = [], player_relic_ids: Array = []) -> Dictionary:
	# M8: session_kind 决定本节点局数。"east_round" → 4 局；"hanchan" → 8 局。
	# total_hands 从 BalanceConstants 查；hands_per_round 固定 4（东/南各 4 局）。
	var total_hands: int = BalanceConstants.get_hands_per_node(session_kind)
	var driver := GameDriver.new(seed, total_hands, HANDS_PER_ROUND)
	driver.use_heuristic_ai = use_heuristic_ai
	driver.use_shanten_ai = use_shanten_ai
	var hand_count: int = 0
	var hand_outcomes: Dictionary = {"tsumo": 0, "ron": 0, "exhaustive_draw": 0}
	while not driver.finished and hand_count < HAND_LIMIT:
		hand_count += 1
		var bc := driver.start_hand()
		if boss_id != &"":
			BossAbilityFactory.inject(bc.registry, boss_id)
		# M7：玩家 deck.abilities → registry（每局重建）
		if not player_ability_ids.is_empty():
			BossAbilityFactory.inject_player_abilities(bc.registry, player_ability_ids, VIEWER_SEAT)
		# M7：玩家 deck.tile_variants → registry（每局重建）
		if not player_tile_variants.is_empty():
			TileSkillFactory.inject_player_tile_variants(bc.registry, player_tile_variants, VIEWER_SEAT)
		if not player_consumable_ids.is_empty():
			ConsumableFactory.inject_all(bc.registry, player_consumable_ids, VIEWER_SEAT)
		if not player_relic_ids.is_empty():
			RelicFactory.inject_all(bc.registry, player_relic_ids, VIEWER_SEAT)
		# M7（baseline 5 假设 J/M）：AI seat 1/2/3 也分配 1 张随机 ability
		if ai_abilities_seed > 0:
			var excluded: Array = player_ability_ids.duplicate()
			if boss_id != &"":
				excluded.append(boss_id)
			BossAbilityFactory.inject_random_ai_seat_abilities(
				bc.registry, ai_abilities_seed + hand_count, [1, 2, 3], excluded
			)
		var run_result: Dictionary = bc.run_to_end()
		var apply_res: Dictionary = driver.apply_result(run_result.events)
		var kind: String = apply_res.kind
		if hand_outcomes.has(kind):
			hand_outcomes[kind] = int(hand_outcomes[kind]) + 1
		if apply_res.kind == "exhaustive_draw":
			apply_res["tenpai_array"] = _detect_tenpai_array(bc)
		driver.advance_or_finish(apply_res)

	# M7：未收的立直棒池转给庄家
	if driver.riichi_sticks > 0:
		driver.cumulative_scores[driver.dealer_seat] += driver.riichi_sticks * 1000
		driver.riichi_sticks = 0

	# M7：tiebreak_seed > 0 时启用公平同分裁决（PR #75 引入）
	var rank: int = NodeResult.rank_for_seat(driver.cumulative_scores, VIEWER_SEAT, tiebreak_seed)
	return {
		"node_result": NodeResult.new(rank, driver.cumulative_scores, session_kind),
		"hand_outcomes": hand_outcomes,
		"final_scores": driver.cumulative_scores.duplicate(),
		"hand_count": hand_count,
	}

# M5 视觉化：带 per-hand observer 的异步版本。
#
# 每局 (hand) 跑完后调用 on_hand_complete(driver, hand_count) 给 UI 一次刷新机会，
# 然后 await tree.process_frame 让 Godot 真正绘制一帧。on_hand_complete 拿
# driver 引用以读 cumulative_scores / battle.state / hand_index / dealer_seat。
#
# 调用方负责：(1) tree 引用要活到调用结束；(2) callable 不抛异常。
# 异步代价：一场 4 局东风战会 yield 4 帧；普通节点 < 100ms 视觉延迟。
static func run_battle_to_node_result_async(
	tree: SceneTree,
	on_hand_complete: Callable,
	seed: int,
	boss_id: StringName = &"",
	player_ability_ids: Array = [],
	use_heuristic_ai: bool = false,
	player_tile_variants: Dictionary = {},
	tiebreak_seed: int = 0,
	ai_abilities_seed: int = 0,
	session_kind: String = "east_round",
	use_shanten_ai: bool = false
) -> NodeResult:
	var total_hands: int = BalanceConstants.get_hands_per_node(session_kind)
	var driver := GameDriver.new(seed, total_hands, HANDS_PER_ROUND)
	driver.use_heuristic_ai = use_heuristic_ai
	driver.use_shanten_ai = use_shanten_ai
	var hand_count: int = 0
	while not driver.finished and hand_count < HAND_LIMIT:
		hand_count += 1
		var bc := driver.start_hand()
		if boss_id != &"":
			BossAbilityFactory.inject(bc.registry, boss_id)
		if not player_ability_ids.is_empty():
			BossAbilityFactory.inject_player_abilities(bc.registry, player_ability_ids, VIEWER_SEAT)
		if not player_tile_variants.is_empty():
			TileSkillFactory.inject_player_tile_variants(bc.registry, player_tile_variants, VIEWER_SEAT)
		if ai_abilities_seed > 0:
			var excluded: Array = player_ability_ids.duplicate()
			if boss_id != &"":
				excluded.append(boss_id)
			BossAbilityFactory.inject_random_ai_seat_abilities(
				bc.registry, ai_abilities_seed + hand_count, [1, 2, 3], excluded
			)
		var run_result: Dictionary = bc.run_to_end()
		var apply_res: Dictionary = driver.apply_result(run_result.events)
		if apply_res.kind == "exhaustive_draw":
			apply_res["tenpai_array"] = _detect_tenpai_array(bc)
		driver.advance_or_finish(apply_res)
		# 通知 UI 刷新；callback 自身可 await（如延时让玩家看清状态）。
		# 用 await 保证 callback 返回的 coroutine 完成后才推进下一局。
		if on_hand_complete.is_valid():
			await on_hand_complete.call(driver, hand_count)
		if tree:
			await tree.process_frame
	if driver.riichi_sticks > 0:
		driver.cumulative_scores[driver.dealer_seat] += driver.riichi_sticks * 1000
		driver.riichi_sticks = 0
	var rank: int = NodeResult.rank_for_seat(driver.cumulative_scores, VIEWER_SEAT, tiebreak_seed)
	return NodeResult.new(rank, driver.cumulative_scores, session_kind)

# 战斗节点真实可玩入口（plan: Step 8）。
#
# 跟 run_battle_to_node_result_async 行为一致（4 局东风战 → NodeResult），
# 不同点：
#   - 用 PlayableBattleController 替代 BattleController（GameDriver.bc_factory 注入）
#   - 调 bc.run_to_end_async() 让玩家输入接入；await PlayableTable.play_hand_async
#     把 BC ←→ UI 牵线
#   - 局间 await tree.process_frame 给 UI 喘息
#
# table 必须是已 _ready 的 PlayableTable 实例（RunFlow 把它 _swap_panel 进来）。
static func run_with_player_input_async(
	table,  # PlayableTable（无强类型避免循环依赖）
	tree: SceneTree,
	seed: int,
	boss_id: StringName = &"",
	player_ability_ids: Array = [],
	player_tile_variants: Dictionary = {},
	session_kind: String = "east_round",
	tiebreak_seed: int = 0,
	player_consumable_ids: Array = [],
	player_relic_ids: Array = [],
	use_heuristic_ai: bool = false
) -> NodeResult:
	var total_hands: int = BalanceConstants.get_hands_per_node(session_kind)
	var driver := GameDriver.new(seed, total_hands, HANDS_PER_ROUND)
	# 调用方按 chapter / difficulty / 节点类型决定:新手节点 SimpleAi(默认),
	# 高难度/Boss/章 2+ 节点 HeuristicAi。之前硬编 false 让所有玩家路径的 AI
	# 都是 SimpleAi(随机弃牌),老手体验不到挑战;但新手第 1 局也需要保护。
	driver.use_heuristic_ai = use_heuristic_ai
	# 让 GameDriver 用 PlayableBattleController（玩家可玩）
	driver.bc_factory = func(s: int, dealer: int, useh: bool, wind: int):
		return PlayableBattleController.new(s, dealer, useh, wind)
	var hand_count: int = 0
	while not driver.finished and hand_count < HAND_LIMIT:
		hand_count += 1
		var bc: PlayableBattleController = driver.start_hand() as PlayableBattleController
		if boss_id != &"":
			BossAbilityFactory.inject(bc.registry, boss_id)
		if not player_ability_ids.is_empty():
			BossAbilityFactory.inject_player_abilities(bc.registry, player_ability_ids, VIEWER_SEAT)
		if not player_tile_variants.is_empty():
			TileSkillFactory.inject_player_tile_variants(bc.registry, player_tile_variants, VIEWER_SEAT)
		if not player_consumable_ids.is_empty():
			ConsumableFactory.inject_all(bc.registry, player_consumable_ids, VIEWER_SEAT)
		if not player_relic_ids.is_empty():
			RelicFactory.inject_all(bc.registry, player_relic_ids, VIEWER_SEAT)
		# 跑这一局 — UI 接入由 PlayableTable.play_hand_async 完成
		var run_result: Dictionary = await table.play_hand_async(bc)
		var apply_res: Dictionary = driver.apply_result(run_result.events)
		if apply_res.kind == "exhaustive_draw":
			apply_res["tenpai_array"] = _detect_tenpai_array(bc)
		driver.advance_or_finish(apply_res)
		# 局间小停顿让玩家看清结算后再开下一局
		await tree.create_timer(0.5).timeout
	# 立直棒池转交（如有）
	if driver.riichi_sticks > 0:
		driver.cumulative_scores[driver.dealer_seat] += driver.riichi_sticks * 1000
		driver.riichi_sticks = 0
	var rank: int = NodeResult.rank_for_seat(driver.cumulative_scores, VIEWER_SEAT, tiebreak_seed)
	return NodeResult.new(rank, driver.cumulative_scores, session_kind)

# 占位节点（CAMP / SHOP / EVENT）的快捷桥接。
static func placeholder_result() -> NodeResult:
	return NodeResult.from_placeholder()

# ---- internal ----

static func _detect_tenpai_array(bc: IBattleController) -> Array:
	var arr: Array = []
	for i in range(4):
		var seat: Seat = bc.state.seats[i]
		var typed_melds: Array[Meld] = []
		for m in seat.melds:
			typed_melds.append(m)
		var waits: Array = WaitCalculator.wait_tiles(seat.hand, typed_melds)
		arr.append(waits.size() > 0)
	return arr
