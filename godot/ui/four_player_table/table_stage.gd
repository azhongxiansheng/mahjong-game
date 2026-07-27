class_name TableStage

# 牌桌只消费仓库自有完整桌布；结界线由 Godot 节点实时绘制。
const FELT_PATH := "res://assets/table_felt.png"
const FELT_FALLBACK := "res://assets/mahjong_table_bg.png"


# 在 parent 最底层搭舞台。返回舞台根节点（调试用）。
static func build(parent: Control, w: float, h: float) -> Control:
	var root := Control.new()
	root.name = "TableStage"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.position = Vector2.ZERO
	root.size = Vector2(w, h)
	parent.add_child(root)
	parent.move_child(root, 0)

	# 生产桌布已经包含闭合四边框，直接铺满固定 1600×900 舞台。
	var path: String = FELT_PATH if ResourceLoader.exists(FELT_PATH) else FELT_FALLBACK
	if ResourceLoader.exists(path):
		var felt := TextureRect.new()
		felt.name = "TableFelt"
		felt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		felt.texture = load(path)
		felt.position = Vector2.ZERO
		felt.size = Vector2(w, h)
		felt.stretch_mode = TextureRect.STRETCH_SCALE
		felt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(felt)

	root.add_child(_build_barrier_field(w, h))
	return root


static func _build_barrier_field(w: float, h: float) -> Node2D:
	var field := Node2D.new()
	field.name = "BarrierField"
	var center := Vector2(w * 0.5, 402.0)
	var diamond := Line2D.new()
	diamond.name = "SealDiamond"
	diamond.points = PackedVector2Array([
		center + Vector2(0, -250), center + Vector2(420, 0),
		center + Vector2(0, 250), center + Vector2(-420, 0),
	])
	diamond.closed = true
	diamond.width = 2.0
	diamond.default_color = Color(0.18, 0.72, 0.72, 0.20)
	diamond.antialiased = true
	field.add_child(diamond)
	for index in range(4):
		var ray := Line2D.new()
		ray.name = "SealRay%d" % index
		var end_points := [Vector2(800, 76), Vector2(1460, 402),
			Vector2(800, 660), Vector2(140, 402)]
		ray.points = PackedVector2Array([center, end_points[index]])
		ray.width = 1.0
		ray.default_color = Color(0.42, 0.92, 0.88, 0.12)
		ray.antialiased = true
		field.add_child(ray)
	return field
