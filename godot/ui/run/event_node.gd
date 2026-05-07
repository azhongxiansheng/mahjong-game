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
			{"label": "拾起（+30 金币）", "hp_delta": 0, "gold_delta": 30},
			{"label": "归还原主（+0）", "hp_delta": 0, "gold_delta": 0},
		],
	},
	{
		"id": "beggar",
		"title": "🥺 街边乞讨者",
		"description": "一位老者站在路边，向你伸出手。",
		"options": [
			{"label": "施舍 30 金币（+1 HP，命运庇佑）", "hp_delta": 1, "gold_delta": -30, "require_gold": 30},
			{"label": "拒绝（-1 HP，怨念缠身）", "hp_delta": -1, "gold_delta": 0},
			{"label": "悄悄走开", "hp_delta": 0, "gold_delta": 0},
		],
	},
	{
		"id": "shrine",
		"title": "⛩️ 麻将之祠",
		"description": "你看到一座古老的祠堂，灯火摇曳。香火供着一只九莲宝灯纹的木雕。",
		"options": [
			{"label": "祈祷（恢复全部 HP）", "hp_delta": 999, "gold_delta": 0},
			{"label": "供奉 50 金币（+2 HP）", "hp_delta": 2, "gold_delta": -50, "require_gold": 50},
			{"label": "走过去", "hp_delta": 0, "gold_delta": 0},
		],
	},
	{
		"id": "merchant_trade",
		"title": "💰 行商兜售",
		"description": "一名行商凑近你低声说：「想要快速致富吗？」",
		"options": [
			{"label": "用 1 HP 换 60 金币", "hp_delta": -1, "gold_delta": 60},
			{"label": "婉拒", "hp_delta": 0, "gold_delta": 0},
		],
	},
	{
		"id": "dora_fortune",
		"title": "🀄 风之牌的低语",
		"description": "桌上散落着几张被风吹乱的牌，其中一张闪着金光。",
		"options": [
			{"label": "拾起（+15 金币）", "hp_delta": 0, "gold_delta": 15},
			{"label": "无视", "hp_delta": 0, "gold_delta": 0},
		],
	},
]

func _ready() -> void:
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
		done_btn.custom_minimum_size = Vector2(0, 50)
		done_btn.pressed.connect(func(): emit_signal("done"))
		_options_box.add_child(done_btn)
		return
	var options: Array = _event_def.get("options", [])
	for i in range(options.size()):
		var opt: Dictionary = options[i]
		var btn := Button.new()
		btn.text = opt.get("label", "选项 %d" % (i + 1))
		btn.custom_minimum_size = Vector2(0, 50)
		btn.disabled = not can_apply(opt, _run_state)
		var captured_opt: Dictionary = opt
		btn.pressed.connect(func(): _on_option_chosen(captured_opt))
		_options_box.add_child(btn)

func _on_option_chosen(option: Dictionary) -> void:
	apply_option(option, _run_state)
	_resolved = true
	_refresh()
