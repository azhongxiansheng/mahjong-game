extends Control

const TABLE_SCENE := preload("res://ui/four_player_table/four_player_table.tscn")
const RIVER_SCRIPT := preload("res://examples/table_2_5d_reference/reference_river.gd")
const WALL_SCRIPT := preload("res://examples/table_2_5d_reference/reference_wall_side.gd")
const MELD_FACE_TO_HAND_SCALE := 0.95
const MELD_HAND_GAP := 12.0

var source_table: FourPlayerTable
var prototype_rivers: Dictionary = {}
var wall_sides: Dictionary = {}
var fixture_discard_count := 18


func _ready() -> void:
	custom_minimum_size = Vector2(1600, 900)
	size = Vector2(1600, 900)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	source_table = TABLE_SCENE.instantiate() as FourPlayerTable
	source_table.name = "RealFourPlayerTable"
	add_child(source_table)
	var state := _build_visual_state()
	source_table.bind_battle_state(state, 0, 4)
	_build_reference_rivers(state)
	_build_walls()
	# 等待真实 SeatPanel 的 Control 布局稳定后，再按最终暗手像素校准副露。
	await get_tree().process_frame
	await get_tree().process_frame
	_tune_reference_melds()


func _build_visual_state() -> BattleState:
	var state := BattleState.for_east_round(3692026, 0, 1, 0, 0)
	var river_ids := [TileId.W1, TileId.W3, TileId.W6, TileId.W9,
		TileId.T2, TileId.T5, TileId.T8, TileId.S1, TileId.S4, TileId.S7,
		TileId.E, TileId.S_WIND, TileId.W_WIND, TileId.N,
		TileId.HAKU, TileId.HATSU, TileId.CHUN, TileId.W5, TileId.T6, TileId.S9]
	for seat_id in range(4):
		for index in range(fixture_discard_count):
			state.seats[seat_id].river.append_discard(Tile.new(
				river_ids[(index + seat_id * 3) % river_ids.size()]))
	_add_meld_fixtures(state)
	return state


func _add_meld_fixtures(state: BattleState) -> void:
	var called := Tile.new(TileId.W7, false, Tile.NO_OWNER, 369001)
	var pon := Meld.make_pon([
		called,
		Tile.new(TileId.W7, false, Tile.NO_OWNER, 369002),
		Tile.new(TileId.W7, false, Tile.NO_OWNER, 369003),
	], 1, 369100, called)
	state.seats[0].melds.add_existing(pon)
	var minkan_called := Tile.new(TileId.CHUN, false, Tile.NO_OWNER, 369030)
	var minkan := Meld.make_minkan([
		minkan_called,
		Tile.new(TileId.CHUN, false, Tile.NO_OWNER, 369031),
		Tile.new(TileId.CHUN, false, Tile.NO_OWNER, 369032),
		Tile.new(TileId.CHUN, false, Tile.NO_OWNER, 369033),
	], 2, 369104, minkan_called)
	state.seats[0].melds.add_existing(minkan)
	var chi_called := Tile.new(TileId.S4, false, Tile.NO_OWNER, 369010)
	var chi := Meld.make_chi([
		Tile.new(TileId.S3, false, Tile.NO_OWNER, 369011),
		chi_called,
		Tile.new(TileId.S5, false, Tile.NO_OWNER, 369012),
	], 0, 369101, chi_called)
	state.seats[1].melds.add_existing(chi)
	var ankan_tiles: Array[Tile] = []
	for index in range(4):
		ankan_tiles.append(Tile.new(TileId.T3, false, Tile.NO_OWNER, 369200 + index))
	state.seats[2].melds.add_existing(Meld.make_ankan(ankan_tiles, 369302))
	var kan_called := Tile.new(TileId.HATSU, false, Tile.NO_OWNER, 369020)
	var added := Tile.new(TileId.HATSU, false, Tile.NO_OWNER, 369023)
	var added_kan := Meld.make_pon([
		kan_called,
		Tile.new(TileId.HATSU, false, Tile.NO_OWNER, 369021),
		Tile.new(TileId.HATSU, false, Tile.NO_OWNER, 369022),
	], 2, 369103, kan_called)
	added_kan.promote_to_added_kan(added)
	state.seats[3].melds.add_existing(added_kan)
	for seat in state.seats:
		var concealed_count: int = 13 - seat.melds.size() * 3
		var concealed: Array = seat.hand.tiles().slice(0, concealed_count)
		seat.hand.restore_tiles(concealed)
		seat.last_drawn_instance_id = Tile.INVALID_INSTANCE_ID


func _build_reference_rivers(state: BattleState) -> void:
	for seat_id in range(4):
		source_table.discard_rivers[seat_id].visible = false
		var river := RIVER_SCRIPT.new()
		river.name = "ReferenceRiver%d" % seat_id
		source_table.get_node("Table").add_child(river)
		river.build(seat_id, state.seats[seat_id].river.tiles().map(
			func(tile: Tile) -> int: return tile.id), 4 + seat_id)
		prototype_rivers[seat_id] = river


