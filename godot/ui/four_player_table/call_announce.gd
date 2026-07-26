class_name CallAnnounce extends Control

# 原创结界舞台的动作宣告演出。普通鸣牌贴近动作席位短促出现；
# 立直、荣和与自摸可使用高冲击窄带，但始终避开牌河、手牌与操作区。
#
# 纯 overlay(MOUSE_FILTER_IGNORE),不阻塞对局;LIFETIME 后自毁。
# 用法:CallAnnounce.play(overlay_parent, &"pon", seat_id, avatar_texture)

const CALL_FONT: FontFile = preload("res://assets/fonts/LiuJianMaoCao-Announce.ttf")
const RIICHI_FONT: FontFile = preload("res://assets/fonts/MaShanZheng-Announce.ttf")

const CALL_LIFETIME: float = 1.38
const WIN_LIFETIME: float = 3.0
const CALL_SLIDE_DIST: float = 24.0
const CALL_SLIDE_TIME: float = 0.5
const WIN_SLIDE_DIST: float = 32.0
const WIN_SLIDE_TIME: float = 0.65
const CALL_HALO_TIME: float = 1.1
const WIN_HALO_TIME: float = 1.4
const CALL_SHOCK_TIME: float = 0.75
const WIN_SHOCK_TIME: float = 1.0
const EFFECT_DELAY: float = 0.05
const CALL_MARK_SIZE := Vector2(120.0, 120.0)
const WIN_SAFE_RECT := Rect2(240.0, 84.0, 300.0, 52.0)

const CALL_HALO_KEYFRAMES: Array = [
	[0.0, 0.0, 32.0, 0.5],
	[0.35, 1.0, 24.0, 1.4],
	[1.0, 0.55, 22.0, 1.1],
]
const WIN_HALO_KEYFRAMES: Array = [
	[0.0, 0.0, 48.0, 0.4],
	[0.35, 1.0, 36.0, 1.5],
	[1.0, 0.6, 34.0, 1.1],
]
# kind → [文案, 描边色, 字号]
const KIND_STYLE: Dictionary = {
	&"chi": ["吃", Color("2eb872"), 46],
	&"pon": ["碰", Color("2e8fd9"), 46],
	&"minkan": ["杠", Color("e8731f"), 46],
	&"ankan": ["杠", Color("e8731f"), 46],
	&"added_kan": ["杠", Color("e8731f"), 46],
	&"riichi": ["听", Color("e8c45a"), 46],
	&"tsumo": ["自摸", Color("e63a28"), 52],
	&"ron": ["荣和", Color("e63a28"), 52],
	&"chankan": ["抢杠", Color("ef8528"), 52],
}

const CALL_EFFECT_STYLE: Dictionary = {
	&"chi": {"halo": Color("78e6aabf"), "shock": Color("b4f0c8e6")},
	&"pon": {"halo": Color("78befabf"), "shock": Color("aad7ffe6")},
	&"minkan": {"halo": Color("ffb464c7"), "shock": Color("ffd28cf2")},
	&"ankan": {"halo": Color("ffb464c7"), "shock": Color("ffd28cf2")},
	&"added_kan": {"halo": Color("ffb464c7"), "shock": Color("ffd28cf2")},
	&"riichi": {"halo": Color("ffdc78c7"), "shock": Color("ffeba0f2")},
}
const WIN_EFFECT_STYLE: Dictionary = {
	&"tsumo": {"halo": Color("f06e5ad1"), "shock": Color("ffc882f2")},
	&"ron": {"halo": Color("f06e5ad1"), "shock": Color("ffc882f2")},
	&"chankan": {"halo": Color("ffaa5ad9"), "shock": Color("ffd78cf2")},
}

# seat → [1600×900 原创舞台安全锚点, 滑入方向单位向量]
# 锚点避开四席最大牌河/副露区、HUD、手牌与固定操作带。
const SEAT_LAYOUT: Dictionary = {
	0: [Vector2(1300, 650), Vector2(0, 1)],
	1: [Vector2(1300, 540), Vector2(1, 0)],
	2: [Vector2(800, 78), Vector2(0, -1)],
	3: [Vector2(300, 540), Vector2(-1, 0)],
}

static var _circle_avatar_shader: Shader = null

var _ring_color: Color = Color.WHITE
var _ring_radius: float = 40.0
var _ring_alpha: float = 0.0
var _ring_width: float = 6.0
var _ring_center: Vector2 = Vector2.ZERO
var _ring_start_diameter: float = 40.0
var _ring_end_diameter: float = 460.0
var _ring_start_width: float = 8.0
var _halo: Label = null
var _halo_keyframes: Array = CALL_HALO_KEYFRAMES
var _is_win_announce: bool = false


static func play(parent: Node, kind: StringName, seat_id: int,
		avatar: Texture2D = null) -> CallAnnounce:
	if parent == null or not KIND_STYLE.has(kind):
		return null
	var ca := CallAnnounce.new()
	ca._build(kind, clampi(seat_id, 0, 3), avatar)
	parent.add_child(ca)
	ca._animate(clampi(seat_id, 0, 3))
	return ca


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 200


