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
var _consumable_container: VBoxContainer = null

const HEAL_AMOUNT: int = 1

func _ready() -> void:
	RunUi.attach_background(self)
	RunUi.attach_panel_icon($VBox, "res://assets/run_icons/node_camp.png")
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
	_rebuild_consumables()

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

func _rebuild_consumables() -> void:
	if _consumable_container:
		_consumable_container.queue_free()
		_consumable_container = null
	if _run_state == null or _run_state.consumables.is_empty():
		return
	var vbox: VBoxContainer = $VBox
	if vbox == null:
		return
	_consumable_container = VBoxContainer.new()
	var sep := HSeparator.new()
	_consumable_container.add_child(sep)
	var header := Label.new()
	header.text = "— 道具 —"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 18)
	header.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	_consumable_container.add_child(header)
	for c in _run_state.consumables:
		if not (c is ConsumableItem):
			continue
		if not c.is_run():
			continue
		var btn := Button.new()
		btn.text = "%s — %s" % [c.display_name, c.description]
		btn.custom_minimum_size = Vector2(400, 40)
		var cid: StringName = c.id
		btn.pressed.connect(func():
			_run_state.use_run_consumable(cid)
			_refresh()
		)
		_consumable_container.add_child(btn)
	vbox.add_child(_consumable_container)
	vbox.move_child(_consumable_container, vbox.get_child_count() - 2)

func _on_leave_pressed() -> void:
	emit_signal("done")
