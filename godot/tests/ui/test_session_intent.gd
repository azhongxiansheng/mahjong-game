extends GutTest

# E1-04（#228）：大厅纯 UI 意图。正式 GameSessionConfig、校验与序列化归 #231。

const INTENT_SCRIPT := "res://ui/lobby/session_intent.gd"

const MODE_CASES := [
	[&"PRACTICE", &"EAST", &"STANDARD", &"PRACTICE_EAST_STANDARD"],
	[&"PRACTICE", &"EAST", &"TRASH_TALK", &"PRACTICE_EAST_TRASH_TALK"],
	[&"PRACTICE", &"HANCHAN", &"STANDARD", &"PRACTICE_HANCHAN_STANDARD"],
	[&"PRACTICE", &"HANCHAN", &"TRASH_TALK", &"PRACTICE_HANCHAN_TRASH_TALK"],
	[&"PUBLIC_CASUAL", &"EAST", &"STANDARD", &"PUBLIC_EAST_STANDARD"],
	[&"PUBLIC_CASUAL", &"EAST", &"TRASH_TALK", &"PUBLIC_EAST_TRASH_TALK"],
	[&"PUBLIC_CASUAL", &"HANCHAN", &"STANDARD", &"PUBLIC_HANCHAN_STANDARD"],
	[&"PUBLIC_CASUAL", &"HANCHAN", &"TRASH_TALK", &"PUBLIC_HANCHAN_TRASH_TALK"],
]


func _load_intent_script() -> GDScript:
	if not ResourceLoader.exists(INTENT_SCRIPT):
		return null
	return load(INTENT_SCRIPT) as GDScript


func test_session_intent_script_exists_as_pure_ui_value() -> void:
	assert_true(ResourceLoader.exists(INTENT_SCRIPT), "#228 应新增 SessionIntent UI 值对象")
	var script := _load_intent_script()
	assert_not_null(script, "SessionIntent 脚本应可加载")
	if script == null:
		return
	var intent: Variant = script.new(&"PRACTICE", &"EAST", &"STANDARD")
	assert_eq(intent.room_kind, &"PRACTICE")
	assert_eq(intent.round_kind, &"EAST")
	assert_eq(intent.game_mode, &"STANDARD")
	assert_eq(intent.selected_character_id, &"", "角色选择在本 Issue 中保持可选")


func test_all_eight_mode_ids_are_stable() -> void:
	var script := _load_intent_script()
	assert_not_null(script)
	if script == null:
		return
	var actual: Array[StringName] = []
	for mode_case in MODE_CASES:
		var intent: Variant = script.new(mode_case[0], mode_case[1], mode_case[2])
		assert_same(intent.get_script(), script, "8 种组合都必须由 SessionIntent 脚本构造")
		assert_eq(intent.room_kind, mode_case[0])
		assert_eq(intent.round_kind, mode_case[1])
		assert_eq(intent.game_mode, mode_case[2])
		assert_eq(intent.selected_character_id, &"")
		var mode_id: StringName = intent.mode_id()
		actual.append(mode_id)
		assert_eq(mode_id, mode_case[3], "三维选择必须稳定还原 mode_id")
	assert_eq(actual.size(), 8)
	var unique := {}
	for mode_id in actual:
		unique[mode_id] = true
	assert_eq(unique.size(), 8, "8 种组合不得发生 mode_id 碰撞")


func test_selected_character_is_optional_and_does_not_change_mode_id() -> void:
	var script := _load_intent_script()
	assert_not_null(script)
	if script == null:
		return
	var intent: Variant = script.new(
		&"PRACTICE", &"HANCHAN", &"TRASH_TALK", &"lin_yeche"
	)
	assert_eq(intent.selected_character_id, &"lin_yeche")
	assert_eq(intent.mode_id(), &"PRACTICE_HANCHAN_TRASH_TALK")


func test_intent_does_not_define_formal_session_or_authority_fields() -> void:
	var script := _load_intent_script()
	assert_not_null(script)
	if script == null:
		return
	var source: String = script.source_code
	for forbidden in [
		"GameSessionConfig",
		"seed",
		"session_id",
		"rule_version",
		"participants",
		"credential",
		"ticket",
		"worker",
	]:
		assert_false(source.contains(forbidden), "SessionIntent 不得越界包含：%s" % forbidden)
