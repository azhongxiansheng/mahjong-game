class_name TableStage

# 本地视觉校准时可放入参考站 1600×900 使用的 felt.jpg（1672×941）；
# 仓库不携带未授权第三方美术，文件不存在时继续使用仓库自有背景。
# 两者都直接铺满桌面，不再重复叠自创光晕、硬暗角或内框。

const FELT_PATH := "res://assets/que_wang_felt.jpg"
const FELT_FALLBACK := "res://assets/mahjong_table_bg.png"
const RAIL_RAW_SIZE := Vector2(120.0, 1040.0)
const RAIL_CAP_RAW_SIZE := Vector2(14.0, 1040.0)
const TABLE_PLANE_TOP: float = -140.0
const TABLE_PLANE_BOTTOM: float = 900.0

const LEFT_RAIL_RAW := [
	Vector2(-130.0, TABLE_PLANE_TOP),
	Vector2(-10.0, TABLE_PLANE_TOP),
	Vector2(-10.0, TABLE_PLANE_BOTTOM),
	Vector2(-130.0, TABLE_PLANE_BOTTOM),
]
const RIGHT_RAIL_RAW := [
	Vector2(1610.0, TABLE_PLANE_TOP),
	Vector2(1730.0, TABLE_PLANE_TOP),
	Vector2(1730.0, TABLE_PLANE_BOTTOM),
	Vector2(1610.0, TABLE_PLANE_BOTTOM),
]
const LEFT_GAP_RAW := [
	Vector2(-10.0, TABLE_PLANE_TOP),
	Vector2(0.0, TABLE_PLANE_TOP),
	Vector2(0.0, TABLE_PLANE_BOTTOM),
	Vector2(-10.0, TABLE_PLANE_BOTTOM),
]
const RIGHT_GAP_RAW := [
	Vector2(1600.0, TABLE_PLANE_TOP),
	Vector2(1610.0, TABLE_PLANE_TOP),
	Vector2(1610.0, TABLE_PLANE_BOTTOM),
	Vector2(1600.0, TABLE_PLANE_BOTTOM),
]
const LEFT_CAP_RAW := [
	Vector2(-24.0, TABLE_PLANE_TOP),
	Vector2(-10.0, TABLE_PLANE_TOP),
	Vector2(-10.0, TABLE_PLANE_BOTTOM),
	Vector2(-24.0, TABLE_PLANE_BOTTOM),
]
const RIGHT_CAP_RAW := [
	Vector2(1610.0, TABLE_PLANE_TOP),
	Vector2(1624.0, TABLE_PLANE_TOP),
	Vector2(1624.0, TABLE_PLANE_BOTTOM),
	Vector2(1610.0, TABLE_PLANE_BOTTOM),
]


# 在 parent 最底层搭舞台。返回毡节点（调试用）。
static func build(parent: Control, w: float, h: float) -> Control:
	var root := Control.new()
	root.name = "TableStage"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.position = Vector2.ZERO
	root.size = Vector2(w, h)
	parent.add_child(root)
	parent.move_child(root, 0)

	# 桌布原图直接铺满固定 1600×900 舞台。
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

	root.add_child(_build_table_rails(w, h))
	return root