func _build_walls() -> void:
	var hosts := {
		0: Rect2(428, 730, 744, 32),
		1: Rect2(1224, 120, 28, 660),
		2: Rect2(428, 1, 744, 32),
		3: Rect2(348, 120, 28, 660),
	}
	for seat_id in range(4):
		var wall := WALL_SCRIPT.new()
		wall.name = "ReferenceWall%d" % seat_id
		source_table.get_node("Table").add_child(wall)
		wall.build(seat_id, hosts[seat_id])
		wall_sides[seat_id] = wall


func _tune_reference_melds() -> void:
	for seat_id in range(4):
		var area: MeldArea = source_table.meld_areas[seat_id]
		var faces := _meld_faces(area)
		var hand_rects: Array[Rect2] = \
			source_table.seat_panels[seat_id].get_visual_hand_rects()
		if faces.is_empty() or hand_rects.is_empty():
			continue
		_compress_meld_depth(area)
		var hand_bounds := _merge_rects(hand_rects)
		var meld_bounds := _polygon_group_bounds(faces)
		var hand_tile: Rect2 = hand_rects[0]
		var face_tile: Rect2 = _polygon_bounds(faces[0])
		var scale_factor := MELD_FACE_TO_HAND_SCALE * sqrt(
			hand_tile.size.x * hand_tile.size.y
			/ (face_tile.size.x * face_tile.size.y))
		var anchor := meld_bounds.get_center()
		match seat_id:
			0: anchor.x = meld_bounds.position.x
			1: anchor.y = meld_bounds.end.y
			2: anchor.x = meld_bounds.end.x
			_: anchor.y = meld_bounds.position.y
		_transform_meld_polygons(area, anchor, scale_factor, Vector2.ZERO)
		meld_bounds = _polygon_group_bounds(faces)
		var offset := Vector2.ZERO
		match seat_id:
			0:
				offset.x = hand_bounds.end.x + MELD_HAND_GAP \
					- meld_bounds.position.x
				offset.y = hand_bounds.get_center().y - meld_bounds.get_center().y
			1:
				offset.x = hand_bounds.end.x - meld_bounds.end.x
				offset.y = hand_bounds.position.y - MELD_HAND_GAP \
					- meld_bounds.end.y
			2:
				offset.x = hand_bounds.position.x - MELD_HAND_GAP \
					- meld_bounds.end.x
				offset.y = hand_bounds.get_center().y - meld_bounds.get_center().y
			_:
				offset.x = hand_bounds.position.x - meld_bounds.position.x
				offset.y = hand_bounds.end.y + MELD_HAND_GAP \
					- meld_bounds.position.y
		_transform_meld_polygons(area, Vector2.ZERO, 1.0, offset)


func _meld_faces(area: MeldArea) -> Array[Polygon2D]:
	var faces: Array[Polygon2D] = []
	for child in area.get_children():
		if child is Polygon2D and not child.has_meta("depth_layer"):
			faces.append(child as Polygon2D)
	return faces


func _compress_meld_depth(area: MeldArea) -> void:
	var pending: Array[Polygon2D] = []
	for child in area.get_children():
		if not (child is Polygon2D):
			continue
		var polygon := child as Polygon2D
		if polygon.has_meta("depth_layer"):
			pending.append(polygon)
			continue
		for layer in pending:
			if layer.polygon.size() != polygon.polygon.size():
				continue
			var factor := 0.55
			match String(layer.get_meta("depth_layer")):
				"shadow": factor = 0.45
				"white": factor = 0.62
			var points := PackedVector2Array()
			for index in range(polygon.polygon.size()):
				points.append(polygon.polygon[index] + (
					layer.polygon[index] - polygon.polygon[index]) * factor)
			layer.polygon = points
		pending.clear()


func _transform_meld_polygons(area: MeldArea, anchor: Vector2,
		scale_factor: float, offset: Vector2) -> void:
	for child in area.get_children():
		if not (child is Polygon2D):
			continue
		var polygon := child as Polygon2D
		var points := PackedVector2Array()
		for point in polygon.polygon:
			points.append(anchor + (point - anchor) * scale_factor + offset)
		polygon.polygon = points


func _polygon_bounds(polygon: Polygon2D) -> Rect2:
	var bounds := Rect2(polygon.polygon[0], Vector2.ZERO)
	for point in polygon.polygon.slice(1):
		bounds = bounds.expand(point)
	return bounds


func _polygon_group_bounds(polygons: Array[Polygon2D]) -> Rect2:
	var bounds := _polygon_bounds(polygons[0])
	for polygon in polygons.slice(1):
		bounds = bounds.merge(_polygon_bounds(polygon))
	return bounds


func _merge_rects(rects: Array[Rect2]) -> Rect2:
	var bounds := rects[0]
	for rect in rects.slice(1):
		bounds = bounds.merge(rect)
	return bounds
