class_name BossAbilityFactory

# 麻将王 — M6 收尾 + M7 扩展：能力 (ability) → SkillRegistry 注册工厂。
#
# 类名保留 "BossAbilityFactory" 历史命名（M6 收尾 plan-6 C 起家时只支持
# 3 章 Boss）；M7 起扩展为通用 ability factory，承担：
#   - 章 Boss 注入到 AI 座（既有 inject(registry, id, seat)）
#   - 玩家角色能力（deck.abilities）注入到玩家座位（新 inject_player_abilities）
#
# 每局对战开始时调用一次构造（每局重建因 SkillResource.consumed 等可变字段
# 需重置）。AbilityCard（CardPool 元数据）只持 id / display / hook_path；
# triggers 在本工厂的 _ABILITY_TRIGGERS 表显式声明（避免改 AbilityCard
# schema，影响 M5 存档兼容性）。
#
# 加新 ability：在 _ABILITY_TRIGGERS 加 entry。

# ability id → owner_triggers 映射。包含 3 章 Boss + M6 9 张玩家能力。
# v1 大量 ability 在 WIN_DECLARED_PRE 加 han（M7 ctx 接通后真生效）。
const _ABILITY_TRIGGERS: Dictionary = {
	# 3 章 Boss
	&"boss1_iron_curtain_v1": [&"RON_DECLARED"],
	&"boss2_fortune_runner_v1": [&"WIN_DECLARED_PRE"],
	&"boss3_kanmon_v1": [&"HAITEI", &"HOUTEI"],
	# M1 demo
	&"seabed_hunter_v1": [&"HAITEI"],  # 海底捞月时强制 owner 自摸
	# M6 神级
	&"shichu_kyu_katsu_v1": [&"WIN_DECLARED_PRE"],
	&"mineu_no_oni_v1": [&"WIN_DECLARED_PRE"],
	&"san_kyoku_kiseki_v1": [&"WIN_DECLARED_PRE"],
	&"isshun_senken_v1": [&"TILE_DRAWN"],
	# M6 史诗
	&"yamagan_v1": [&"GAME_BEGIN"],
	&"tenpai_seethru_v1": [&"HAND_FORMED"],
	&"ryukyoku_yudou_v1": [&"WIN_DECLARED_PRE"],
	&"tousotsu_v1": [&"WIN_DECLARED_PRE"],
	&"riichi_kago_v1": [&"WIN_DECLARED_PRE"],
	# M7 收尾：tougenkyo_v1（M6 holdout）
	&"tougenkyo_v1": [&"WIN_DECLARED_PRE"],
	# 角色被动
	&"char_akagi_passive_v1": [&"TILE_DRAWN"],
	&"char_kaiji_passive_v1": [&"WIN_DECLARED_PRE"],
	&"char_washizu_passive_v1": [&"GAME_BEGIN"],
	&"char_saki_passive_v1": [&"WIN_DECLARED_PRE"],
	&"char_teru_passive_v1": [&"WIN_DECLARED_PRE"],
	&"char_awai_passive_v1": [&"GAME_BEGIN"],
}

# Boss-only 子集（用于 chapter_config 校验：每章 boss_id 必须在 boss 列表里）。
const _BOSS_IDS: Array = [
	&"boss1_iron_curtain_v1",
	&"boss2_fortune_runner_v1",
	&"boss3_kanmon_v1",
]

# 用 ability_id 从 CardPool 查 hook_resource_path + 用 _ABILITY_TRIGGERS 取
# triggers 构造 fresh SkillResource。返 null 表示 id 未知或无 hook（调用方
# 应 fallback）。参数 boss_id 命名保留兼容旧调用点；语义上是任意 ability id。
static func build(boss_id: StringName) -> SkillResource:
	if boss_id == &"" or not _ABILITY_TRIGGERS.has(boss_id):
		return null
	var card: AbilityCard = _find_ability_in_pool(boss_id)
	if card == null or card.hook_resource_path == "":
		return null
	var hook_script: GDScript = load(card.hook_resource_path)
	if hook_script == null:
		return null
	var s := SkillResource.new()
	s.id = boss_id
	s.display_name = card.display_name
	s.description = card.description
	s.rarity = card.rarity
	s.is_ability = true
	var triggers: Array[StringName] = []
	for t in _ABILITY_TRIGGERS[boss_id]:
		triggers.append(t)
	s.owner_triggers = triggers
	s.hook_script = hook_script
	return s

# 把 ability SkillResource 注册到目标 seat（默认 AI seat 1，沿用 Boss 用例）。
static func inject(registry: SkillRegistry, boss_id: StringName, boss_seat: int = 1) -> bool:
	var sk: SkillResource = build(boss_id)
	if sk == null:
		return false
	registry.register(sk, boss_seat)
	return true

# M7（baseline 5 假设 J/M）：给 AI 座位（默认 1/2/3）随机分配一张非-Boss
# ability，让 4 家更对称（解 simulation "玩家偏强" 根因）。
#
# - rng_seed: int —— 决定 ability 选择（决定性）
# - ai_seats: Array[int] = [1, 2, 3] —— 要装备的 AI 座位
# - excluded_ids: Array[StringName] = [] —— 跳过的 id（避免与 boss / 玩家 deck 重）
#
# 每 AI seat 得 1 张 ability。返成功注册的数（max=ai_seats.size()）。
static func inject_random_ai_seat_abilities(registry: SkillRegistry, rng_seed: int, ai_seats: Array = [1, 2, 3], excluded_ids: Array = []) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	# Pool = 全部 ability id 减 Boss + excluded
	var pool: Array[StringName] = []
	for id_ in known_ability_ids():
		var s_id := id_ as StringName
		if _BOSS_IDS.has(s_id):
			continue
		if excluded_ids.has(s_id):
			continue
		pool.append(s_id)
	if pool.is_empty():
		return 0
	var count: int = 0
	for seat in ai_seats:
		var idx: int = rng.randi_range(0, pool.size() - 1)
		if inject(registry, pool[idx], int(seat)):
			count += 1
	return count

# M7：把玩家 deck.abilities 数组（id 列表）批量注入到玩家座位（默认 0）。
# 未知 / 无 hook 的 id 静默跳过；返成功注册的 id 数。
static func inject_player_abilities(registry: SkillRegistry, ability_ids: Array, player_seat: int = 0) -> int:
	var count: int = 0
	for raw_id in ability_ids:
		var id := raw_id as StringName
		if inject(registry, id, player_seat):
			count += 1
	return count

# 已知的 Boss id 列表（供 GUT / debug；不变量：_BOSS_IDS 是 _ABILITY_TRIGGERS 子集）。
static func known_boss_ids() -> Array:
	return _BOSS_IDS.duplicate()

# 全部 ability id（含 boss + 玩家能力）。
static func known_ability_ids() -> Array:
	return _ABILITY_TRIGGERS.keys()

# ---- internal ----

static func _find_ability_in_pool(ab_id: StringName) -> AbilityCard:
	for a in CardPool.all_abilities():
		if a.id == ab_id:
			return a
	return null
