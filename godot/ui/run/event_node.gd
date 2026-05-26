class_name EventNode extends Control

# US-007：事件节点真实 UI。3-5 个硬编码 v1 事件，每个 2-3 选项。
# 每个选项触发对应 RunState 副作用，emit done 让 RunFlow 推进。

signal done

@onready var _title: Label = $VBox/Title
@onready var _description: Label = $VBox/Description
@onready var _options_box: VBoxContainer = $VBox/OptionsBox

var _run_state: RunState = null
var _event_def: Dictionary = {}
var _resolved: bool = false

# v1 硬编码事件池：title / desc / options[]。
# option = {label, hp_delta, gold_delta, kind ("normal"/"end"), require}
const EVENT_POOL: Array = [
	{
		"id": "found_gold",
		"title": "🪙 路边拾遗",
		"description": "你在路边发现一袋遗失的金币，旁边没有失主。",
		"options": [
			{"label": "拾起", "hp_delta": 0, "gold_delta": 30},
			{"label": "归还原主", "hp_delta": 0, "gold_delta": 0},
		],
	},
	{
		"id": "beggar",
		"title": "🥺 街边乞讨者",
		"description": "一位老者站在路边，向你伸出手。",
		"options": [
			{"label": "施舍（命运庇佑）", "hp_delta": 1, "gold_delta": -30, "require_gold": 30},
			{"label": "拒绝（怨念缠身）", "hp_delta": -1, "gold_delta": 0},
			{"label": "悄悄走开", "hp_delta": 0, "gold_delta": 0},
		],
	},
	{
		"id": "shrine",
		"title": "⛩️ 麻将之祠",
		"description": "你看到一座古老的祠堂，灯火摇曳。香火供着一只九莲宝灯纹的木雕。",
		"options": [
			{"label": "祈祷", "hp_delta": 999, "gold_delta": 0},
			{"label": "供奉", "hp_delta": 2, "gold_delta": -50, "require_gold": 50},
			{"label": "走过去", "hp_delta": 0, "gold_delta": 0},
		],
	},
	{
		"id": "merchant_trade",
		"title": "💰 行商兜售",
		"description": "一名行商凑近你低声说：「想要快速致富吗？」",
		"options": [
			{"label": "卖血换金", "hp_delta": -1, "gold_delta": 60},
			{"label": "婉拒", "hp_delta": 0, "gold_delta": 0},
		],
	},
	{
		"id": "dora_fortune",
		"title": "🀄 风之牌的低语",
		"description": "桌上散落着几张被风吹乱的牌，其中一张闪着金光。",
		"options": [
			{"label": "拾起", "hp_delta": 0, "gold_delta": 15},
			{"label": "无视", "hp_delta": 0, "gold_delta": 0},
		],
	},
	{
		"id": "hot_spring",
		"title": "♨️ 温泉休憩",
		"description": "你发现一处隐秘的温泉。热气氤氲中，疲惫感逐渐消散。",
		"options": [
			{"label": "泡汤放松（恢复 2 HP）", "hp_delta": 2, "gold_delta": 0},
			{"label": "温泉赌局（赌 HP 换金币）", "hp_delta": -1, "gold_delta": 80},
			{"label": "路过不停", "hp_delta": 0, "gold_delta": 0},
		],
	},
	{
		"id": "yakuza_threat",
		"title": "🔪 暗巷威胁",
		"description": "三个黑衣人挡在你面前：「留下买路钱，或者……」",
		"options": [
			{"label": "付钱打发", "hp_delta": 0, "gold_delta": -40, "require_gold": 40},
			{"label": "以牌技抵债", "hp_delta": 0, "gold_delta": 20},
			{"label": "硬闯（受伤）", "hp_delta": -2, "gold_delta": 0},
		],
	},
	{
		"id": "mysterious_dealer",
		"title": "🃏 神秘牌师",
		"description": "一位蒙面人坐在路边摆着牌阵。「想知道你的命运吗？代价是一点生命力。」",
		"options": [
			{"label": "占卜未来（损 HP 换大量金币）", "hp_delta": -2, "gold_delta": 120},
			{"label": "礼貌拒绝", "hp_delta": 0, "gold_delta": 0},
		],
	},
	{
		"id": "abandoned_dojo",
		"title": "🏯 废弃雀庄",
		"description": "推开破旧的门，里面竟然有人在打牌。一位老者看向你：「想试试手气吗？」",
		"options": [
			{"label": "对局（大赢或大输）", "hp_delta": -1, "gold_delta": 100},
			{"label": "观战学习（小收获）", "hp_delta": 0, "gold_delta": 25},
			{"label": "离开", "hp_delta": 0, "gold_delta": 0},
		],
	},
	{
		"id": "lucky_cat_statue",
		"title": "🐱 招财猫石像",
		"description": "路旁有一尊金色招财猫石像，底座刻着：「付出越多，回报越丰」。",
		"options": [
			{"label": "投入大量金币", "hp_delta": 2, "gold_delta": -60, "require_gold": 60},
			{"label": "投入少量金币", "hp_delta": 1, "gold_delta": -20, "require_gold": 20},
			{"label": "摸摸猫头离开", "hp_delta": 0, "gold_delta": 5},
		],
	},
	{
		"id": "storm_shelter",
		"title": "⛈️ 暴风雨避难",
		"description": "突然暴风雨来袭。你在一间破屋中避雨，发现地板下藏着什么。",
		"options": [
			{"label": "翻开地板（风险探索）", "hp_delta": -1, "gold_delta": 70},
			{"label": "安静等雨停", "hp_delta": 1, "gold_delta": 0},
		],
	},
	{
		"id": "rival_challenge",
		"title": "⚔️ 宿敌挑衅",
		"description": "一位过去的对手拦住你的去路：「上次是你赢了，这次不会再让你走。」",
		"options": [
			{"label": "接受挑战", "hp_delta": -1, "gold_delta": 50},
			{"label": "以退为进（损失金币换安全）", "hp_delta": 0, "gold_delta": -30, "require_gold": 30},
			{"label": "绕道而行", "hp_delta": 0, "gold_delta": 0},
		],
	},
	{
		"id": "sake_house",
		"title": "🍶 居酒屋",
		"description": "一间温暖的居酒屋飘出诱人的酒香。老板娘热情招呼：「进来坐坐吧？」",
		"options": [
			{"label": "喝一杯（恢复精力）", "hp_delta": 1, "gold_delta": -15, "require_gold": 15},
			{"label": "畅饮一番（醉酒状态）", "hp_delta": 2, "gold_delta": -40, "require_gold": 40},
			{"label": "赶路不停", "hp_delta": 0, "gold_delta": 0},
		],
	},
	{
		"id": "fallen_player",
		"title": "💀 倒下的雀士",
		"description": "你看到一位雀士倒在路边，衣衫褴褛，手里还握着几张牌。",
		"options": [
			{"label": "救助（获得感恩）", "hp_delta": 0, "gold_delta": 40},
			{"label": "搜刮遗物（罪恶感）", "hp_delta": -1, "gold_delta": 80},
			{"label": "默默走过", "hp_delta": 0, "gold_delta": 0},
		],
	},
]

