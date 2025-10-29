extends Node2D

## 主游戏场景
## 管理游戏的主要逻辑和玩家交互

# Leaderboard system
var leaderboard_system: LeaderboardSystem
var rank_calculator: RankCalculator
var leaderboard_ui: LeaderboardUI

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
	print("🎲 游戏初始化中...")
	
	# TODO: 初始化游戏逻辑
	# - 加载玩家数据
	# - 设置游戏规则
	# - 初始化牌局
	
	print("✅ 游戏初始化完成")

func _input(event: InputEvent) -> void:
	"""处理输入事件"""
	# 按 ESC 返回登录界面（测试用）
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		print("🔙 返回登录界面")
		get_tree().change_scene_to_file("res://scenes/loading_screen.tscn")

func _init_leaderboard_system() -> void:
	"""Initialize and setup the leaderboard system"""
	leaderboard_system = LeaderboardSystem.new()
	add_child(leaderboard_system)
	
	rank_calculator = RankCalculator.new()
	add_child(rank_calculator)
	
	leaderboard_ui = LeaderboardUI.new()
	add_child(leaderboard_ui)
	
	leaderboard_ui.set_leaderboard_system(leaderboard_system, rank_calculator)
	
	# Connect leaderboard signals
	leaderboard_system.leaderboard_updated.connect(_on_leaderboard_updated)
	leaderboard_system.player_ranked.connect(_on_player_ranked)
	
	print("[Main] Leaderboard system initialized successfully")

func _on_leaderboard_updated() -> void:
	"""Handle leaderboard update events"""
	print("[Main] Leaderboard updated")
	# Emit game event if needed
	game_event.emit("leaderboard_updated", {})

func _on_player_ranked(player_id: String, rank: int) -> void:
	"""Handle player ranked event"""
	print("[Main] Player %s ranked at %d" % [player_id, rank])
	game_event.emit("player_ranked", {"player_id": player_id, "rank": rank})

func get_leaderboard_system() -> LeaderboardSystem:
	"""Get the leaderboard system instance"""
	return leaderboard_system

func get_rank_calculator() -> RankCalculator:
	"""Get the rank calculator instance"""
	return rank_calculator

func get_leaderboard_ui() -> LeaderboardUI:
	"""Get the leaderboard UI instance"""
	return leaderboard_ui
