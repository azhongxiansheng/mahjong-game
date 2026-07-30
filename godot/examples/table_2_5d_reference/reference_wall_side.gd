extends Node2D

const STACKS := 17
const TILE_SIZE := Vector2(40.0, 32.0)
const STACK_GAP := 4.0
const LEVEL_OFFSET := Vector2(0.0, -16.0)
# 侧墙跨越远近端，raw pitch 单独收束后，最终单墩才与上下墙保持同一视觉尺度。
const SIDE_TILE_SIZE := Vector2(36.0, 28.0)
const SIDE_STACK_GAP := 3.0
const SIDE_LEVEL_OFFSET := Vector2(0.0, -7.0)

var seat_id := 0


func build(p_seat_id: int, raw_host: Rect2) -> void:
	seat_id = p_seat_id
	var side_seat := seat_id == 1 or seat_id == 3
	var tile_size := SIDE_TILE_SIZE if side_seat else TILE_SIZE
	var stack_gap := SIDE_STACK_GAP if side_seat else STACK_GAP
	var level_offset := SIDE_LEVEL_OFFSET if side_seat else LEVEL_OFFSET
	for stack_index in range(STACKS):
		for level in range(2):
			var root := Node2D.new()
			root.name = "Wall_%02d_%d" % [stack_index, level]
			root.set_meta("wall_stack", stack_index)
			root.set_meta("wall_level", level)
			add_child(root)
			var pos := Vector2(
				stack_index * (tile_size.x + stack_gap),
				level * level_offset.y)
			var quad := TableLayout.project_seat_local_rect(
				seat_id, raw_host, Rect2(pos, tile_size))
			var shadow_depth := 7.0 + level * 1.5 if side_seat \
				else 13.0 + level * 4.0
			var shadow := Polygon2D.new()
			shadow.name = "WallShadow"
			shadow.polygon = TableLayout.offset_polygon(quad,
				TableLayout.public_tile_depth_offset(seat_id, shadow_depth))
			shadow.color = Color(0, 0, 0, 0.28)
			root.add_child(shadow)
			var side := Polygon2D.new()
			side.name = "IvoryEdge"
			var side_depth := 4.0 + level if side_seat else 7.0 + level * 2.0
			side.polygon = TableLayout.offset_polygon(quad,
				TableLayout.public_tile_depth_offset(seat_id, side_depth))
			side.color = Color("d7d5c8")
			root.add_child(side)
			var back := Polygon2D.new()
			back.name = "WovenBack"
			back.polygon = quad
			back.color = Color("285d4d") if (stack_index + level) % 2 == 0 \
				else Color("2d6755")
			root.add_child(back)
