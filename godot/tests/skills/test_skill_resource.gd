extends GutTest

func test_default_fields():
	var s := SkillResource.new()
	assert_eq(s.rarity, 0)
	assert_false(s.is_ability)
	assert_false(s.consumed)
	assert_eq(s.owner_triggers.size(), 0)
	assert_eq(s.holder_triggers.size(), 0)

func test_assign_id_and_triggers():
	var s := SkillResource.new()
	s.id = &"thunder_5w_v1"
	s.owner_triggers = [&"WIN_DECLARED"]
	assert_eq(s.id, &"thunder_5w_v1")
	assert_eq(s.owner_triggers[0], &"WIN_DECLARED")

func test_consumed_runtime_flag():
	var s := SkillResource.new()
	s.consumed = true
	assert_true(s.consumed)
