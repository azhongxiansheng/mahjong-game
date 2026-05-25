class_name ConfirmDialog extends Control

# 通用确认对话框 — yes/no 二选一。用于不可逆操作前的"你确定吗"提示。
#
# 用法:
#   var d := ConfirmDialog.show_dialog("放弃当前 Run?", "进度将丢失,该 Run 不可恢复",
#                                       "确认放弃", "取消")
#   d.confirmed.connect(...)
#   d.cancelled.connect(...)
#   get_tree().root.add_child(d)
#
# ESC 或点取消 = cancelled,Enter 或点确认 = confirmed。点击 overlay 外不响应
# (mouse_filter=STOP)。1.5s 内无响应不自动 dismiss。

signal confirmed
signal cancelled

const PANEL_W: int = 480
const PANEL_H: int = 220


var _title: String = ""
var _message: String = ""
var _confirm_text: String = "确认"
var _cancel_text: String = "取消"
var _destructive: bool = false  # 确认按钮显猩红(强调不可逆)


static func show_dialog(title: String, message: String,
		confirm_text: String = "确认", cancel_text: String = "取消",
		destructive: bool = true) -> ConfirmDialog:
	var d := ConfirmDialog.new()
	d._title = title
	d._message = message
	d._confirm_text = confirm_text
	d._cancel_text = cancel_text
	d._destructive = destructive
	return d


func _init() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 250  # 高于 SettingsOverlay / TutorialOverlay


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(DT.BG_BASE.r, DT.BG_BASE.g, DT.BG_BASE.b, DT.MODAL_BG_DIM)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(PANEL_W, PANEL_H)
	panel.size = Vector2(PANEL_W, PANEL_H)
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -PANEL_W / 2.0
	panel.offset_top = -PANEL_H / 2.0
	panel.offset_right = PANEL_W / 2.0
	panel.offset_bottom = PANEL_H / 2.0
	add_child(panel)

	var title_lbl := Label.new()
	title_lbl.text = _title
	title_lbl.position = Vector2(0, 28)
	title_lbl.size = Vector2(PANEL_W, 36)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", DT.FONT_SUBTITLE)
	title_lbl.add_theme_color_override("font_color",
		DT.TEXT_DANGER if _destructive else DT.TEXT_TITLE)
	panel.add_child(title_lbl)

	var msg_lbl := Label.new()
	msg_lbl.text = _message
	msg_lbl.position = Vector2(30, 72)
	msg_lbl.size = Vector2(PANEL_W - 60, 70)
	msg_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	msg_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg_lbl.add_theme_font_size_override("font_size", DT.FONT_BODY)
	msg_lbl.add_theme_color_override("font_color", DT.TEXT_PRIMARY)
	panel.add_child(msg_lbl)

	# Cancel 在左,Confirm 在右 — Windows/macOS 通用习惯
	var cancel_btn := Button.new()
	cancel_btn.text = _cancel_text
	cancel_btn.position = Vector2(40, PANEL_H - 60)
	cancel_btn.custom_minimum_size = Vector2(140, 40)
	cancel_btn.pressed.connect(_on_cancel)
	panel.add_child(cancel_btn)

	var confirm_btn := Button.new()
	confirm_btn.text = _confirm_text
	confirm_btn.position = Vector2(PANEL_W - 40 - 140, PANEL_H - 60)
	confirm_btn.custom_minimum_size = Vector2(140, 40)
	if _destructive:
		# 猩红 styling 强调"不可逆"
		var sb_normal := StyleBoxFlat.new()
		sb_normal.bg_color = Color(DT.TEXT_DANGER.r * 0.6, DT.TEXT_DANGER.g * 0.2, DT.TEXT_DANGER.b * 0.2)
		sb_normal.border_color = DT.TEXT_DANGER
		sb_normal.border_width_left = 2
		sb_normal.border_width_right = 2
		sb_normal.border_width_top = 2
		sb_normal.border_width_bottom = 2
		sb_normal.corner_radius_top_left = 4
		sb_normal.corner_radius_top_right = 4
		sb_normal.corner_radius_bottom_left = 4
		sb_normal.corner_radius_bottom_right = 4
		confirm_btn.add_theme_stylebox_override("normal", sb_normal)
		confirm_btn.add_theme_color_override("font_color", DT.TEXT_PRIMARY)
	confirm_btn.pressed.connect(_on_confirm)
	panel.add_child(confirm_btn)


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k: InputEventKey = event
		if k.pressed and not k.echo:
			match k.keycode:
				KEY_ESCAPE:
					_on_cancel()
					get_viewport().set_input_as_handled()
				KEY_ENTER, KEY_KP_ENTER:
					_on_confirm()
					get_viewport().set_input_as_handled()


func _on_confirm() -> void:
	confirmed.emit()
	queue_free()


func _on_cancel() -> void:
	cancelled.emit()
	queue_free()
