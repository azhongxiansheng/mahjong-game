class_name TableStage

# 牌桌复用用户自有参考项目的龙纹桌布；左右木沿按同一 18° 桌面投影绘制。
const FELT_PATH := "res://assets/table_felt.png"
const FELT_FALLBACK := "res://assets/mahjong_table_bg.png"

const RAIL_RAW_WIDTH: float = 120.0
const RAIL_RAW_OUTSET: float = 130.0
const RAIL_INNER_GAP: float = 10.0
const INNER_BEVEL_WIDTH: float = 14.0
const HIGHLIGHT_INSET: float = 12.0
const HIGHLIGHT_GRADIENT_OFFSETS := [
	0.0, 0.05, 0.22, 0.35, 0.50, 0.60, 0.78, 0.95, 1.0,
]

static var _rail_shader: Shader = null


# 在 parent 最底层搭舞台。返回舞台根节点（调试用）。
static func build(parent: Control, w: float, h: float) -> Control:
	var root := Control.new()
	root.name = "TableStage"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.position = Vector2.ZERO
	root.size = Vector2(w, h)
	parent.add_child(root)
	parent.move_child(root, 0)

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

	# 桌布原始平面只占 x=0..1600；投影外侧以黑色遮罩恢复舞台留空，
	# 木沿位于 x=-130..-10 / 1610..1730，中间自然留下 10px 黑缝。
	root.add_child(_build_table_clip_masks(w, h))
	root.add_child(_build_felt_edge_shadows(w, h))
	root.add_child(_build_table_rails(w, h))
	return root


static func _build_table_clip_masks(w: float, h: float) -> Node2D:
	var masks := Node2D.new()
	masks.name = "TableClipMasks"
	var raw_top := TableLayout.TABLE_PLANE_RECT.position.y
	var raw_bottom := TableLayout.TABLE_PLANE_RECT.end.y
	var left_top := _project(Vector2(0, raw_top), w, h)
	var right_top := _project(Vector2(TableLayout.VIEW_W, raw_top), w, h)
	var left := Polygon2D.new()
	left.name = "LeftOutsideMask"
	left.polygon = PackedVector2Array([
		Vector2(0, left_top.y), left_top,
		_project(Vector2(0, raw_bottom), w, h),
	])
	left.color = Color("020100")
	masks.add_child(left)
	var right := Polygon2D.new()
	right.name = "RightOutsideMask"
	right.polygon = PackedVector2Array([
		Vector2(w, right_top.y), right_top,
		_project(Vector2(TableLayout.VIEW_W, raw_bottom), w, h),
	])
	right.color = Color("020100")
	masks.add_child(right)
	return masks


static func _build_felt_edge_shadows(w: float, h: float) -> Node2D:
	var shadows := Node2D.new()
	shadows.name = "FeltEdgeShadows"
	var raw_top := TableLayout.TABLE_PLANE_RECT.position.y
	var raw_bottom := TableLayout.TABLE_PLANE_RECT.end.y
	for side_index in range(2):
		var raw_x: float = 0.0 if side_index == 0 else TableLayout.VIEW_W
		var line := Line2D.new()
		line.name = "LeftFeltShadow" if side_index == 0 else "RightFeltShadow"
		line.points = PackedVector2Array([
			_project(Vector2(raw_x, raw_top), w, h),
			_project(Vector2(raw_x, raw_bottom), w, h),
		])
		line.width = 18.0
		line.default_color = Color("00000073")
		line.antialiased = true
		shadows.add_child(line)
	return shadows


static func _build_table_rails(w: float, h: float) -> Node2D:
	var rails := Node2D.new()
	rails.name = "TableRails"
	rails.z_index = 0
	rails.add_child(_build_rail("LeftRail", false, w, h))
	rails.add_child(_build_rail("RightRail", true, w, h))
	return rails


static func _build_rail(node_name: String, right_side: bool,
		w: float, h: float) -> Node2D:
	var rail := Node2D.new()
	rail.name = node_name
	var soft_shadow := Line2D.new()
	soft_shadow.name = "SoftShadow"
	soft_shadow.points = _rail_inner_edge_points(right_side, w, h)
	soft_shadow.width = 16.0
	soft_shadow.default_color = Color("0000009e")
	soft_shadow.antialiased = true
	rail.add_child(soft_shadow)

	var body := Polygon2D.new()
	body.name = "Body"
	body.polygon = _rail_body_polygon(right_side, w, h)
	body.uv = _rail_body_uv(right_side)
	body.texture = _make_rail_uv_texture()
	body.material = _make_rail_material()
	body.color = Color.WHITE
	rail.add_child(body)

	var inner_bevel := Polygon2D.new()
	inner_bevel.name = "InnerBevel"
	inner_bevel.polygon = _rail_inner_bevel_polygon(right_side, w, h)
	inner_bevel.color = Color("0502018f")
	rail.add_child(inner_bevel)

	var glow := Line2D.new()
	glow.name = "HighlightGlow"
	glow.points = _rail_highlight_points(right_side, w, h)
	glow.width = 8.0
	glow.gradient = _make_highlight_gradient(0.28)
	glow.antialiased = true
	rail.add_child(glow)

	var highlight := Line2D.new()
	highlight.name = "Highlight"
	highlight.points = _rail_highlight_points(right_side, w, h)
	highlight.width = 2.0
	highlight.gradient = _make_highlight_gradient(1.0)
	highlight.antialiased = true
	rail.add_child(highlight)
	return rail


