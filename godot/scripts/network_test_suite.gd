# 网络测试套件 - 测试所有网络模块功能
class_name NetworkTestSuite
extends Node

# 测试统计
var _total_tests: int = 0
var _passed_tests: int = 0
var _failed_tests: int = 0
var _test_results: Array = []

# 被测试的组件
var network_manager: NetworkManager
var network_client: NetworkClient
var room_manager: RoomManager
var player_matcher: PlayerMatcher
var lobby_manager: LobbyManager
var game_synchronizer: GameSynchronizer

# 信号
signal test_started(test_name: String)
signal test_completed(test_name: String, passed: bool)
signal all_tests_completed(passed: int, failed: int)

# ==================== 初始化 ====================

func _init() -> void:
	print("[NetworkTestSuite] 初始化测试套件")
	_setup_components()

func _setup_components() -> void:
	network_manager = NetworkManager.new()
	network_client = NetworkClient.new()
	room_manager = RoomManager.new()
	player_matcher = PlayerMatcher.new()
	lobby_manager = LobbyManager.new()
	game_synchronizer = GameSynchronizer.new()

	print("[NetworkTestSuite] 所有组件已初始化")

# ==================== 单元测试 ====================

func test_network_message() -> bool:
	"""测试网络消息类型和序列化"""
	print("\n【单元测试】网络消息")
	_total_tests += 1

	# 测试消息创建
	var msg = NetworkMessage.create_connect_message("player_001")
	if not msg:
		_record_failure("消息创建失败")
		return false

	# 测试消息序列化
	var json_str = msg.to_json()
	if json_str.is_empty():
		_record_failure("JSON序列化失败")
		return false

	# 测试消息解析
	var parsed_msg = NetworkMessage.parse_message(json_str)
	if not parsed_msg:
		_record_failure("消息解析失败")
		return false

	_record_success("网络消息")
	return true

func test_room_management() -> bool:
	"""测试房间管理功能"""
	print("\n【单元测试】房间管理")
	_total_tests += 1

	# 创建房间
	var room_id = room_manager.create_room("TestRoom", "player_001")
	if room_id.is_empty():
		_record_failure("房间创建失败")
		return false

	# 验证房间存在
	var room = room_manager.get_room(room_id)
	if not room:
		_record_failure("房间查询失败")
		return false

	# 加入房间
	var success = room_manager.join_room(room_id, "player_002", {"name": "Player2"})
	if not success:
		_record_failure("加入房间失败")
		return false

	# 验证房间人数
	if room.get_player_count() != 2:
		_record_failure("房间人数计算错误")
		return false

	_record_success("房间管理")
	return true

func test_player_matching() -> bool:
	"""测试玩家配对功能"""
	print("\n【单元测试】玩家配对")
	_total_tests += 1

	# 加入配对队列
	var success1 = player_matcher.join_queue("player_001", "Alice", PlayerMatcher.MatchMode.CASUAL)
	var success2 = player_matcher.join_queue("player_002", "Bob", PlayerMatcher.MatchMode.CASUAL)

	if not (success1 and success2):
		_record_failure("加入队列失败")
		return false

	# 验证队列大小
	var status = player_matcher.get_queue_status()
	if status["casual_queue"] != 2:
		_record_failure("队列计数错误")
		return false

	# 验证队列位置
	var pos = player_matcher.get_queue_position("player_001")
	if pos <= 0:
		_record_failure("队列位置查询失败")
		return false

	_record_success("玩家配对")
	return true

func test_game_state() -> bool:
	"""测试游戏状态管理"""
	print("\n【单元测试】游戏状态")
	_total_tests += 1

	var state = GameState.new()

	# 测试状态更新
	state.update_phase(GameState.GamePhase.PLAYING)
	if state.get_phase() != GameState.GamePhase.PLAYING:
		_record_failure("状态更新失败")
		return false

	# 测试版本递增
	state.update_scores({"player_001": 100})
	var v1 = state.get_version()
	state.update_scores({"player_001": 150})
	var v2 = state.get_version()

	if v2 <= v1:
		_record_failure("版本递增失败")
		return false

	# 测试历史记录
	var history = state.get_history()
	if history.size() < 2:
		_record_failure("历史记录失败")
		return false

	_record_success("游戏状态")
	return true

func test_operation_queue() -> bool:
	"""测试操作队列"""
	print("\n【单元测试】操作队列")
	_total_tests += 1

	var queue = OperationQueue.new()

	# 添加操作
	var op1 = queue.add_draw_card("player_001")
	var op2 = queue.add_play_card("player_001", {"suit": 0, "number": 5})

	if not (op1 and op2):
		_record_failure("操作添加失败")
		return false

	# 验证队列大小
	if queue.get_queue_size() != 2:
		_record_failure("队列大小错误")
		return false

	# 确认操作
	var confirmed = queue.confirm_operation(op1.sequence)
	if not confirmed:
		_record_failure("操作确认失败")
		return false

	# 执行操作
	var executed = queue.execute_next()
	if not executed:
		_record_failure("操作执行失败")
		return false

	_record_success("操作队列")
	return true

# ==================== 集成测试 ====================

