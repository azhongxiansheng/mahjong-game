class_name RunSummary extends Control

# 麻将王 — 里程碑 4 第 3 步：Run 结算 UI（plan-4 第 4 步使用）
#
# 通关 / 失败两态共用一场景。显示：标题 + 概览（HP / 金币 / 章节 / 节点数）+
# "声望 +N" 占位（M5 实装真元进度）+ "返回主菜单"按钮。

signal back_to_menu
# 失败时玩家点"花 X gold 复活"emit;RunFlow 接住后把 hp 恢复 1 + 扣 gold +
# 把当前 run 状态回放到失败节点重玩。仅 rs.won=false 且 gold>=cost 时按钮显示。
signal revive_requested

# 复活费用 — gold 数。设为略低于通关单局奖励 (60 hanchan / 30 east_round),
# 让玩家失败后"咬咬牙就能再来"。每场 run 复活次数无限,但每次都要 gold,
# 防止无脑利用 (没 gold 就只能放弃)。M7 平衡时按数据调。
const REVIVE_GOLD_COST: int = 50

@onready var _title: Label = $VBox/Title
@onready var _summary_label: Label = $VBox/Summary
@onready var _renown_label: Label = $VBox/Renown
@onready var _back_btn: Button = $VBox/BackBtn

func _ready() -> void:
	RunUi.attach_background(self)
	if _back_btn:
		_back_btn.pressed.connect(func(): emit_signal("back_to_menu"))
	# "查看战绩" + "复活" 共用 _back_btn 父容器,横向并列在结算页底部。
	if _back_btn != null and _back_btn.get_parent() != null:
		var stats_btn := Button.new()
		stats_btn.text = "查看战绩"
		stats_btn.custom_minimum_size = Vector2(160, DT.BUTTON_H)
		stats_btn.pressed.connect(_on_stats_pressed)
		_back_btn.get_parent().add_child(stats_btn)


func _on_stats_pressed() -> void:
	var view := StatsView.new()
	view.name = "_stats_view_root"
	get_tree().root.add_child(view)


# 失败态根据 gold 添加 / 不添加 "花 X gold 复活" 按钮。bind_run_state 调用。
# gold 不够则按钮 disabled + 文字提示;够则可点 → emit revive_requested。
func _maybe_add_revive_button(rs: RunState) -> void:
	if rs == null or rs.won:
		return
	if _back_btn == null or _back_btn.get_parent() == null:
		return
	var revive_btn := Button.new()
	revive_btn.name = "ReviveBtn"
	revive_btn.custom_minimum_size = Vector2(220, DT.BUTTON_H)
	var afford: bool = rs.gold >= REVIVE_GOLD_COST
	if afford:
		revive_btn.text = "💰 花 %d gold 复活" % REVIVE_GOLD_COST
		revive_btn.add_theme_color_override("font_color", DT.TEXT_TITLE)
		revive_btn.pressed.connect(func(): emit_signal("revive_requested"))
	else:
		revive_btn.text = "复活需要 %d gold (你有 %d)" % [REVIVE_GOLD_COST, rs.gold]
		revive_btn.disabled = true
		revive_btn.add_theme_color_override("font_color", DT.TEXT_MUTED)
	# 放在第一位 (主推这个 CTA),让"再来一把"成为失败页面的视觉重点
	var parent := _back_btn.get_parent()
	parent.add_child(revive_btn)
	parent.move_child(revive_btn, 0)

# ---- public setters ----

func bind_run_state(rs: RunState) -> void:
	if _title == null:
		return
	_title.text = format_outcome_title(rs.won)
	# 商业级:通关 → 金大字、失败 → 猩红大字,把胜负情绪放在标题。64 是结算专
	# 用的"超大字"(DT.FONT_TITLE 36 不够,这页就一个标题,留特例)。
	_title.add_theme_font_size_override("font_size", 64)
	if rs.won:
		_title.add_theme_color_override("font_color", DT.TEXT_TITLE)
	else:
		_title.add_theme_color_override("font_color", DT.TEXT_DANGER)
	_title.add_theme_constant_override("shadow_offset_x", 2)
	_title.add_theme_constant_override("shadow_offset_y", 2)
	_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_summary_label.text = format_summary(rs)
	# M5 第 3 步：尝试从 MetaProgress autoload 取真声望；若不存在 fallback 占位
	var mp := get_tree().root.get_node_or_null("MetaProgress") if is_inside_tree() else null
	if mp:
		_renown_label.text = format_renown_with_meta(rs.won, int(mp.renown), int(mp.runs_completed), int(mp.runs_won))
	else:
		_renown_label.text = format_renown_placeholder(rs.won)
	_maybe_add_revive_button(rs)

# ---- helpers (static) ----

static func format_outcome_title(won: bool) -> String:
	if won:
		return "通关"
	return "Run 失败"

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
		return "声望 +50"
	return "声望 +5"

# M5 第 3 步：MetaProgress 已存在时显示真声望增量 + 累计 + 跨 Run 战绩
static func format_renown_with_meta(won: bool, total_renown: int, runs_completed: int, runs_won: int) -> String:
	var amount: int = MetaProgress.RENOWN_RUN_WON if won else MetaProgress.RENOWN_RUN_FAILED
	var lines: Array[String] = []
	lines.append("声望 +%d" % amount)
	lines.append("累计声望: %d" % total_renown)
	lines.append("跨 Run 战绩: %d 胜 / %d 局" % [runs_won, runs_completed])
	return "  |  ".join(lines)