func _build(kind: StringName, seat_id: int, avatar: Texture2D) -> void:
	var style: Array = KIND_STYLE[kind]
	var text: String = style[0]
	var color: Color = style[1]
	var font_size: int = int(style[2])
	var anchor: Vector2 = WIN_SAFE_RECT.get_center() if WIN_EFFECT_STYLE.has(kind) \
		else SEAT_LAYOUT[seat_id][0]
	position = anchor
	_is_win_announce = WIN_EFFECT_STYLE.has(kind)
	set_meta("is_win_announce", _is_win_announce)
	set_meta("layout_direction", "row")
	set_meta("seat_direction", SEAT_LAYOUT[seat_id][1])
	var effect: Dictionary = WIN_EFFECT_STYLE[kind] if _is_win_announce \
		else CALL_EFFECT_STYLE.get(kind, {
			"halo": Color("fff0c8b3"), "shock": Color("fff0c8e6")})
	_ring_color = effect["shock"]
	_ring_start_diameter = 60.0 if _is_win_announce else 28.0
	_ring_end_diameter = WIN_SAFE_RECT.size.y if _is_win_announce \
		else CALL_MARK_SIZE.x
	_ring_start_width = 10.0 if _is_win_announce else 8.0
	_halo_keyframes = WIN_HALO_KEYFRAMES if _is_win_announce else CALL_HALO_KEYFRAMES

	var label_font: FontFile = RIICHI_FONT if kind == &"riichi" \
		else CALL_FONT if _is_win_announce or CALL_EFFECT_STYLE.has(kind) else RIICHI_FONT
	var letter_spacing := 0.12 if _is_win_announce else 0.1
	var text_w: float = font_size * (text.length() + letter_spacing)
	var text_size := Vector2(text_w, font_size)
	var avatar_size := Vector2(48, 48)
	var text_position: Vector2
	var avatar_position := Vector2.ZERO
	var gap := 10.0 if _is_win_announce else 6.0
	var total_w := text_size.x + (avatar_size.x + gap if avatar != null else 0.0)
	var left := -total_w / 2.0
	avatar_position = Vector2(left, -avatar_size.y / 2.0)
	text_position = Vector2(left + (avatar_size.x + gap if avatar != null else 0.0),
		-text_size.y / 2.0)

	if avatar != null:
		var av := TextureRect.new()
		av.name = "Avatar"
		av.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		av.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		av.texture = avatar
		av.custom_minimum_size = avatar_size
		av.clip_contents = true
		av.mouse_filter = Control.MOUSE_FILTER_IGNORE
		av.material = _make_circle_avatar_material()
		add_child(av)
		av.position = avatar_position
		av.size = avatar_size

	# 单层文字 halo；shadow_size 承载光晕宽度。
	_halo = _make_label(text, font_size, effect["halo"], 0,
		Color.TRANSPARENT, false, label_font)
	_halo.name = "Halo"
	_halo.position = text_position
	_halo.size = text_size
	_halo.pivot_offset = text_size / 2.0
	_halo.label_settings.shadow_color = effect["halo"]
	_halo.label_settings.shadow_size = int(_halo_keyframes[0][2])
	_halo.modulate.a = 0.0
	_halo.scale = Vector2.ONE * float(_halo_keyframes[0][3])
	add_child(_halo)

	# 主字：普通 9px；和牌 10px，用阴影与桌面分层。
	var main := _make_label(text, font_size, Color.WHITE,
		10 if _is_win_announce else 9, color, true, label_font)
	main.position = text_position
	main.size = text_size
	main.pivot_offset = text_size / 2.0
	main.label_settings.shadow_offset = Vector2(0, 8 if _is_win_announce else 6)
	main.label_settings.shadow_size = 12 if _is_win_announce else 10
	main.label_settings.shadow_color = Color(0, 0, 0,
		0.75 if _is_win_announce else 0.70)
	main.name = "MainText"
	add_child(main)
	_ring_center = text_position + text_size / 2.0


