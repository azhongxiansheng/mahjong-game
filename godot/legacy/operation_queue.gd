# 操作队列 - 管理和同步玩家操作
class_name OperationQueue

# 操作类型
enum OperationType {
	DRAW_CARD = 0,        # 摸牌
	PLAY_CARD = 1,        # 出牌
	DECLARE_WIN = 2,      # 宣布胜牌
	PASS = 3,             # 跳过
	DISCARD = 4,          # 弃牌
	DRAW_FROM_PILE = 5    # 从弃牌堆抽牌
}

# 操作记录
class Operation:
	var op_type: int = OperationType.DRAW_CARD
	var player_id: String = ""
	var timestamp: int = 0
	var sequence: int = 0              # 操作序列号
	var data: Dictionary = {}          # 操作数据
	var confirmed: bool = false        # 是否已确认
	
	func _init(type: int, player: String, seq: int) -> void:
		op_type = type
		player_id = player
		sequence = seq
		timestamp = Time.get_ticks_msec()
	
	func to_dict() -> Dictionary:
		return {
			"type": op_type,
			"player_id": player_id,
			"timestamp": timestamp,
			"sequence": sequence,
			"data": data.duplicate(true),
			"confirmed": confirmed
		}

# 队列管理
var _queue: Array = []                # 待处理操作
var _history: Array = []              # 操作历史
var _sequence_counter: int = 0        # 操作序列计数
var _pending_confirms: Dictionary = {} # 待确认操作: sequence -> operation
var _max_history: int = 200           # 最大历史记录

# 信号
signal operation_added(operation: Operation)
signal operation_confirmed(operation: Operation)
signal operation_executed(operation: Operation)
signal queue_cleared()

# ==================== 操作入队 ====================

func add_operation(op_type: int, player_id: String, data: Dictionary = {}) -> Operation:
	var op = Operation.new(op_type, player_id, _sequence_counter)
	op.data = data.duplicate(true)
	_sequence_counter += 1
	
	_queue.append(op)
	_pending_confirms[op.sequence] = op
	
	print("[OperationQueue] 操作入队: %s (玩家: %s, 序列: %d)" % [
		_get_operation_name(op_type),
		player_id,
		op.sequence
	])
	
	operation_added.emit(op)
	return op

func add_draw_card(player_id: String) -> Operation:
	return add_operation(OperationType.DRAW_CARD, player_id, {})

func add_play_card(player_id: String, card_data: Dictionary) -> Operation:
	return add_operation(OperationType.PLAY_CARD, player_id, {"card": card_data})

func add_win(player_id: String, win_data: Dictionary) -> Operation:
	return add_operation(OperationType.DECLARE_WIN, player_id, {"win": win_data})

func add_pass(player_id: String) -> Operation:
	return add_operation(OperationType.PASS, player_id, {})

# ==================== 操作确认 ====================

func confirm_operation(sequence: int) -> bool:
	if sequence not in _pending_confirms:
		print("[OperationQueue] 无效的序列: %d" % sequence)
		return false
	
	var op = _pending_confirms[sequence]
	op.confirmed = true
	_pending_confirms.erase(sequence)
	
	print("[OperationQueue] 操作已确认: 序列 %d" % sequence)
	operation_confirmed.emit(op)
	
	return true

func is_operation_confirmed(sequence: int) -> bool:
	return sequence not in _pending_confirms

# ==================== 操作执行 ====================

func execute_next() -> Operation:
	if _queue.is_empty():
		print("[OperationQueue] 队列为空")
		return null
	
	var op = _queue.pop_front()
	_history.append(op)
	
	print("[OperationQueue] 操作已执行: %s" % _get_operation_name(op.op_type))
	operation_executed.emit(op)
	
	# 限制历史大小
	if _history.size() > _max_history:
		_history.pop_front()
	
	return op

