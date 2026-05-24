class_name SettingsOverlay extends Control

# 设置 overlay — ESC 唤起,1 个滑条(SFX 音量)+ 关闭按钮。
# 暗背景 + 中央 Panel,接 SettingsManager 持久化。
#
# 由 PlayableTable / RunFlow 在 _input 监到 ESC 时实例化挂到根。

signal closed

const PANEL_W: int = 460
const PANEL_H: int = 320

var _sfx_slider: HSlider = null
var _sfx_value_label: Label = null


func _init() -> void:
	# 全屏接管 mouse 防穿透
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	# 全屏暗背景
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.72)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# 中央面板(StyleBoxFlat 暗底)
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(PANEL_W, PANEL_H)
	panel.size = Vector2(PANEL_W, PANEL_H)
	# 居中
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -PANEL_W / 2.0
	panel.offset_top = -PANEL_H / 2.0
	panel.offset_right = PANEL_W / 2.0
	panel.offset_bottom = PANEL_H / 2.0
	add_child(panel)

	# 标题
	var title := Label.new()
	title.text = "设置"
	title.position = Vector2(0, 22)
	title.size = Vector2(PANEL_W, 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.5))
	panel.add_child(title)

	# SFX 音量
	var sfx_label := Label.new()
	sfx_label.text = "音效音量"
	sfx_label.position = Vector2(40, 90)
	sfx_label.size = Vector2(160, 28)
	sfx_label.add_theme_font_size_override("font_size", 18)
	sfx_label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.78))
	panel.add_child(sfx_label)

	_sfx_slider = HSlider.new()
	_sfx_slider.position = Vector2(40, 124)
	_sfx_slider.size = Vector2(PANEL_W - 80 - 60, 28)
	_sfx_slider.min_value = 0.0
	_sfx_slider.max_value = 1.0
	_sfx_slider.step = 0.01
	_sfx_slider.value = _sm().sfx_volume
	_sfx_slider.value_changed.connect(_on_sfx_changed)
	panel.add_child(_sfx_slider)

	_sfx_value_label = Label.new()
	_sfx_value_label.position = Vector2(PANEL_W - 90, 122)
	_sfx_value_label.size = Vector2(60, 30)
	_sfx_value_label.text = "%d%%" % int(_sm().sfx_volume * 100)
	_sfx_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_sfx_value_label.add_theme_font_size_override("font_size", 18)
	_sfx_value_label.add_theme_color_override("font_color", Color(1, 0.9, 0.55))
	panel.add_child(_sfx_value_label)

	# 试听按钮 — 点了奏 button_click,玩家立刻听到当前音量
	var test_btn := Button.new()
	test_btn.text = "试听"
	test_btn.position = Vector2(40, 174)
	test_btn.custom_minimum_size = Vector2(100, 36)
	test_btn.pressed.connect(_on_test_pressed)
	panel.add_child(test_btn)

	# 重看新手引导按钮(清 tutorial_seen 标志 + 立刻弹 TutorialOverlay)
	var tut_btn := Button.new()
	tut_btn.text = "重看新手引导"
	tut_btn.position = Vector2(160, 174)
	tut_btn.custom_minimum_size = Vector2(160, 36)
	tut_btn.pressed.connect(_on_tutorial_pressed)
	panel.add_child(tut_btn)

	# 查看战绩按钮(开 StatsView overlay)
	var stats_btn := Button.new()
	stats_btn.text = "查看战绩"
	stats_btn.position = Vector2(40, PANEL_H - 60)
	stats_btn.custom_minimum_size = Vector2(120, 40)
	stats_btn.pressed.connect(_on_stats_pressed)
	panel.add_child(stats_btn)

	# 放弃本场 Run 按钮 — 仅当当前有进行中的 run 时可见(SaveSystem.has_save)
	var ss = get_node_or_null("/root/SaveSystem")
	if ss and ss.has_save():
		var quit_btn := Button.new()
		quit_btn.text = "放弃本场"
		quit_btn.position = Vector2(170, PANEL_H - 60)
		quit_btn.custom_minimum_size = Vector2(120, 40)
		# 猩红 styling 警示
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.45, 0.18, 0.18)
		sb.border_color = Color(0.85, 0.32, 0.32)
		sb.border_width_left = 2
		sb.border_width_right = 2
		sb.border_width_top = 2
		sb.border_width_bottom = 2
		sb.corner_radius_top_left = 4
		sb.corner_radius_top_right = 4
		sb.corner_radius_bottom_left = 4
		sb.corner_radius_bottom_right = 4
		quit_btn.add_theme_stylebox_override("normal", sb)
		quit_btn.add_theme_color_override("font_color", Color(1, 0.92, 0.85))
		quit_btn.pressed.connect(_on_quit_run_pressed)
		panel.add_child(quit_btn)

	# 关闭按钮
	var close_btn := Button.new()
	close_btn.text = "关闭 (ESC)"
	close_btn.position = Vector2(PANEL_W - 40 - 140, PANEL_H - 60)
	close_btn.custom_minimum_size = Vector2(140, 40)
	close_btn.pressed.connect(_on_close)
	panel.add_child(close_btn)

	# 设为最顶层(其它 overlay/HUD 不挡)
	z_index = 100


func _on_stats_pressed() -> void:
	var view := StatsView.new()
	view.name = "_stats_view_root"
	get_tree().root.add_child(view)


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k: InputEventKey = event
		if k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
			_on_close()
			get_viewport().set_input_as_handled()


func _on_sfx_changed(v: float) -> void:
	_sm().set_sfx_volume(v)
	if _sfx_value_label:
		_sfx_value_label.text = "%d%%" % int(v * 100)


func _on_test_pressed() -> void:
	var am = get_node_or_null("/root/AudioManager")
	if am:
		am.play("tile_click")


func _on_tutorial_pressed() -> void:
	# 关闭本 overlay,在 root 弹 TutorialOverlay
	var t := TutorialOverlay.new()
	t.name = "_tutorial_overlay_root"
	get_tree().root.add_child(t)
	_on_close()


# 放弃本场 Run — 弹 ConfirmDialog,确认 → SaveSystem.clear_run() + 退出战斗。
# 用 get_tree().reload_current_scene() 简洁地把当前场景重置,回到 run_flow 起点
# (检测无存档 → starter picker)。
func _on_quit_run_pressed() -> void:
	var d := ConfirmDialog.show_dialog(
		"放弃当前 Run?",
		"你的 Run 进度将被清除,这是不可逆操作。回到主菜单后请重新开始。",
		"确认放弃", "取消", true)
	d.confirmed.connect(_on_quit_confirmed)
	get_tree().root.add_child(d)


func _on_quit_confirmed() -> void:
	var ss = get_node_or_null("/root/SaveSystem")
	if ss:
		ss.clear_run()
	# 关 settings overlay 然后 reload current_scene 回 run_flow start
	_on_close()
	# defer 避免 reload 时还在 settings 的 _input 解栈链上
	get_tree().call_deferred("reload_current_scene")


func _on_close() -> void:
	closed.emit()
	queue_free()


func _sm() -> Node:
	return get_node("/root/SettingsManager")
