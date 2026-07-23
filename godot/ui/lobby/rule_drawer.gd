class_name RuleDrawer extends Control

# 大厅规则选择抽屉（E1-04 / #228）。
# 同一实例服务电脑练习与公共匹配；只输出 SessionIntent，不启动牌局。

signal confirmed(intent: SessionIntent)
signal cancelled

const DRAWER_W: float = 520.0
const OPEN_SEC: float = 0.22

var _room_kind: StringName = &"PRACTICE"
var _panel: PanelContainer = null
var _title: Label = null
var _back_btn: Button = null
var _east_btn: Button = null
var _hanchan_btn: Button = null
var _standard_btn: Button = null
var _trash_talk_btn: Button = null
var _cancel_btn: Button = null
var _start_btn: Button = null
var _round_group: ButtonGroup = null
var _mode_group: ButtonGroup = null
var _tween: Tween = null
var _built: bool = false


func _init() -> void:
	name = "RuleDrawer"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()


func _ready() -> void:
	# get_path_to 需在树内才可靠；进树后再锁焦点图。
	_wire_focus_graph()


func get_hook_nodes() -> Array[Node]:
	var nodes: Array[Node] = []
	for n in [
		_panel,
		_back_btn,
		_title,
		_east_btn,
		_hanchan_btn,
		_standard_btn,
		_trash_talk_btn,
		_cancel_btn,
		_start_btn,
	]:
		if n != null:
			nodes.append(n)
	return nodes


## 打开抽屉：每次重置为东风战 + 标准场。
func open_for(room_kind: StringName) -> void:
	_room_kind = room_kind
	_apply_title()
	_reset_selection()
	_play_open_anim()
	if _east_btn:
		_east_btn.grab_focus()


func close_visual() -> void:
	if _tween and is_instance_valid(_tween):
		_tween.kill()
		_tween = null
	_snap_panel_closed()


func _snap_panel_closed() -> void:
	if _panel == null:
		return
	_panel.offset_left = 0.0
	_panel.offset_right = DRAWER_W


func _snap_panel_open() -> void:
	if _panel == null:
		return
	_panel.offset_left = -DRAWER_W
	_panel.offset_right = 0.0


func _build_ui() -> void:
	if _built:
		return
	_built = true

	var dim := ColorRect.new()
	dim.name = "DrawerDim"
	dim.color = Color(0, 0, 0, DesignTokens.MODAL_BG_DIM * 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_dim_gui_input)
	add_child(dim)

	_panel = PanelContainer.new()
	_panel.name = "RuleDrawerPanel"
	_panel.custom_minimum_size = Vector2(DRAWER_W, 0)
	# 锚定右侧全高；用 offset 做入场滑动，不依赖首帧 size。
	_panel.anchor_left = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_top = 0.0
	_panel.offset_bottom = 0.0
	_snap_panel_closed()
	var sb := StyleBoxFlat.new()
	sb.bg_color = DesignTokens.SURFACE_PANEL
	sb.border_color = DesignTokens.BORDER_GOLD
	sb.border_width_left = DesignTokens.CARD_BORDER
	sb.border_width_top = 0
	sb.border_width_right = 0
	sb.border_width_bottom = 0
	sb.content_margin_left = DesignTokens.GAP_LOOSE
	sb.content_margin_right = DesignTokens.GAP_LOOSE
	sb.content_margin_top = DesignTokens.GAP_NORMAL
	sb.content_margin_bottom = DesignTokens.GAP_NORMAL
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 18
	sb.shadow_offset = Vector2(-6, 0)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)

	var root := VBoxContainer.new()
	root.name = "DrawerRoot"
	root.add_theme_constant_override("separation", DesignTokens.GAP_LOOSE)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel.add_child(root)

	root.add_child(_build_header())
	root.add_child(_build_round_section())
	root.add_child(_build_mode_section())

	var spacer := Control.new()
	spacer.name = "DrawerSpacer"
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(spacer)

	root.add_child(_build_footer())
	_apply_title()
	_reset_selection()


func _build_header() -> Control:
	var row := HBoxContainer.new()
	row.name = "DrawerHeader"
	row.add_theme_constant_override("separation", DesignTokens.GAP_NORMAL)

	_back_btn = DesignTokens.make_button("返回", DesignTokens.BtnRole.GHOST, Vector2(88, DesignTokens.BUTTON_H))
	_back_btn.name = "DrawerBackButton"
	_back_btn.focus_mode = Control.FOCUS_ALL
	_back_btn.pressed.connect(_emit_cancelled)
	row.add_child(_back_btn)

	_title = Label.new()
	_title.name = "DrawerTitle"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", DesignTokens.FONT_SUBTITLE)
	_title.add_theme_color_override("font_color", DesignTokens.TEXT_TITLE)
	row.add_child(_title)
	return row


