# 大厅UI - 显示房间列表和配对界面
class_name LobbyUI
extends Control

var lobby_manager: LobbyManager
var selected_room_id: String = ""
var current_player_id: String = ""

# UI组件（示例）
@onready var room_list_container = Label.new()
@onready var player_stats_label = Label.new()
@onready var queue_status_label = Label.new()
@onready var match_timer_label = Label.new()

# 状态
var match_wait_time: float = 0.0
var is_in_queue: bool = false
var in_game: bool = false

# 信号
signal create_room_requested(room_name: String)
signal join_room_requested(room_id: String)
signal start_matchmaking_requested(mode: int)
signal game_started(room_id: String, players: Array)

func _ready() -> void:
	if not lobby_manager:
		lobby_manager = LobbyManager.new()

	# 初始化UI
	_setup_ui()

	# 连接信号
	lobby_manager.room_list_updated.connect(_on_room_list_updated)
	lobby_manager.match_status_changed.connect(_on_match_status_changed)
	lobby_manager.player_info_updated.connect(_on_player_info_updated)

func _process(delta: float) -> void:
	if is_in_queue:
		match_wait_time += delta
		_update_queue_display()

func _setup_ui() -> void:
	# 创建UI组件
	room_list_container.text = "房间列表\n"
	add_child(room_list_container)

	player_stats_label.text = "玩家信息"
	add_child(player_stats_label)

	queue_status_label.text = "配对状态: 未配对"
	add_child(queue_status_label)

	match_timer_label.text = "等待时间: 0s"
	add_child(match_timer_label)

	print("[LobbyUI] UI已初始化")

# ==================== 房间操作 ====================

func create_room(room_name: String, max_players: int = 4) -> void:
	var room_id = lobby_manager.create_room(room_name, current_player_id, max_players)
	print("[LobbyUI] 房间已创建: %s" % room_id)

	# 更新UI并开始游戏准备
	_refresh_room_list()

func join_room(room_id: String) -> void:
	if lobby_manager.join_room(room_id, current_player_id):
		selected_room_id = room_id
		print("[LobbyUI] 已加入房间: %s" % room_id)
		_refresh_room_list()
	else:
		print("[LobbyUI] 无法加入房间")

func leave_room() -> void:
	if lobby_manager.leave_room(current_player_id):
		selected_room_id = ""
		print("[LobbyUI] 已离开房间")
		_refresh_room_list()

func start_game() -> void:
	if selected_room_id == "":
		print("[LobbyUI] 未选择房间")
		return

	if lobby_manager.start_room_game(selected_room_id):
		print("[LobbyUI] 游戏已开始")
		in_game = true
		var room = lobby_manager.room_manager.get_room(selected_room_id)
		if room:
			game_started.emit(selected_room_id, room.players.keys())
	else:
		print("[LobbyUI] 无法启动游戏")

# ==================== 配对操作 ====================

func start_matchmaking(mode: int = PlayerMatcher.MatchMode.CASUAL) -> void:
	if lobby_manager.start_matchmaking(current_player_id, "Player_%s" % current_player_id, mode):
		is_in_queue = true
		match_wait_time = 0.0
		print("[LobbyUI] 已加入配对队列")
		_update_queue_display()
	else:
		print("[LobbyUI] 无法加入配对队列")

func cancel_matchmaking() -> void:
	if lobby_manager.cancel_matchmaking(current_player_id):
		is_in_queue = false
		match_wait_time = 0.0
		print("[LobbyUI] 已取消配对")
		_update_queue_display()

# ==================== UI更新 ====================

func _refresh_room_list() -> void:
	var joinable_rooms = lobby_manager.get_joinable_rooms()
	var text = "【可加入的房间】\n"

	if joinable_rooms.is_empty():
		text += "没有可加入的房间\n"
	else:
		for room_info in joinable_rooms:
			text += "房间: %s (%d/%d)\n" % [
				room_info["room_name"],
				room_info["player_count"],
				room_info["max_players"]
			]

	room_list_container.text = text

func _update_queue_display() -> void:
	if is_in_queue:
		var position = lobby_manager.get_queue_position(current_player_id)
		var status_text = "配对中... (第%d个)" % position
		queue_status_label.text = status_text
		match_timer_label.text = "等待时间: %.0fs" % match_wait_time
	else:
		queue_status_label.text = "配对状态: 未配对"
		match_timer_label.text = "等待时间: 0s"

func _update_player_stats() -> void:
	var info = lobby_manager.get_player_info(current_player_id)
	if info.is_empty():
		return

	var stats_text = "玩家: %s\n" % info.get("player_name", "Unknown")
	stats_text += "等级: %s\n" % _get_rank_name(info.get("rank", 0))
	stats_text += "游戏数: %d\n" % info.get("total_games", 0)
	stats_text += "胜场: %d\n" % info.get("wins", 0)
	stats_text += "胜率: %.1f%%\n" % (info.get("skill_level", 0.0) * 100)

	player_stats_label.text = stats_text

# ==================== 信号处理 ====================

func _on_room_list_updated(rooms: Array) -> void:
	_refresh_room_list()

func _on_match_status_changed(status: String) -> void:
	print("[LobbyUI] 配对状态改变: %s" % status)

	if status == "matched":
		is_in_queue = false
		match_wait_time = 0.0
		print("[LobbyUI] 配对成功！")
	elif status == "queued":
		is_in_queue = true
		match_wait_time = 0.0

func _on_player_info_updated(player_id: String) -> void:
	if player_id == current_player_id:
		_update_player_stats()

# ==================== 工具函数 ====================

func _get_rank_name(rank: int) -> String:
	match rank:
		PlayerMatcher.PlayerRank.BRONZE:
			return "青铜"
		PlayerMatcher.PlayerRank.SILVER:
			return "白银"
		PlayerMatcher.PlayerRank.GOLD:
			return "黄金"
		PlayerMatcher.PlayerRank.PLATINUM:
			return "铂金"
		PlayerMatcher.PlayerRank.DIAMOND:
			return "钻石"
		PlayerMatcher.PlayerRank.MASTER:
			return "大师"
		_:
			return "未知"

# ==================== 测试函数 ====================

func test_lobby_flow() -> void:
	print("\n╔════════════════════════════════════════╗")
	print("║ 🧪 大厅测试流程 ║")
	print("╚════════════════════════════════════════╝\n")

	# 设置测试玩家
	current_player_id = "player_001"

	# 测试1: 创建房间
	print("【测试1】创建房间")
	create_room("TestRoom1", 4)
	await get_tree().create_timer(0.5).timeout

	# 测试2: 显示房间列表
	print("\n【测试2】房间列表")
	_refresh_room_list()
	print(room_list_container.text)

	# 测试3: 配对功能
	print("\n【测试3】配对功能")
	leave_room()
	start_matchmaking()
	await get_tree().create_timer(2.0).timeout
	_update_queue_display()
	print(queue_status_label.text)

	# 测试4: 取消配对
	print("\n【测试4】取消配对")
	cancel_matchmaking()
	_update_queue_display()

	# 显示统计
	lobby_manager.print_lobby_status()

	print("\n╚════════════════════════════════════════╝\n")

# 设置玩家ID
func set_player_id(player_id: String) -> void:
	current_player_id = player_id
	lobby_manager.update_player_info(player_id, {
		"player_id": player_id,
		"player_name": "Player_%s" % player_id
	})
	_update_player_stats()
