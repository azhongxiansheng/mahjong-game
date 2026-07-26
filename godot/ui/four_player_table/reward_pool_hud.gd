extends Control

# Issue #326：左右各两槽的常驻 icon-first 奖池 HUD（display-only）。

const ICON_RESOLVER := preload("res://ui/four_player_table/table_icon_resolver.gd")
const LEFT_RECT := Rect2(16.0, 124.0, 208.0, 152.0)
const RIGHT_RECT := Rect2(1376.0, 124.0, 208.0, 152.0)

var _title: Label
var _feedback: Label
var _slots: Array = []
var _icons: Array = []
var _name_labels: Array = []
var _tag_labels: Array = []


func _ready() -> void:
	name = "RewardPoolHud"
	position = Vector2.ZERO
	size = Vector2(1600.0, 900.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


func pool_group_rects() -> Array:
	return [LEFT_RECT, RIGHT_RECT]


func set_title(text: String) -> void:
	if _title:
		_title.text = text


func set_feedback(text: String) -> void:
	if _feedback:
		_feedback.text = text
		_feedback.visible = not text.is_empty()


func feedback_text() -> String:
	return _feedback.text if _feedback else ""


func set_prize_pool_rows(rows: Array) -> void:
	for i in range(_slots.size()):
		var row: Dictionary = rows[i] if i < rows.size() and typeof(rows[i]) == TYPE_DICTIONARY else {}
		_slots[i].visible = not row.is_empty()
		if row.is_empty():
			_icons[i].texture = null
			_name_labels[i].text = ""
			_tag_labels[i].text = ""
			continue
		_icons[i].texture = ICON_RESOLVER.texture(String(row.get("icon_path", ICON_RESOLVER.UNKNOWN_ICON)))
		_name_labels[i].text = String(row.get("display_name", row.get("item_id", "?")))
		var parts := PackedStringArray()
		for tag_v in row.get("tag_labels", row.get("tags", [])):
			var tag := String(tag_v)
			if not tag.is_empty():
				parts.append(tag)
		_tag_labels[i].text = " · ".join(parts)


func _build() -> void:
	var left := _make_group("PoolLeft", LEFT_RECT)
	var right := _make_group("PoolRight", RIGHT_RECT)
	add_child(left)
	add_child(right)

	_title = Label.new()
	_title.name = "Title"
	_title.text = "垃圾话奖池 · 0/24"
	_title.position = Vector2(22, 130)
	_title.size = Vector2(196, 20)
	_title.add_theme_font_size_override("font_size", 13)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title)

	_feedback = Label.new()
	_feedback.name = "FeedbackBar"
	_feedback.position = Vector2(1382, 130)
	_feedback.size = Vector2(196, 20)
	_feedback.add_theme_font_size_override("font_size", 11)
	_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_feedback.visible = false
	_feedback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_feedback)


func _make_group(node_name: String, rect: Rect2) -> PanelContainer:
	var group := PanelContainer.new()
	group.name = node_name
	group.position = rect.position
	group.size = rect.size
	group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.07, 0.07, 0.12, 0.92)
	bg.border_color = Color(0.84, 0.57, 0.26, 0.9)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(10)
	bg.content_margin_left = 6
	bg.content_margin_right = 6
	bg.content_margin_top = 30
	bg.content_margin_bottom = 6
	group.add_theme_stylebox_override("panel", bg)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	group.add_child(list)
	for local_index in range(2):
		var index := _slots.size()
		var slot := PanelContainer.new()
		slot.name = "PrizeSlot%d" % index
		slot.custom_minimum_size = Vector2(0, 54)
		var slot_style := StyleBoxFlat.new()
		slot_style.bg_color = Color(0.12, 0.10, 0.18, 0.94)
		slot_style.border_color = Color(0.76, 0.46, 0.78, 0.72)
		slot_style.set_border_width_all(1)
		slot_style.set_corner_radius_all(7)
		slot_style.content_margin_left = 4
		slot_style.content_margin_right = 4
		slot_style.content_margin_top = 3
		slot_style.content_margin_bottom = 3
		slot.add_theme_stylebox_override("panel", slot_style)
		list.add_child(slot)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 5)
		slot.add_child(row)
		var icon := TextureRect.new()
		icon.name = "ItemIcon%d" % index
		icon.custom_minimum_size = Vector2(46, 46)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
		var labels := VBoxContainer.new()
		labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		labels.add_theme_constant_override("separation", 0)
		row.add_child(labels)
		var name_label := Label.new()
		name_label.name = "ItemName"
		name_label.add_theme_font_size_override("font_size", 12)
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		labels.add_child(name_label)
		var tag_label := Label.new()
		tag_label.name = "ItemTags"
		tag_label.add_theme_font_size_override("font_size", 10)
		tag_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		labels.add_child(tag_label)
		_slots.append(slot)
		_icons.append(icon)
		_name_labels.append(name_label)
		_tag_labels.append(tag_label)
		slot.visible = false
	return group
