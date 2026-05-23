extends GutTest

# 麻将王 — 商店消耗品链路验证

func test_gacha_shop_has_5_slots():
	var results := Gacha.refresh_shop(42)
	assert_eq(results.size(), 5, "商店应有 5 个槽位")

func test_gacha_shop_has_consumable_slot():
	var results := Gacha.refresh_shop(42)
	var has_consumable := false
	for r in results:
		if r.kind == GachaResult.KIND_CONSUMABLE:
			has_consumable = true
			break
	assert_true(has_consumable, "商店应至少包含 1 个消耗品槽")

func test_gacha_result_make_consumable():
	var item := ConsumableItem.new(&"test_c", ConsumableItem.Kind.BATTLE, Rarity.Kind.EPIC)
	item.display_name = "测试道具"
	var r := GachaResult.make_consumable(item)
	assert_eq(r.kind, GachaResult.KIND_CONSUMABLE)
	assert_not_null(r.consumable)
	assert_eq(r.rarity, Rarity.Kind.EPIC)

func test_shop_format_slot_text_consumable():
	var item := ConsumableItem.new(&"iron_shield_v1", ConsumableItem.Kind.BATTLE, Rarity.Kind.UNCOMMON)
	item.display_name = "铁盾"
	item.description = "取消荣胡 1 次"
	var r := GachaResult.make_consumable(item)
	var text := ShopView.format_slot_text(r)
	assert_true(text.contains("铁盾"), "应包含消耗品名")
	assert_true(text.contains("取消荣胡"), "应包含描述")

func test_apply_gacha_consumable_to_run_state():
	var rs := RunState.new(42)
	var item: ConsumableItem = CardPool.all_consumables()[0]
	var result: GachaResult = GachaResult.make_consumable(item)
	assert_eq(rs.consumable_count(), 0)
	if result.kind == GachaResult.KIND_CONSUMABLE and result.consumable:
		rs.add_consumable(result.consumable)
	assert_eq(rs.consumable_count(), 1)

func test_run_state_max_consumables():
	var rs := RunState.new(42)
	var pool: Array = CardPool.all_consumables()
	for i in range(RunState.MAX_CONSUMABLES):
		rs.add_consumable(pool[i % pool.size()])
	assert_eq(rs.consumable_count(), RunState.MAX_CONSUMABLES)
	var overflow: bool = rs.add_consumable(pool[0])
	assert_false(overflow, "超过上限应拒绝")

func test_run_state_use_hp_potion():
	var rs := RunState.new(42)
	rs.hp = 3
	var item: ConsumableItem = null
	for c in CardPool.all_consumables():
		if c.id == &"hp_potion_v1":
			item = c
			break
	assert_not_null(item)
	rs.add_consumable(item)
	rs.use_run_consumable(&"hp_potion_v1")
	assert_eq(rs.hp, 4, "回复药应 +1 HP")
	assert_eq(rs.consumable_count(), 0, "使用后应移除")

func test_consumable_serialization_round_trip():
	var rs := RunState.new(42)
	for c in CardPool.all_consumables():
		rs.add_consumable(c)
	var d := rs.to_dict()
	var restored := RunState.from_dict(d)
	assert_eq(restored.consumable_count(), rs.consumable_count())
	for i in range(restored.consumables.size()):
		var c: ConsumableItem = restored.consumables[i]
		assert_not_null(c)
		assert_ne(String(c.id), "")

func test_shop_5_seeds_all_produce_valid_results():
	for seed_val in [42, 99, 200, 555, 1001]:
		var results := Gacha.refresh_shop(seed_val)
		assert_eq(results.size(), 5, "seed %d 应有 5 槽" % seed_val)
		for r in results:
			assert_true(
				r.kind == GachaResult.KIND_TILE or
				r.kind == GachaResult.KIND_ABILITY or
				r.kind == GachaResult.KIND_CONSUMABLE,
				"seed %d 每槽应有有效 kind" % seed_val
			)
