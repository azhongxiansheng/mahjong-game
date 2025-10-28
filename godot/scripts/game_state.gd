class_name GameState

# 游戏状态枚举
enum State {
	INIT,           # 初始化
	READY,          # 准备
	DEALING,        # 发牌
	PLAYING,        # 游戏进行中
	WAITING_ACTION, # 等待玩家操作
	DISCARD,        # 出牌
	DRAW,           # 抽牌
	WIN,            # 胜利
	LOSE,           # 失败
	END             # 结束
}

# 当前状态
var current_state: State = State.INIT

# 状态转换日志
var state_history: Array = []

func _init() -> void:
	"""初始化状态管理器"""
	add_state_to_history(State.INIT)

func set_state(new_state: State) -> void:
	"""设置新状态"""
	if new_state != current_state:
		print("状态转换: %s → %s" % [get_state_name(current_state), get_state_name(new_state)])
		current_state = new_state
		add_state_to_history(new_state)

func get_state() -> State:
	"""获取当前状态"""
	return current_state

func get_state_name(state: State = current_state) -> String:
	"""获取状态名称"""
	match state:
		State.INIT: return "初始化"
		State.READY: return "准备"
		State.DEALING: return "发牌"
		State.PLAYING: return "游戏进行"
		State.WAITING_ACTION: return "等待操作"
		State.DISCARD: return "出牌"
		State.DRAW: return "抽牌"
		State.WIN: return "胜利"
		State.LOSE: return "失败"
		State.END: return "结束"
		_: return "未知"

func add_state_to_history(state: State) -> void:
	"""添加状态到历史记录"""
	state_history.append(state)

func get_state_history() -> Array:
	"""获取状态历史"""
	return state_history

func get_state_count() -> int:
	"""获取状态转换次数"""
	return state_history.size()

func is_playing() -> bool:
	"""游戏是否进行中"""
	return current_state in [State.PLAYING, State.WAITING_ACTION, State.DISCARD, State.DRAW]

func can_discard() -> bool:
	"""是否可以出牌"""
	return current_state == State.WAITING_ACTION

func print_state_info() -> void:
	"""打印状态信息"""
	print("\n【游戏状态信息】")
	print("当前状态: %s" % get_state_name())
	print("状态历史: " + str(state_history))
	print("状态转换次数: %d" % get_state_count())
