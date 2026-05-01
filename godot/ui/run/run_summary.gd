class_name RunSummary extends Control

# 麻将王 — 里程碑 4 第 3 步：Run 结算 UI（plan-4 第 4 步使用）
#
# 通关 / 失败两态共用一场景。显示：标题 + 概览（HP / 金币 / 章节 / 节点数）+
# "声望 +N" 占位（M5 实装真元进度）+ "返回主菜单"按钮。

signal back_to_menu

@onready var _title: Label = $VBox/Title
@onready var _summary_label: Label = $VBox/Summary
@onready var _renown_label: Label = $VBox/Renown
@onready var _back_btn: Button = $VBox/BackBtn

func _ready() -> void:
	if _back_btn:
		_back_btn.pressed.connect(func(): emit_signal("back_to_menu"))

# ---- public setters ----

func bind_run_state(rs: RunState) -> void:
	if _title == null:
		return
	_title.text = format_outcome_title(rs.won)
	_summary_label.text = format_summary(rs)
	# M5 第 3 步：尝试从 MetaProgress autoload 取真声望；若不存在 fallback 占位
	var mp := get_tree().root.get_node_or_null("MetaProgress") if is_inside_tree() else null
	if mp:
		_renown_label.text = format_renown_with_meta(rs.won, int(mp.renown), int(mp.runs_completed), int(mp.runs_won))
	else:
		_renown_label.text = format_renown_placeholder(rs.won)

# ---- helpers (static) ----

static func format_outcome_title(won: bool) -> String:
	if won:
		return "🎉 通关！"
	return "💀 Run 失败"

static func format_summary(rs: RunState) -> String:
	var lines: Array[String] = []
	lines.append("到达章节: %d / %d" % [rs.chapter, RunState.MAX_CHAPTERS])
	lines.append("剩余 HP: %d / %d" % [rs.hp, rs.max_hp])
	lines.append("累计金币: %d" % rs.gold)
	lines.append("访问节点: %d" % rs.history.size())
	return "\n".join(lines)

# 占位声望奖励：通关 +50 / 失败 +5（M4 占位；M5 第 2 步起 MetaProgress
# 实装真元进度）。format_renown_with_meta 用真数据；本函数仅作 fallback。
static func format_renown_placeholder(won: bool) -> String:
	if won:
		return "声望 +50（占位）"
	return "声望 +5（占位）"

# M5 第 3 步：MetaProgress 已存在时显示真声望增量 + 累计 + 跨 Run 战绩
static func format_renown_with_meta(won: bool, total_renown: int, runs_completed: int, runs_won: int) -> String:
	var amount: int = MetaProgress.RENOWN_RUN_WON if won else MetaProgress.RENOWN_RUN_FAILED
	var lines: Array[String] = []
	lines.append("声望 +%d" % amount)
	lines.append("累计声望: %d" % total_renown)
	lines.append("跨 Run 战绩: %d 胜 / %d 局" % [runs_won, runs_completed])
	return "  |  ".join(lines)
