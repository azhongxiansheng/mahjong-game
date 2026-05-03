class_name BossAbilityFactory

# 麻将王 — M6 收尾：把 plan-6 C "boss inject 到 SkillRegistry" 落地。
#
# Boss SkillResource 在 BOSS 节点对战的每局开始时构造一次。每局都重建是因为
# SkillResource.consumed = true 等可变字段需要重置。
#
# AbilityCard（CardPool 注册的 ability 元数据）只持 id / display_name /
# hook_resource_path 等显示信息；triggers 是 SkillResource 字段，需在此明示
# 给每个 Boss。这避免改 AbilityCard schema（M5 存档兼容性）。
#
# 加新 Boss：在 _BOSS_TRIGGERS 加 entry；保留 v1 简化"hook 固定 = ability id
# 对应的 hook_resource_path"约定（同 chapter_config.boss_id）。

# Boss id → triggers 映射；hook_path 仍走 CardPool 的 ability metadata。
# M7：boss2 改用 WIN_DECLARED_PRE（在 ScoreCalc 之前）让 +2 番真生效；
# WIN_DECLARED 是 ScoreCalc 之后的"结果通知"事件。
const _BOSS_TRIGGERS: Dictionary = {
	&"boss1_iron_curtain_v1": [&"RON_DECLARED"],
	&"boss2_fortune_runner_v1": [&"WIN_DECLARED_PRE"],
	&"boss3_kanmon_v1": [&"HAITEI", &"HOUTEI"],
}

# 用 boss_id 从 CardPool 查 hook_resource_path + 用 _BOSS_TRIGGERS 取 triggers
# 构造 fresh SkillResource。返 null 表示 boss_id 未知或无 hook（调用方应 fallback）。
static func build(boss_id: StringName) -> SkillResource:
	if boss_id == &"" or not _BOSS_TRIGGERS.has(boss_id):
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
	for t in _BOSS_TRIGGERS[boss_id]:
		triggers.append(t)
	s.owner_triggers = triggers
	s.hook_script = hook_script
	return s

# 把 Boss SkillResource 注册到目标 seat（默认 AI seat 1）。
static func inject(registry: SkillRegistry, boss_id: StringName, boss_seat: int = 1) -> bool:
	var sk: SkillResource = build(boss_id)
	if sk == null:
		return false
	registry.register(sk, boss_seat)
	return true

# 已知的 Boss id 列表（供 GUT / debug）
static func known_boss_ids() -> Array:
	return _BOSS_TRIGGERS.keys()

# ---- internal ----

static func _find_ability_in_pool(ab_id: StringName) -> AbilityCard:
	for a in CardPool.all_abilities():
		if a.id == ab_id:
			return a
	return null
