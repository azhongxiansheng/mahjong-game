extends Control

const RELATIVE_LABELS := ["自家", "下家", "对家", "上家"]
const TITLE_W := 104.0
const SLOT_W := 44.0
const TILE_W := 24.0
const TILE_H := 34.0

var _title := "四席窥运"
var _viewer_seat := 0
var _by_target: Dictionary = {}
var _slot_texts: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_rebuild()


func set_title(value: String) -> void:
	_title = value if not value.is_empty() else "四席窥运"
	_rebuild()


func set_predictions(rows: Array, viewer_seat: int) -> void:
	_viewer_seat = viewer_seat
	_by_target = {}
	for value in rows:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var row := value as Dictionary
		var target := int(row.get("target_seat", -1))
		var anchor := row.get("tile", null) as TileSkillAnchor
		if target >= 0 and target <= 3 and anchor != null and anchor.tile != null:
			_by_target[target] = anchor
	_rebuild()


func prediction_count() -> int:
	return _by_target.size()


func missing_count() -> int:
	return 4 - prediction_count() if visible else 0


func slot_labels() -> Array:
	return RELATIVE_LABELS.duplicate()


func slot_texts() -> Array:
	return _slot_texts.duplicate()


func revealed_instance_ids() -> Array:
	var out: Array = []
	for offset in range(4):
		var target := (_viewer_seat + offset) % 4
		if _by_target.has(target):
			out.append(int((_by_target[target] as TileSkillAnchor).tile.instance_id))
	return out


func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_slot_texts = []
	if _by_target.is_empty():
		visible = false
		size = Vector2.ZERO
		custom_minimum_size = Vector2.ZERO
		return
	visible = true
	size = Vector2(TITLE_W + SLOT_W * 4.0 + 8.0, 58.0)
	custom_minimum_size = size
	var panel := Panel.new()
	panel.size = size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.045, 0.09, 0.95)
	style.border_color = Color("b8a6ff")
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var title := Label.new()
	title.text = _title
	title.position = Vector2(6, 4)
	title.size = Vector2(TITLE_W - 8.0, 50.0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color("ddd4ff"))
	panel.add_child(title)
	for offset in range(4):
		var x := TITLE_W + offset * SLOT_W
		var seat_label := Label.new()
		seat_label.text = RELATIVE_LABELS[offset]
		seat_label.position = Vector2(x, 2)
		seat_label.size = Vector2(SLOT_W, 16)
		seat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		seat_label.add_theme_font_size_override("font_size", 10)
		seat_label.add_theme_color_override("font_color", Color("c8c0e8"))
		panel.add_child(seat_label)
		var target := (_viewer_seat + offset) % 4
		if _by_target.has(target):
			var anchor := _by_target[target] as TileSkillAnchor
			var tile := CardTileBack.new()
			tile.position = Vector2(x + (SLOT_W - TILE_W) / 2.0, 19.0)
			tile.scale = Vector2(
				TILE_W / float(CardTileBack.TILE_WIDTH),
				TILE_H / float(CardTileBack.TILE_HEIGHT))
			panel.add_child(tile)
			tile.set_face_up(anchor.tile.id, anchor.tile.is_red_dora)
			tile.set_clickable(false)
			_slot_texts.append(str(anchor.tile.id))
		else:
			var missing := Label.new()
			missing.text = "—"
			missing.position = Vector2(x, 18)
			missing.size = Vector2(SLOT_W, TILE_H)
			missing.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			missing.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			missing.add_theme_font_size_override("font_size", 18)
			missing.add_theme_color_override("font_color", Color("7f7996"))
			panel.add_child(missing)
			_slot_texts.append("—")
