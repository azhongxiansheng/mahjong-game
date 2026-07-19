class_name CallAnnounce extends Control

# 牌桌体验重做 T1(spec 2026-06-11 G1):动作宣告演出。
#
# 吃/碰/杠/立直/自摸/荣和/役満 触发时的书法大字三层合成,对标参考作的
# call-announce / win-announce:
#   1. 本体 — Ma Shan Zheng 书法大字,白字 + 按动作配色的粗描边
#   2. 光晕 — 同字 3 层错位放大淡色字模拟 blur 绽放(1.1s ease-out)
#   3. 冲击波 — 圆环从字心扩散淡出(0.75s)
# 大字 + 头像从动作发起座位的方向滑入(自家底/下家右/对面顶/上家左)。
#
# 纯 overlay(MOUSE_FILTER_IGNORE),不阻塞对局;LIFETIME 后自毁。
# 用法:CallAnnounce.play(overlay_parent, &"pon", seat_id, avatar_texture)

const FONT: FontFile = preload("res://assets/fonts/MaShanZheng-Announce.ttf")

const LIFETIME: float = 1.25
const SLIDE_DIST: float = 30.0
const SLIDE_TIME: float = 0.4

# kind → [文案, 描边色, 字号]
const KIND_STYLE: Dictionary = {
	&"chi": ["吃", Color("2eb872"), 100],
	&"pon": ["碰", Color("3c8cbe"), 100],
	&"minkan": ["杠", Color("e0862e"), 100],
	&"ankan": ["杠", Color("e0862e"), 100],
	&"added_kan": ["杠", Color("e0862e"), 100],
	&"riichi": ["立直", Color("d9b65b"), 92],
	&"tsumo": ["自摸", Color("e63a28"), 108],
	&"ron": ["荣和", Color("e63a28"), 108],
	&"yakuman": ["役満", Color("c41e1e"), 124],
	# 途中流局：九種单独紫系大字；其它 reason 走「流局」
	&"kyuusyu": ["九種", Color("a050d0"), 100],
	&"ryuukyoku": ["流局", Color("8a7aa8"), 96],
}

# seat → [锚点位置(1280×800), 滑入方向单位向量]
const SEAT_LAYOUT: Dictionary = {
	0: [Vector2(640, 545), Vector2(0, 1)],
	1: [Vector2(950, 350), Vector2(1, 0)],
	2: [Vector2(640, 205), Vector2(0, -1)],
	3: [Vector2(330, 350), Vector2(-1, 0)],
}

var _ring_color: Color = Color.WHITE
var _ring_radius: float = 40.0
var _ring_alpha: float = 0.0
var _ring_width: float = 6.0


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
	var font_size: int = style[2]
	var anchor: Vector2 = SEAT_LAYOUT[seat_id][0]
	position = anchor
	_ring_color = Color(1.0, 0.94, 0.78, 1.0)

	# 字宽估算(书法字近方形):排版头像 + 大字水平排列,整体居中
	var text_w: float = font_size * text.length() * 1.05
	var avatar_w: float = 120.0 if avatar != null else 0.0
	var total_w: float = text_w + avatar_w + (16.0 if avatar != null else 0.0)
	var x0: float = -total_w / 2.0

	if avatar != null:
		var av := TextureRect.new()
		av.texture = avatar
		av.custom_minimum_size = Vector2(120, 150)
		av.size = Vector2(120, 150)
		av.position = Vector2(x0, -75)
		av.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		av.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		av.clip_contents = true
		av.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# 暖金描边底板,替代圆形裁切(v1;立绘是 64×80 竖图,方形裁切更合适)
		var frame := Panel.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0.35)
		sb.border_color = Color(1.0, 0.94, 0.78, 0.9)
		sb.set_border_width_all(3)
		sb.set_corner_radius_all(10)
		frame.add_theme_stylebox_override("panel", sb)
		frame.position = av.position - Vector2(4, 4)
		frame.size = av.size + Vector2(8, 8)
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(frame)
		add_child(av)
		x0 += avatar_w + 16.0

	# 光晕层:3 份错位放大的淡暖色字(模拟 blur 绽放),在本体之下。
	# 不带阴影 — 带阴影会在放大淡出时产生脏黑残影。
	for i in range(3):
		var halo := _make_label(text, font_size, Color(1.0, 0.94, 0.78, 0.0),
			0, Color.TRANSPARENT, false)
		halo.position = Vector2(x0, -font_size * 0.75)
		halo.size = Vector2(text_w, font_size * 1.5)
		halo.pivot_offset = halo.size / 2.0
		halo.name = "Halo%d" % i
		add_child(halo)

	# 本体大字:白字 + kind 配色粗描边 + 投影
	var main := _make_label(text, font_size, Color.WHITE, int(font_size * 0.18), color)
	main.position = Vector2(x0, -font_size * 0.75)
	main.size = Vector2(text_w, font_size * 1.5)
	main.pivot_offset = main.size / 2.0
	main.name = "MainText"
	add_child(main)


func _make_label(text: String, font_size: int, color: Color,
		outline_size: int, outline_color: Color, with_shadow: bool = true) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ls := LabelSettings.new()
	ls.font = FONT
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
	var slide: Vector2 = SEAT_LAYOUT[seat_id][1] * SLIDE_DIST
	var target := position
	position = target + slide
	modulate = Color(1, 1, 1, 0)

	var tw := create_tween().set_parallel(true)
	# 入场:滑入 + 淡入(expo-out 近似参考作 cubic-bezier(.16,1,.3,1))
	tw.tween_property(self, "position", target, SLIDE_TIME) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate:a", 1.0, SLIDE_TIME * 0.6)
	# 光晕绽放:alpha 0.5→0,scale 1→1.18,逐层错峰
	for i in range(3):
		var halo := get_node_or_null("Halo%d" % i) as Label
		if halo == null:
			continue
		halo.label_settings.font_color = Color(1.0, 0.94, 0.78, 0.6 - i * 0.13)
		var htw := create_tween()
		htw.tween_interval(0.05 + i * 0.06)
		htw.tween_property(halo, "scale", Vector2.ONE * (1.18 + i * 0.1), 1.0) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		htw.parallel().tween_property(halo, "modulate:a", 0.0, 1.0)
	# 冲击波圆环
	_ring_alpha = 0.9
	var rtw := create_tween()
	rtw.tween_method(_set_ring, 0.0, 1.0, 0.75) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# 整体退场 + 自毁
	var out := create_tween()
	out.tween_interval(LIFETIME - 0.3)
	out.tween_property(self, "modulate:a", 0.0, 0.3)
	out.tween_callback(queue_free)


func _set_ring(t: float) -> void:
	_ring_radius = 40.0 + t * 180.0
	_ring_alpha = 0.9 * (1.0 - t)
	_ring_width = 6.0 * (1.0 - t * 0.6) + 1.0
	queue_redraw()


func _draw() -> void:
	if _ring_alpha <= 0.01:
		return
	var c := _ring_color
	c.a = _ring_alpha
	draw_arc(Vector2.ZERO, _ring_radius, 0, TAU, 64, c, _ring_width, true)
