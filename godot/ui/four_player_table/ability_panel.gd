class_name AbilityPanel extends Control

# 麻将王 — 里程碑 3 第 2 步：角色能力面板（spec §10 + §14：5 槽默认）
#
# v1（第 2 步）：5 个空 Slot 占位容器。M3 内不放真实 ability，留接口。
# 后续步骤可填 ability 数据；M7 会接入 AIProfile.

const SLOT_COUNT: int = 5
const SLOT_HEIGHT: float = 80.0

var _slots: Array[Control] = []  # 5 个空 Slot 容器

func _ready() -> void:
	# 程序化生成 5 个 Slot；让 .tscn 不必硬编码 5 个子节点。
	var vbox: VBoxContainer = $VBox
	if vbox == null:
		return
	for i in range(SLOT_COUNT):
		var slot := Control.new()
		slot.name = "Slot%d" % i
		slot.custom_minimum_size = Vector2(180, SLOT_HEIGHT)
		var bg := ColorRect.new()
		bg.color = Color(0.18, 0.18, 0.22, 0.8)
		bg.anchor_right = 1.0
		bg.anchor_bottom = 1.0
		slot.add_child(bg)
		var label := Label.new()
		label.text = "(空槽 %d)" % (i + 1)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.anchor_right = 1.0
		label.anchor_bottom = 1.0
		slot.add_child(label)
		vbox.add_child(slot)
		_slots.append(slot)

# 后续步骤接入 ability 时调：把第 i 槽设为某个 ability 的视觉
func set_slot_ability(i: int, ability_label: String) -> void:
	if i < 0 or i >= _slots.size():
		return
	var lbl: Label = _slots[i].get_child(1)
	lbl.text = ability_label

func slot_count() -> int:
	return _slots.size()