# 直接翻译参考 `.table-rail`：透视几何沿用同一个 table-plane 投影，
# 基础木色、噪声、内收边与高光按 CSS 层级叠放。
static func _build_table_rails(w: float, h: float) -> Node2D:
	var rails := Node2D.new()
	rails.name = "TableRails"
	var left_rail := _project_quad(LEFT_RAIL_RAW)
	var right_rail := _project_quad(RIGHT_RAIL_RAW)

	# 桌面投影之外是深色场景；用跨出 viewport 的梯形避免多边形在
	# 木轨外缘越过屏幕边界时发生自交。
	rails.add_child(_solid_polygon("ExteriorLeft", PackedVector2Array([
		Vector2(-w, left_rail[0].y), left_rail[0], left_rail[3],
		Vector2(-w, h),
	]), Color("0c0a08")))
	rails.add_child(_solid_polygon("ExteriorRight", PackedVector2Array([
		Vector2(w * 2.0, right_rail[1].y), right_rail[1], right_rail[2],
		Vector2(w * 2.0, h),
	]), Color("0c0a08")))

	rails.add_child(_solid_polygon("GapLeft", _project_quad(LEFT_GAP_RAW),
		Color("050201")))
	rails.add_child(_solid_polygon("GapRight", _project_quad(RIGHT_GAP_RAW),
		Color("050201")))

	var base_texture := _rail_base_texture()
	rails.add_child(_textured_quad("RailLeft", left_rail, base_texture,
		RAIL_RAW_SIZE))
	rails.add_child(_textured_quad("RailRight", right_rail, base_texture,
		RAIL_RAW_SIZE))

	var noise_texture := _rail_noise_texture()
	var left_noise := _textured_quad("NoiseLeft", left_rail, noise_texture,
		RAIL_RAW_SIZE)
	left_noise.color = Color(0.0, 0.0, 0.0, 0.22)
	rails.add_child(left_noise)
	var right_noise := _textured_quad("NoiseRight", right_rail, noise_texture,
		RAIL_RAW_SIZE)
	right_noise.color = Color(0.0, 0.0, 0.0, 0.22)
	rails.add_child(right_noise)

	rails.add_child(_textured_quad("CapLeft", _project_quad(LEFT_CAP_RAW),
		_rail_cap_texture(false), RAIL_CAP_RAW_SIZE))
	rails.add_child(_textured_quad("CapRight", _project_quad(RIGHT_CAP_RAW),
		_rail_cap_texture(true), RAIL_CAP_RAW_SIZE))

	rails.add_child(_rail_glow("GlowLeft", -23.0))
	rails.add_child(_rail_glow("GlowRight", 1623.0))
	rails.add_child(_rail_highlight("HighlightLeft", -23.0))
	rails.add_child(_rail_highlight("HighlightRight", 1623.0))
	return rails


static func _project_quad(raw_points: Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	for point: Vector2 in raw_points:
		points.append(TableLayout.project_table_point(point))
	return points


static func _solid_polygon(node_name: String, points: PackedVector2Array,
		color: Color) -> Polygon2D:
	var polygon := Polygon2D.new()
	polygon.name = node_name
	polygon.polygon = points
	polygon.color = color
	polygon.antialiased = true
	return polygon


static func _textured_quad(node_name: String, points: PackedVector2Array,
		texture: Texture2D, raw_size: Vector2) -> Polygon2D:
	var polygon := Polygon2D.new()
	polygon.name = node_name
	polygon.polygon = points
	polygon.uv = PackedVector2Array([
		Vector2.ZERO,
		Vector2(raw_size.x, 0.0),
		raw_size,
		Vector2(0.0, raw_size.y),
	])
	polygon.texture = texture
	polygon.color = Color.WHITE
	polygon.antialiased = true
	return polygon


static func _rail_base_texture() -> GradientTexture2D:
	# CSS 在 11px / 109px 处使用同位色标制造硬木棱；用相邻的
	# 0.1px 色标保留突变，同时满足 Gradient 的严格升序约束。
	return _gradient_texture(PackedColorArray([
		Color("050201"), Color("050201"), Color("1d0805"),
		Color("38150c"), Color("0c0301"), Color("0c0301"),
		Color("4e1d11"), Color("4e1d11"), Color("0c0301"),
		Color("0c0301"), Color("38150c"), Color("1d0805"),
		Color("050201"), Color("050201"),
	]), PackedFloat32Array([
		0.0, 2.0 / 120.0, 8.0 / 120.0, 10.9 / 120.0,
		11.1 / 120.0, 12.0 / 120.0, 14.0 / 120.0,
		106.0 / 120.0, 108.0 / 120.0, 108.9 / 120.0,
		109.1 / 120.0, 112.0 / 120.0, 118.0 / 120.0, 1.0,
	]), RAIL_RAW_SIZE, Vector2(0.0, 0.5), Vector2(1.0, 0.5))


static func _rail_cap_texture(mirrored: bool) -> GradientTexture2D:
	var colors := PackedColorArray([
		Color("4e1d11"), Color("3e1709"), Color("2a0e07"),
		Color("0e0402"), Color("050201"),
	])
	if mirrored:
		colors.reverse()
	return _gradient_texture(colors,
		PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0]),
		RAIL_CAP_RAW_SIZE, Vector2(0.0, 0.5), Vector2(1.0, 0.5))


