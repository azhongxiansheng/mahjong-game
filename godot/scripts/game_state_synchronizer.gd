class_name GameStateSynchronizer
extends Node

# 同步策略
enum SyncStrategy {
	AUTHORITATIVE,  # 服务器权威模式
	PEER_TO_PEER,   # 对等同步模式
	HYBRID          # 混合模式
}

# 游戏状态快照
class GameStateSnapshot:
	var round_number: int = 0
	var current_player_index: int = 0
	var player_hands: Dictionary = {}  # player_id -> cards
	var board_state: Dictionary = {}
	var last_actions: Array = []
	var timestamp: float = 0.0
	var state_hash: String = ""
	var version: int = 0
	
	func _init() -> void:
		timestamp = Time.get_ticks_msec()
	
	func to_dict() -> Dictionary:
		return {
			"round_number": round_number,
			"current_player_index": current_player_index,
			"player_hands": player_hands,
			"board_state": board_state,
			"last_actions": last_actions,
			"timestamp": timestamp,
			"state_hash": state_hash,
			"version": version
		}
	
	func from_dict(data: Dictionary) -> void:
		round_number = data.get("round_number", 0)
		current_player_index = data.get("current_player_index", 0)
		player_hands = data.get("player_hands", {})
		board_state = data.get("board_state", {})
		last_actions = data.get("last_actions", [])
		timestamp = data.get("timestamp", 0.0)
		state_hash = data.get("state_hash", "")
		version = data.get("version", 0)

# 同步配置
var sync_strategy: int = SyncStrategy.HYBRID
var sync_interval: float = 1.0  # 秒
var max_version_history: int = 20

# 状态管理
var local_state: GameStateSnapshot
var remote_states: Dictionary = {}  # player_id -> GameStateSnapshot
var state_history: Array = []
var last_sync_time: float = 0.0
var sync_counter: int = 0
var version_number: int = 0

# 冲突解决
var conflict_resolution_method: String = "timestamp"  # "timestamp" or "version"
var accepted_state_conflicts: int = 0
var rejected_state_conflicts: int = 0

# 信号
signal state_updated(new_state: GameStateSnapshot)
signal state_conflict_detected(player_id: String, local_state: Dictionary, remote_state: Dictionary)
signal state_synchronized(player_id: String)
signal sync_failed(reason: String)

func _ready() -> void:
	print("========== 游戏状态同步系统初始化 ==========")
	local_state = GameStateSnapshot.new()
	print("✓ GameStateSynchronizer已初始化")
	print("同步策略: ", SyncStrategy.keys()[sync_strategy])

func _process(delta: float) -> void:
	# 定期发送状态同步
	last_sync_time += delta
	if last_sync_time >= sync_interval:
		broadcast_state()
		last_sync_time = 0.0

func capture_state() -> GameStateSnapshot:
	"""捕获当前游戏状态"""
	local_state.timestamp = Time.get_ticks_msec()
	local_state.version = version_number
	
	# 计算状态哈希
	local_state.state_hash = calculate_state_hash(local_state)
	
	# 存储到历史
	state_history.append(local_state)
	if state_history.size() > max_version_history:
		state_history.pop_front()
	
	version_number += 1
	
	return local_state

func sync_state_to_players(state: GameStateSnapshot) -> void:
	"""向所有玩家同步状态"""
	sync_counter += 1
	print("📤 同步游戏状态 (版本: ", state.version, ")")
	emit_signal("state_updated", state)

func broadcast_state() -> void:
	"""广播当前状态"""
	capture_state()
	sync_state_to_players(local_state)

func apply_remote_state(player_id: String, remote_state_dict: Dictionary) -> bool:
	"""应用接收到的远程状态"""
	var remote_state = GameStateSnapshot.new()
	remote_state.from_dict(remote_state_dict)
	
	remote_states[player_id] = remote_state
	
	# 检查状态一致性
	if not validate_state_consistency(local_state, remote_state):
		print("⚠ 状态不一致，发起冲突解决")
		return handle_state_conflict(player_id, local_state, remote_state)
	
	print("✓ 接收到玩家 ", player_id, " 的状态")
	emit_signal("state_synchronized", player_id)
	return true

