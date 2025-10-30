extends Node2D

## 主游戏场景
## 管理游戏的主要逻辑和玩家交互

var game_controller: GameController
var game_state: GameState
var hand_display: HandDisplayManager
var animation: CardAnimation

## 调试模式
var debug_mode: bool = true

func _ready() -> void:
	print("🎮 主游戏场景已加载")

	# 检查用户是否已登录
	if has_node("/root/GameManager"):
		var user_data = GameManager.get_user_data()
		if user_data.is_empty():
			push_warning("⚠ 未检测到登录信息")
		else:
			print("👤 当前用户: ", GameManager.get_nickname())
			print("🆔 登录类型: ", GameManager.get_login_type())

	# 初始化游戏
	_initialize_game()

func _initialize_game() -> void:
	"""初始化游戏"""
	print("\n" + "======================================================")
	print("🎲 游戏初始化中...")
	print("======================================================\n")

	# 创建游戏控制器
	game_controller = GameController.new()
	game_controller._ready()
	add_child(game_controller)

	# 获取游戏状态和UI系统引用
	game_state = game_controller.game_state
	hand_display = game_controller.get_hand_display()
	animation = game_controller.get_animation()

	# 添加UI系统到场景树
	add_child(hand_display)
	add_child(animation)

	# 设置手牌显示位置和大小
	hand_display.position = Vector2(50, 300)
	hand_display.custom_minimum_size = Vector2(400, 150)

	# 连接游戏信号
	game_controller.game_initialized.connect(_on_game_initialized)
	game_controller.turn_started.connect(_on_turn_started)
	game_controller.card_drawn.connect(_on_card_drawn)
	game_controller.card_played.connect(_on_card_played)
	game_controller.win_detected.connect(_on_win_detected)
	game_controller.round_complete.connect(_on_round_complete)

	# 开始游戏
	game_controller.initialize_game()

	print("✅ 游戏初始化完成\n")

## 游戏初始化完成
func _on_game_initialized() -> void:
	print("✅ 游戏已初始化，等待玩家操作...")

## 回合开始
func _on_turn_started(player: String) -> void:
	if player == "player":
		print("\n🔵 轮到玩家了！")
		print("   操作: 摸牌或点击卡牌出牌")
		# 这里可以启用UI交互
		_show_player_controls()
	else:
		print("\n🔴 AI的回合")

## 卡牌被摸
func _on_card_drawn(player: String, card: CardData) -> void:
	if debug_mode:
		var player_name = "玩家" if player == "player" else "AI"
		print("   %s摸了: %s" % [player_name, card.get_display_name()])

## 卡牌被出
func _on_card_played(player: String, card: CardData) -> void:
	if debug_mode:
		var player_name = "玩家" if player == "player" else "AI"
		print("   %s出了: %s" % [player_name, card.get_display_name()])

## 胡牌检测
func _on_win_detected(winner: String, win_info: Dictionary) -> void:
	print("\n" + ("🏆" + "🏆" + "🏆" + "🏆" + "🏆" + "🏆" + "🏆" + "🏆" + "🏆" + "🏆" + "🏆" + "🏆" + "🏆" + "🏆" + "🏆" + "🏆" + "🏆" + "🏆" + "🏆" + "🏆"))
	var winner_name = "玩家" if winner == "player" else "AI"
	print("🏆 %s胡牌了！" % winner_name)
	print("   胜牌方式: %s" % win_info.get("win_type", "未知"))
	print(("🏆" + "🏆" + "🏆" + "🏆" + "🏆" + "🏆" + "🏆" + "🏆" + "🏆" + "🏆" + "🏆" + "🏆" + "🏆" + "🏆" + "🏆" + "🏆" + "🏆" + "🏆" + "🏆" + "🏆"))

## 回合完成
func _on_round_complete(winner: String) -> void:
	var winner_name = "玩家" if winner == "player" else "AI"
	print("\n第 %d 轮完成，胜者: %s" % [game_state.game_round - 1, winner_name])

## 显示玩家控制选项
func _show_player_controls() -> void:
	if debug_mode:
		print("\n📋 可用操作:")
		print("   [D] - 摸牌")
		print("   [点击卡牌] - 选择要出的牌")
		print("   [I] - 查看手牌信息")
		print("   [S] - 查看游戏状态")
		print("   [ESC] - 退出游戏")

## 处理调试输入
func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		return

	match event.keycode:
		KEY_D: # 摸牌
			if game_state.is_player_turn():
				game_controller.player_draw_card()

		KEY_I: # 查看手牌
			_print_player_hand()

		KEY_S: # 查看状态
			game_state.debug_state()

		KEY_ESCAPE: # 退出
			print("\n👋 返回登录界面")
			get_tree().change_scene_to_file("res://scenes/loading_screen.tscn")

## 显示玩家手牌
func _print_player_hand() -> void:
	var cards = game_state.player_hand.cards

	if cards.size() == 0:
		print("你没有手牌")
		return

	print("\n📋 你的手牌 (%d张):" % cards.size())
	print("──────────────────────────────────────────────────────")

	for i in range(cards.size()):
		var card = cards[i]
		print("[%d] %s" % [i, card.get_display_name()])

	print("──────────────────────────────────────────────────────")

	# 显示听牌提示
	if cards.size() == 13:
		var ting_cards = WinChecker.check_can_hear(game_state.player_hand)
		if ting_cards.size() > 0:
			print("\n💡 听牌提示:")
			for ting_card in ting_cards:
				print("   - %s" % ting_card.get_display_name())
		else:
			print("\n❌ 当前无法听牌")
