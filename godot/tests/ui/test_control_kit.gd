extends GutTest

# DT 交互控件 kit：按钮角色 / 滑条 / 主题补丁


func test_make_button_primary_has_gold_border() -> void:
	var btn := DT.make_button("确定", DT.BtnRole.PRIMARY)
	add_child_autofree(btn)
	var sb: StyleBoxFlat = btn.get_theme_stylebox("normal") as StyleBoxFlat
	assert_not_null(sb)
	assert_eq(sb.border_color, DT.BORDER_GOLD)
	assert_eq(btn.get_theme_color("font_color"), DT.TEXT_TITLE)


func test_make_button_danger_red_border() -> void:
	var btn := DT.make_button("删除", DT.BtnRole.DANGER)
	add_child_autofree(btn)
	var sb: StyleBoxFlat = btn.get_theme_stylebox("normal") as StyleBoxFlat
	assert_not_null(sb)
	assert_eq(sb.border_color, DT.TEXT_DANGER)


func test_make_button_secondary_soft_border() -> void:
	var btn := DT.make_button("取消", DT.BtnRole.SECONDARY)
	add_child_autofree(btn)
	var sb: StyleBoxFlat = btn.get_theme_stylebox("normal") as StyleBoxFlat
	assert_not_null(sb)
	assert_eq(sb.border_color, DT.BORDER_GOLD_SOFT)


func test_style_hslider_sets_min_height() -> void:
	var s := HSlider.new()
	add_child_autofree(s)
	DT.style_hslider(s)
	assert_gte(s.custom_minimum_size.y, 28.0)
	assert_not_null(s.get_theme_stylebox("slider"))


func test_style_option_button_applies() -> void:
	var o := OptionButton.new()
	add_child_autofree(o)
	DT.style_option_button(o)
	assert_not_null(o.get_theme_stylebox("normal"))


func test_style_line_edit_applies() -> void:
	var le := LineEdit.new()
	add_child_autofree(le)
	DT.style_line_edit(le)
	assert_not_null(le.get_theme_stylebox("normal"))
	assert_eq(le.get_theme_color("font_color"), DT.TEXT_PRIMARY)


func test_patch_project_theme_idempotent() -> void:
	# DT autoload 启动已 patch；再调一次不崩
	DT.patch_project_theme()
	DT.patch_project_theme()
	assert_true(DT._theme_patched)
	var theme: Theme = ThemeDB.get_project_theme()
	if theme:
		assert_not_null(theme.get_stylebox("slider", "HSlider"))
		assert_not_null(theme.get_stylebox("panel", "PopupMenu"))
