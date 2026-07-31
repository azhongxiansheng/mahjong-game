class_name DoraWidget extends Control

# 参考桌面左上角：五个宝牌指示槽与本场棒、立直棒共用一条紧凑信息框。
# 已翻槽使用真实牌面；未翻槽使用固定深绿牌背，避免复用红色 back.png。

const SLOT_W: float = 26.0
const SLOT_H: float = 34.0
const SLOT_GAP: float = 2.0
const SLOTS: int = 5
const WIDGET_SIZE := Vector2(246.0, 50.0)
const GREEN_BACK_COLOR := Color("2c5e3f")

var _rendered_key: String = "__unset__"
var _honba: int = 0
var _riichi_sticks: int = 0


func _init() -> void:
	name = "DoraWidget"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = WIDGET_SIZE
	custom_minimum_size = WIDGET_SIZE


# 兼容旧调用；只有宝牌变化时保留当前本场数。
func update_indicators(indicators: Array) -> void:
	update_state(indicators, _honba, _riichi_sticks)


func update_state(indicators: Array, honba: int, riichi_sticks: int) -> void:
	_honba = maxi(0, honba)
	_riichi_sticks = maxi(0, riichi_sticks)
	var key := "%s|%d|%d" % [
		",".join(indicators.map(func(value): return str(value))),
		_honba, _riichi_sticks,
	]
	if key == _rendered_key:
		return
	_rendered_key = key
	for child in get_children():
		remove_child(child)
		child.queue_free()
	add_child(_make_background())
	for slot_index in range(SLOTS):
		var tile_id := int(indicators[slot_index]) \
			if slot_index < indicators.size() else -1
		add_child(_make_indicator_slot(slot_index, tile_id))
	add_child(_make_separator())
	add_child(_make_honba_stick())
	add_child(_make_honba_count())
	add_child(_make_riichi_stick())
	add_child(_make_riichi_count())


static func _make_background() -> Panel:
	var background := Panel.new()
	background.name = "PanelBackground"
	background.size = WIDGET_SIZE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("08110cbf")
	style.border_color = Color("d9b65b73")
	style.set_border_width_all(1)
	style.set_corner_radius_all(9)
	style.shadow_color = Color("00000066")
	style.shadow_size = 5
	style.shadow_offset = Vector2(0, 2)
	background.add_theme_stylebox_override("panel", style)
	return background


static func _make_indicator_slot(slot_index: int, tile_id: int) -> Control:
	var slot := Control.new()
	slot.name = "IndicatorSlot%d" % slot_index
	slot.position = Vector2(8 + slot_index * (SLOT_W + SLOT_GAP), 8)
	slot.size = Vector2(SLOT_W, SLOT_H)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if tile_id >= 0:
		var face := CardTileBack.new()
		face.name = "Face"
		face.scale = Vector2(
			SLOT_W / float(CardTileBack.TILE_WIDTH),
			SLOT_H / float(CardTileBack.TILE_HEIGHT))
		face.set_face_up(tile_id)
		slot.add_child(face)
	else:
		slot.add_child(_make_green_back())
	return slot


static func _make_green_back() -> Panel:
	var back := Panel.new()
	back.name = "GreenBack"
	back.size = Vector2(SLOT_W, SLOT_H)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = GREEN_BACK_COLOR
	style.border_color = Color("163522")
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	style.shadow_color = Color("00000070")
	style.shadow_size = 3
	style.shadow_offset = Vector2(0, 2)
	back.add_theme_stylebox_override("panel", style)
	var top_light := ColorRect.new()
	top_light.name = "TopHighlight"
	top_light.position = Vector2(2, 1)
	top_light.size = Vector2(SLOT_W - 4, 2)
	top_light.color = Color("c8d4cb99")
	top_light.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_child(top_light)
	return back


static func _make_separator() -> ColorRect:
	var separator := ColorRect.new()
	separator.name = "CounterSeparator"
	separator.position = Vector2(151, 8)
	separator.size = Vector2(1, 34)
	separator.color = Color("d9b65b47")
	separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return separator


static func _make_honba_stick() -> Control:
	var marker := Control.new()
	marker.name = "HonbaStick"
	marker.position = Vector2(158, 8)
	marker.size = Vector2(28, 12)
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var body := Panel.new()
	body.name = "StickBody"
	body.position = Vector2(0, 2)
	body.size = Vector2(28, 7)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("ecece4")
	style.border_color = Color("3b332b")
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	body.add_theme_stylebox_override("panel", style)
	marker.add_child(body)
	for dot_index in range(3):
		var dot := ColorRect.new()
		dot.name = "RedDot%d" % dot_index
		dot.position = Vector2(7 + dot_index * 7, 4)
		dot.size = Vector2(3, 3)
		dot.color = Color("b7372e")
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		marker.add_child(dot)
	return marker


func _make_honba_count() -> Label:
	var count := Label.new()
	count.name = "HonbaCount"
	count.position = Vector2(190, 2)
	count.size = Vector2(50, 22)
	count.text = "×%d" % _honba
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count.add_theme_font_size_override("font_size", 14)
	count.add_theme_color_override("font_color", Color("f3f0e5"))
	count.add_theme_color_override("font_outline_color", Color("11150f"))
	count.add_theme_constant_override("outline_size", 2)
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return count


static func _make_riichi_stick() -> Control:
	var marker := Control.new()
	marker.name = "RiichiStick"
	marker.position = Vector2(158, 29)
	marker.size = Vector2(28, 12)
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var body := Panel.new()
	body.name = "StickBody"
	body.position = Vector2(0, 2)
	body.size = Vector2(28, 7)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("f2f0e7")
	style.border_color = Color("3b332b")
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	body.add_theme_stylebox_override("panel", style)
	marker.add_child(body)
	var dot := ColorRect.new()
	dot.name = "RedDot"
	dot.position = Vector2(12, 3)
	dot.size = Vector2(5, 5)
	dot.color = Color("c62f2b")
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.add_child(dot)
	return marker


func _make_riichi_count() -> Label:
	var count := Label.new()
	count.name = "RiichiCount"
	count.position = Vector2(190, 23)
	count.size = Vector2(50, 22)
	count.text = "×%d" % _riichi_sticks
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count.add_theme_font_size_override("font_size", 14)
	count.add_theme_color_override("font_color", Color("f3f0e5"))
	count.add_theme_color_override("font_outline_color", Color("11150f"))
	count.add_theme_constant_override("outline_size", 2)
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return count
