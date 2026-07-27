extends Control

# Issue #326 rework：四枚贴边“结界钉”，常态仅显示 icon。

const ICON_RESOLVER := preload("res://ui/four_player_table/table_icon_resolver.gd")
const PRIZE_ICON_SIZE := Vector2(52.0, 52.0)
const PRIZE_ICON_RECTS := [
	Rect2(24.0, 132.0, 52.0, 52.0),
	Rect2(24.0, 192.0, 52.0, 52.0),
	Rect2(1524.0, 132.0, 52.0, 52.0),
	Rect2(1524.0, 192.0, 52.0, 52.0),
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
	return [
		Rect2(PRIZE_ICON_RECTS[0].position, Vector2(52.0, 112.0)),
		Rect2(PRIZE_ICON_RECTS[2].position, Vector2(52.0, 112.0)),
	]


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
		var icon: TextureRect = _slots[i]
		var row: Dictionary = rows[i] if i < rows.size() and typeof(rows[i]) == TYPE_DICTIONARY else {}
		icon.visible = not row.is_empty()
		if row.is_empty():
			icon.texture = null
			icon.tooltip_text = ""
			continue
		icon.texture = ICON_RESOLVER.texture(String(row.get(
			"icon_path", ICON_RESOLVER.UNKNOWN_ICON)))
		var display_name := String(row.get("display_name", row.get("item_id", "未知奖品")))
		var effect := String(row.get("effect_summary", row.get("description", "")))
		icon.tooltip_text = display_name if effect.is_empty() \
			else "%s\n%s" % [display_name, effect]


func _build() -> void:
	for i in range(PRIZE_ICON_RECTS.size()):
		var rect: Rect2 = PRIZE_ICON_RECTS[i]
		var icon := TextureRect.new()
		icon.name = "ItemIcon%d" % i
		icon.position = rect.position
		icon.size = rect.size
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_STOP
		icon.visible = false
		add_child(icon)
		_slots.append(icon)

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