func execute_operation_at(sequence: int) -> Operation:
	for i in range(_queue.size()):
		if _queue[i].sequence == sequence:
			var op = _queue.pop_at(i)
			_history.append(op)
			operation_executed.emit(op)
			return op
	
	print("[OperationQueue] 找不到序列为 %d 的操作" % sequence)
	return null

# ==================== 队列查询 ====================

func get_queue_size() -> int:
	return _queue.size()

func peek_next() -> Operation:
	if _queue.is_empty():
		return null
	return _queue[0]

func get_pending_operations() -> Array:
	return _queue.duplicate()

func get_pending_count() -> int:
	return _pending_confirms.size()

func get_pending_operation(sequence: int) -> Operation:
	return _pending_confirms.get(sequence)

func get_history() -> Array:
	return _history.duplicate()

func get_history_size() -> int:
	return _history.size()

# ==================== 操作检查 ====================

func is_queue_empty() -> bool:
	return _queue.is_empty()

func has_pending_operations() -> bool:
	return _pending_confirms.size() > 0

func get_player_pending_operations(player_id: String) -> Array:
	var player_ops = []
	for seq in _pending_confirms.keys():
		var op = _pending_confirms[seq]
		if op.player_id == player_id:
			player_ops.append(op)
	return player_ops

func wait_for_confirmation(sequence: int, timeout_ms: int = 5000) -> bool:
	var start_time = Time.get_ticks_msec()
	
	while sequence in _pending_confirms:
		if Time.get_ticks_msec() - start_time > timeout_ms:
			print("[OperationQueue] 确认超时: 序列 %d" % sequence)
			return false
		
		await Engine.get_main_loop().process_frame
	
	return true

# ==================== 清空操作 ====================

func clear_queue() -> void:
	_queue.clear()
	print("[OperationQueue] 队列已清空")
	queue_cleared.emit()

func clear_pending() -> void:
	_pending_confirms.clear()
	print("[OperationQueue] 待确认操作已清空")

func clear_history() -> void:
	_history.clear()
	print("[OperationQueue] 历史记录已清空")

func clear_all() -> void:
	clear_queue()
	clear_pending()
	clear_history()

# ==================== 同步 ====================

func apply_remote_operations(operations: Array) -> void:
	for op_data in operations:
		var op = Operation.new(
			op_data.get("type", OperationType.DRAW_CARD),
			op_data.get("player_id", ""),
			op_data.get("sequence", -1)
		)
		op.timestamp = op_data.get("timestamp", 0)
		op.data = op_data.get("data", {}).duplicate(true)
		op.confirmed = op_data.get("confirmed", false)
		
		_history.append(op)
		_sequence_counter = max(_sequence_counter, op.sequence + 1)
	
	print("[OperationQueue] 已应用 %d 个远程操作" % operations.size())

func get_operations_since(sequence: int) -> Array:
	var result = []
	for op in _history:
		if op.sequence > sequence:
			result.append(op.to_dict())
	return result

# ==================== 统计 ====================

func get_statistics() -> Dictionary:
	return {
		"queue_size": _queue.size(),
		"history_size": _history.size(),
		"pending_confirms": _pending_confirms.size(),
		"total_sequences": _sequence_counter
	}

# ==================== 工具函数 ====================

func _get_operation_name(op_type: int) -> String:
	match op_type:
		OperationType.DRAW_CARD:
			return "摸牌"
		OperationType.PLAY_CARD:
			return "出牌"
		OperationType.DECLARE_WIN:
			return "宣布胜牌"
		OperationType.PASS:
			return "跳过"
		OperationType.DISCARD:
			return "弃牌"
		OperationType.DRAW_FROM_PILE:
			return "从弃牌堆抽牌"
		_:
			return "未知操作"

# ==================== 调试 ====================

func print_status() -> void:
	print("\n=== 操作队列状态 ===")
	print("队列大小: %d" % _queue.size())
	print("历史记录: %d" % _history.size())
	print("待确认: %d" % _pending_confirms.size())
	print("序列计数: %d" % _sequence_counter)
	print("====================\n")
