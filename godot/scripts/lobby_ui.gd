class_name LobbyUI
extends ScreenBase

# 游戏大厅UI
# 房间列表和房间管理界面

# 信号
signal room_selected(room_id: String)
signal create_room_pressed
signal logout_pressed

# UI组件
var title_label: Label
var user_info_label: Label
var room_list_container: VBoxContainer
var scroll_container: ScrollContainer
var create_room_button: Button
var logout_button: Button
var stats_button: Button
var status_label: Label

# 数据
var current_user_id: String = ""
var current_username: String = ""
var game_server: GameServer
var rooms: Array = []

func _ready() -> void:
	"""初始化大厅界面"""
	super()

	# 创建标题
	title_label = Label.new()
	title_label.text = "🀄 游戏大厅"
	title_label.add_theme_font_size_override("font_size", 48)
	title_label.anchor_left = 0.5
	title_label.anchor_top = 0.03
	title_label.offset_left = -100
	add_child(title_label)

	# 创建用户信息标签
	user_info_label = Label.new()
	user_info_label.text = "欢迎玩家"
	user_info_label.add_theme_font_size_override("font_size", 14)
	user_info_label.anchor_left = 0.02
	user_info_label.anchor_top = 0.05
	add_child(user_info_label)

	# 创建房间列表容器
	scroll_container = ScrollContainer.new()
	scroll_container.anchor_left = 0.1
	scroll_container.anchor_top = 0.12
	scroll_container.anchor_right = 0.9
	scroll_container.anchor_bottom = 0.75
	add_child(scroll_container)

	room_list_container = VBoxContainer.new()
	room_list_container.anchor_left = 0.0
	room_list_container.anchor_right = 1.0
	room_list_container.custom_minimum_size = Vector2(400, 100)
	scroll_container.add_child(room_list_container)

	# 创建状态标签
	status_label = Label.new()
	status_label.text = "正在加载房间列表..."
	status_label.anchor_left = 0.5
	status_label.anchor_top = 0.35
	status_label.offset_left = -100
	add_child(status_label)

	# 创建创建房间按钮
	create_room_button = Button.new()
	create_room_button.text = "+ 创建房间"
	create_room_button.custom_minimum_size = Vector2(150, 50)
	create_room_button.anchor_left = 0.1
	create_room_button.anchor_top = 0.8
	create_room_button.pressed.connect(_on_create_room_pressed)
	add_child(create_room_button)

	# 创建查看统计按钮
	stats_button = Button.new()
	stats_button.text = "📊 统计"
	stats_button.custom_minimum_size = Vector2(120, 50)
	stats_button.anchor_left = 0.4
	stats_button.anchor_top = 0.8
	add_child(stats_button)

	# 创建退出登录按钮
	logout_button = Button.new()
	logout_button.text = "退出登录"
	logout_button.custom_minimum_size = Vector2(120, 50)
	logout_button.anchor_left = 0.75
	logout_button.anchor_top = 0.8
	logout_button.pressed.connect(_on_logout_pressed)
	add_child(logout_button)

	# 初始化游戏服务器
	game_server = GameServer.new()

	print("LobbyUI: 已初始化")

func on_enter() -> void:
	"""进入大厅时的回调"""
	print("LobbyUI: 进入游戏大厅")
	refresh_room_list()

func on_exit() -> void:
	"""离开大厅时的回调"""
	print("LobbyUI: 离开游戏大厅")

func set_user_info(user_id: String, username: String) -> void:
	"""设置用户信息"""
	current_user_id = user_id
	current_username = username
	user_info_label.text = "玩家: %s" % username
	print("LobbyUI: 用户已登录 - %s" % username)

func refresh_room_list() -> void:
	"""刷新房间列表"""
	print("LobbyUI: 刷新房间列表")

	# 清空现有房间卡片
	for child in room_list_container.get_children():
		child.queue_free()

	rooms.clear()

	# 模拟生成一些房间
	_generate_sample_rooms()

	if rooms.is_empty():
		status_label.text = "暂无可用房间，请创建一个"
		status_label.visible = true
	else:
		status_label.visible = false

		# 显示所有房间
		for room in rooms:
			var card = _create_room_card(room)
			room_list_container.add_child(card)

func _generate_sample_rooms() -> void:
	"""生成示例房间（模拟）"""
	# 房间1
	var room1 = {
		"id": "room_001",
		"name": "新手房间",
		"players": 2,
		"max_players": 4,
		"level": "简单",
		"creator": "admin"
	}
	rooms.append(room1)

	# 房间2
	var room2 = {
		"id": "room_002",
		"name": "高手房间",
		"players": 3,
		"max_players": 4,
		"level": "困难",
		"creator": "master"
	}
	rooms.append(room2)

	# 房间3
	var room3 = {
		"id": "room_003",
		"name": "竞技房间",
		"players": 1,
		"max_players": 4,
		"level": "专家",
		"creator": "expert"
	}
	rooms.append(room3)

func _create_room_card(room: Dictionary) -> PanelContainer:
	"""创建房间卡片"""
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(800, 80)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 20)
	card.add_child(hbox)

	# 房间名称
	var name_label = Label.new()
	name_label.text = "[%s] %s" % [room.level, room.name]
	name_label.custom_minimum_size = Vector2(200, 0)
	hbox.add_child(name_label)

	# 玩家数量
	var players_label = Label.new()
	players_label.text = "玩家: %d/%d" % [room.players, room.max_players]
	players_label.custom_minimum_size = Vector2(100, 0)
	hbox.add_child(players_label)

	# 房主
	var creator_label = Label.new()
	creator_label.text = "房主: %s" % room.creator
	creator_label.custom_minimum_size = Vector2(100, 0)
	hbox.add_child(creator_label)

	# 加入按钮
	var join_button = Button.new()
	join_button.text = "加入"
	join_button.custom_minimum_size = Vector2(80, 40)

	# 保存房间ID到按钮
	var room_id = room.id
	join_button.pressed.connect(func(): _on_room_selected(room_id))
	hbox.add_child(join_button)

	return card

func _on_room_selected(room_id: String) -> void:
	"""房间被选中"""
	print("LobbyUI: 选择房间 - %s" % room_id)
	room_selected.emit(room_id)

func _on_create_room_pressed() -> void:
	"""创建房间按钮被按下"""
	print("LobbyUI: 创建房间")
	create_room_pressed.emit()

func _on_logout_pressed() -> void:
	"""退出登录按钮被按下"""
	print("LobbyUI: 退出登录")
	logout_pressed.emit()

func show_room_count() -> void:
	"""显示房间数量"""
	var count = rooms.size()
	status_label.text = "当前%d个房间" % count
	print("LobbyUI: 房间数量 - %d" % count)
