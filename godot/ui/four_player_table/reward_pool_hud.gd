extends Control

# E5-06 / #254：常驻紧凑垃圾话奖池 HUD（display-only）。
# 几何契约：x=480..1120, y=132..224（1600×900）。
# 无全局 class_name。

const HUD_X := 480.0
const HUD_Y := 132.0
const HUD_W := 640.0
const HUD_H := 92.0

var _title: Label = null
var _feedback: Label = null
var _slots: Array = []  # Array[PanelContainer]
var _name_labels: Array = []
var _tag_labels: Array = []


func _ready() -> void:
	name = "RewardPoolHud"
	position = Vector2(HUD_X, HUD_Y)
	size = Vector2(HUD_W, HUD_H)
	custom_minimum_size = Vector2(HUD_W, HUD_H)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


func hud_rect() -> Rect2:
	return Rect2(HUD_X, HUD_Y, HUD_W, HUD_H)


func set_title(text: String) -> void:
	if _title:
		_title.text = text


func set_feedback(text: String) -> void:
	if _feedback:
		_feedback.text = text
		_feedback.visible = not text.is_empty()


func feedback_text() -> String:
	if _feedback == null:
		return ""
	return _feedback.text


func set_prize_pool_rows(rows: Array) -> void:
	for i in range(_slots.size()):
		var panel: PanelContainer = _slots[i]
		var name_l: Label = _name_labels[i]
		var tag_l: Label = _tag_labels[i]
		if i >= rows.size():
			panel.visible = false
			name_l.text = ""
			tag_l.text = ""
			continue
		var row: Dictionary = rows[i] if typeof(rows[i]) == TYPE_DICTIONARY else {}
		panel.visible = true
		name_l.text = String(row.get("display_name", row.get("item_id", "?")))
		var tags: Array = row.get("tag_labels", row.get("tags", []))
		var parts: PackedStringArray = PackedStringArray()
		for t in tags:
			var s := String(t)
			if not s.is_empty():
				parts.append(s)
		tag_l.text = " · ".join(parts) if parts.size() > 0 else ""


func _build() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.10, 0.08, 0.88)
	style.border_color = DT.BORDER_GOLD
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6

	var root := PanelContainer.new()
	root.name = "HudPanel"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_theme_stylebox_override("panel", style)
	add_child(root)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 4)
	root.add_child(vbox)

	_title = Label.new()
	_title.name = "Title"
	_title.text = "垃圾话奖池 · 0/24"
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.add_theme_font_size_override("font_size", 14)
	_title.add_theme_color_override("font_color", DT.TEXT_TITLE)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_title)

	var hbox := HBoxContainer.new()
	hbox.name = "PrizeSlots"
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 6)
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(hbox)

	for i in range(4):
		var slot := PanelContainer.new()
		slot.name = "PrizeSlot%d" % i
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ss := StyleBoxFlat.new()
		ss.bg_color = Color(0.08, 0.12, 0.10, 0.92)
		ss.border_color = DT.BORDER_GOLD_SOFT
		ss.set_border_width_all(1)
		ss.set_corner_radius_all(6)
		ss.content_margin_left = 4
		ss.content_margin_right = 4
		ss.content_margin_top = 2
		ss.content_margin_bottom = 2
		slot.add_theme_stylebox_override("panel", ss)

		var sv := VBoxContainer.new()
		sv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sv.add_theme_constant_override("separation", 1)
		slot.add_child(sv)

		var nl := Label.new()
		nl.name = "ItemName"
		nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		nl.add_theme_font_size_override("font_size", 12)
		nl.add_theme_color_override("font_color", DT.TEXT_PRIMARY)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		sv.add_child(nl)

		var tl := Label.new()
		tl.name = "ItemTags"
		tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tl.add_theme_font_size_override("font_size", 10)
		tl.add_theme_color_override("font_color", DT.TEXT_MUTED)
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		sv.add_child(tl)

		hbox.add_child(slot)
		_slots.append(slot)
		_name_labels.append(nl)
		_tag_labels.append(tl)
		slot.visible = false

	_feedback = Label.new()
	_feedback.name = "FeedbackBar"
	_feedback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feedback.add_theme_font_size_override("font_size", 13)
	_feedback.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55, 1.0))
	_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_feedback.visible = false
	vbox.add_child(_feedback)
