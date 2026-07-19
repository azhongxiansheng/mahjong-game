class_name ChapterMapView extends Control

# 麻将王 — 里程碑 4 第 3 步：节点选择 UI
#
# US-004：从纯文本按钮升级为视觉 DAG 地图（按层级布局 + 节点图标 + 边）。
# 当传入 chapter_map 时显示视觉地图；否则 fallback 到文本按钮列表。
# 点击下层可达节点 → emit signal("node_chosen", node_index)。

signal node_chosen(node_index: int)

@onready var _label_last: Label = $VBox/LastResult
@onready var _options_box: VBoxContainer = $VBox/OptionsBox
@onready var _map_view: Control = get_node_or_null("MapView")

var _last_result_text: String = ""
var _options: Array = []  # Array[NodeRef]
var _chapter_map: ChapterMap = null

# 视觉地图参数（尖塔式可读：更大节点 + 更宽路径间距）
const NODE_RADIUS: float = 36.0
const COLUMN_WIDTH: float = 130.0
const ROW_HEIGHT: float = 96.0
const MAP_PADDING_LEFT: float = 100.0
const MAP_PADDING_TOP: float = 36.0

# 节点按 NodeKind 着色（spec §7 6 类）
static func node_color(kind: int) -> Color:
	match kind:
		NodeKind.Kind.NORMAL: return Color(0.50, 0.55, 0.65)  # 灰蓝
		NodeKind.Kind.ELITE:  return Color(0.85, 0.65, 0.20)  # 金黄
		NodeKind.Kind.CAMP:   return Color(0.30, 0.65, 0.40)  # 绿
		NodeKind.Kind.SHOP:   return Color(0.40, 0.60, 0.85)  # 蓝
		NodeKind.Kind.EVENT:  return Color(0.75, 0.45, 0.85)  # 紫
		NodeKind.Kind.BOSS:   return Color(0.85, 0.25, 0.25)  # 红
	return Color(0.5, 0.5, 0.5)

static func node_glyph(kind: int) -> String:
	match kind:
		NodeKind.Kind.NORMAL: return "战"
		NodeKind.Kind.ELITE:  return "精"
		NodeKind.Kind.CAMP:   return "营"
		NodeKind.Kind.SHOP:   return "店"
		NodeKind.Kind.EVENT:  return "事"
		NodeKind.Kind.BOSS:   return "王"
	return "?"

# 节点种类 → run_icons 资源名。缺图时（资产未生成）返回 null，
# 调用方 fall-back 到 node_glyph 文字。
static func node_icon(kind: int) -> Texture2D:
	var name := ""
	match kind:
		NodeKind.Kind.NORMAL: name = "node_normal"
		NodeKind.Kind.ELITE:  name = "node_elite"
		NodeKind.Kind.CAMP:   name = "node_camp"
		NodeKind.Kind.SHOP:   name = "node_shop"
		NodeKind.Kind.EVENT:  name = "node_event"
		NodeKind.Kind.BOSS:   name = "node_boss"
	if name == "":
		return null
	var path := "res://assets/run_icons/%s.png" % name
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D

func _ready() -> void:
	RunUi.attach_background(self)
	_rebuild()

# ---- public setters ----

func set_options(options: Array) -> void:
	_options = options
	if is_inside_tree():
		_rebuild()

# US-004：完整 ChapterMap（含 nodes / edges / current_node）注入；触发视觉地图渲染。
# 不传则 fallback 文本按钮（向后兼容）。
func set_chapter_map(p_map: ChapterMap) -> void:
	_chapter_map = p_map
	if is_inside_tree():
		_rebuild()

func set_last_result_text(text: String) -> void:
	_last_result_text = text
	if is_inside_tree():
		_rebuild()

# ---- helpers (static) ----

