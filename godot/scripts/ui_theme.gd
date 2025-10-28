class_name UITheme
extends Node

# 颜色方案
const COLORS = {
	"background": Color(0.15, 0.15, 0.15, 1.0),
	"card_panel": Color(0.2, 0.2, 0.2, 1.0),
	"card_text": Color.WHITE,
	"card_selected": Color.YELLOW,
	"button_normal": Color(0.3, 0.3, 0.3, 1.0),
	"button_hover": Color(0.4, 0.4, 0.4, 1.0),
	"button_pressed": Color(0.2, 0.2, 0.2, 1.0),
	"text": Color.WHITE,
	"accent": Color(0.2, 0.8, 1.0, 1.0),
	"success": Color(0.2, 1.0, 0.2, 1.0),
	"warning": Color(1.0, 0.8, 0.2, 1.0),
	"error": Color(1.0, 0.2, 0.2, 1.0),
}

# 字体大小
const FONT_SIZES = {
	"large": 32,
	"normal": 16,
	"small": 12,
	"title": 24,
}

# 间距
const SPACING = {
	"small": 5,
	"normal": 10,
	"large": 20,
	"xlarge": 40,
}

func create_theme() -> Theme:
	"""创建自定义主题"""
	var theme = Theme.new()
	
	# 设置按钮样式
	var button_style = StyleBoxFlat.new()
	button_style.bg_color = COLORS.button_normal
	button_style.set_corner_radius_all(5)
	theme.set_stylebox("normal", "Button", button_style)
	
	# 设置按钮字体颜色
	theme.set_color("font_color", "Button", COLORS.text)
	theme.set_color("font_hover_color", "Button", COLORS.accent)
	theme.set_font_size("font_size", "Button", FONT_SIZES.normal)
	
	# 设置标签样式
	theme.set_color("font_color", "Label", COLORS.text)
	theme.set_font_size("font_size", "Label", FONT_SIZES.normal)
	
	return theme

func apply_card_style(card_node: Node, is_selected: bool = false) -> void:
	"""应用卡牌样式"""
	if is_selected:
		card_node.modulate = COLORS.card_selected
		card_node.scale = Vector2(1.15, 1.15)
	else:
		card_node.modulate = COLORS.card_text
		card_node.scale = Vector2(1.0, 1.0)

func apply_button_style(button: Button) -> void:
	"""应用按钮样式"""
	var style = StyleBoxFlat.new()
	style.bg_color = COLORS.button_normal
	style.set_corner_radius_all(5)
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_color_override("font_color", COLORS.text)

func create_panel_background(color: Color = COLORS.card_panel) -> ColorRect:
	"""创建面板背景"""
	var panel = ColorRect.new()
	panel.color = color
	return panel

func show_notification(message: String, type: String = "info") -> void:
	"""显示通知消息"""
	var color = COLORS.accent
	match type:
		"success":
			color = COLORS.success
		"warning":
			color = COLORS.warning
		"error":
			color = COLORS.error
	
	print("\n[" + type.to_upper() + "] ", message)

func animate_button_press(button: Button) -> void:
	"""按钮按下动画"""
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_ELASTIC)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", Vector2(0.95, 0.95), 0.1)
	tween.tween_property(button, "scale", Vector2(1.0, 1.0), 0.1)
