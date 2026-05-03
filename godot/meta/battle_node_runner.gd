class_name BattleNodeRunner

# 麻将王 — 里程碑 4 第 4 步：战斗节点纯逻辑封装
#
# 把 east_round_e2e_smoke 里的"驱动 GameDriver 跑完整场东风战 + 算 viewer
# 排名"逻辑提取成可复用的纯函数。RunFlow / GUT integration test 都能调。
#
# 不持 UI 引用，方便单测；显示层（4 人桌）由调用方决定是否实例化。
#
# v1 同步跑：调用阻塞直到东风战结束。M5/M6 想要"边跑边显示"时改 await + frame yield。

const HAND_LIMIT: int = 30  # 连庄保护上限（east_round_e2e 一致）
const VIEWER_SEAT: int = 0  # 玩家固定 seat 0

# 跑一整场东风战，返 NodeResult（已含 viewer 排名 / hp_delta / final_scores）。
# seed 决定洗牌；node_index 通常作为 seed 偏移避免同 Run 内不同节点重复牌局。
#
# boss_id（plan-6 C，M6 收尾）：传非空 StringName 时，每局开始把对应 Boss 能力
# inject 到 BattleController 的 SkillRegistry（默认 AI seat 1）。若 boss_id
# 未在 BossAbilityFactory 注册或 CardPool 找不到，本调用静默 fallback 到
# 普通对局（不 inject）。
static func run_battle_to_node_result(seed: int, boss_id: StringName = &"", player_ability_ids: Array = []) -> NodeResult:
	var driver := GameDriver.new(seed)
	var hand_count := 0
	while not driver.finished and hand_count < HAND_LIMIT:
		hand_count += 1
		var bc := driver.start_hand()
		if boss_id != &"":
			BossAbilityFactory.inject(bc.registry, boss_id)
		# M7：玩家 deck.abilities → registry（每局重建）
		if not player_ability_ids.is_empty():
			BossAbilityFactory.inject_player_abilities(bc.registry, player_ability_ids, VIEWER_SEAT)
		var run_result: Dictionary = bc.run_to_end()
		var apply_res: Dictionary = driver.apply_result(run_result.events)
		if apply_res.kind == "exhaustive_draw":
			apply_res["tenpai_array"] = _detect_tenpai_array(bc)
		driver.advance_or_finish(apply_res)

	var rank: int = NodeResult.rank_for_seat(driver.cumulative_scores, VIEWER_SEAT)
	return NodeResult.new(rank, driver.cumulative_scores)

# 占位节点（CAMP / SHOP / EVENT）的快捷桥接。
static func placeholder_result() -> NodeResult:
	return NodeResult.from_placeholder()

# ---- internal ----

static func _detect_tenpai_array(bc: BattleController) -> Array:
	var arr: Array = []
	for i in range(4):
		var seat: Seat = bc.state.seats[i]
		var typed_melds: Array[Meld] = []
		for m in seat.melds:
			typed_melds.append(m)
		var waits: Array = WaitCalculator.wait_tiles(seat.hand, typed_melds)
		arr.append(waits.size() > 0)
	return arr
