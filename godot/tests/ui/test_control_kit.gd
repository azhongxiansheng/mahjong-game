extends GutTest

# DT 交互控件 kit：按钮角色 / 滑条 / 主题补丁

const EXPECTED_PRIMARY := Color("c99a55")
const EXPECTED_SECONDARY := Color("8f8577")
const EXPECTED_DANGER := Color("c9675f")
const EXPECTED_FOCUS := Color("d7b56d")
const EXPECTED_TEXT := Color("eee9df")


func test_make_button_primary_uses_narrow_copper_edge() -> void:
	var btn := DT.make_button("确定", DT.BtnRole.PRIMARY)
	add_child_autofree(btn)
	var sb: StyleBoxFlat = btn.get_theme_stylebox("normal") as StyleBoxFlat
	assert_not_null(sb)
	assert_eq(sb.border_color, EXPECTED_PRIMARY)
	assert_eq(sb.border_width_left, 1, "方案 A 常态必须是 1px 窄边")
	assert_eq(btn.get_theme_color("font_color"), EXPECTED_TEXT)


func test_make_button_danger_red_border() -> void:
	var btn := DT.make_button("删除", DT.BtnRole.DANGER)
	add_child_autofree(btn)
	var sb: StyleBoxFlat = btn.get_theme_stylebox("normal") as StyleBoxFlat
	assert_not_null(sb)
	assert_eq(sb.border_color, EXPECTED_DANGER)


func test_make_button_secondary_soft_border() -> void:
	var btn := DT.make_button("取消", DT.BtnRole.SECONDARY)
	add_child_autofree(btn)
	var sb: StyleBoxFlat = btn.get_theme_stylebox("normal") as StyleBoxFlat
	assert_not_null(sb)
	assert_eq(sb.border_color, EXPECTED_SECONDARY)


func test_button_roles_share_obsidian_talisman_five_state_contract() -> void:
	for role in [DT.BtnRole.PRIMARY, DT.BtnRole.SECONDARY, DT.BtnRole.DANGER, DT.BtnRole.GHOST]:
		var btn := DT.make_button("状态", role)
		add_child_autofree(btn)
		for state in ["normal", "hover", "focus", "pressed", "disabled"]:
			assert_true(btn.get_theme_stylebox(state) is StyleBoxFlat,
				"角色 %s 的 %s 必须使用内建 StyleBoxFlat" % [role, state])
		var normal := btn.get_theme_stylebox("normal") as StyleBoxFlat
		var hover := btn.get_theme_stylebox("hover") as StyleBoxFlat
		var focus := btn.get_theme_stylebox("focus") as StyleBoxFlat
		var pressed := btn.get_theme_stylebox("pressed") as StyleBoxFlat
		var disabled := btn.get_theme_stylebox("disabled") as StyleBoxFlat
		assert_eq(normal.corner_radius_top_left, 2)
		assert_eq(normal.corner_radius_top_right, 7)
		assert_eq(normal.corner_radius_bottom_right, 2)
		assert_eq(normal.corner_radius_bottom_left, 7)
		if role == DT.BtnRole.GHOST:
			assert_eq(normal.border_width_left, 0, "Ghost 可用态保持开放边缘")
			assert_gt(disabled.border_width_left, normal.border_width_left,
				"Ghost disabled 以断续侧缘区别可用态")
		else:
			assert_eq(normal.border_width_left, 1)
			assert_eq(normal.border_width_top, 1)
			assert_eq(normal.border_width_right, 1)
			assert_eq(normal.border_width_bottom, 1)
		assert_gt(hover.border_width_top, normal.border_width_top,
			"hover 除提亮外还要加粗上缘")
		assert_eq(focus.bg_color.a, 0.0, "focus 是独立透明叠层，不能冒充 hover 底色")
		assert_eq(focus.border_color, EXPECTED_FOCUS)
		assert_gt(focus.border_width_left, hover.border_width_left,
			"focus 需要独立左侧记号")
		assert_eq(pressed.content_margin_top - pressed.content_margin_bottom, 4.0,
			"pressed 仅把文字下移 2px，不缩放控件")
		assert_eq(disabled.border_width_top, 0,
			"disabled 必须断开上下缘，提供非颜色提示")
		assert_eq(disabled.border_width_bottom, 0)
		assert_eq(disabled.shadow_size, 0)


func test_button_text_is_single_line_ellipsis_with_full_tooltip() -> void:
	var long_text := "Supercalifragilisticexpialidocious"
	var btn := DT.make_button(long_text, DT.BtnRole.SECONDARY, Vector2(140, 48))
	add_child_autofree(btn)
	assert_true(btn.clip_text)
	assert_eq(btn.text_overrun_behavior, TextServer.OVERRUN_TRIM_ELLIPSIS)
	assert_eq(btn.tooltip_text, long_text)
	assert_eq(btn.custom_minimum_size, Vector2(140, 48),
		"文字策略不得反向撑大调用方固定槽位")
	assert_eq(btn.get_theme_font_size("font_size"), DT.FONT_BODY,
		"不得缩到 10–12px 掩盖溢出")


func test_explicit_compact_height_is_preserved_but_unset_button_gets_standard_height() -> void:
	var compact := DT.make_button("试听", DT.BtnRole.SECONDARY, Vector2(76, 34))
	add_child_autofree(compact)
	assert_eq(compact.custom_minimum_size, Vector2(76, 34))
	var raw := Button.new()
	raw.text = "返回"
	add_child_autofree(raw)
	DT.apply_button_role(raw, DT.BtnRole.GHOST)
	assert_eq(raw.custom_minimum_size.y, float(DT.BUTTON_H))


func test_lobby_material_compatibility_entry_keeps_shared_role_style() -> void:
	var btn := DT.make_button("开始", DT.BtnRole.PRIMARY, Vector2(180, 48))
	add_child_autofree(btn)
	DT.apply_lobby_material_button(btn)
	var normal := btn.get_theme_stylebox("normal") as StyleBoxFlat
	assert_not_null(normal)
	if normal != null:
		assert_eq(normal.border_color, EXPECTED_PRIMARY)


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
		var tooltip := theme.get_stylebox("panel", "TooltipPanel") as StyleBoxFlat
		assert_not_null(tooltip)
		if tooltip != null:
			assert_eq(tooltip.bg_color, Color("111217f5"))
			assert_eq(tooltip.border_width_left, 1)