static func _rail_body_polygon(right_side: bool,
		w: float, h: float) -> PackedVector2Array:
	var raw_top := TableLayout.TABLE_PLANE_RECT.position.y
	var raw_bottom := TableLayout.TABLE_PLANE_RECT.end.y
	if right_side:
		var inner_x := TableLayout.VIEW_W + RAIL_INNER_GAP
		var outer_x := inner_x + RAIL_RAW_WIDTH
		return PackedVector2Array([
			_project(Vector2(inner_x, raw_top), w, h),
			_project(Vector2(outer_x, raw_top), w, h),
			_project(Vector2(outer_x, raw_bottom), w, h),
			_project(Vector2(inner_x, raw_bottom), w, h),
		])
	var outer_x := -RAIL_RAW_OUTSET
	var inner_x := -RAIL_INNER_GAP
	return PackedVector2Array([
		_project(Vector2(outer_x, raw_top), w, h),
		_project(Vector2(inner_x, raw_top), w, h),
		_project(Vector2(inner_x, raw_bottom), w, h),
		_project(Vector2(outer_x, raw_bottom), w, h),
	])


static func _rail_body_uv(right_side: bool) -> PackedVector2Array:
	var raw_height := TableLayout.TABLE_PLANE_RECT.size.y
	if right_side:
		return PackedVector2Array([
			Vector2(RAIL_RAW_WIDTH, 0), Vector2(0, 0),
			Vector2(0, raw_height), Vector2(RAIL_RAW_WIDTH, raw_height),
		])
	return PackedVector2Array([
		Vector2(0, 0), Vector2(RAIL_RAW_WIDTH, 0),
		Vector2(RAIL_RAW_WIDTH, raw_height), Vector2(0, raw_height),
	])


static func _rail_inner_bevel_polygon(right_side: bool,
		w: float, h: float) -> PackedVector2Array:
	var raw_top := TableLayout.TABLE_PLANE_RECT.position.y
	var raw_bottom := TableLayout.TABLE_PLANE_RECT.end.y
	if right_side:
		var inner_x := TableLayout.VIEW_W + RAIL_INNER_GAP
		return PackedVector2Array([
			_project(Vector2(inner_x, raw_top), w, h),
			_project(Vector2(inner_x + INNER_BEVEL_WIDTH, raw_top), w, h),
			_project(Vector2(inner_x + INNER_BEVEL_WIDTH, raw_bottom), w, h),
			_project(Vector2(inner_x, raw_bottom), w, h),
		])
	var inner_x := -RAIL_INNER_GAP
	return PackedVector2Array([
		_project(Vector2(inner_x - INNER_BEVEL_WIDTH, raw_top), w, h),
		_project(Vector2(inner_x, raw_top), w, h),
		_project(Vector2(inner_x, raw_bottom), w, h),
		_project(Vector2(inner_x - INNER_BEVEL_WIDTH, raw_bottom), w, h),
	])


static func _rail_inner_edge_points(right_side: bool,
		w: float, h: float) -> PackedVector2Array:
	var raw_x := TableLayout.VIEW_W + RAIL_INNER_GAP \
		if right_side else -RAIL_INNER_GAP
	return PackedVector2Array([
		_project(Vector2(raw_x, TableLayout.TABLE_PLANE_RECT.position.y), w, h),
		_project(Vector2(raw_x, TableLayout.TABLE_PLANE_RECT.end.y), w, h),
	])


static func _rail_highlight_points(right_side: bool,
		w: float, h: float) -> PackedVector2Array:
	var raw_x := TableLayout.VIEW_W + RAIL_INNER_GAP + HIGHLIGHT_INSET \
		if right_side else -RAIL_INNER_GAP - HIGHLIGHT_INSET
	var start := _project(Vector2(
		raw_x, TableLayout.TABLE_PLANE_RECT.position.y), w, h)
	var end := _project(Vector2(
		raw_x, TableLayout.TABLE_PLANE_RECT.end.y), w, h)
	var points := PackedVector2Array()
	for offset in HIGHLIGHT_GRADIENT_OFFSETS:
		points.append(start.lerp(end, float(offset)))
	return points


static func _project(raw_point: Vector2, w: float, h: float) -> Vector2:
	var projected := TableLayout.project_table_point(raw_point)
	return Vector2(
		projected.x * w / TableLayout.VIEW_W,
		projected.y * h / TableLayout.VIEW_H)


