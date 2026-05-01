class_name PlaceholderNode extends Control

# 麻将王 — 里程碑 4 第 3 步：占位节点通用场景（plan-4 D3）
#
# 营地 / 商店 / 事件 三类占位节点共用。设 NodeKind 切换标题文字；
# 点击"下一步"emit signal("done")，让 RunFlow 调 RunState.complete_node(
# NodeResult.from_placeholder()) 推进。

signal done

@onready var _title: Label = $VBox/Title
@onready var _description: Label = $VBox/Description
@onready var _next_btn: Button = $VBox/NextBtn

var _kind: int = NodeKind.Kind.CAMP

func _ready() -> void:
	if _next_btn:
		_next_btn.pressed.connect(_on_next_pressed)
	_refresh()

# ---- public setters ----

func set_node_kind(kind: int) -> void:
	_kind = kind
	if is_inside_tree():
		_refresh()

# ---- helpers (static) ----

static func title_for_kind(kind: int) -> String:
	match kind:
		NodeKind.Kind.CAMP: return "营地"
		NodeKind.Kind.SHOP: return "商店"
		NodeKind.Kind.EVENT: return "事件"
	return NodeKind.display_name(kind)

static func description_for_kind(kind: int) -> String:
	match kind:
		NodeKind.Kind.CAMP:
			return "在此地休整。M5 实装后可恢复 HP / 升级技能。"
		NodeKind.Kind.SHOP:
			return "刷新商品。M5 实装后可购买卡 / 角色能力 / 消耗品。"
		NodeKind.Kind.EVENT:
			return "随机事件。M5 实装后会有文字选项分支与奖惩。"
	return "占位节点（M5 实装）"

# ---- internal ----

func _refresh() -> void:
	if _title:
		_title.text = title_for_kind(_kind)
	if _description:
		_description.text = "%s\n\n（M4 v1：纯占位场景，跳过即可。M5 内容生产时填充。）\n\n%s" % [
			description_for_kind(_kind), "点击下方按钮推进。"
		]

func _on_next_pressed() -> void:
	emit_signal("done")
