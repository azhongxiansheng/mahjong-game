extends GutTest

# 麻将王 — 营地消耗品使用 TDD

func test_run_state_hp_potion_heals():
	var rs := RunState.new(42)
	rs.hp = 2
	rs.max_hp = 5
	var potion: ConsumableItem = null
	for c in CardPool.all_consumables():
		if c.id == &"hp_potion_v1":
			potion = c
			break
	assert_not_null(potion)
	rs.add_consumable(potion)
	assert_eq(rs.consumable_count(), 1)
	var ok: bool = rs.use_run_consumable(&"hp_potion_v1")
	assert_true(ok, "使用应成功")
	assert_eq(rs.hp, 3, "HP 应 +1")
	assert_eq(rs.consumable_count(), 0, "使用后移除")

func test_hp_potion_capped_at_max():
	var rs := RunState.new(42)
	rs.hp = 5
	rs.max_hp = 5
	var potion: ConsumableItem = null
	for c in CardPool.all_consumables():
		if c.id == &"hp_potion_v1":
			potion = c
			break
	rs.add_consumable(potion)
	rs.use_run_consumable(&"hp_potion_v1")
	assert_eq(rs.hp, 5, "不超过 max_hp")

func test_gold_doubler_adds_gold():
	var rs := RunState.new(42)
	rs.gold = 100
	var doubler: ConsumableItem = null
	for c in CardPool.all_consumables():
		if c.id == &"gold_doubler_v1":
			doubler = c
			break
	assert_not_null(doubler)
	rs.add_consumable(doubler)
	rs.use_run_consumable(&"gold_doubler_v1")
	assert_eq(rs.gold, 600, "金币应 +500")

func test_use_nonexistent_consumable_returns_false():
	var rs := RunState.new(42)
	var ok: bool = rs.use_run_consumable(&"nonexistent_v1")
	assert_false(ok)

func test_battle_consumable_cannot_be_used_as_run():
	var rs := RunState.new(42)
	var shield: ConsumableItem = null
	for c in CardPool.all_consumables():
		if c.id == &"iron_shield_v1":
			shield = c
			break
	assert_not_null(shield)
	rs.add_consumable(shield)
	var ok: bool = rs.use_run_consumable(&"iron_shield_v1")
	assert_false(ok, "战斗消耗品不能在营地使用")
	assert_eq(rs.consumable_count(), 1, "不应被移除")
