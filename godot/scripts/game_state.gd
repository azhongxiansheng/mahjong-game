# 游戏状态 - 捕获和管理游戏状态快照
class_name GameState

# 游戏阶段
enum GamePhase {
	WAITING = 0,      # 等待开始
	DRAWING = 1,      # 摸牌阶段
	PLAYING = 2,      # 出牌阶段
	DISCARDING = 3,   # 弃牌阶段
	WIN = 4,          # 胜牌
	FINISHED = 5      # 游戏结束
}

# 游戏状态快照
class Snapshot:
	var version: int = 0                    # 版本号
	var timestamp: int = 0                  # 时间戳
	var phase: int = GamePhase.WAITING      # 当前阶段
	var current_player_id: String = ""      # 当前玩家ID
	var game_round: int = 1                 # 当前轮数
	var players: Dictionary = {}            # 玩家状态: player_id -> player_state
	var discard_pile: Array = []            # 弃牌堆
	var drawn_card: Dictionary = {}         # 摸到的牌
	var scores: Dictionary = {}             # 各玩家得分
	var game_data: Dictionary = {}          # 额外游戏数据
	
	func _init() -> void:
		timestamp = Time.get_ticks_msec()
	
	func to_dict() -> Dictionary:
		return {
			"version": version,
			"timestamp": timestamp,
			"phase": phase,
			"current_player_id": current_player_id,
			"round": game_round,
			"players": players.duplicate(true),
			"discard_pile": discard_pile.duplicate(true),
			"drawn_card": drawn_card.duplicate(true),
			"scores": scores.duplicate(true),
			"game_data": game_data.duplicate(true)
		}
	
	func to_json() -> String:
		return JSON.stringify(to_dict())

# 状态管理
var _current_state: Snapshot = Snapshot.new()
var _state_history: Array = []            # 状态历史
var _version_counter: int = 0             # 版本计数器
var _max_history: int = 100               # 最大历史记录

# 信号
signal state_changed(new_state: Snapshot)
signal state_synced(version: int)

# 初始化
func _init() -> void:
	_current_state.version = _version_counter
	_state_history.append(_current_state.duplicate())
	print("[GameState] 初始化完成")

# ==================== 状态更新 ====================

func update_phase(new_phase: int) -> void:
	_current_state.phase = new_phase
	_increment_version()
	state_changed.emit(_current_state)

func set_current_player(player_id: String) -> void:
	_current_state.current_player_id = player_id
	_increment_version()

func add_to_discard_pile(card: Dictionary) -> void:
	_current_state.discard_pile.append(card)
	_increment_version()

func set_drawn_card(card: Dictionary) -> void:
	_current_state.drawn_card = card.duplicate()
	_increment_version()

func update_player_state(player_id: String, player_state: Dictionary) -> void:
	_current_state.players[player_id] = player_state.duplicate(true)
	_increment_version()
	state_changed.emit(_current_state)

func update_score(player_id: String, score: int) -> void:
	_current_state.scores[player_id] = score
	_increment_version()

func update_scores(scores: Dictionary) -> void:
	_current_state.scores = scores.duplicate()
	_increment_version()

func set_game_data(key: String, value) -> void:
	_current_state.game_data[key] = value
	_increment_version()

func increment_round() -> void:
	_current_state.game_round += 1
	_increment_version()

# ==================== 状态查询 ====================

func get_current_state() -> Snapshot:
	return _current_state

func get_phase() -> int:
	return _current_state.phase

func get_current_player() -> String:
	return _current_state.current_player_id

func get_discard_pile() -> Array:
	return _current_state.discard_pile.duplicate()

func get_player_count() -> int:
	return _current_state.players.size()

func get_round() -> int:
	return _current_state.game_round

func get_version() -> int:
	return _current_state.version

func get_scores() -> Dictionary:
	return _current_state.scores.duplicate()

func get_player_state(player_id: String) -> Dictionary:
	if player_id in _current_state.players:
		return _current_state.players[player_id].duplicate(true)
	return {}