func test_lobby_flow() -> bool:
	"""测试大厅完整流程"""
	print("\n【集成测试】大厅流程")
	_total_tests += 1

	# 玩家A创建房间
	var room_id = lobby_manager.create_room("GameRoom", "player_001")
	if room_id.is_empty():
		_record_failure("大厅创建房间失败")
		return false

	# 玩家B加入房间
	var success = lobby_manager.join_room(room_id, "player_002")
	if not success:
		_record_failure("大厅加入房间失败")
		return false

	# 启动游戏
	var game_started = lobby_manager.start_room_game(room_id)
	if not game_started:
		_record_failure("大厅启动游戏失败")
		return false

	_record_success("大厅流程")
	return true

func test_game_sync_flow() -> bool:
	"""测试游戏同步流程"""
	print("\n【集成测试】游戏同步流程")
	_total_tests += 1

	var sync = GameSynchronizer.new()

	# 模拟本地操作
	sync.local_play_card("player_001", {"suit": 0, "number": 1})

	# 验证状态更新
	var state = sync.game_state
	if state.get_phase() != GameState.GamePhase.PLAYING:
		_record_failure("游戏状态未更新")
		return false

	# 验证操作入队
	if sync.operation_queue.get_queue_size() == 0:
		_record_failure("操作未入队")
		return false

	_record_success("游戏同步流程")
	return true

# ==================== 压力测试 ====================

func test_concurrent_connections() -> bool:
	"""测试并发连接"""
	print("\n【压力测试】并发连接")
	_total_tests += 1

	var connection_count = 0

	# 模拟100个连接
	for i in range(100):
		var success = player_matcher.join_queue("player_%d" % i, "Player%d" % i)
		if success:
			connection_count += 1

	if connection_count < 100:
		_record_failure("并发连接失败: %d/100" % connection_count)
		return false

	_record_success("并发连接 (100个)")
	return true

func test_message_throughput() -> bool:
	"""测试消息吞吐量"""
	print("\n【压力测试】消息吞吐量")
	_total_tests += 1

	var start_time = Time.get_ticks_msec()
	var message_count = 0

	# 创建1000条消息
	for i in range(1000):
		var msg = NetworkMessage.create_play_card_message("player_001", "room_001", {
			"suit": i % 4,
			"number": (i % 9) + 1
		})
		if msg:
			message_count += 1

	var elapsed = Time.get_ticks_msec() - start_time

	if message_count != 1000:
		_record_failure("消息创建失败")
		return false

	print(" 创建1000条消息耗时: %dms" % elapsed)

	_record_success("消息吞吐量 (1000条, %dms)" % elapsed)
	return true

func test_memory_usage() -> bool:
	"""测试内存使用"""
	print("\n【压力测试】内存使用")
	_total_tests += 1

	var state = GameState.new()

	# 创建1000个状态快照
	for i in range(1000):
		state.update_scores({"player_001": i * 100})

	var history_size = state.get_history_size()

	# 由于限制为100条，应该只保留最后100条
	if history_size > 100:
		_record_failure("内存未被限制: %d条记录" % history_size)
		return false

	print(" 历史记录限制在: %d条" % history_size)

	_record_success("内存限制 (最多100条)")
	return true

# ==================== 记录和报告 ====================

func _record_success(test_name: String) -> void:
	_passed_tests += 1
	_test_results.append({
		"name": test_name,
		"passed": true,
		"time": Time.get_ticks_msec()
	})
	print(" ✅ 通过: %s" % test_name)

func _record_failure(reason: String) -> void:
	_failed_tests += 1
	_test_results.append({
		"name": reason,
		"passed": false,
		"time": Time.get_ticks_msec()
	})
	print(" ❌ 失败: %s" % reason)

# ==================== 运行测试 ====================

func run_all_tests() -> void:
	"""运行所有测试"""
	print("\n╔════════════════════════════════════════╗")
	print("║ 🧪 Phase 7 网络测试套件 ║")
	print("╚════════════════════════════════════════╝\n")

	# 单元测试
	print("\n【第1部分】单元测试")
	var separator_1 = ""
	for i in range(40):
		separator_1 += "─"
	print(separator_1)
	test_network_message()
	test_room_management()
	test_player_matching()
	test_game_state()
	test_operation_queue()

	# 集成测试
	print("\n【第2部分】集成测试")
	var separator_2 = ""
	for i in range(40):
		separator_2 += "─"
	print(separator_2)
	test_lobby_flow()
	test_game_sync_flow()

	# 压力测试
	print("\n【第3部分】压力测试")
	var separator_3 = ""
	for i in range(40):
		separator_3 += "─"
	print(separator_3)
	test_concurrent_connections()
	test_message_throughput()
	test_memory_usage()

	# 最终报告
	print_test_report()

func print_test_report() -> void:
	"""打印测试报告"""
	print("\n╔════════════════════════════════════════╗")
	print("║ 📊 测试报告 ║")
	print("╚════════════════════════════════════════╝\n")

	print("【测试统计】")
	print("总测试数: %d" % _total_tests)
	print("通过: %d ✅" % _passed_tests)
	print("失败: %d ❌" % _failed_tests)

	if _failed_tests == 0:
		var pass_rate = (float(_passed_tests) / float(_total_tests)) * 100
		print("\n【结果】 所有测试通过! (通过率: %.1f%%)" % pass_rate)
	else:
		print("\n【结果】 存在失败的测试")
		print("\n【失败详情】")
		for result in _test_results:
			if not result["passed"]:
				print(" - %s" % result["name"])

	print("\n════════════════════════════════════════\n")
