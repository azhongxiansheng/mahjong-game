class_name GameLogger

# 游戏日志系统
# 提供统一的日志管理和输出

# 日志级别枚举
enum LogLevel { DEBUG = 0, INFO = 1, WARN = 2, ERROR = 3 }

# 全局配置
static var debug_mode: bool = true
static var current_log_level: int = LogLevel.DEBUG
static var log_to_file: bool = false
static var log_file_path: String = "user://game.log"
static var log_buffer: Array = []
static var max_buffer_size: int = 1000

# ==================== 核心日志方法 ====================

static func debug(message: String, tag: String = "DEBUG") -> void:
	"""输出调试信息"""
	if current_log_level <= LogLevel.DEBUG:
		_log(message, tag)

static func info(message: String, tag: String = "INFO") -> void:
	"""输出信息"""
	if current_log_level <= LogLevel.INFO:
		_log(message, tag)

static func warn(message: String, tag: String = "WARN") -> void:
	"""输出警告"""
	if current_log_level <= LogLevel.WARN:
		_log(message, tag)

static func error(message: String, tag: String = "ERROR") -> void:
	"""输出错误"""
	if current_log_level <= LogLevel.ERROR:
		_log(message, tag)

static func success(message: String, tag: String = "SUCCESS") -> void:
	"""输出成功消息"""
	_log(message, tag)

# ==================== 内部方法 ====================

static func _log(message: String, tag: String) -> void:
	"""内部日志处理"""
	var timestamp = _get_timestamp()
	var formatted_message = "[%s] <%s> %s" % [timestamp, tag, message]
	
	# 打印到控制台
	if debug_mode:
		print(formatted_message)
	
	# 添加到缓冲区
	_add_to_buffer(formatted_message)
	
	# 保存到文件
	if log_to_file:
		_write_to_file(formatted_message)

static func _get_timestamp() -> String:
	"""获取时间戳"""
	var time_dict = Time.get_datetime_dict_from_system(false)
	return "%02d:%02d:%02d" % [time_dict.hour, time_dict.minute, time_dict.second]

static func _add_to_buffer(message: String) -> void:
	"""添加消息到缓冲区"""
	log_buffer.append(message)
	
	# 限制缓冲区大小
	if log_buffer.size() > max_buffer_size:
		log_buffer.pop_front()

static func _write_to_file(message: String) -> void:
	"""将消息写入文件"""
	var file = FileAccess.open(log_file_path, FileAccess.READ_WRITE)
	if file:
		file.seek_end()
		file.store_line(message)

# ==================== 配置方法 ====================

static func set_debug_mode(enabled: bool) -> void:
	"""设置调试模式"""
	debug_mode = enabled
	info("调试模式已%s" % ("启用" if enabled else "禁用"))

static func set_log_level(level: int) -> void:
	"""设置日志级别"""
	current_log_level = level
	var level_names = ["DEBUG", "INFO", "WARN", "ERROR"]
	info("日志级别已设置为: %s" % level_names[level])

static func set_file_logging(enabled: bool, path: String = "user://game.log") -> void:
	"""启用/禁用文件日志"""
	log_to_file = enabled
	log_file_path = path
	info("文件日志已%s (路径: %s)" % ["启用" if enabled else "禁用", path])

# ==================== 缓冲区操作 ====================

static func get_log_buffer() -> Array:
	"""获取日志缓冲区"""
	return log_buffer.duplicate()

static func clear_log_buffer() -> void:
	"""清空日志缓冲区"""
	log_buffer.clear()
	info("日志缓冲区已清空")

static func get_buffer_size() -> int:
	"""获取缓冲区大小"""
	return log_buffer.size()

static func get_last_n_logs(n: int) -> Array:
	"""获取最后N条日志"""
	var start_index = max(0, log_buffer.size() - n)
	return log_buffer.slice(start_index)

# ==================== 统计方法 ====================

static func print_statistics() -> void:
	"""打印日志统计信息"""
	print("\n【日志统计】")
	print("  调试模式: %s" % ("启用" if debug_mode else "禁用"))
	print("  当前级别: %d" % current_log_level)
	print("  缓冲区大小: %d/%d" % [log_buffer.size(), max_buffer_size])
	print("  文件日志: %s" % ("启用" if log_to_file else "禁用"))
	print()

static func print_all_logs() -> void:
	"""打印所有日志"""
	print("\n【全部日志】")
	for i in range(log_buffer.size()):
		print("[%d] %s" % [i, log_buffer[i]])
	print()

# ==================== 系统集成 ====================

static func log_scene_change(from_scene: String, to_scene: String) -> void:
	"""记录场景切换"""
	info("场景切换: %s → %s" % [from_scene, to_scene], "SCENE")

static func log_game_event(event_type: String, details: String = "") -> void:
	"""记录游戏事件"""
	var message = event_type
	if details != "":
		message += " (%s)" % details
	info(message, "EVENT")

static func log_performance(metric_name: String, value: float, unit: String = "") -> void:
	"""记录性能指标"""
	var message = "%s: %.2f%s" % [metric_name, value, unit]
	debug(message, "PERF")

static func log_error_with_stacktrace(error_msg: String) -> void:
	"""记录错误并附加堆栈跟踪"""
	error(error_msg, "ERROR")
	error("堆栈跟踪: (详见调试器)", "TRACE")