func _build_round_section() -> Control:
	var col := VBoxContainer.new()
	col.name = "RoundSection"
	col.add_theme_constant_override("separation", DesignTokens.GAP_TIGHT)

	var caption := Label.new()
	caption.name = "RoundCaption"
	caption.text = "局制"
	caption.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	caption.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)
	col.add_child(caption)

	var row := HBoxContainer.new()
	row.name = "RoundRow"
	row.add_theme_constant_override("separation", DesignTokens.GAP_NORMAL)
	col.add_child(row)

	_round_group = ButtonGroup.new()
	_round_group.allow_unpress = false

	_east_btn = _make_choice_button("EastButton", "东风战", _round_group)
	_hanchan_btn = _make_choice_button("HanchanButton", "半庄战", _round_group)
	row.add_child(_east_btn)
	row.add_child(_hanchan_btn)
	return col


func _build_mode_section() -> Control:
	var col := VBoxContainer.new()
	col.name = "ModeSection"
	col.add_theme_constant_override("separation", DesignTokens.GAP_TIGHT)

	var caption := Label.new()
	caption.name = "ModeCaption"
	caption.text = "玩法"
	caption.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	caption.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)
	col.add_child(caption)

	var row := VBoxContainer.new()
	row.name = "ModeRow"
	row.add_theme_constant_override("separation", DesignTokens.GAP_TIGHT)
	col.add_child(row)

	_mode_group = ButtonGroup.new()
	_mode_group.allow_unpress = false

	_standard_btn = _make_choice_button("StandardButton", "标准场", _mode_group)
	_trash_talk_btn = _make_choice_button("TrashTalkButton", "嘴强欢乐场", _mode_group)
	_standard_btn.custom_minimum_size = Vector2(0, 64)
	_trash_talk_btn.custom_minimum_size = Vector2(0, 64)
	_standard_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_trash_talk_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_standard_btn)
	row.add_child(_trash_talk_btn)

	var hint := Label.new()
	hint.name = "ModeHint"
	hint.text = "标准场纯日麻；欢乐场启用角色与道具"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	DesignTokens.apply_caption_style(hint)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(hint)
	return col


func _build_footer() -> Control:
	var row := HBoxContainer.new()
	row.name = "DrawerFooter"
	row.add_theme_constant_override("separation", DesignTokens.GAP_NORMAL)
	row.alignment = BoxContainer.ALIGNMENT_END

	_cancel_btn = DesignTokens.make_button(
		"取消", DesignTokens.BtnRole.SECONDARY, Vector2(140, DesignTokens.BUTTON_H)
	)
	_cancel_btn.name = "DrawerCancelButton"
	_cancel_btn.focus_mode = Control.FOCUS_ALL
	_cancel_btn.pressed.connect(_emit_cancelled)
	row.add_child(_cancel_btn)

	_start_btn = DesignTokens.make_button(
		"开始", DesignTokens.BtnRole.PRIMARY, Vector2(180, DesignTokens.BUTTON_H)
	)
	_start_btn.name = "DrawerStartButton"
	_start_btn.focus_mode = Control.FOCUS_ALL
	_start_btn.pressed.connect(_emit_confirmed)
	row.add_child(_start_btn)
	return row


func _make_choice_button(btn_name: String, text: String, group: ButtonGroup) -> Button:
	var btn := DesignTokens.make_button(text, DesignTokens.BtnRole.SECONDARY, Vector2(200, 56))
	btn.name = btn_name
	btn.toggle_mode = true
	btn.button_group = group
	btn.focus_mode = Control.FOCUS_ALL
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return btn


