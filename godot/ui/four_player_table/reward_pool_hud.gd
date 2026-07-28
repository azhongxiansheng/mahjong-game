extends Control

# Issue #326：四枚贴边 icon-first 奖池槽，常态保留名称与属性短签。

const ICON_RESOLVER := preload("res://ui/four_player_table/table_icon_resolver.gd")
const PRIZE_ICON_SIZE := Vector2(52.0, 52.0)
const PRIZE_ICON_RECTS := [
	Rect2(24.0, 132.0, 52.0, 52.0),
	Rect2(24.0, 192.0, 52.0, 52.0),
	Rect2(1524.0, 132.0, 52.0, 52.0),
	Rect2(1524.0, 192.0, 52.0, 52.0),
]
const PRIZE_GROUP_RECTS := [
	Rect2(16.0, 124.0, 208.0, 152.0),
	Rect2(1376.0, 124.0, 208.0, 152.0),
]
const PRIZE_ROW_RECTS := [
	Rect2(16.0, 128.0, 208.0, 56.0),
	Rect2(16.0, 188.0, 208.0, 56.0),
	Rect2(1376.0, 128.0, 208.0, 56.0),
	Rect2(1376.0, 188.0, 208.0, 56.0),
]

var _progress: Label
var _feedback: Label
var _slots: Array = []


func _ready() -> void:
	name = "RewardPoolHud"
	position = Vector2.ZERO
	size = Vector2(1600.0, 900.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


func prize_icon_rects() -> Array:
	return PRIZE_ICON_RECTS.duplicate()


func pool_group_rects() -> Array:
	return PRIZE_GROUP_RECTS.duplicate()


func set_title(text: String) -> void:
	if _progress == null:
		return
	_progress.tooltip_text = text
	var parts := text.split("·", false, 1)
	_progress.text = String(parts[1]).strip_edges() if parts.size() > 1 else text


func set_feedback(text: String) -> void:
	if _feedback:
		_feedback.text = text
	if _progress and not text.is_empty():
		_progress.tooltip_text = text


func feedback_text() -> String:
	return _feedback.text if _feedback else ""


func set_prize_pool_rows(rows: Array) -> void:
	for i in range(_slots.size()):
		var slot: Dictionary = _slots[i]
		var focus_button: Button = slot["focus"] as Button
		var icon: TextureRect = slot["icon"] as TextureRect
		var name_label: Label = slot["name"] as Label
		var tags_label: Label = slot["tags"] as Label
		var row: Dictionary = rows[i] if i < rows.size() and typeof(rows[i]) == TYPE_DICTIONARY else {}
		focus_button.visible = not row.is_empty()
		if row.is_empty():
			icon.texture = null
			icon.tooltip_text = ""
			name_label.text = ""
			tags_label.text = ""
			slot["tag_text"] = ""
			slot["effect"] = ""
			continue
		icon.texture = ICON_RESOLVER.texture(String(row.get(
			"icon_path", ICON_RESOLVER.UNKNOWN_ICON)))
		var display_name := String(row.get("display_name", row.get("item_id", "未知奖品")))
		var effect := String(row.get("effect_summary", row.get("description", "")))
		var tag_labels: Array = row.get("tag_labels", []) as Array
		var tag_text := "无属性"
		if not tag_labels.is_empty():
			var visible_tags := PackedStringArray()
			for tag in tag_labels.slice(0, 2):
				visible_tags.append(String(tag))
			tag_text = " · ".join(visible_tags)
		var details := display_name if effect.is_empty() else "%s\n%s" % [display_name, effect]
		focus_button.tooltip_text = details
		icon.tooltip_text = details
		name_label.text = display_name
		tags_label.text = tag_text
		slot["tag_text"] = tag_text
		slot["effect"] = effect


func _build() -> void:
	for i in range(PRIZE_ICON_RECTS.size()):
		var row_rect: Rect2 = PRIZE_ROW_RECTS[i]
		var icon_rect: Rect2 = PRIZE_ICON_RECTS[i]
		var is_left := i < 2
		var focus_button := Button.new()
		focus_button.name = "ItemFocus%d" % i
		focus_button.position = row_rect.position
		focus_button.size = row_rect.size
		focus_button.flat = true
		focus_button.focus_mode = Control.FOCUS_ALL
		focus_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var focus_style := StyleBoxFlat.new()
		focus_style.bg_color = Color(0.08, 0.05, 0.12, 0.22)
		focus_style.border_color = Color(0.96, 0.76, 0.36, 0.92)
		focus_style.set_border_width_all(1)
		focus_style.set_corner_radius_all(7)
		focus_button.add_theme_stylebox_override("focus", focus_style)
		add_child(focus_button)
		var icon := TextureRect.new()
		icon.name = "ItemIcon%d" % i
		icon.position = icon_rect.position - row_rect.position
		icon.size = icon_rect.size
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		focus_button.add_child(icon)
		var text_x := 68.0 if is_left else 8.0
		var text_w := 132.0
		var name_label := Label.new()
		name_label.name = "ItemName%d" % i
		name_label.position = Vector2(text_x, 3.0)
		name_label.size = Vector2(text_w, 25.0)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT \
			if is_left else HORIZONTAL_ALIGNMENT_RIGHT
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.add_theme_font_size_override("font_size", 14)
		name_label.add_theme_color_override("font_color", DT.TEXT_TITLE)
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		focus_button.add_child(name_label)
		var tags_label := Label.new()
		tags_label.name = "ItemTags%d" % i
		tags_label.position = Vector2(text_x, 28.0)
		tags_label.size = Vector2(text_w, 22.0)
		tags_label.horizontal_alignment = name_label.horizontal_alignment
		tags_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tags_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		tags_label.add_theme_font_size_override("font_size", 12)
		tags_label.add_theme_color_override("font_color", Color(0.91, 0.72, 0.43))
		tags_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		focus_button.add_child(tags_label)
		focus_button.mouse_entered.connect(_show_slot_detail.bind(i))
		focus_button.mouse_exited.connect(_restore_slot_tags.bind(i))
		focus_button.focus_entered.connect(_show_slot_detail.bind(i))
		focus_button.focus_exited.connect(_restore_slot_tags.bind(i))
		focus_button.visible = false
		_slots.append({
			"focus": focus_button,
			"icon": icon,
			"name": name_label,
			"tags": tags_label,
			"tag_text": "",
			"effect": "",
		})

	_progress = Label.new()
	_progress.name = "PoolProgress"
	_progress.position = Vector2(24.0, 248.0)
	_progress.size = Vector2(52.0, 18.0)
	_progress.text = "0/24"
	_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress.add_theme_font_size_override("font_size", 11)
	_progress.add_theme_color_override("font_color", Color(0.90, 0.72, 0.42))
	_progress.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_progress)

	# 保留既有反馈查询契约；实际反馈由字幕 banner 展示，避免再造浮窗。
	_feedback = Label.new()
	_feedback.name = "FeedbackBar"
	_feedback.visible = false
	add_child(_feedback)


func _show_slot_detail(index: int) -> void:
	if index < 0 or index >= _slots.size():
		return
	var slot: Dictionary = _slots[index]
	var effect := String(slot.get("effect", ""))
	if effect.is_empty():
		return
	(slot["tags"] as Label).text = effect


func _restore_slot_tags(index: int) -> void:
	if index < 0 or index >= _slots.size():
		return
	var slot: Dictionary = _slots[index]
	if (slot["focus"] as Button).has_focus():
		return
	(slot["tags"] as Label).text = String(slot.get("tag_text", ""))