# 给 NodeRef 生成"[N] 类型名 (描述)"按钮文本
static func format_option_text(option_index: int, node_ref: NodeRef) -> String:
	if node_ref == null:
		return "[%d] ?" % option_index
	var hint := ""
	match node_ref.kind:
		NodeKind.Kind.NORMAL:
			hint = " (vs 3 SimpleAi)"
		NodeKind.Kind.ELITE:
			hint = " (精英 vs 3 SimpleAi)"
		NodeKind.Kind.BOSS:
			hint = " (Boss 桌)"
		NodeKind.Kind.CAMP:
			hint = " (占位 — M5)"
		NodeKind.Kind.SHOP:
			hint = " (占位 — M5)"
		NodeKind.Kind.EVENT:
			hint = " (占位 — M5)"
	return "[%d] %s%s" % [option_index, node_ref.display_name(), hint]

# 给 NodeResult 生成"上一节点：普通桌（排名 2，无血损）"摘要
static func format_last_result(node_ref: NodeRef, result: NodeResult) -> String:
	if node_ref == null or result == null:
		return ""
	var hp_str: String = "无血损" if result.hp_delta == 0 else "-%d HP" % -result.hp_delta
	return "上一节点：%s（排名 %d，%s）" % [
		node_ref.display_name(), result.rank, hp_str
	]

# ---- internal ----

func _rebuild() -> void:
	if _label_last:
		_label_last.text = _last_result_text if _last_result_text != "" else "（尚未推进）"
	if _options_box == null:
		return
	# 清空旧子节点
	for child in _options_box.get_children():
		child.queue_free()
	if _map_view:
		for child in _map_view.get_children():
			child.queue_free()
	# 视觉地图模式（有 ChapterMap 数据 + MapView 容器）
	if _chapter_map != null and _map_view != null:
		# 首帧 size 常为 0 → 子按钮点不中；等布局后再画
		if _map_view.size.y < 80.0:
			call_deferred("_render_visual_map_when_ready")
		else:
			_render_visual_map()
		return
	# Fallback: 文本按钮（向后兼容）
	_rebuild_text_options()


func _render_visual_map_when_ready() -> void:
	if not is_inside_tree() or _map_view == null or _chapter_map == null:
		return
	# 再清一次，避免 deferred 与二次 rebuild 叠两套节点
	for child in _map_view.get_children():
		child.queue_free()
	_render_visual_map()


func _rebuild_text_options() -> void:
	for i in range(_options.size()):
		var node_ref: NodeRef = _options[i]
		var btn := DT.make_button(format_option_text(i + 1, node_ref),
			DT.BtnRole.PRIMARY, Vector2(0, DT.BUTTON_H))
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var index_capture: int = node_ref.index
		btn.pressed.connect(func(): emit_signal("node_chosen", index_capture))
		_options_box.add_child(btn)

# 计算每个节点的层级（BFS depth from entry）
static func compute_layers(map: ChapterMap) -> Dictionary:
	var depth: Dictionary = {}
	if map.entry_node < 0:
		return depth
	depth[map.entry_node] = 0
	var queue: Array = [map.entry_node]
	while queue.size() > 0:
		var n: int = queue.pop_front()
		var d: int = int(depth[n])
		for nb in map.neighbors(n):
			if not depth.has(nb) or int(depth[nb]) < d + 1:
				depth[nb] = d + 1
				queue.append(nb)
	return depth

