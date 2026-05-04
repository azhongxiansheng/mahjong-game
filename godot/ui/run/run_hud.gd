class_name RunHud extends Control

# 麻将王 — 里程碑 4 第 3 步：Run HUD 顶栏
#
# 显示：Chapter X / Floor Y | HP a/b | 金币 N
# v1 纯文本占位（M5 美术 / M6 内容生产时再雕花）。

@onready var _label_chapter: Label = $HBox/Chapter
@onready var _label_hp: Label = $HBox/Hp
@onready var _label_gold: Label = $HBox/Gold

func _ready() -> void:
	_refresh_default()

# ---- public setters ----

func bind_run_state(rs: RunState) -> void:
	if _label_chapter == null:
		return
	var floor_str := "?"
	var node_ref: NodeRef = rs.current_node_ref()
	if node_ref:
		floor_str = String.num(node_ref.floor_index + 1)
	_label_chapter.text = format_chapter_text(rs.chapter, floor_str)
	_label_hp.text = format_hp_text(rs.hp, rs.max_hp)
	_label_gold.text = format_gold_text(rs.gold)

# ---- helpers (static, 测试可用) ----

static func format_chapter_text(chapter: int, floor_str: String) -> String:
	return "Chapter %d / Floor %s" % [chapter, floor_str]

static func format_hp_text(hp: int, max_hp: int) -> String:
	return "HP: %d / %d" % [hp, max_hp]

static func format_gold_text(gold: int) -> String:
	return "金币: %d" % gold

# ---- internal ----

func _refresh_default() -> void:
	if _label_chapter == null:
		return
	_label_chapter.text = format_chapter_text(1, "?")
	var hp_init: int = int(BalanceConstants.lookup(&"starting_hp"))
	_label_hp.text = format_hp_text(hp_init, hp_init)
	_label_gold.text = format_gold_text(0)
