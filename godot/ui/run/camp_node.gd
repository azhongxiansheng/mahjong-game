class_name CampNode extends Control

# US-005：营地节点真实 UI。替代 PlaceholderNode for NodeKind.CAMP。
#
# 玩家进营地可选：
#   1. 恢复 1 HP（hp < max_hp 才可选；点完按钮 disabled）
#   2. 离开营地（任何时候）
# 触发 done signal 让 RunFlow 调 RunState.complete_node(NodeResult.from_placeholder())。

signal done

@onready var _title: Label = $VBox/Title
@onready var _description: Label = $VBox/Description
@onready var _hp_label: Label = $VBox/HpLabel
@onready var _heal_btn: Button = $VBox/HealBtn
@onready var _leave_btn: Button = $VBox/LeaveBtn

var _run_state: RunState = null
var _heal_used: bool = false

const HEAL_AMOUNT: int = 1

func _ready() -> void:
	if _heal_btn:
		_heal_btn.pressed.connect(_on_heal_pressed)
	if _leave_btn:
		_leave_btn.pressed.connect(_on_leave_pressed)
	_refresh()

# ---- public setters ----

func bind_run_state(rs: RunState) -> void:
	_run_state = rs
	if is_inside_tree():
		_refresh()

# ---- internal ----

func _refresh() -> void:
	if _hp_label and _run_state:
		_hp_label.text = "HP: %d / %d" % [_run_state.hp, _run_state.max_hp]
	if _heal_btn:
		var can_heal: bool = _run_state != null and not _heal_used and _run_state.hp < _run_state.max_hp
		_heal_btn.disabled = not can_heal
		if _run_state == null:
			_heal_btn.text = "恢复 %d HP" % HEAL_AMOUNT
		elif _heal_used:
			_heal_btn.text = "已恢复 %d HP" % HEAL_AMOUNT
		elif _run_state.hp >= _run_state.max_hp:
			_heal_btn.text = "HP 已满"
		else:
			_heal_btn.text = "恢复 %d HP" % HEAL_AMOUNT

# 把恢复 HP 应用到 run_state。返回实际恢复量（受 max_hp 上限）。
func apply_heal() -> int:
	if _run_state == null or _heal_used:
		return 0
	if _run_state.hp >= _run_state.max_hp:
		return 0
	var before: int = _run_state.hp
	_run_state.hp = min(_run_state.hp + HEAL_AMOUNT, _run_state.max_hp)
	_heal_used = true
	return _run_state.hp - before

func _on_heal_pressed() -> void:
	apply_heal()
	_refresh()

func _on_leave_pressed() -> void:
	emit_signal("done")