# 视觉 DAG 渲染：节点圆+图标 + 路径 + 当前/可达/已过三态
func _render_visual_map() -> void:
	if _map_view == null or _chapter_map == null:
		return
	_map_view.mouse_filter = Control.MOUSE_FILTER_STOP
	_map_view.clip_contents = false
	var depth: Dictionary = compute_layers(_chapter_map)
	var layers: Dictionary = {}  # layer → Array[node_index]
	for n in depth.keys():
		var d: int = int(depth[n])
		if not layers.has(d):
			layers[d] = []
		layers[d].append(n)
	for d in layers.keys():
		layers[d].sort()
	var positions: Dictionary = {}  # node_index → Vector2
	var max_layer: int = 0
	for d in layers.keys():
		max_layer = max(max_layer, int(d))
	# 用地图像素高度居中；未布局时用稳定 fallback
	var map_h: float = _map_view.size.y if _map_view.size.y > 80 else 520.0
	var map_w: float = _map_view.size.x if _map_view.size.x > 80 else 1200.0
	var center_y: float = map_h * 0.42
	# 横向居中整条 DAG
	var total_w: float = max_layer * COLUMN_WIDTH
	var x0: float = maxf(MAP_PADDING_LEFT, (map_w - total_w) * 0.5 - COLUMN_WIDTH * 0.25)
	for d in layers.keys():
		var di: int = int(d)
		var nodes_in_layer: Array = layers[d]
		var n_count: int = nodes_in_layer.size()
		for i in range(n_count):
			var ni: int = int(nodes_in_layer[i])
			var x: float = x0 + di * COLUMN_WIDTH
			var y_offset: float = (i - (n_count - 1) / 2.0) * ROW_HEIGHT
			var y: float = MAP_PADDING_TOP + center_y + y_offset
			positions[ni] = Vector2(x, y)
	var available: Dictionary = {}
	for opt in _options:
		available[int(opt.index)] = true
	# 边：可达支路亮金，其余暗灰（Node2D 不挡点击）
	var edges_root := Node2D.new()
	edges_root.name = "Edges"
	_map_view.add_child(edges_root)
	for n in range(_chapter_map.node_count()):
		if not positions.has(n):
			continue
		var p1: Vector2 = positions[n]
		for nb in _chapter_map.neighbors(n):
			if not positions.has(nb):
				continue
			var p2: Vector2 = positions[nb]
			var line := Line2D.new()
			line.add_point(p1)
			line.add_point(p2)
			var path_hot: bool = available.has(nb) or available.has(n) \
					or n == _chapter_map.current_node or nb == _chapter_map.current_node
			if path_hot:
				line.width = 4.0
				line.default_color = Color(DT.TEXT_TITLE.r, DT.TEXT_TITLE.g, DT.TEXT_TITLE.b, 0.55)
			else:
				line.width = 2.5
				line.default_color = Color(DT.TEXT_MUTED.r, DT.TEXT_MUTED.g, DT.TEXT_MUTED.b, 0.45)
			edges_root.add_child(line)
	# 先画不可点，再画可达（可达在上层，避免被挡）
	var order: Array = []
	for n in range(_chapter_map.node_count()):
		if positions.has(n):
			order.append(n)
	order.sort_custom(func(a, b):
		var aa: bool = available.has(int(a))
		var bb: bool = available.has(int(b))
		if aa == bb:
			return int(a) < int(b)
		return not aa and bb  # 不可点在前，可达后加 = 更上
	)
	for n in order:
		var node_ref: NodeRef = _chapter_map.nodes[n]
		var pos: Vector2 = positions[n]
		var is_current: bool = (n == _chapter_map.current_node)
		var is_available: bool = available.has(n)
		var is_visited: bool = (depth.has(n) and not is_available and not is_current
			and _chapter_map.current_node >= 0
			and int(depth.get(n, 9999)) <= int(depth.get(_chapter_map.current_node, -1)))
		_add_node_button(node_ref, pos, is_current, is_available, is_visited)
	# 底部再列可达节点文字按钮，避免只靠圆点点不中
	if _options_box and not _options.is_empty():
		for child in _options_box.get_children():
			child.queue_free()
		var hint := Label.new()
		hint.text = "可进入："
		hint.add_theme_color_override("font_color", DT.TEXT_MUTED)
		hint.add_theme_font_size_override("font_size", DT.FONT_CAPTION)
		_options_box.add_child(hint)
		for opt in _options:
			var nr: NodeRef = opt
			var b := DT.make_button(nr.display_name(), DT.BtnRole.PRIMARY, Vector2(160, 40))
			var idx: int = nr.index
			b.pressed.connect(func(): emit_signal("node_chosen", idx))
			_options_box.add_child(b)


