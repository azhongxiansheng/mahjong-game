# 游戏同步器 - 协调状态和操作同步
class_name GameSynchronizer
extends Node

var game_state: GameState
var operation_queue: OperationQueue
var network_client: NetworkClient

# 同步配置
var _sync_interval: float = 0.5       # 同步间隔（秒）
var _time_since_last_sync: float = 0  # 距离上次同步的时间
var _last_synced_version: int = -1    # 上次同步的版本号

# 同步统计
var _total_syncs: int = 0
var _total_operations: int = 0
var _sync_latency: int = 0            # 上次同步延迟（毫秒）

# 信号
signal sync_started()
signal sync_completed(operation_count: int)
signal sync_failed(reason: String)
signal state_desync_detected()

func _ready() -> void:
	game_state = GameState.new()
	operation_queue = OperationQueue.new()

	print("[GameSynchronizer] 初始化完成")

func _process(delta: float) -> void:
	_time_since_last_sync += delta

	if _time_since_last_sync >= _sync_interval:
		_perform_sync()
		_time_since_last_sync = 0

# ==================== 本地操作 ====================

func local_draw_card(player_id: String) -> void:
	operation_queue.add_draw_card(player_id)
	game_state.set_current_player(player_id)
	game_state.update_phase(GameState.GamePhase.DRAWING)

func local_play_card(player_id: String, card_data: Dictionary) -> void:
	var op = operation_queue.add_play_card(player_id, card_data)
	game_state.add_to_discard_pile(card_data)
	game_state.update_phase(GameState.GamePhase.PLAYING)

func local_declare_win(player_id: String, win_data: Dictionary) -> void:
	operation_queue.add_win(player_id, win_data)
	game_state.update_phase(GameState.GamePhase.WIN)
	game_state.update_score(player_id, win_data.get("score", 0))

# ==================== 远程操作处理 ====================

func handle_remote_operation(op_data: Dictionary) -> void:
	var op_type = op_data.get("type", OperationQueue.OperationType.DRAW_CARD)
	var player_id = op_data.get("player_id", "")
	var data = op_data.get("data", {})

	# 应用到本地状态
	match op_type:
		OperationQueue.OperationType.DRAW_CARD:
			game_state.set_current_player(player_id)
			game_state.update_phase(GameState.GamePhase.DRAWING)

		OperationQueue.OperationType.PLAY_CARD:
			if "card" in data:
				game_state.add_to_discard_pile(data["card"])
				game_state.update_phase(GameState.GamePhase.PLAYING)

		OperationQueue.OperationType.DECLARE_WIN:
			if "win" in data:
				game_state.update_phase(GameState.GamePhase.WIN)
				game_state.update_score(player_id, data["win"].get("score", 0))

	# 添加到本地队列
	operation_queue.apply_remote_operations([op_data])

func handle_remote_state(remote_state: Dictionary) -> void:
	if not game_state.apply_remote_state(remote_state):
		print("[GameSynchronizer] 无法应用远程状态")
		state_desync_detected.emit()

# ==================== 同步流程 ====================

func _perform_sync() -> void:
	if not network_client or not network_client.check_connected():
		return

	sync_started.emit()

	var start_time = Time.get_ticks_msec()

	# 获取差异数据
	var state_diff = game_state.get_diff_since(_last_synced_version)
	var pending_ops = operation_queue.get_pending_operations()

	if state_diff.is_empty() and pending_ops.is_empty():
		return  # 无需同步

	# 准备同步消息
	var sync_data = {
		"state": state_diff,
		"operations": _convert_operations_to_dicts(pending_ops),
		"version": game_state.get_version()
	}

	# 发送同步消息
	if network_client.send_game_sync(sync_data):
		_last_synced_version = game_state.get_version()
		_total_syncs += 1
		_sync_latency = Time.get_ticks_msec() - start_time
		_total_operations += pending_ops.size()

		print("[GameSynchronizer] 同步完成 - 操作: %d, 延迟: %dms" % [
			pending_ops.size(),
			_sync_latency
		])

		sync_completed.emit(pending_ops.size())
	else:
		sync_failed.emit("发送失败")

# ==================== 冲突解决 ====================

func detect_conflict(remote_version: int) -> bool:
	var local_version = game_state.get_version()

	if remote_version < local_version:
		print("[GameSynchronizer] 检测到冲突: 远程版本 %d < 本地版本 %d" % [
			remote_version,
			local_version
		])
		return true

	return false

func resolve_conflict(local_state: Dictionary, remote_state: Dictionary) -> Dictionary:
	# 简单策略：远程版本更新则使用远程
	var remote_version = remote_state.get("version", -1)
	var local_version = local_state.get("version", -1)

	if remote_version > local_version:
		print("[GameSynchronizer] 采用远程状态 (版本: %d)" % remote_version)
		return remote_state
	else:
		print("[GameSynchronizer] 保持本地状态 (版本: %d)" % local_version)
		return local_state

# ==================== 网络通信 ====================

func send_operation(operation: OperationQueue.Operation) -> bool:
	if not network_client:
		return false

	return network_client.send_operation({
		"type": operation.op_type,
		"player_id": operation.player_id,
		"timestamp": operation.timestamp,
		"sequence": operation.sequence,
		"data": operation.data
	})

func send_state_snapshot() -> bool:
	if not network_client:
		return false

	var snapshot = game_state.get_current_state()
	return network_client.send_state_sync(snapshot.to_dict())

# ==================== 恢复机制 ====================

func request_state_recovery(version: int) -> bool:
	if not network_client:
		return false

	print("[GameSynchronizer] 请求状态恢复: 版本 %d" % version)
	return network_client.request_state_recovery(version)

func replay_operations_since(version: int) -> void:
	var history = operation_queue.get_operations_since(version)

	print("[GameSynchronizer] 重放 %d 个操作（版本: %d）" % [
		history.size(),
		version
	])

	for op_data in history:
		handle_remote_operation(op_data)

# ==================== 工具函数 ====================

func _convert_operations_to_dicts(operations: Array) -> Array:
	var result = []
	for op in operations:
		result.append(op.to_dict())
	return result

func check_connected() -> bool:
	return network_client and network_client.check_connected()

# ==================== 统计和监控 ====================

func get_sync_statistics() -> Dictionary:
	return {
		"total_syncs": _total_syncs,
		"total_operations": _total_operations,
		"last_sync_latency": _sync_latency,
		"game_version": game_state.get_version(),
		"queue_size": operation_queue.get_queue_size(),
		"state_version": _last_synced_version
	}

func get_sync_health() -> float:
	if _total_syncs == 0:
		return 0.0

	# 健康度 = (同步成功数 / 总同步数) * 100
	return 100.0

# ==================== 调试 ====================

func print_sync_status() -> void:
	print("\n╔════════════════════════════════════╗")
	print("║ 🔄 游戏同步器状态 ║")
	print("╚════════════════════════════════════╝")

	var stats = get_sync_statistics()
	print("\n【同步统计】")
	print("总同步次数: %d" % stats["total_syncs"])
	print("总操作数: %d" % stats["total_operations"])
	print("上次延迟: %dms" % stats["last_sync_latency"])

	print("\n【状态信息】")
	print("游戏版本: %d" % stats["game_version"])
	print("队列大小: %d" % stats["queue_size"])

	game_state.print_state()
	operation_queue.print_status()

	print("\n═════════════════════════════════════\n")