static func _make_rail_uv_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color.WHITE, Color.WHITE])
	var texture := GradientTexture2D.new()
	texture.width = int(RAIL_RAW_WIDTH)
	texture.height = int(TableLayout.TABLE_PLANE_RECT.size.y)
	texture.fill_from = Vector2.ZERO
	texture.fill_to = Vector2(1, 0)
	texture.gradient = gradient
	return texture


static func _make_rail_material() -> ShaderMaterial:
	if _rail_shader == null:
		_rail_shader = Shader.new()
		_rail_shader.code = """
shader_type canvas_item;

float hash21(vec2 point) {
	return fract(sin(dot(point, vec2(127.1, 311.7))) * 43758.5453123);
}

float value_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 local = fract(point);
	local = local * local * (3.0 - 2.0 * local);
	return mix(
		mix(hash21(cell), hash21(cell + vec2(1.0, 0.0)), local.x),
		mix(hash21(cell + vec2(0.0, 1.0)), hash21(cell + vec2(1.0)), local.x),
		local.y);
}

float fbm(vec2 point) {
	float result = 0.0;
	float amplitude = 0.5;
	for (int octave = 0; octave < 4; octave++) {
		result += value_noise(point) * amplitude;
		point = point * 2.03 + vec2(17.0, 9.0);
		amplitude *= 0.5;
	}
	return result;
}

float soft_spot(vec2 uv, vec2 center, vec2 radius) {
	return 1.0 - smoothstep(0.2, 1.0, length((uv - center) / radius));
}

void fragment() {
	float u = UV.x;
	float edge_px = min(u, 1.0 - u) * 120.0;
	vec3 wood = vec3(0.306, 0.114, 0.067);
	if (edge_px < 2.0) {
		wood = vec3(0.020, 0.008, 0.004);
	} else if (edge_px < 8.0) {
		wood = mix(vec3(0.114, 0.031, 0.020), vec3(0.220, 0.082, 0.047),
			(edge_px - 2.0) / 6.0);
	} else if (edge_px < 11.0) {
		wood = mix(vec3(0.220, 0.082, 0.047), vec3(0.047, 0.012, 0.004),
			(edge_px - 8.0) / 3.0);
	} else if (edge_px < 14.0) {
		wood = mix(vec3(0.047, 0.012, 0.004), vec3(0.306, 0.114, 0.067),
			(edge_px - 11.0) / 3.0);
	}
	float bend = value_noise(vec2(UV.y * 8.0, 3.7)) * 7.0;
	float grain = fbm(vec2(UV.x * 72.0 + bend, UV.y * 14.0));
	float streak = value_noise(vec2(UV.x * 138.0 + bend * 1.7, UV.y * 3.0));
	float material_mask = smoothstep(11.0, 18.0, edge_px);
	wood *= mix(1.0, 0.76 + grain * 0.34 + streak * 0.10, material_mask);
	float warm = soft_spot(UV, vec2(0.30, 0.18), vec2(0.24, 0.17));
	warm += soft_spot(UV, vec2(0.70, 0.62), vec2(0.20, 0.14));
	warm += soft_spot(UV, vec2(0.38, 0.88), vec2(0.22, 0.15));
	float knot = soft_spot(UV, vec2(0.64, 0.33), vec2(0.25, 0.18));
	knot += soft_spot(UV, vec2(0.26, 0.72), vec2(0.20, 0.13));
	wood += vec3(0.120, 0.025, 0.012) * warm * 0.42 * material_mask;
	wood -= vec3(0.055, 0.026, 0.018) * knot * 0.48 * material_mask;
	float center_light = 1.0 - smoothstep(0.0, 0.34, abs(UV.x - 0.5));
	wood += vec3(0.055, 0.035, 0.026) * center_light * material_mask;
	float pore = step(0.987, hash21(floor(UV * vec2(52.0, 150.0))));
	wood += vec3(0.18, 0.14, 0.11) * pore * 0.32 * material_mask;
	COLOR = vec4(clamp(wood, vec3(0.0), vec3(1.0)), 1.0);
}
"""
	var material := ShaderMaterial.new()
	material.shader = _rail_shader
	return material


static func _make_highlight_gradient(alpha_scale: float) -> Gradient:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array(HIGHLIGHT_GRADIENT_OFFSETS)
	gradient.colors = PackedColorArray([
		Color(1.0, 0.92, 0.84, 0.0),
		Color(1.0, 0.92, 0.84, 0.0),
		Color(1.0, 0.92, 0.84, 0.92 * alpha_scale),
		Color(1.0, 0.92, 0.84, 1.00 * alpha_scale),
		Color(1.0, 0.94, 0.86, 1.00 * alpha_scale),
		Color(1.0, 0.92, 0.84, 0.98 * alpha_scale),
		Color(1.0, 0.92, 0.84, 0.47 * alpha_scale),
		Color(1.0, 0.92, 0.84, 0.0),
		Color(1.0, 0.92, 0.84, 0.0),
	])
	gradient.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_LINEAR
	gradient.interpolation_color_space = Gradient.GRADIENT_COLOR_SPACE_SRGB
	return gradient