func _add_node_button(node_ref: NodeRef, pos: Vector2, is_current: bool, is_available: bool, is_visited: bool) -> void:
	var diameter: float = NODE_RADIUS * 2.0
	# 当前节点外环（不挡点）
	if is_current:
		var ring := Panel.new()
		ring.position = pos - Vector2(NODE_RADIUS + 8, NODE_RADIUS + 8)
		ring.size = Vector2(diameter + 16, diameter + 16)
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rsb := StyleBoxFlat.new()
		rsb.bg_color = Color(0, 0, 0, 0)
		rsb.border_color = DT.TEXT_TITLE
		rsb.set_border_width_all(3)
		rsb.set_corner_radius_all(int(NODE_RADIUS + 8))
		ring.add_theme_stylebox_override("panel", rsb)
		_map_view.add_child(ring)
		var rtw := create_tween().set_loops()
		rtw.tween_property(ring, "modulate:a", 0.35, 0.55).set_trans(Tween.TRANS_SINE)
		rtw.tween_property(ring, "modulate:a", 1.0, 0.55).set_trans(Tween.TRANS_SINE)

	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(diameter, diameter)
	btn.size = Vector2(diameter, diameter)
	btn.position = pos - Vector2(NODE_RADIUS, NODE_RADIUS)
	btn.clip_text = true
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	var icon: Texture2D = node_icon(node_ref.kind)
	if icon != null:
		btn.icon = icon
		btn.expand_icon = true
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	else:
		btn.text = node_glyph(node_ref.kind)
		btn.add_theme_font_size_override("font_size", DT.FONT_SUBTITLE)
	var base: Color = node_color(node_ref.kind)
	if is_visited:
		base = base.darkened(0.55)
		btn.modulate = Color(1, 1, 1, 0.55)
	elif is_current:
		base = base.lightened(0.15)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(base.r * 0.35, base.g * 0.35, base.b * 0.35, 0.95)
	sb.set_corner_radius_all(int(NODE_RADIUS))
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 8
	sb.shadow_offset = Vector2(0, 3)
	if is_current:
		sb.border_color = DT.TEXT_TITLE
		sb.set_border_width_all(3)
	elif is_available:
		sb.border_color = Color(1, 1, 1, 0.95)
		sb.set_border_width_all(3)
		sb.shadow_color = Color(base.r, base.g, base.b, 0.5)
		sb.shadow_size = 12
	else:
		sb.border_color = Color(base.r, base.g, base.b, 0.5)
		sb.set_border_width_all(1)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sbc := sb.duplicate() as StyleBoxFlat
		if state == "hover" and is_available:
			sbc.bg_color = sbc.bg_color.lightened(0.15)
		btn.add_theme_stylebox_override(state, sbc)
	btn.disabled = not is_available
	if is_available:
		var idx_capture: int = node_ref.index
		btn.pressed.connect(func(): emit_signal("node_chosen", idx_capture))
		# 呼吸只用 modulate，避免 scale 破坏点击命中
		var ptw := create_tween().set_loops()
		ptw.tween_property(btn, "modulate", Color(1.15, 1.1, 0.95, 1.0), 0.65)\
			.set_trans(Tween.TRANS_SINE)
		ptw.tween_property(btn, "modulate", Color.WHITE, 0.65)\
			.set_trans(Tween.TRANS_SINE)
	btn.tooltip_text = "%s (#%d)" % [node_ref.display_name(), node_ref.index]
	_map_view.add_child(btn)
	# 脚下短名（IGNORE，不挡点）
	var name_lbl := Label.new()
	name_lbl.text = node_ref.display_name()
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.position = Vector2(pos.x - 48, pos.y + NODE_RADIUS + 4)
	name_lbl.size = Vector2(96, 20)
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color",
		DT.TEXT_TITLE if is_current or is_available else DT.TEXT_MUTED)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_visited:
		name_lbl.modulate.a = 0.55
	_map_view.add_child(name_lbl)