func _ready() -> void:
	RunUi.attach_background(self)
	RunUi.attach_panel_icon($VBox, "res://assets/run_icons/node_event.png")
	_refresh()

# ---- public setters ----

func bind_run_state(rs: RunState) -> void:
	_run_state = rs
	if is_inside_tree():
		_refresh()

# 用 seed 决定本节点抽哪个事件（保证同 Run 同 seed 同事件，可复现）
func set_event_seed(seed: int) -> void:
	if EVENT_POOL.is_empty():
		_event_def = {}
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var idx := rng.randi_range(0, EVENT_POOL.size() - 1)
	_event_def = EVENT_POOL[idx]
	if is_inside_tree():
		_refresh()

# ---- helpers (static) ----

# 单选项应用：返回 true 如果选项可执行（条件满足）。
static func can_apply(option: Dictionary, rs: RunState) -> bool:
	if rs == null:
		return false
	var require_gold: int = int(option.get("require_gold", 0))
	if require_gold > 0 and rs.gold < require_gold:
		return false
	return true

# 应用单选项到 RunState，返 true 表示成功执行。
static func apply_option(option: Dictionary, rs: RunState) -> bool:
	if rs == null:
		return false
	if not can_apply(option, rs):
		return false
	var hp_delta: int = int(option.get("hp_delta", 0))
	var gold_delta: int = int(option.get("gold_delta", 0))
	# hp_delta = 999 视为恢复全部 HP（满血）
	if hp_delta == 999:
		rs.hp = rs.max_hp
	else:
		rs.hp = clamp(rs.hp + hp_delta, 0, rs.max_hp)
	rs.gold = max(0, rs.gold + gold_delta)
	return true

# ---- internal ----

func _refresh() -> void:
	if _title:
		_title.text = _event_def.get("title", "事件")
	if _description:
		_description.text = _event_def.get("description", "")
	if _options_box == null:
		return
	for child in _options_box.get_children():
		child.queue_free()
	if _resolved:
		var done_btn := Button.new()
		done_btn.text = "继续 →"
		done_btn.custom_minimum_size = Vector2(0, DT.BUTTON_H)
		done_btn.pressed.connect(func(): emit_signal("done"))
		_options_box.add_child(done_btn)
		return
	var options: Array = _event_def.get("options", [])
	for i in range(options.size()):
		var opt: Dictionary = options[i]
		# 选项 Button 用 DT.make_text_card_button 防 minimum_size 被多行文字撑爆。
		# 宽度按容器自适应,卡片 0 宽 + 80 高,内嵌 Label autowrap。
		var delta_line: String = format_option_delta(opt)
		var label_text: String = opt.get("label", "选项 %d" % (i + 1))
		var card_text: String = label_text if delta_line == "" else "%s\n[%s]" % [label_text, delta_line]
		var btn := DT.make_text_card_button(
				_options_box,
				card_text,
				Vector2(0, 80),
				DT.TEXT_MUTED)
		btn.disabled = not can_apply(opt, _run_state)
		var captured_opt: Dictionary = opt
		btn.pressed.connect(func(): _on_option_chosen(captured_opt))


# 从 option dict 拼"HP +1 · -30 金币 · 需 30 金币"风格预览串(纯派生字段,
# 不读 label)。无任何 delta/require 时返回 ""。
static func format_option_delta(opt: Dictionary) -> String:
	var parts: Array[String] = []
	var hp_delta: int = int(opt.get("hp_delta", 0))
	if hp_delta == 999:
		parts.append("HP 全满")
	elif hp_delta > 0:
		parts.append("HP +%d" % hp_delta)
	elif hp_delta < 0:
		parts.append("HP %d" % hp_delta)
	var gold_delta: int = int(opt.get("gold_delta", 0))
	if gold_delta > 0:
		parts.append("+%d 金币" % gold_delta)
	elif gold_delta < 0:
		parts.append("%d 金币" % gold_delta)
	var require_gold: int = int(opt.get("require_gold", 0))
	if require_gold > 0:
		parts.append("需 %d 金币" % require_gold)
	return " · ".join(parts)

func _on_option_chosen(option: Dictionary) -> void:
	apply_option(option, _run_state)
	_resolved = true
	_refresh()