static func _make_circle_avatar_material() -> ShaderMaterial:
	if _circle_avatar_shader == null:
		_circle_avatar_shader = Shader.new()
		_circle_avatar_shader.code = """
shader_type canvas_item;
void fragment() {
	vec2 p = UV - vec2(0.5);
	float edge = 1.0 - smoothstep(0.485, 0.5, length(p));
	vec4 tex = texture(TEXTURE, UV);
	COLOR = vec4(tex.rgb, tex.a * edge);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = _circle_avatar_shader
	return mat


func _make_label(text: String, font_size: int, color: Color,
		outline_size: int, outline_color: Color, with_shadow: bool = true,
		font: Font = RIICHI_FONT) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ls := LabelSettings.new()
	ls.font = font
	ls.font_size = font_size
	ls.font_color = color
	ls.outline_size = outline_size
	ls.outline_color = outline_color
	if with_shadow:
		ls.shadow_size = 10
		ls.shadow_color = Color(0, 0, 0, 0.7)
		ls.shadow_offset = Vector2(0, 6)
	lbl.label_settings = ls
	return lbl


func _animate(seat_id: int) -> void:
	var slide_dist := WIN_SLIDE_DIST if _is_win_announce else CALL_SLIDE_DIST
	var slide_time := WIN_SLIDE_TIME if _is_win_announce else CALL_SLIDE_TIME
	var halo_time := WIN_HALO_TIME if _is_win_announce else CALL_HALO_TIME
	var shock_time := WIN_SHOCK_TIME if _is_win_announce else CALL_SHOCK_TIME
	var lifetime := WIN_LIFETIME if _is_win_announce else CALL_LIFETIME
	var slide: Vector2 = SEAT_LAYOUT[seat_id][1] * slide_dist
	var target := position
	position = target + slide
	modulate = Color(1, 1, 1, 0)

	var tw := create_tween().set_parallel(true)
	# 位移与透明度共享同一减速曲线。
	tw.tween_property(self, "position", target, slide_time) \
		.set_custom_interpolator(_slide_ease)
	tw.tween_property(self, "modulate:a", 1.0, slide_time) \
		.set_custom_interpolator(_slide_ease)
	var htw := create_tween()
	htw.tween_interval(EFFECT_DELAY)
	htw.tween_method(_set_halo_progress, 0.0, 1.0, halo_time)
	# shock 同样延后 50ms，尺寸/边宽/透明度由公开 keyframes 驱动。
	_ring_alpha = 0.0
	var rtw := create_tween()
	rtw.tween_interval(EFFECT_DELAY)
	rtw.tween_method(_set_ring, 0.0, 1.0, shock_time)
	# 状态结束时直接卸载，不延长输入窗口。
	var out := create_tween()
	out.tween_interval(lifetime)
	out.tween_callback(queue_free)


func _set_ring(t: float) -> void:
	var eased := sample_cubic_bezier(t, 0.2, 0.7, 0.3, 1.0)
	_ring_radius = lerpf(_ring_start_diameter, _ring_end_diameter, eased) / 2.0
	_ring_width = lerpf(_ring_start_width, 1.0, eased)
	_ring_alpha = eased / 0.2 if eased < 0.2 else (1.0 - eased) / 0.8
	queue_redraw()


func _set_halo_progress(t: float) -> void:
	if _halo == null or not is_instance_valid(_halo):
		return
	var first: Array = _halo_keyframes[0]
	var second: Array = _halo_keyframes[1]
	var third: Array = _halo_keyframes[2]
	var from_key := first
	var to_key := second
	if t >= float(second[0]):
		from_key = second
		to_key = third
	var span := float(to_key[0]) - float(from_key[0])
	var local := clampf((t - float(from_key[0])) / span, 0.0, 1.0)
	# 每段 keyframe 独立应用 ease-out。
	local = sample_cubic_bezier(local, 0.0, 0.0, 0.58, 1.0)
	_halo.modulate.a = lerpf(float(from_key[1]), float(to_key[1]), local)
	_halo.label_settings.shadow_size = roundi(lerpf(
		float(from_key[2]), float(to_key[2]), local))
	_halo.scale = Vector2.ONE * lerpf(float(from_key[3]), float(to_key[3]), local)


func _slide_ease(t: float) -> float:
	return sample_cubic_bezier(t, 0.16, 1.0, 0.3, 1.0)


# cubic-bezier：先以 Newton-Raphson 求 x(t)=progress，再回代 y(t)。
static func sample_cubic_bezier(progress: float, x1: float, y1: float,
		x2: float, y2: float) -> float:
	var target := clampf(progress, 0.0, 1.0)
	var parameter := target
	for _iteration in range(8):
		var inverse := 1.0 - parameter
		var x := 3.0 * inverse * inverse * parameter * x1 \
			+ 3.0 * inverse * parameter * parameter * x2 \
			+ parameter * parameter * parameter
		var derivative := 3.0 * inverse * inverse * x1 \
			+ 6.0 * inverse * parameter * (x2 - x1) \
			+ 3.0 * parameter * parameter * (1.0 - x2)
		if absf(derivative) < 0.000001:
			break
		parameter = clampf(parameter - (x - target) / derivative, 0.0, 1.0)
	var final_inverse := 1.0 - parameter
	return 3.0 * final_inverse * final_inverse * parameter * y1 \
		+ 3.0 * final_inverse * parameter * parameter * y2 \
		+ parameter * parameter * parameter


func _draw() -> void:
	if _ring_alpha <= 0.01:
		return
	var c := _ring_color
	c.a = _ring_alpha
	draw_arc(_ring_center, _ring_radius, 0, TAU, 64, c, _ring_width, true)
