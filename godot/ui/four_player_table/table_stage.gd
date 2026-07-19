class_name TableStage

# 雀魂式整桌舞台：毡 + 木框已烘焙进 table_felt；此处再叠
# 径向暗角 / 中心光晕 / 内场虚影，让桌「沉」下去。
# 不替换牌面资源，只做舞台层（调用方负责挂到 FourPlayerTable）。

const FELT_PATH := "res://assets/table_felt.png"
const FELT_FALLBACK := "res://assets/mahjong_table_bg.png"


# 在 parent 最底层搭舞台。返回毡节点（调试用）。
static func build(parent: Control, w: float, h: float) -> Control:
	var root := Control.new()
	root.name = "TableStage"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.position = Vector2.ZERO
	root.size = Vector2(w, h)
	parent.add_child(root)
	parent.move_child(root, 0)

	# 1) 外场深色（桌外）
	var outer := ColorRect.new()
	outer.color = Color(0.03, 0.025, 0.02, 1.0)
	outer.position = Vector2.ZERO
	outer.size = Vector2(w, h)
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(outer)

	# 2) 毡图
	var path: String = FELT_PATH if ResourceLoader.exists(FELT_PATH) else FELT_FALLBACK
	if ResourceLoader.exists(path):
		var felt := TextureRect.new()
		felt.name = "TableFelt"
		felt.texture = load(path)
		felt.position = Vector2.ZERO
		felt.size = Vector2(w, h)
		felt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		felt.stretch_mode = TextureRect.STRETCH_SCALE
		felt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(felt)

	# 3) 中心椭圆光晕（舞台聚光）
	var glow := Panel.new()
	glow.name = "CenterGlow"
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gw: float = w * 0.55
	var gh: float = h * 0.42
	glow.position = Vector2((w - gw) * 0.5, (h - gh) * 0.38)
	glow.size = Vector2(gw, gh)
	var gsb := StyleBoxFlat.new()
	gsb.bg_color = Color(0.35, 0.75, 0.45, 0.07)
	gsb.set_corner_radius_all(int(minf(gw, gh) * 0.5))
	gsb.shadow_color = Color(0.2, 0.55, 0.3, 0.12)
	gsb.shadow_size = 40
	glow.add_theme_stylebox_override("panel", gsb)
	root.add_child(glow)

	# 4) 四角暗角（叠在毡上，加深景深）
	_add_vignette(root, w, h)

	# 5) 内场细金框（在木框内侧再勾一层，衬托「台面」）
	var inner := Panel.new()
	inner.name = "InnerRail"
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var inset := 40.0
	inner.position = Vector2(inset, inset)
	inner.size = Vector2(w - inset * 2.0, h - inset * 2.0)
	var isb := StyleBoxFlat.new()
	isb.bg_color = Color(0, 0, 0, 0)
	isb.border_color = Color(0.85, 0.72, 0.38, 0.18)
	isb.set_border_width_all(1)
	isb.set_corner_radius_all(8)
	inner.add_theme_stylebox_override("panel", isb)
	root.add_child(inner)

	return root


static func _add_vignette(root: Control, w: float, h: float) -> void:
	var bands: Array = [
		# top / bottom / left / right — 渐变用多条半透明条近似
		[Vector2(0, 0), Vector2(w, 90), Color(0, 0, 0, 0.45)],
		[Vector2(0, h - 100), Vector2(w, 100), Color(0, 0, 0, 0.50)],
		[Vector2(0, 0), Vector2(70, h), Color(0, 0, 0, 0.35)],
		[Vector2(w - 70, 0), Vector2(70, h), Color(0, 0, 0, 0.35)],
	]
	for b in bands:
		var r := ColorRect.new()
		r.color = b[2]
		r.position = b[0]
		r.size = b[1]
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(r)