## 方向键八条契约 + Tab 循环顺序。
func _wire_focus_graph() -> void:
	if _back_btn == null or _east_btn == null or _hanchan_btn == null:
		return
	if _standard_btn == null or _trash_talk_btn == null:
		return
	if _cancel_btn == null or _start_btn == null:
		return

	# 方向键：测试契约 + 对称回边；左右显式闭合，防止焦点逃回大厅
	_back_btn.focus_neighbor_bottom = _back_btn.get_path_to(_east_btn)
	_back_btn.focus_neighbor_top = _back_btn.get_path_to(_start_btn)
	_back_btn.focus_neighbor_right = _back_btn.get_path_to(_east_btn)
	_back_btn.focus_neighbor_left = _back_btn.get_path_to(_start_btn)

	_east_btn.focus_neighbor_right = _east_btn.get_path_to(_hanchan_btn)
	_east_btn.focus_neighbor_left = _east_btn.get_path_to(_hanchan_btn)
	_east_btn.focus_neighbor_bottom = _east_btn.get_path_to(_standard_btn)
	_east_btn.focus_neighbor_top = _east_btn.get_path_to(_back_btn)

	_hanchan_btn.focus_neighbor_left = _hanchan_btn.get_path_to(_east_btn)
	_hanchan_btn.focus_neighbor_right = _hanchan_btn.get_path_to(_east_btn)
	_hanchan_btn.focus_neighbor_bottom = _hanchan_btn.get_path_to(_standard_btn)
	_hanchan_btn.focus_neighbor_top = _hanchan_btn.get_path_to(_back_btn)

	_standard_btn.focus_neighbor_top = _standard_btn.get_path_to(_east_btn)
	_standard_btn.focus_neighbor_bottom = _standard_btn.get_path_to(_trash_talk_btn)
	_standard_btn.focus_neighbor_left = _standard_btn.get_path_to(_east_btn)
	_standard_btn.focus_neighbor_right = _standard_btn.get_path_to(_hanchan_btn)

	_trash_talk_btn.focus_neighbor_top = _trash_talk_btn.get_path_to(_standard_btn)
	_trash_talk_btn.focus_neighbor_bottom = _trash_talk_btn.get_path_to(_cancel_btn)
	_trash_talk_btn.focus_neighbor_left = _trash_talk_btn.get_path_to(_east_btn)
	_trash_talk_btn.focus_neighbor_right = _trash_talk_btn.get_path_to(_hanchan_btn)

	_cancel_btn.focus_neighbor_right = _cancel_btn.get_path_to(_start_btn)
	_cancel_btn.focus_neighbor_left = _cancel_btn.get_path_to(_start_btn)
	_cancel_btn.focus_neighbor_top = _cancel_btn.get_path_to(_trash_talk_btn)
	_cancel_btn.focus_neighbor_bottom = _cancel_btn.get_path_to(_back_btn)

	_start_btn.focus_neighbor_left = _start_btn.get_path_to(_cancel_btn)
	_start_btn.focus_neighbor_right = _start_btn.get_path_to(_cancel_btn)
	_start_btn.focus_neighbor_top = _start_btn.get_path_to(_trash_talk_btn)
	_start_btn.focus_neighbor_bottom = _start_btn.get_path_to(_back_btn)

	# Tab / Shift+Tab：返回 → 东风 → 半庄 → 标准 → 欢乐 → 取消 → 开始 → 返回
	_back_btn.focus_next = _back_btn.get_path_to(_east_btn)
	_east_btn.focus_next = _east_btn.get_path_to(_hanchan_btn)
	_hanchan_btn.focus_next = _hanchan_btn.get_path_to(_standard_btn)
	_standard_btn.focus_next = _standard_btn.get_path_to(_trash_talk_btn)
	_trash_talk_btn.focus_next = _trash_talk_btn.get_path_to(_cancel_btn)
	_cancel_btn.focus_next = _cancel_btn.get_path_to(_start_btn)
	_start_btn.focus_next = _start_btn.get_path_to(_back_btn)

	_back_btn.focus_previous = _back_btn.get_path_to(_start_btn)
	_east_btn.focus_previous = _east_btn.get_path_to(_back_btn)
	_hanchan_btn.focus_previous = _hanchan_btn.get_path_to(_east_btn)
	_standard_btn.focus_previous = _standard_btn.get_path_to(_hanchan_btn)
	_trash_talk_btn.focus_previous = _trash_talk_btn.get_path_to(_standard_btn)
	_cancel_btn.focus_previous = _cancel_btn.get_path_to(_trash_talk_btn)
	_start_btn.focus_previous = _start_btn.get_path_to(_cancel_btn)


func _apply_title() -> void:
	if _title == null:
		return
	if _room_kind == &"PUBLIC_CASUAL":
		_title.text = "公共匹配 · 规则选择"
	else:
		_title.text = "电脑练习 · 规则选择"


func _reset_selection() -> void:
	if _east_btn:
		_east_btn.button_pressed = true
	if _hanchan_btn:
		_hanchan_btn.button_pressed = false
	if _standard_btn:
		_standard_btn.button_pressed = true
	if _trash_talk_btn:
		_trash_talk_btn.button_pressed = false


func _current_round_kind() -> StringName:
	if _hanchan_btn and _hanchan_btn.button_pressed:
		return &"HANCHAN"
	return &"EAST"


func _current_game_mode() -> StringName:
	if _trash_talk_btn and _trash_talk_btn.button_pressed:
		return &"TRASH_TALK"
	return &"STANDARD"


func _emit_confirmed() -> void:
	var intent := SessionIntent.new(_room_kind, _current_round_kind(), _current_game_mode())
	confirmed.emit(intent)


func _emit_cancelled() -> void:
	cancelled.emit()


func _on_dim_gui_input(event: InputEvent) -> void:
	# 点击遮罩不关闭（仅取消/返回/Esc），避免误触；仍消费事件挡住大厅。
	if event is InputEventMouseButton and event.pressed:
		accept_event()


func _play_open_anim() -> void:
	if _panel == null:
		return
	if _tween and is_instance_valid(_tween):
		_tween.kill()
	_snap_panel_closed()
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_panel, "offset_left", -DRAWER_W, OPEN_SEC)
	_tween.parallel().tween_property(_panel, "offset_right", 0.0, OPEN_SEC)
