extends Control

@onready var title_label = $TitleContainer/TitleLabel
@onready var glow1 = $TitleContainer/GlowLabel1
@onready var glow2 = $TitleContainer/GlowLabel2

var time_passed = 0.0
var glow_speed = 2.0

func _ready():
	# 启动发光动画
	_start_glow_animation()

func _process(delta):
	time_passed += delta
	
	# 动态发光效果
	var glow_intensity = (sin(time_passed * glow_speed) + 1.0) / 2.0
	
	if glow1:
		glow1.modulate.a = 0.2 + glow_intensity * 0.3
		glow1.scale = Vector2(1.0 + glow_intensity * 0.02, 1.0 + glow_intensity * 0.02)
	
	if glow2:
		glow2.modulate.a = 0.1 + glow_intensity * 0.2
		glow2.scale = Vector2(1.0 + glow_intensity * 0.03, 1.0 + glow_intensity * 0.03)

func _start_glow_animation():
	# 创建呼吸光效动画
	if title_label:
		var tween = create_tween()
		tween.set_loops()
		tween.set_trans(Tween.TRANS_SINE)
		tween.set_ease(Tween.EASE_IN_OUT)
		
		# 主文字轻微缩放
		tween.tween_property(title_label, "scale", Vector2(1.05, 1.05), 1.5)
		tween.tween_property(title_label, "scale", Vector2(1.0, 1.0), 1.5)