func validate_state_consistency(local: GameStateSnapshot, remote: GameStateSnapshot) -> bool:
	"""验证状态一致性"""
	# 检查版本号
	if remote.version < local.version:
		print("⚠ 接收到旧版本状态")
		return false
	
	# 检查轮次
	if abs(remote.round_number - local.round_number) > 1:
		print("⚠ 轮次差异过大")
		return false
	
	# 检查状态哈希
	var remote_hash = calculate_state_hash(remote)
	if remote_hash != remote.state_hash:
		print("⚠ 状态哈希不匹配")
		return false
	
	return true

func handle_state_conflict(player_id: String, local_state: GameStateSnapshot, remote_state: GameStateSnapshot) -> bool:
	"""处理状态冲突"""
	print("🔴 检测到状态冲突!")
	emit_signal("state_conflict_detected", player_id, local_state.to_dict(), remote_state.to_dict())
	
	var resolved_state: GameStateSnapshot
	
	if conflict_resolution_method == "timestamp":
		# 使用时间戳解决
		if remote_state.timestamp > local_state.timestamp:
			resolved_state = remote_state
			print("✓ 使用远程状态 (时间戳较新)")
		else:
			resolved_state = local_state
			print("✓ 使用本地状态 (时间戳较新)")
	else:
		# 使用版本号解决
		if remote_state.version > local_state.version:
			resolved_state = remote_state
			print("✓ 使用远程状态 (版本较新)")
		else:
			resolved_state = local_state
			print("✓ 使用本地状态 (版本较新)")
	
	# 应用解决后的状态
	if resolved_state == remote_state:
		local_state = resolved_state
		accepted_state_conflicts += 1
		print("✅ 状态冲突已接受远程状态")
		return true
	else:
		rejected_state_conflicts += 1
		print("✅ 状态冲突已拒绝远程状态")
		return false

func get_state_hash() -> String:
	"""获取当前状态哈希"""
	return local_state.state_hash

func calculate_state_hash(state: GameStateSnapshot) -> String:
	"""计算状态哈希"""
	var hash_string = str(state.round_number) + "_" + str(state.current_player_index) + "_" + str(state.timestamp)
	
	# 添加玩家手牌哈希
	for player_id in state.player_hands.keys():
		hash_string += "_" + player_id + ":" + str(state.player_hands[player_id])
	
	# 使用Godot的哈希函数
	return str(hash(hash_string))

func get_state_version() -> int:
	"""获取当前状态版本"""
	return version_number

func get_state_history() -> Array:
	"""获取状态历史"""
	var history = []
	for state in state_history:
		history.append(state.to_dict())
	return history

func update_player_hand(player_id: String, hand_data: Array) -> void:
	"""更新玩家手牌"""
	local_state.player_hands[player_id] = hand_data
	print("📝 更新玩家手牌: ", player_id, " (", hand_data.size(), "张)")

func add_action_to_history(player_id: String, action: String, action_data: Dictionary) -> void:
	"""添加操作到历史"""
	var action_record = {
		"player_id": player_id,
		"action": action,
		"data": action_data,
		"timestamp": Time.get_ticks_msec()
	}
	
	local_state.last_actions.append(action_record)
	
	# 保持历史长度
	if local_state.last_actions.size() > 100:
		local_state.last_actions.pop_front()

func get_sync_info() -> Dictionary:
	"""获取同步信息"""
	return {
		"sync_counter": sync_counter,
		"version": version_number,
		"last_sync_time": last_sync_time,
		"state_conflicts_accepted": accepted_state_conflicts,
		"state_conflicts_rejected": rejected_state_conflicts,
		"remote_states_count": remote_states.size(),
		"history_size": state_history.size()
	}

func print_sync_status() -> void:
	"""打印同步状态"""
	print("\n========== 游戏状态同步状态 ==========")
	print("当前版本: ", version_number)
	print("同步计数: ", sync_counter)
	print("上次同步: ", int(last_sync_time * 1000), "ms前")
	print("接受的冲突: ", accepted_state_conflicts)
	print("拒绝的冲突: ", rejected_state_conflicts)
	print("远程状态数: ", remote_states.size())
	print("历史记录: ", state_history.size(), "/", max_version_history)
	
	print("\n当前状态:")
	print("  轮次: ", local_state.round_number)
	print("  当前玩家: ", local_state.current_player_index)
	print("  玩家数: ", local_state.player_hands.size())
	print("  最近操作: ", local_state.last_actions.size())
	
	print("====================================\n")

func reset_state() -> void:
	"""重置状态"""
	local_state = GameStateSnapshot.new()
	remote_states.clear()
	state_history.clear()
	version_number = 0
	sync_counter = 0
	print("✓ 游戏状态已重置")
