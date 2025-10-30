extends Control

var hand_display: Control

func _ready():
	print("=== 麻将游戏主场景启动 ===")

	# 设置背景
	var bg = ColorRect.new()
	bg.color = Color(0.1, 0.3, 0.2, 1.0)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	add_child(bg)
	move_child(bg, 0)

	# ✅ TextureExtractor 已经作为 AutoLoad 单例加载,不需要再实例化
	print("✅ 使用 AutoLoad TextureExtractor 单例")

	# ⏱️ 延迟初始化游戏 UI,确保纹理提取完成
	await get_tree().process_frame
	await get_tree().process_frame
	_initialize_game_ui()

func _initialize_game_ui():
	"""初始化游戏UI - 显示麻将牌"""
	print("初始化游戏UI...")

	# 创建标题
	var title = Label.new()
	title.text = "🎴 麻将游戏"
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_top = 0.0
	title.anchor_right = 1.0
	title.position.y = 20
	add_child(title)

	# 创建手牌显示区域
	var hand_container = Control.new()
	hand_container.anchor_left = 0.0
	hand_container.anchor_top = 0.5
	hand_container.anchor_right = 1.0
	hand_container.anchor_bottom = 1.0
	hand_container.offset_top = 50
	add_child(hand_container)

	# 创建示例手牌 - 13 张麻将牌
	print("生成示例手牌...")
	var card_data_list = _generate_sample_hand()

	# 显示手牌
	var cards_per_row = 13
	var card_spacing = 110 # 卡牌宽度 100 + 间距 10
	var start_x = 20
	var start_y = 100

	for i in range(card_data_list.size()):
		var card_data = card_data_list[i]

		# 创建卡牌 UI
		var card_ui = CardUI.new()
		card_ui.card_data = card_data
		card_ui.position.x = start_x + (i % cards_per_row) * card_spacing
		card_ui.position.y = start_y + int(i / float(cards_per_row)) * 180
		hand_container.add_child(card_ui)

		print("✅ 创建卡牌: %s%d" % [card_data.suit, card_data.number])

	# 创建游戏信息标签
	var info_label = Label.new()
	info_label.text = """
✅ 游戏加载成功！

观察手牌：麻将牌应该清晰锐利，每个牌面都能看清数字

🎮 控制：
  • 点击选择牌
  • D 键摸牌
  • ESC 返回登录

✨ 纹理优化已启用
  • 最近邻滤波：确保清晰
  • 高质量压缩：保持细节
  • 智能纹理提取：自动适配
"""
	info_label.add_theme_font_size_override("font_size", 14)
	info_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1.0))
	info_label.anchor_left = 0.02
	info_label.anchor_top = 0.02
	info_label.anchor_right = 0.35
	info_label.anchor_bottom = 0.4
	add_child(info_label)

	print("✅ 游戏UI初始化完成")

func _generate_sample_hand() -> Array:
	"""生成 13 张示例手牌"""
	var hand = []

	# 万牌：1-4（各1张）
	for i in range(1, 5):
		var card = CardData.new(CardData.Suit.WAN, i)
		hand.append(card)

	# 筒牌：1-4（各1张）
	for i in range(1, 5):
		var card = CardData.new(CardData.Suit.TONG, i)
		hand.append(card)

	# 条牌：1-4（各1张）
	for i in range(1, 5):
		var card = CardData.new(CardData.Suit.TIAO, i)
		hand.append(card)

	# 字牌：东南西北
	var zi_numbers = [1, 2, 3, 4] # 东、南、西、北
	for zi_num in zi_numbers:
		var card = CardData.new(CardData.Suit.ZI, zi_num)
		hand.append(card)

	return hand

func _input(event):
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			print("🔙 返回登录界面")
			get_tree().change_scene_to_file("res://scenes/wechat_login_final.tscn")
		elif event.keycode == KEY_D:
			print("📍 摸牌（演示）")
