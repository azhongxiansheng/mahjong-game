extends Control

const MAX_COLUMNS := 6
const TILE_W := 24.0
const TILE_H := 34.0
const TILE_GAP := 3.0
const LABEL_W := 32.0
const ROW_GAP := 3.0

var _instances: Array = []
var _panel: Panel = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_rebuild()


func set_tiles(instances: Array) -> void:
	_instances = []
	for value in instances:
		if value is TileSkillAnchor and (value as TileSkillAnchor).tile != null:
			_instances.append(value)
	_rebuild()


func revealed_count() -> int:
	return _instances.size()


func revealed_instance_ids() -> Array:
	var out: Array = []
	for instance in _instances:
		out.append(int((instance as TileSkillAnchor).tile.instance_id))
	return out


func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_panel = null
	if _instances.is_empty():
		visible = false
		custom_minimum_size = Vector2.ZERO
		size = Vector2.ZERO
		return
	var columns := mini(MAX_COLUMNS, _instances.size())
	var rows := ceili(float(_instances.size()) / float(MAX_COLUMNS))
	var content_w := columns * TILE_W + maxi(columns - 1, 0) * TILE_GAP
	var content_h := rows * TILE_H + maxi(rows - 1, 0) * ROW_GAP
	size = Vector2(LABEL_W + 8.0 + content_w + 6.0, content_h + 8.0)
	custom_minimum_size = size
	visible = true
	_panel = Panel.new()
	_panel.size = size
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.055, 0.11, 0.94)
	style.border_color = Color("8fb8ff")
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	var label := Label.new()
	label.text = "读脊"
	label.position = Vector2(4, 4)
	label.size = Vector2(LABEL_W, TILE_H)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color("b9d4ff"))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(label)
	for index in range(_instances.size()):
		var instance := _instances[index] as TileSkillAnchor
		var tile := CardTileBack.new()
		var column := index % MAX_COLUMNS
		var row := index / MAX_COLUMNS
		tile.position = Vector2(
			LABEL_W + 8.0 + column * (TILE_W + TILE_GAP),
			4.0 + row * (TILE_H + ROW_GAP))
		tile.scale = Vector2(
			TILE_W / float(CardTileBack.TILE_WIDTH),
			TILE_H / float(CardTileBack.TILE_HEIGHT))
		_panel.add_child(tile)
		tile.set_face_up(instance.tile.id, instance.tile.is_red_dora)
		tile.set_clickable(false)
