extends Control

@onready var title_label: Label = $TitleLabel
var time_passed: float = 0.0

func _ready():
	# 设置标签样式
	title_label.add_theme_font_size_override("font_size", 72)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	
	# 启动动画
	_start_glow_animation()

func _process(delta: float):
	time_passed += delta
	
	# 金色渐变闪烁效果
	var pulse = sin(time_passed * 2.0) * 0.3 + 0.7
	var gold_color = Color(1.0, 0.8 + pulse * 0.2, 0.2 + pulse * 0.3, 1.0)
	title_label.add_theme_color_override("font_color", gold_color)
	
	# 发光效果脉冲
	var glow_intensity = sin(time_passed * 1.5) * 0.5 + 0.5
	var outline_color = Color(1.0, 0.6, 0.0, 0.8 + glow_intensity * 0.2)
	title_label.add_theme_color_override("font_outline_color", outline_color)

func _start_glow_animation():
	# 创建缩放动画
	var tween = create_tween()
	tween.set_loops()
	tween.tween_property(title_label, "scale", Vector2(1.05, 1.05), 1.5)
	tween.tween_property(title_label, "scale", Vector2(1.0, 1.0), 1.5)
