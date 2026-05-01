extends GutTest

# 麻将王 — M5 第 1 步：Deck 单测

func _mk_tile(id: StringName, tile_id: int, rarity: int = Rarity.Kind.COMMON) -> TileVariant:
	return TileVariant.new(id, tile_id, rarity)

func _mk_ability(id: StringName, rarity: int = Rarity.Kind.COMMON) -> AbilityCard:
	return AbilityCard.new(id, rarity)

# ---- tile_variants ----

func test_initial_empty():
	var d := Deck.new()
	assert_eq(d.tile_variant_count(), 0)
	assert_eq(d.ability_count(), 0)

func test_add_tile_variant():
	var d := Deck.new()
	assert_true(d.add_tile_variant(_mk_tile(&"v1", TileId.W5)))
	assert_eq(d.tile_variant_count(), 1)
	assert_true(d.has_tile_variant(TileId.W5))

func test_add_tile_variant_null_returns_false():
	var d := Deck.new()
	assert_false(d.add_tile_variant(null))

func test_add_tile_variant_invalid_tile_id_returns_false():
	var d := Deck.new()
	var v := TileVariant.new(&"bad", -1)
	assert_false(d.add_tile_variant(v))

func test_add_same_tile_id_overwrites():
	var d := Deck.new()
	d.add_tile_variant(_mk_tile(&"a", TileId.W5))
	d.add_tile_variant(_mk_tile(&"b", TileId.W5))
	assert_eq(d.tile_variant_count(), 1)
	assert_eq(d.get_tile_variant(TileId.W5).id, &"b", "后注册覆盖前者")

func test_remove_tile_variant():
	var d := Deck.new()
	d.add_tile_variant(_mk_tile(&"a", TileId.W5))
	assert_true(d.remove_tile_variant(TileId.W5))
	assert_eq(d.tile_variant_count(), 0)

func test_remove_unknown_tile_returns_false():
	var d := Deck.new()
	assert_false(d.remove_tile_variant(TileId.W5))

# ---- abilities ----

func test_add_ability_until_full():
	var d := Deck.new()
	for i in range(Deck.MAX_ABILITIES):
		assert_true(d.add_ability(_mk_ability(StringName("a%d" % i))))
	assert_eq(d.ability_count(), Deck.MAX_ABILITIES)
	assert_eq(d.ability_slots_remaining(), 0)

func test_add_ability_when_full_rejects():
	var d := Deck.new()
	for i in range(Deck.MAX_ABILITIES):
		d.add_ability(_mk_ability(StringName("a%d" % i)))
	assert_false(d.add_ability(_mk_ability(&"overflow")))
	assert_eq(d.ability_count(), Deck.MAX_ABILITIES)

func test_remove_ability_by_id():
	var d := Deck.new()
	d.add_ability(_mk_ability(&"a1"))
	d.add_ability(_mk_ability(&"a2"))
	assert_true(d.remove_ability(&"a1"))
	assert_eq(d.ability_count(), 1)
	assert_false(d.has_ability(&"a1"))
	assert_true(d.has_ability(&"a2"))

func test_max_abilities_is_5():
	# spec §10 + §14：5 槽角色能力
	assert_eq(Deck.MAX_ABILITIES, 5)
