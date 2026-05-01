class_name StarterPackPicker extends Control

# 麻将王 — 里程碑 4 第 3 步：起始包 3 选 1 UI（plan-4 D7）
#
# 3 张卡片：火力 / 速胡 / 控场。v1 仅"控场型" Button 可点（available=true），
# 其余 2 张 disabled 灰显，按钮文字含"（M6 实装）"提示。
# 玩家点击可选卡片 → emit signal("pack_chosen", pack_id)。

signal pack_chosen(pack_id: StringName)

@onready var _hbox: HBoxContainer = $VBox/HBox

var _packs: Array = []  # Array[Dictionary]，从 StarterPacks.all() 拿

func _ready() -> void:
	_packs = StarterPacks.all()
	_rebuild()

# ---- helpers (static) ----

static func format_card_text(pack: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append(pack.display_name)
	lines.append("")
	if not pack.get("available", false):
		lines.append("（M6 实装）")
		lines.append("")
	lines.append(pack.description)
	return "\n".join(lines)

# ---- internal ----

func _rebuild() -> void:
	if _hbox == null:
		return
	for child in _hbox.get_children():
		child.queue_free()
	for pack in _packs:
		var btn := Button.new()
		btn.text = format_card_text(pack)
		btn.custom_minimum_size = Vector2(220, 280)
		btn.disabled = not pack.get("available", false)
		var pack_id_capture: StringName = pack.id
		btn.pressed.connect(func(): emit_signal("pack_chosen", pack_id_capture))
		_hbox.add_child(btn)
