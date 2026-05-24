extends GutTest

func test_tile_variant_starts_at_level_0():
	var v := TileVariant.new(&"test", TileId.W5, Rarity.Kind.UNCOMMON)
	assert_eq(v.level, 0)
	assert_false(v.is_upgraded())

func test_tile_variant_upgrade():
	var v := TileVariant.new(&"test", TileId.W5, Rarity.Kind.UNCOMMON)
	v.skill_resource_path = "res://skills/hooks/thunder_5w_hook.gd"
	v.upgraded_skill_resource_path = "res://skills/hooks/thunder_5w_hook_plus.gd"
	var ok: bool = v.upgrade()
	assert_true(ok)
	assert_true(v.is_upgraded())
	assert_eq(v.level, 1)

func test_tile_variant_no_double_upgrade():
	var v := TileVariant.new(&"test", TileId.W5, Rarity.Kind.UNCOMMON)
	v.upgrade()
	var ok: bool = v.upgrade()
	assert_false(ok, "不允许双重升级")

func test_active_hook_path_before_upgrade():
	var v := TileVariant.new(&"test", TileId.W5, Rarity.Kind.UNCOMMON)
	v.skill_resource_path = "res://skills/hooks/thunder_5w_hook.gd"
	v.upgraded_skill_resource_path = "res://skills/hooks/thunder_5w_hook_plus.gd"
	assert_eq(v.active_hook_path(), "res://skills/hooks/thunder_5w_hook.gd")

func test_active_hook_path_after_upgrade():
	var v := TileVariant.new(&"test", TileId.W5, Rarity.Kind.UNCOMMON)
	v.skill_resource_path = "res://skills/hooks/thunder_5w_hook.gd"
	v.upgraded_skill_resource_path = "res://skills/hooks/thunder_5w_hook_plus.gd"
	v.upgrade()
	assert_eq(v.active_hook_path(), "res://skills/hooks/thunder_5w_hook_plus.gd")

func test_upgraded_variant_serialization():
	var v := TileVariant.new(&"test", TileId.W5, Rarity.Kind.UNCOMMON)
	v.skill_resource_path = "a.gd"
	v.upgraded_skill_resource_path = "b.gd"
	v.upgrade()
	var d := v.to_dict()
	var restored := TileVariant.from_dict(d)
	assert_eq(restored.level, 1)
	assert_eq(restored.upgraded_skill_resource_path, "b.gd")
	assert_eq(restored.active_hook_path(), "b.gd")

func test_thunder_5w_plus_gives_double_han():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	var v := TileVariant.new(&"thunder_5w_v1", TileId.W5, Rarity.Kind.UNCOMMON)
	v.skill_resource_path = "res://skills/hooks/thunder_5w_hook.gd"
	v.upgraded_skill_resource_path = "res://skills/hooks/thunder_5w_hook_plus.gd"
	v.upgrade()
	var variants: Dictionary = {TileId.W5: v}
	TileSkillFactory.inject_player_tile_variants(reg, variants, 0)
	var ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	var base: int = int(BalanceConstants.lookup(&"thunder_5w_han_bonus"))
	assert_eq(int(ctx.han_deltas.get(0, 0)), base * 2, "升级版应 ×2")

func test_non_upgraded_thunder_gives_base_han():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	TileSkillFactory.inject_one(reg, &"thunder_5w_v1", 0)
	var ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	var base: int = int(BalanceConstants.lookup(&"thunder_5w_han_bonus"))
	assert_eq(int(ctx.han_deltas.get(0, 0)), base, "基础版应 = BalanceConstants 值")

func test_card_pool_thunder_has_upgrade_path():
	var pool: Array = CardPool.all_tile_variants()
	for v in pool:
		if v.id == &"thunder_5w_v1":
			assert_ne(v.upgraded_skill_resource_path, "", "thunder 应有升级路径")
			return
	assert_true(false, "CardPool 应包含 thunder_5w_v1")
