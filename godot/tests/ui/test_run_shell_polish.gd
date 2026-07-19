extends GutTest

# Run 壳层视觉 helper：卡片 StyleBox / 暗角背景 / 字头圆章


func test_make_card_stylebox_has_gold_border_and_shadow() -> void:
	var sb := DT.make_card_stylebox(DT.BORDER_GOLD, "normal")
	assert_eq(sb.border_color, DT.BORDER_GOLD)
	assert_eq(sb.border_width_left, DT.CARD_BORDER)
	assert_gt(sb.shadow_size, 0, "卡片应有投影")
	assert_eq(sb.bg_color, DT.SURFACE_PANEL)


func test_make_card_stylebox_hover_brighter() -> void:
	var n := DT.make_card_stylebox(DT.TEXT_TITLE, "normal")
	var h := DT.make_card_stylebox(DT.TEXT_TITLE, "hover")
	assert_true(h.bg_color.r >= n.bg_color.r - 0.001, "hover 底应不低于 normal")


func test_make_centered_panel_is_centered() -> void:
	var p := DT.make_centered_panel(400, 300)
	assert_almost_eq(p.anchor_left, 0.5, 0.01)
	assert_almost_eq(p.offset_left, -200.0, 0.5)
	assert_not_null(p.get_theme_stylebox("panel"))


func test_run_ui_attach_background_adds_vignette() -> void:
	var root := Control.new()
	add_child_autofree(root)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	RunUi.attach_background(root)
	assert_not_null(root.get_node_or_null("RunVignette"), "应有暗角层")
	# 重复调用不叠第二层
	RunUi.attach_background(root)
	var n := 0
	for c in root.get_children():
		if c.name == "RunVignette":
			n += 1
	assert_eq(n, 1)


func test_make_glyph_badge_has_label() -> void:
	var badge := RunUi.make_glyph_badge("守", Color(0.3, 0.5, 0.9), 80)
	add_child_autofree(badge)
	var found := false
	for c in badge.get_children():
		if c is Label and (c as Label).text == "守":
			found = true
	assert_true(found, "字头圆章应有 Label")


func test_make_item_card_shell_title() -> void:
	var card := RunUi.make_item_card_shell(
		Vector2(200, 280), DT.TEXT_TITLE, "", "测试物", "稀有", "描述一行", 64)
	add_child_autofree(card)
	var title := card.find_child("CardTitle", true, false) as Label
	assert_not_null(title)
	assert_eq(title.text, "测试物")