# ==================== 版本管理 ====================

func _increment_version() -> void:
	_version_counter += 1
	_current_state.version = _version_counter
	_current_state.timestamp = Time.get_ticks_msec()
	
	# 保存到历史
	_save_to_history()

func _save_to_history() -> void:
	var snapshot_copy = Snapshot.new()
	snapshot_copy.version = _current_state.version
	snapshot_copy.timestamp = _current_state.timestamp
	snapshot_copy.phase = _current_state.phase
	snapshot_copy.current_player_id = _current_state.current_player_id
	snapshot_copy.game_round = _current_state.game_round
	snapshot_copy.players = _current_state.players.duplicate(true)
	snapshot_copy.discard_pile = _current_state.discard_pile.duplicate()
	snapshot_copy.drawn_card = _current_state.drawn_card.duplicate()
	snapshot_copy.scores = _current_state.scores.duplicate()
	snapshot_copy.game_data = _current_state.game_data.duplicate(true)
	
	_state_history.append(snapshot_copy)
	
	# 限制历史大小
	if _state_history.size() > _max_history:
		_state_history.pop_front()

# ==================== 历史管理 ====================

func get_history() -> Array:
	return _state_history.duplicate()

func get_state_at_version(version: int) -> Snapshot:
	for snapshot in _state_history:
		if snapshot.version == version:
			return snapshot
	return null

func get_history_size() -> int:
	return _state_history.size()

func clear_history() -> void:
	_state_history.clear()
	_state_history.append(_current_state.duplicate())

# ==================== 同步 ====================

func apply_remote_state(remote_state: Dictionary) -> bool:
	var remote_version = remote_state.get("version", -1)
	var current_version = _current_state.version
	
	if remote_version <= current_version:
		print("[GameState] 远程版本过旧: %d <= %d" % [remote_version, current_version])
		return false
	
	# 应用远程状态
	_current_state.version = remote_version
	_current_state.timestamp = remote_state.get("timestamp", 0)
	_current_state.phase = remote_state.get("phase", GamePhase.WAITING)
	_current_state.current_player_id = remote_state.get("current_player_id", "")
	_current_state.game_round = remote_state.get("round", 1)
	_current_state.players = remote_state.get("players", {}).duplicate(true)
	_current_state.discard_pile = remote_state.get("discard_pile", []).duplicate()
	_current_state.drawn_card = remote_state.get("drawn_card", {}).duplicate()
	_current_state.scores = remote_state.get("scores", {}).duplicate()
	_current_state.game_data = remote_state.get("game_data", {}).duplicate(true)
	
	_save_to_history()
	state_synced.emit(remote_version)
	
	print("[GameState] 状态已同步: 版本 %d" % remote_version)
	return true

func get_diff_since(version: int) -> Dictionary:
	var old_state = get_state_at_version(version)
	if not old_state:
		return _current_state.to_dict()
	
	var diff = {}
	var current_dict = _current_state.to_dict()
	var old_dict = old_state.to_dict()
	
	for key in current_dict.keys():
		if current_dict[key] != old_dict.get(key):
			diff[key] = current_dict[key]
	
	return diff

# ==================== 重置 ====================

func reset() -> void:
	_current_state = Snapshot.new()
	_current_state.version = _version_counter
	_state_history.clear()
	_state_history.append(_current_state.duplicate())
	print("[GameState] 状态已重置")

# ==================== 调试 ====================

func print_state() -> void:
	print("\n=== 游戏状态 ===")
	print("版本: %d" % _current_state.version)
	print("阶段: %d" % _current_state.phase)
	print("当前玩家: %s" % _current_state.current_player_id)
	print("轮数: %d" % _current_state.game_round)
	print("玩家数: %d" % _current_state.players.size())
	print("弃牌堆: %d张" % _current_state.discard_pile.size())
	print("历史记录: %d条" % _state_history.size())
	print("================\n")
