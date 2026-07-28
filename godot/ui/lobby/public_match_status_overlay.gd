class_name PublicMatchStatusOverlay extends Control

# #301：只读消费 PublicMatchCoordinator view 的生产可见层。
# 本类不持有 token、不推导网络状态；动作只转发给既有协调器。

signal cancel_requested
signal retry_requested
signal close_requested

var _state := "idle"
var _dim: ColorRect = null
var _modal: Panel = null
var _state_mark: Label = null
var _title: Label = null
var _detail: Label = null
var _reason: Label = null
var _cancel_btn: Button = null
var _retry_btn: Button = null
var _close_btn: Button = null
var _recovered_notice: PanelContainer = null


func _init() -> void:
	name = "PublicMatchStatusOverlay"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	z_index = 500
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()


func _ready() -> void:
	_wire_focus()


func get_hook_nodes() -> Array[Node]:
	var nodes: Array[Node] = []
	for node in [
		self, _dim, _modal, _state_mark, _title, _detail, _reason,
		_cancel_btn, _retry_btn, _close_btn, _recovered_notice,
	]:
		if node != null:
			nodes.append(node)
	return nodes


func is_blocking() -> bool:
	return visible and _modal != null and _modal.visible


func present(view: Dictionary) -> void:
	_state = str(view.get("state", "idle"))
	if _state in ["idle", "cancelled"]:
		visible = false
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		return
	visible = true
	if _state == "recovered":
		# 没有展示时长合同：只保留由真实 view 驱动的非动画、非阻断小提示。
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_dim.visible = false
		_modal.visible = false
		_recovered_notice.visible = true
		return
	_recovered_notice.visible = false
	_dim.visible = true
	_modal.visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_apply_copy(view)
	_apply_actions(view)
	_wire_focus()
	_focus_first_action()


func _build_ui() -> void:
	_dim = ColorRect.new()
	_dim.name = "PublicMatchDim"
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(DT.BG_BASE.r, DT.BG_BASE.g, DT.BG_BASE.b, DT.MODAL_BG_DIM * 0.72)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.gui_input.connect(_on_dim_gui_input)
	add_child(_dim)

	_modal = DT.make_centered_panel(520, 330)
	_modal.name = "PublicMatchModal"
	_modal.focus_mode = Control.FOCUS_ALL
	add_child(_modal)

	_state_mark = Label.new()
	_state_mark.name = "PublicMatchStateMark"
	_state_mark.position = Vector2(36, 30)
	_state_mark.size = Vector2(64, 56)
	_state_mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_state_mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_state_mark.add_theme_font_size_override("font_size", DT.FONT_TITLE)
	_state_mark.add_theme_color_override("font_color", DT.TEXT_TITLE)
	_modal.add_child(_state_mark)

	_title = Label.new()
	_title.name = "PublicMatchTitle"
	_title.position = Vector2(108, 28)
	_title.size = Vector2(376, 38)
	DT.apply_subtitle_style(_title)
	_modal.add_child(_title)

	_detail = Label.new()
	_detail.name = "PublicMatchDetail"
	_detail.position = Vector2(108, 70)
	_detail.size = Vector2(376, 26)
	DT.apply_body_style(_detail)
	_modal.add_child(_detail)

	_reason = Label.new()
	_reason.name = "PublicMatchReason"
	_reason.position = Vector2(44, 124)
	_reason.size = Vector2(432, 82)
	_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reason.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	DT.apply_caption_style(_reason)
	_modal.add_child(_reason)

	_cancel_btn = DT.make_button("取消匹配", DT.BtnRole.SECONDARY, Vector2(160, DT.BUTTON_H))
	_cancel_btn.name = "PublicMatchCancelButton"
	_cancel_btn.position = Vector2(180, 244)
	_cancel_btn.focus_mode = Control.FOCUS_ALL
	_cancel_btn.pressed.connect(_on_cancel_pressed)
	_modal.add_child(_cancel_btn)

	_retry_btn = DT.make_button("重新连接", DT.BtnRole.PRIMARY, Vector2(160, DT.BUTTON_H))
	_retry_btn.name = "PublicMatchRetryButton"
	_retry_btn.position = Vector2(180, 244)
	_retry_btn.focus_mode = Control.FOCUS_ALL
	_retry_btn.pressed.connect(_on_retry_pressed)
	_modal.add_child(_retry_btn)

	_close_btn = DT.make_button("关闭", DT.BtnRole.GHOST, Vector2(160, DT.BUTTON_H))
	_close_btn.name = "PublicMatchCloseButton"
	_close_btn.position = Vector2(180, 244)
	_close_btn.focus_mode = Control.FOCUS_ALL
	_close_btn.pressed.connect(_on_close_pressed)
	_modal.add_child(_close_btn)

	_recovered_notice = PanelContainer.new()
	_recovered_notice.name = "PublicMatchRecoveredNotice"
	_recovered_notice.anchor_left = 0.5
	_recovered_notice.anchor_right = 0.5
	_recovered_notice.offset_left = -150
	_recovered_notice.offset_right = 150
	_recovered_notice.offset_top = 24
	_recovered_notice.offset_bottom = 72
	_recovered_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var recovered_style := DT.make_card_stylebox(DT.TEXT_SUCCESS, "normal")
	_recovered_notice.add_theme_stylebox_override("panel", recovered_style)
	add_child(_recovered_notice)
	var recovered_label := Label.new()
	recovered_label.text = "◇ 结界已复原"
	recovered_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	recovered_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	recovered_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	DT.apply_body_style(recovered_label)
	_recovered_notice.add_child(recovered_label)


