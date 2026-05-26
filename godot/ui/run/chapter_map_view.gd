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

# 视觉地图参数
const NODE_RADIUS: float = 28.0
const COLUMN_WIDTH: float = 100.0
const ROW_HEIGHT: float = 70.0
const MAP_PADDING_LEFT: float = 60.0
const MAP_PADDING_TOP: float = 40.0

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
		_render_visual_map()
		return
	# Fallback: 文本按钮（向后兼容）
	for i in range(_options.size()):
		var node_ref: NodeRef = _options[i]
		var btn := Button.new()
		btn.text = format_option_text(i + 1, node_ref)
		btn.custom_minimum_size = Vector2(0, DT.BUTTON_H)
		btn.add_theme_font_size_override("font_size", DT.FONT_BODY)
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

# 视觉 DAG 渲染：节点圆+字 + 边连线 + 当前节点高亮 + 可选节点 clickable
func _render_visual_map() -> void:
	var depth: Dictionary = compute_layers(_chapter_map)
	# 按 layer 分组
	var layers: Dictionary = {}  # layer → Array[node_index]
	for n in depth.keys():
		var d: int = int(depth[n])
		if not layers.has(d):
			layers[d] = []
		layers[d].append(n)
	# 排序使布局稳定
	for d in layers.keys():
		layers[d].sort()
	# 计算每个 node 的位置
	var positions: Dictionary = {}  # node_index → Vector2
	var max_layer: int = 0
	for d in layers.keys():
		max_layer = max(max_layer, int(d))
	for d in layers.keys():
		var di: int = int(d)
		var nodes_in_layer: Array = layers[d]
		var n_count: int = nodes_in_layer.size()
		for i in range(n_count):
			var ni: int = int(nodes_in_layer[i])
			var x: float = MAP_PADDING_LEFT + di * COLUMN_WIDTH
			var y_offset: float = (i - (n_count - 1) / 2.0) * ROW_HEIGHT
			var y: float = MAP_PADDING_TOP + 240.0 + y_offset  # 240 是地图区域中心
			positions[ni] = Vector2(x, y)
	# 边线绘制（用 Line2D）
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
			line.width = 2.0
			line.default_color = Color(DT.TEXT_MUTED.r, DT.TEXT_MUTED.g, DT.TEXT_MUTED.b, 0.7)
			edges_root.add_child(line)
	# 节点按钮：每个节点 = 圆形 Button
	var available: Dictionary = {}
	for opt in _options:
		available[int(opt.index)] = true
	for n in range(_chapter_map.node_count()):
		if not positions.has(n):
			continue
		var node_ref: NodeRef = _chapter_map.nodes[n]
		var pos: Vector2 = positions[n]
		var is_current: bool = (n == _chapter_map.current_node)
		var is_available: bool = available.has(n)
		var is_visited: bool = (depth.has(n) and not is_available and not is_current
			and _chapter_map.current_node >= 0
			and int(depth.get(n, 9999)) <= int(depth.get(_chapter_map.current_node, -1)))
		_add_node_button(node_ref, pos, is_current, is_available, is_visited)

func _add_node_button(node_ref: NodeRef, pos: Vector2, is_current: bool, is_available: bool, is_visited: bool) -> void:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(NODE_RADIUS * 2.0, NODE_RADIUS * 2.0)
	btn.position = pos - Vector2(NODE_RADIUS, NODE_RADIUS)
	# 有节点图标资产时用图标，否则 fall-back 到文字字形。
	var icon: Texture2D = node_icon(node_ref.kind)
	if icon != null:
		btn.icon = icon
		btn.expand_icon = true
	else:
		btn.text = node_glyph(node_ref.kind)
		btn.add_theme_font_size_override("font_size", DT.FONT_SUBTITLE)
	# 配色：当前节点亮金边，可选节点正常色，已访问灰显
	var base: Color = node_color(node_ref.kind)
	if is_visited:
		base = base.darkened(0.5)
	elif is_current:
		base = base.lightened(0.2)
	var sb := StyleBoxFlat.new()
	sb.bg_color = base
	sb.corner_radius_top_left = int(NODE_RADIUS)
	sb.corner_radius_top_right = int(NODE_RADIUS)
	sb.corner_radius_bottom_left = int(NODE_RADIUS)
	sb.corner_radius_bottom_right = int(NODE_RADIUS)
	if is_current:
		sb.border_color = DT.TEXT_TITLE
		sb.border_width_left = 3
		sb.border_width_right = 3
		sb.border_width_top = 3
		sb.border_width_bottom = 3
	elif is_available:
		sb.border_color = DT.TEXT_PRIMARY
		sb.border_width_left = 2
		sb.border_width_right = 2
		sb.border_width_top = 2
		sb.border_width_bottom = 2
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.add_theme_stylebox_override("disabled", sb)
	btn.disabled = not is_available
	if is_available:
		var idx_capture: int = node_ref.index
		btn.pressed.connect(func(): emit_signal("node_chosen", idx_capture))
	# tooltip
	btn.tooltip_text = "%s (#%d)" % [node_ref.display_name(), node_ref.index]
	_map_view.add_child(btn)
