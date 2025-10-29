class_name LoadingScreen
extends CanvasLayer

@onready var background: TextureRect = $Background
var loading_progress: float = 0.0
var loading_complete: bool = false
var transition_time: float = 3.0  # 显示 3 秒后自动进入游戏
var elapsed_time: float = 0.0

func _ready() -> void:
	print("🎮 加载画面已显示")

	# 确保背景铺满整个屏幕
	if background:
		background.anchor_left = 0.0
		background.anchor_top = 0.0
		background.anchor_right = 1.0
		background.anchor_bottom = 1.0
		background.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		background.size_flags_vertical = Control.SIZE_EXPAND_FILL

		# 尝试加载图片
		var image_path = "res://assets/loading_screen.png"
		if ResourceLoader.exists(image_path):
			background.texture = load(image_path)
			print("✅ 加载画面图片已加载: ", image_path)
		else:
			print("⚠ 加载画面图片未找到: ", image_path)
			# 使用默认颜色代替（绿色背景）
			background.modulate = Color(0.1, 0.4, 0.1, 1.0)

func _process(delta: float) -> void:
	elapsed_time += delta

	# 3 秒后自动进入游戏
	if elapsed_time >= transition_time and not loading_complete:
		loading_complete = true
		_transition_to_game()

func _transition_to_game() -> void:
	"""过渡到主游戏场景"""
	print("🎮 加载完成，进入游戏...")

	# 淡出动画
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_property(self, "modulate:a", 0.0, 0.5)

	# 加载主场景
	await tween.finished
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _input(event: InputEvent) -> void:
	"""按任何键跳过加载画面"""
	if event is InputEventMouseButton or event is InputEventKey:
		if not loading_complete:
			loading_complete = true
			_transition_to_game()
