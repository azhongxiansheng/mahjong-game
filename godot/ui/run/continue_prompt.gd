class_name ContinuePrompt extends Control

# 麻将王 — 里程碑 5 第 4 步：启动时存档恢复提示（plan-5 第 4 步）
#
# 当 SaveSystem.has_save() 为 true 时，RunFlow._ready 实例化本场景；
# 玩家点 Continue 触发 continue_run signal；点 New 触发 new_run（清旧档）。

signal continue_run
signal new_run

@onready var _info: Label = $Panel/VBox/Info
@onready var _continue_btn: Button = $Panel/VBox/Continue
@onready var _new_btn: Button = $Panel/VBox/New

var _save_summary_text: String = "（无存档摘要）"

func _ready() -> void:
	RunUi.attach_background(self)
	if _continue_btn:
		DT.apply_button_role(_continue_btn, DT.BtnRole.PRIMARY)
		_continue_btn.pressed.connect(func(): emit_signal("continue_run"))
	if _new_btn:
		DT.apply_button_role(_new_btn, DT.BtnRole.SECONDARY)
		_new_btn.pressed.connect(func(): emit_signal("new_run"))
	if _info:
		_info.text = _save_summary_text

# 调用方在 instantiate 后调（传入 RunState 摘要）
func set_save_summary(rs: RunState) -> void:
	if rs == null:
		_save_summary_text = "（存档损坏；点新 Run 清档继续）"
	else:
		_save_summary_text = format_save_summary(rs)
	if _info:
		_info.text = _save_summary_text

static func format_save_summary(rs: RunState) -> String:
	if rs == null:
		return "无效存档"
	var lines: Array[String] = []
	lines.append("已有 Run：")
	lines.append("  Chapter %d / HP %d / 金币 %d" % [rs.chapter, rs.hp, rs.gold])
	lines.append("  访问节点 %d / Deck %d 张牌 + %d 角色能力" % [
		rs.history.size(),
		rs.player_deck.tile_variant_count() if rs.player_deck else 0,
		rs.player_deck.ability_count() if rs.player_deck else 0,
	])
	return "\n".join(lines)
