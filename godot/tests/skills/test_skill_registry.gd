extends GutTest

func _make_skill(id: StringName) -> SkillResource:
	var s := SkillResource.new()
	s.id = id
	return s

func test_register_appends_entry():
	var reg := SkillRegistry.new()
	reg.register(_make_skill(&"a"), 0)
	assert_eq(reg.get_all_entries().size(), 1)

func test_register_assigns_incrementing_reg_order():
	var reg := SkillRegistry.new()
	reg.register(_make_skill(&"a"), 0)
	reg.register(_make_skill(&"b"), 1)
	var entries := reg.get_all_entries()
	assert_eq(entries[0].reg_order, 0)
	assert_eq(entries[1].reg_order, 1)

func test_unregister_removes_first_match():
	var reg := SkillRegistry.new()
	var sk := _make_skill(&"a")
	reg.register(sk, 0)
	reg.register(_make_skill(&"b"), 1)
	reg.unregister(sk, 0)
	var entries := reg.get_all_entries()
	assert_eq(entries.size(), 1)
	assert_eq(entries[0].skill.id, &"b")

func test_register_with_tile_instance_anchor():
	var reg := SkillRegistry.new()
	var ti := TileSkillAnchor.make(Tile.new(TileId.W5), 0)
	reg.register(_make_skill(&"tile_skill"), ti)
	var entry = reg.get_all_entries()[0]
	assert_eq(entry.anchor, ti)

func test_get_all_entries_returns_copy():
	var reg := SkillRegistry.new()
	reg.register(_make_skill(&"a"), 0)
	var copy := reg.get_all_entries()
	copy.clear()
	assert_eq(reg.get_all_entries().size(), 1, "外部修改返回值不应影响内部")

func test_register_with_hook_script_instantiates_hook():
	var reg := SkillRegistry.new()
	var sk := _make_skill(&"a")
	sk.hook_script = preload("res://skills/skill_hook.gd")
	reg.register(sk, 0)
	var entry = reg.get_all_entries()[0]
	assert_not_null(entry.hook)

func test_register_without_hook_script_yields_null_hook():
	var reg := SkillRegistry.new()
	var sk := _make_skill(&"a")
	reg.register(sk, 0)
	var entry = reg.get_all_entries()[0]
	assert_null(entry.hook)
