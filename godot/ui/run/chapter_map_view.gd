class_name ChapterMapView extends Control

# 麻将王 — 里程碑 4 第 3 步：节点选择 UI（plan-4 D5 文本按钮列表）
#
# 显示：上一节点结算文字 + 下层节点 Button 列表。
# 点击某 Button → emit signal("node_chosen", node_index)。
# 数据流：外部调 set_run_state + set_last_result 注入；面板自己渲染。

signal node_chosen(node_index: int)

@onready var _label_last: Label = $VBox/LastResult
@onready var _options_box: VBoxContainer = $VBox/OptionsBox

var _last_result_text: String = ""
var _options: Array = []  # Array[NodeRef]

func _ready() -> void:
	_rebuild()

# ---- public setters ----

func set_options(options: Array) -> void:
	_options = options
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
	# 清空旧 Button
	for child in _options_box.get_children():
		child.queue_free()
	# 新建按钮
	for i in range(_options.size()):
		var node_ref: NodeRef = _options[i]
		var btn := Button.new()
		btn.text = format_option_text(i + 1, node_ref)
		btn.custom_minimum_size = Vector2(0, 44)
		var index_capture: int = node_ref.index
		btn.pressed.connect(func(): emit_signal("node_chosen", index_capture))
		_options_box.add_child(btn)
