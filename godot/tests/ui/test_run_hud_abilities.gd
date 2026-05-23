extends GutTest

# RunHud 能力芯片静态 helper 单测:短名截断 + tooltip 格式。

func _make_ability(id: String, name: String, desc: String, rarity: int) -> AbilityCard:
	var a := AbilityCard.new()
	a.id = StringName(id)
	a.display_name = name
	a.description = desc
	a.rarity = rarity
	return a


# ---- _ability_short_name ----

func test_short_name_uses_display_name_when_short() -> void:
	var a := _make_ability("foo", "速攻", "", Rarity.Kind.COMMON)
	assert_eq(RunHud._ability_short_name(a), "速攻")


func test_short_name_truncates_long_display_name() -> void:
	var a := _make_ability("foo", "九蓮宝燈秘伝", "", Rarity.Kind.EPIC)
	# 长度 > 4 → 前 3 字
	assert_eq(RunHud._ability_short_name(a), "九蓮宝")


func test_short_name_falls_back_to_id_when_display_name_empty() -> void:
	var a := _make_ability("speed_run", "", "", Rarity.Kind.COMMON)
	# "speed_run" 长度 > 4 → 前 3 字
	assert_eq(RunHud._ability_short_name(a), "spe")


func test_short_name_handles_null() -> void:
	assert_eq(RunHud._ability_short_name(null), "?")


# ---- _ability_tooltip ----

func test_tooltip_includes_name_rarity_and_description() -> void:
	var a := _make_ability("riichi_kago", "立直加护", "立直后免一次振听", Rarity.Kind.EPIC)
	var tip := RunHud._ability_tooltip(a)
	assert_true(tip.find("立直加护") >= 0, "应含全名")
	assert_true(tip.find("史诗") >= 0, "应含稀有度")
	assert_true(tip.find("立直后免一次振听") >= 0, "应含描述")


func test_tooltip_omits_description_when_empty() -> void:
	var a := _make_ability("noop", "空", "", Rarity.Kind.COMMON)
	var tip := RunHud._ability_tooltip(a)
	assert_true(tip.find("空") >= 0)
	assert_eq(tip.split("\n").size(), 1, "无描述时只有 1 行标题")


func test_tooltip_handles_null() -> void:
	assert_eq(RunHud._ability_tooltip(null), "")