func _apply_copy(view: Dictionary) -> void:
	var round_label := "半庄战" if str(view.get("round_kind", "")) == "HANCHAN" else "东风战"
	var mode_label := "嘴强欢乐场" if str(view.get("game_mode", "")) == "TRASH_TALK" else "标准场"
	_detail.text = "%s · %s" % [round_label, mode_label]
	_reason.text = str(view.get("message", ""))
	match _state:
		"joining":
			_state_mark.text = "◉"
			_title.text = "正在缔结匹配契约"
			_reason.text = "正在连接公共匹配服务，请稍候。"
		"waiting":
			_state_mark.text = "◎"
			_title.text = "等待匹配"
			if _reason.text.is_empty():
				_reason.text = "仪式席位正在汇集；取消只会调用真实队列动作。"
		"matched":
			_state_mark.text = "◇"
			_title.text = "席位已锁定"
			_reason.text = "正在进入已分配的牌桌。"
		"reconnecting":
			_state_mark.text = "⟲"
			_title.text = "正在重连"
			if _reason.text.is_empty():
				_reason.text = str(view.get("error_code", "连接已断开"))
		"terminal_error":
			_state_mark.text = "!"
			_title.text = "结界连接失败"
			var code := str(view.get("error_code", ""))
			if _reason.text.is_empty():
				_reason.text = code if not code.is_empty() else "公共匹配暂不可用。"
			elif not code.is_empty():
				_reason.text = "%s\n%s" % [code, _reason.text]
		_:
			_state_mark.text = "◇"
			_title.text = "公共匹配"


func _apply_actions(view: Dictionary) -> void:
	_cancel_btn.visible = _state == "waiting"
	_cancel_btn.disabled = not bool(view.get("can_cancel", false))
	_cancel_btn.tooltip_text = "等待权威队列允许取消" if _cancel_btn.disabled else "取消当前匹配"
	_retry_btn.visible = _state == "reconnecting"
	_retry_btn.disabled = not bool(view.get("can_retry", false))
	_retry_btn.tooltip_text = "当前连接尚不可重试" if _retry_btn.disabled else "重新连接当前房间"
	_close_btn.visible = _state == "terminal_error"
	_close_btn.disabled = false


func _focus_first_action() -> void:
	for control in [_cancel_btn, _retry_btn, _close_btn]:
		if control.visible and not control.disabled:
			control.grab_focus()
			return
	_modal.grab_focus()


func _wire_focus() -> void:
	if _cancel_btn == null or _retry_btn == null or _close_btn == null:
		return
	for button in [_cancel_btn, _retry_btn, _close_btn]:
		button.focus_next = button.get_path_to(button)
		button.focus_previous = button.get_path_to(button)


func _on_cancel_pressed() -> void:
	if _state == "waiting" and not _cancel_btn.disabled:
		cancel_requested.emit()


func _on_retry_pressed() -> void:
	if _state == "reconnecting" and not _retry_btn.disabled:
		retry_requested.emit()


func _on_close_pressed() -> void:
	if _state == "terminal_error":
		close_requested.emit()


func _on_dim_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		accept_event()


func _input(event: InputEvent) -> void:
	if not is_blocking():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
