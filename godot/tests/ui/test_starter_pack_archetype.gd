extends GutTest

# StarterPackPicker 打法字头 / 颜色 静态 helper 单测。
# 三张起始包对应:控场=守(蓝) / 火力=攻(红) / 速胡=速(金)。

func test_archetype_glyph_control() -> void:
	assert_eq(StarterPackPicker.archetype_glyph(&"starter_control"), "守")


func test_archetype_glyph_aggro() -> void:
	assert_eq(StarterPackPicker.archetype_glyph(&"starter_aggro"), "攻")


func test_archetype_glyph_fast() -> void:
	assert_eq(StarterPackPicker.archetype_glyph(&"starter_fast"), "速")


func test_archetype_glyph_unknown_empty() -> void:
	assert_eq(StarterPackPicker.archetype_glyph(&"unknown"), "")
	assert_eq(StarterPackPicker.archetype_glyph(&""), "")


func test_archetype_color_three_packs_distinct() -> void:
	var c1 := StarterPackPicker.archetype_color(&"starter_control")
	var c2 := StarterPackPicker.archetype_color(&"starter_aggro")
	var c3 := StarterPackPicker.archetype_color(&"starter_fast")
	assert_ne(c1, c2, "守色应与攻色不同")
	assert_ne(c2, c3, "攻色应与速色不同")
	assert_ne(c1, c3, "守色应与速色不同")


func test_archetype_color_control_is_blue() -> void:
	var c := StarterPackPicker.archetype_color(&"starter_control")
	assert_gt(c.b, c.r, "守色蓝通道应高于红")


func test_archetype_color_aggro_is_red() -> void:
	var c := StarterPackPicker.archetype_color(&"starter_aggro")
	assert_gt(c.r, c.b, "攻色红通道应高于蓝")


func test_archetype_color_fast_is_gold() -> void:
	var c := StarterPackPicker.archetype_color(&"starter_fast")
	# 金色:红+绿高,蓝低
	assert_gt(c.r, c.b)
	assert_gt(c.g, c.b)


func test_format_card_text_includes_glyph() -> void:
	# format_card_text 应在显示名前面附打法字头【守】等
	var pack := StarterPacks.control_pack()
	var s := StarterPackPicker.format_card_text(pack)
	assert_true(s.find("【守】") >= 0,
		"控场卡片头应有【守】打法字头,实际:\n%s" % s)


func test_format_card_text_unknown_pack_no_glyph() -> void:
	# 未知 pack id 不加 glyph
	var s := StarterPackPicker.format_card_text({
		"id": &"unknown_pack",
		"display_name": "试验型",
		"description": "实验性玩法",
		"available": true,
	})
	assert_false(s.find("【") >= 0, "未知 pack 不应出现 glyph 标记")