static func _gradient_texture(colors: PackedColorArray,
		offsets: PackedFloat32Array, size_: Vector2, fill_from: Vector2,
		fill_to: Vector2) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.colors = colors
	gradient.offsets = offsets
	gradient.interpolation_color_space = Gradient.GRADIENT_COLOR_SPACE_SRGB
	var texture := GradientTexture2D.new()
	texture.width = int(size_.x)
	texture.height = int(size_.y)
	texture.fill = GradientTexture2D.FILL_LINEAR
	texture.fill_from = fill_from
	texture.fill_to = fill_to
	texture.gradient = gradient
	return texture


static func _rail_noise_texture() -> NoiseTexture2D:
	var source := FastNoiseLite.new()
	source.seed = 2701
	source.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	source.frequency = 0.035
	source.fractal_type = FastNoiseLite.FRACTAL_FBM
	source.fractal_octaves = 3
	var texture := NoiseTexture2D.new()
	texture.width = int(RAIL_RAW_SIZE.x)
	texture.height = int(RAIL_RAW_SIZE.y)
	texture.noise = source
	return texture


static func _rail_highlight(node_name: String, raw_x: float) -> Polygon2D:
	return _rail_light_quad(node_name, raw_x, 2.0,
		PackedColorArray([
			Color(1.0, 0.92, 0.84, 0.0),
			Color(1.0, 0.92, 0.84, 0.6),
			Color("ffebd7"), Color("fff0dc"), Color("ffebd7"),
			Color(1.0, 0.92, 0.84, 0.6),
			Color(1.0, 0.92, 0.84, 0.0),
		]), 2)


static func _rail_glow(node_name: String, raw_x: float) -> Polygon2D:
	return _rail_light_quad(node_name, raw_x, 6.0,
		PackedColorArray([
			Color(1.0, 0.92, 0.84, 0.0),
			Color(1.0, 0.92, 0.84, 0.14),
			Color(1.0, 0.92, 0.84, 0.28),
			Color(1.0, 0.94, 0.86, 0.32),
			Color(1.0, 0.92, 0.84, 0.28),
			Color(1.0, 0.92, 0.84, 0.14),
			Color(1.0, 0.92, 0.84, 0.0),
		]), 1)


# Line2D.gradient 在当前 Godot 4.6.1 Metal 渲染器中资源采样正确、实际却
# 不出图；用同几何的窄 Polygon2D + GradientTexture2D 翻译 CSS 伪元素。
static func _rail_light_quad(node_name: String, raw_x: float,
		raw_width: float, colors: PackedColorArray, z: int) -> Polygon2D:
	var half_width := raw_width * 0.5
	var raw_points := [
		Vector2(raw_x - half_width, TABLE_PLANE_TOP),
		Vector2(raw_x + half_width, TABLE_PLANE_TOP),
		Vector2(raw_x + half_width, TABLE_PLANE_BOTTOM),
		Vector2(raw_x - half_width, TABLE_PLANE_BOTTOM),
	]
	var texture := _gradient_texture(colors, PackedFloat32Array([
		0.05, 0.22, 0.35, 0.5, 0.65, 0.78, 0.95,
	]), Vector2(raw_width, RAIL_RAW_SIZE.y),
		Vector2(0.5, 0.0), Vector2(0.5, 1.0))
	var polygon := _textured_quad(node_name, _project_quad(raw_points),
		texture, Vector2(raw_width, RAIL_RAW_SIZE.y))
	polygon.z_index = z
	return polygon
