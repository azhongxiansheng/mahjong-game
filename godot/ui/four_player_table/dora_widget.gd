class_name DoraWidget extends Control

# 宝牌指示窗(对标参考截图左上角):5 个指示牌槽,已翻的 face-up,
# 未翻的牌背;槽位随杠翻新增量点亮。挂 PlayableTable 平面层左上,
# 把 dora 信息从中心盘解放出来(中心盘只留局数/余张/回合)。

const SLOT_W: float = 34.0
const SLOT_H: float = 48.0
const SLOT_GAP: float = 3.0
const SLOTS: int = 5

# 初始哨兵值非空串:否则 update_indicators([]) 的 key="" 与初始值相同,
# 首次空状态被去重 early-return,5 个牌背槽压根不渲染。
var _rendered_key: String = "__unset__"

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(SLOTS * (SLOT_W + SLOT_GAP) + 16, SLOT_H + 14)

# indicators: Array[int] 已翻指示牌 id(state.dora_indicators.visible_tiles() 的 id)
func update_indicators(indicators: Array) -> void:
	var key: String = ",".join(indicators.map(func(v): return str(v)))
	if key == _rendered_key:
		return
	_rendered_key = key
	for child in get_children():
		child.queue_free()
	# 暗底圆角条
	var bg := Panel.new()
	bg.position = Vector2.ZERO
	bg.size = size
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.07, 0.05, 0.66)
	sb.border_color = Color(0.85, 0.71, 0.36, 0.30)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	bg.add_theme_stylebox_override("panel", sb)
	add_child(bg)
	var sx: float = SLOT_W / float(CardTileBack.TILE_WIDTH)
	var sy: float = SLOT_H / float(CardTileBack.TILE_HEIGHT)
	for i in range(SLOTS):
		var card := CardTileBack.new()
		card.position = Vector2(8 + i * (SLOT_W + SLOT_GAP), 7)
		card.scale = Vector2(sx, sy)
		add_child(card)
		if i < indicators.size():
			card.set_face_up(int(indicators[i]))
		else:
			card.set_owner_seat(-1)  # 牌背(未翻槽)
