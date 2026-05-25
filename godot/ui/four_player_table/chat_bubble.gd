class_name ChatBubble extends Control

signal phrase_chosen(text: String)

var _buttons: Array[Button] = []

const PRESETS: Array = [
	"必胜！绝对不会输！",
	"冷静分析，读懂你的牌",
	"嘿嘿，中计了吧",
	"燃烧吧！立直一发！",
	"我感应到了……奇迹之牌",
	"来吧，勝負！",
]

func _ready() -> void:
	visible = false
	_build_ui()

func _build_ui() -> void:
	var panel := PanelContainer.new()
	var vbox := VBoxContainer.new()
	panel.add_child(vbox)
	add_child(panel)
	for i in range(PRESETS.size()):
		var btn := Button.new()
		btn.text = PRESETS[i]
		btn.add_theme_font_size_override("font_size", 12)
		btn.pressed.connect(_on_preset.bind(i))
		vbox.add_child(btn)
		_buttons.append(btn)

func show_presets() -> void:
	visible = true

func hide_presets() -> void:
	visible = false

func _on_preset(index: int) -> void:
	if index >= 0 and index < PRESETS.size():
		phrase_chosen.emit(PRESETS[index])
		hide_presets()
