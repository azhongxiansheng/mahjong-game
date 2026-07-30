extends Node2D

const TILE_W := 51.0
const TILE_H := 60.0
const TILE_GAP := 5.0
const ROW_GAP := 3.0
const TILES_PER_ROW := 6
const ROW_COUNT := 3
# 保留真牌尺度时，侧河沿径向外移，给相邻席最终牌面留下可见净距。
const SIDE_RIVER_OUTSET := 58.0

var seat_id := 0


func build(p_seat_id: int, tiles: Array, riichi_index: int = -1) -> void:
	seat_id = p_seat_id
	for child in get_children():
		child.queue_free()
	var extractor := get_tree().root.get_node_or_null("TextureExtractor")
	if extractor == null:
		push_error("#369 reference river requires TextureExtractor")
		return
	var raw_host := TableLayout.river_raw_rect(seat_id)
	if seat_id == 1:
		raw_host.position.x += SIDE_RIVER_OUTSET
	elif seat_id == 3:
		raw_host.position.x -= SIDE_RIVER_OUTSET
	var standard_row_width := TILES_PER_ROW * TILE_W \
		+ (TILES_PER_ROW - 1) * TILE_GAP
	var row_cursors: Array[float] = []
	for row_index in range(ROW_COUNT):
		row_cursors.append((300.0 - standard_row_width) * 0.5)
	for index in range(tiles.size()):
		var row: int = mini(floori(float(index) / TILES_PER_ROW), ROW_COUNT - 1)
		var column: int = index - row * TILES_PER_ROW
		var local_position: Vector2 = Vector2(
			row_cursors[row],
			row * (TILE_H + ROW_GAP))
		var is_riichi := index == riichi_index
		_add_tile(index, row, column, int(tiles[index]), local_position,
			is_riichi, extractor, raw_host)
		row_cursors[row] += (TILE_H if is_riichi else TILE_W) + TILE_GAP


func _add_tile(index: int, row: int, column: int, tile_id: int,
		local_position: Vector2, is_riichi: bool, extractor: Node,
		raw_host: Rect2) -> void:
	var root := Node2D.new()
	root.name = "RiverTile_%02d" % index
	root.set_meta("tile_index", index)
	root.set_meta("row", row)
	root.set_meta("column", column)
	root.set_meta("is_riichi", is_riichi)
	add_child(root)
	var slot_size := Vector2(TILE_H, TILE_W) if is_riichi \
		else Vector2(TILE_W, TILE_H)
	var quad := TableLayout.project_seat_local_rect(
		seat_id, raw_host,
		Rect2(local_position, slot_size))
	_add_layer(root, "TileShadow", quad,
		TableLayout.PUBLIC_TILE_SHADOW_OFFSET, Color(0, 0, 0, 0.34))
	_add_layer(root, "GreenSide", quad,
		TableLayout.PUBLIC_TILE_GREEN_DEPTH, Color("315f4d"))
	_add_layer(root, "WhiteSide", quad,
		TableLayout.PUBLIC_TILE_WHITE_DEPTH, Color("d8d6ca"))
	var key := CardTileBack.tile_id_to_atlas_key(tile_id, false)
	var texture: Texture2D = extractor.get_tile_texture(key)
	var face := Polygon2D.new()
	face.name = "TileFace"
	face.polygon = quad
	face.texture = texture
	if texture != null:
		var size := texture.get_size()
		face.uv = PackedVector2Array([
			Vector2(size.x, 0), size, Vector2(0, size.y), Vector2.ZERO,
		]) if is_riichi else PackedVector2Array([
			Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)])
	root.add_child(face)


func _add_layer(parent: Node, node_name: String, quad: PackedVector2Array,
		distance: float, color: Color) -> void:
	var layer := Polygon2D.new()
	layer.name = node_name
	layer.polygon = TableLayout.offset_polygon(
		quad, TableLayout.public_tile_depth_offset(seat_id, distance))
	layer.color = color
	parent.add_child(layer)
