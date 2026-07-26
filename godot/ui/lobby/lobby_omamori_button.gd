extends Button

# 单侧御守功能按钮：AtlasTexture 裁切素材，根节点继续承载真实 Button 语义。

const ICON_SHEET := preload("res://assets/ui/lobby_stage/side_omamori_icons_transparent.png")
const ICON_REGIONS := [
	Rect2(48, 34, 380, 360),
	Rect2(450, 34, 370, 360),
	Rect2(830, 34, 390, 360),
	Rect2(42, 420, 400, 380),
	Rect2(442, 420, 390, 380),
	Rect2(820, 420, 410, 380),
]

@export_range(0, 5) var icon_index: int = 0
@export var action_text: String = "功能"


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	text = action_text
	tooltip_text = action_text
	var atlas := AtlasTexture.new()
	atlas.atlas = ICON_SHEET
	atlas.region = ICON_REGIONS[icon_index]
	$Icon.texture = atlas
	$Caption.text = action_text
	for child in find_children("*", "Control", true, false):
		(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := StyleBoxFlat.new()
		if state == "normal":
			style.bg_color = Color(0.05, 0.035, 0.03, 0.42)
			style.border_color = Color(0.76, 0.12, 0.08, 0.3)
			style.set_border_width_all(1)
		elif state == "hover" or state == "focus":
			style.bg_color = Color(0.05, 0.035, 0.06, 0.78)
			style.border_color = Color(0.55, 0.2, 0.93, 0.92)
			style.set_border_width_all(2)
		elif state == "pressed":
			style.bg_color = Color(0.08, 0.025, 0.02, 0.88)
			style.border_color = Color(0.84, 0.15, 0.09, 0.98)
			style.set_border_width_all(2)
		else:
			style.bg_color = Color(0.04, 0.035, 0.035, 0.34)
			style.border_color = Color(0.4, 0.38, 0.36, 0.45)
			style.set_border_width_all(1)
		style.set_corner_radius_all(8)
		add_theme_stylebox_override(state, style)
	for color_name in ["font_color", "font_hover_color", "font_pressed_color",
			"font_focus_color", "font_disabled_color"]:
		add_theme_color_override(color_name, Color.TRANSPARENT)
