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
		DT.apply_button_role(_back_btn, DT.BtnRole.PRIMARY)
		_back_btn.pressed.connect(func(): emit_signal("back_to_menu"))
	# "查看战绩" + "复活" 共用 _back_btn 父容器,横向并列在结算页底部。
	if _back_btn != null and _back_btn.get_parent() != null:
		var stats_btn := DT.make_button("查看战绩", DT.BtnRole.SECONDARY, Vector2(160, DT.BUTTON_H))
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
	var afford: bool = rs.gold >= REVIVE_GOLD_COST
	var revive_btn := DT.make_button(
		"💰 花 %d gold 复活" % REVIVE_GOLD_COST if afford \
			else "复活需要 %d gold (你有 %d)" % [REVIVE_GOLD_COST, rs.gold],
		DT.BtnRole.PRIMARY if afford else DT.BtnRole.SECONDARY,
		Vector2(240, DT.BUTTON_H))
	revive_btn.name = "ReviveBtn"
	if afford:
		revive_btn.pressed.connect(func(): emit_signal("revive_requested"))
	else:
		revive_btn.disabled = true
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
	_summary_label.text = format_summary(rs) + _format_highlights_line(rs) + _format_daily_quests_line()
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

# "本 run 亮点":StatsManager.diff_from(rs.stats_at_start) 算这场 run 的增量,
# 只显示非零项,让玩家看到"我这场 N 次胡牌 / M 次役満"。stats_at_start 为空
# 说明 baseline 没记(旧档),跳过本段返 ""。失败 run 仍显示("虽然死了,但拿了
# 1 次役満")让结算页有 ego boost。
func _format_highlights_line(rs: RunState) -> String:
	if rs == null or rs.stats_at_start.is_empty():
		return ""
	var sm = get_tree().root.get_node_or_null("StatsManager") if is_inside_tree() else null
	if sm == null or not sm.has_method("diff_from"):
		return ""
	var d: Dictionary = sm.diff_from(rs.stats_at_start)
	var parts: Array[String] = []
	if int(d.get("hands_played", 0)) > 0:
		parts.append("打了 %d 局" % int(d.hands_played))
	if int(d.get("hands_won", 0)) > 0:
		var tsumo: int = int(d.get("tsumo_count", 0))
		var ron: int = int(d.get("ron_count", 0))
		parts.append("胡 %d (自摸 %d / 荣和 %d)" % [int(d.hands_won), tsumo, ron])
	if int(d.get("riichi_count", 0)) > 0:
		parts.append("立直 %d" % int(d.riichi_count))
	if int(d.get("yakuman_count", 0)) > 0:
		parts.append("⭐ 役満 %d" % int(d.yakuman_count))
	if int(d.get("ippatsu_count", 0)) > 0:
		parts.append("一発 %d" % int(d.ippatsu_count))
	if int(d.get("hands_lost_by_deal_in", 0)) > 0:
		parts.append("放铳 %d" % int(d.hands_lost_by_deal_in))
	if parts.is_empty():
		return ""
	return "\n\n— 本 run 亮点 —\n" + "  ·  ".join(parts)


# 每日任务进度 + 自动 claim 行。完成自动 claim 不让玩家再点(简化 UX),
# 通过 SaveToast 弹 "✅ 任务完成 +X gold/+Y renown"。RunSummary 显示所有
# 3 个任务的进度条 "今日胡 5 次 [3/5]"。
func _format_daily_quests_line() -> String:
	var dq = get_tree().root.get_node_or_null("DailyQuest") if is_inside_tree() else null
	if dq == null:
		return ""
	dq._ensure_today()  # 防 day 切换没刷
	var lines: Array[String] = []
	for q in dq.quests:
		var cur: int = dq.progress_for(q)
		var tgt: int = int(q.target)
		var mark: String = "✅" if cur >= tgt else "◯"
		if q.get("claimed", false):
			mark = "💰"
		lines.append("%s %s [%d/%d]" % [mark, q.desc, cur, tgt])
		# auto-claim 完成未领的
		if cur >= tgt and not q.get("claimed", false):
			dq.claim(q.id)
	if lines.is_empty():
		return ""
	return "\n\n— 今日任务 —\n" + "\n".join(lines)


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

# M5 第 3 步：MetaProgress 脚本常量（E1-02 后不再走 Autoload，用 preload）
const _META_PROGRESS_SCRIPT: GDScript = preload("res://meta/meta_progress.gd")


# M5 第 3 步：MetaProgress 已存在时显示真声望增量 + 累计 + 跨 Run 战绩
static func format_renown_with_meta(won: bool, total_renown: int, runs_completed: int, runs_won: int) -> String:
	var amount: int = (
		_META_PROGRESS_SCRIPT.RENOWN_RUN_WON if won else _META_PROGRESS_SCRIPT.RENOWN_RUN_FAILED
	)
	var lines: Array[String] = []
	lines.append("声望 +%d" % amount)
	lines.append("累计声望: %d" % total_renown)
	lines.append("跨 Run 战绩: %d 胜 / %d 局" % [runs_won, runs_completed])
	return "  |  ".join(lines)
