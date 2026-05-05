# 网络调试器 - 监听和记录网络通信
class_name NetworkDebugger
extends Node

# 日志配置
var _enable_logging: bool = true
var _log_level: int = 0  # 0=DEBUG, 1=INFO, 2=WARN, 3=ERROR
var _max_log_size: int = 1000
var _log_buffer: Array = []

# 监控数据
var _message_stats: Dictionary = {}
var _network_stats: Dictionary = {
	"total_messages_sent": 0,
	"total_messages_received": 0,
	"total_bytes_sent": 0,
	"total_bytes_received": 0,
	"connection_time": 0,
	"disconnection_count": 0
}

# 消息历史
var _message_history: Array = []
var _max_history: int = 100

# ==================== 日志 ====================

func log_debug(message: String, context: String = "") -> void:
	if _log_level <= 0:
		_add_log(message, context, "DEBUG")

func log_info(message: String, context: String = "") -> void:
	if _log_level <= 1:
		_add_log(message, context, "INFO")

func log_warn(message: String, context: String = "") -> void:
	if _log_level <= 2:
		_add_log(message, context, "WARN")

func log_error(message: String, context: String = "") -> void:
	if _log_level <= 3:
		_add_log(message, context, "ERROR")

func _add_log(message: String, context: String, level: String) -> void:
	if not _enable_logging:
		return

	var timestamp = Time.get_ticks_msec()
	var log_entry = {
		"timestamp": timestamp,
		"level": level,
		"message": message,
		"context": context
	}

	_log_buffer.append(log_entry)

	# 限制日志大小
	if _log_buffer.size() > _max_log_size:
		_log_buffer.pop_front()

	# 打印到控制台
	var formatted = "[%s] %s: %s" % [level, context, message]
	print(formatted)

# ==================== 消息监听 ====================

func on_message_sent(message_type: String, size: int) -> void:
	"""记录发送的消息"""
	_network_stats["total_messages_sent"] += 1
	_network_stats["total_bytes_sent"] += size

	if message_type not in _message_stats:
		_message_stats[message_type] = {"sent": 0, "received": 0}

	_message_stats[message_type]["sent"] += 1
	_add_message_to_history(message_type, "SEND", size)

	log_debug("消息已发送: %s (%d字节)" % [message_type, size], "Network")

func on_message_received(message_type: String, size: int) -> void:
	"""记录接收的消息"""
	_network_stats["total_messages_received"] += 1
	_network_stats["total_bytes_received"] += size

	if message_type not in _message_stats:
		_message_stats[message_type] = {"sent": 0, "received": 0}

	_message_stats[message_type]["received"] += 1
	_add_message_to_history(message_type, "RECV", size)

	log_debug("消息已接收: %s (%d字节)" % [message_type, size], "Network")

func _add_message_to_history(msg_type: String, direction: String, size: int) -> void:
	"""添加消息到历史记录"""
	_message_history.append({
		"timestamp": Time.get_ticks_msec(),
		"type": msg_type,
		"direction": direction,
		"size": size
	})

	if _message_history.size() > _max_history:
		_message_history.pop_front()

# ==================== 连接监听 ====================

func on_connection_started() -> void:
	"""记录连接开始"""
	_network_stats["connection_time"] = Time.get_ticks_msec()
	log_info("连接已启动", "Network")

func on_connection_established() -> void:
	"""记录连接建立"""
	var elapsed = Time.get_ticks_msec() - _network_stats["connection_time"]
	log_info("连接已建立 (耗时: %dms)" % elapsed, "Network")

func on_disconnection() -> void:
	"""记录断开连接"""
	_network_stats["disconnection_count"] += 1
	log_warn("已断开连接", "Network")

# ==================== 性能监控 ====================

func get_network_stats() -> Dictionary:
	"""获取网络统计"""
	var avg_message_size = 0
	if _network_stats["total_messages_sent"] > 0:
		avg_message_size = _network_stats["total_bytes_sent"] / _network_stats["total_messages_sent"]

	return {
		"messages_sent": _network_stats["total_messages_sent"],
		"messages_received": _network_stats["total_messages_received"],
		"bytes_sent": _network_stats["total_bytes_sent"],
		"bytes_received": _network_stats["total_bytes_received"],
		"avg_message_size": avg_message_size,
		"disconnections": _network_stats["disconnection_count"]
	}

func get_message_stats() -> Dictionary:
	"""获取消息统计"""
	return _message_stats.duplicate(true)

func get_bandwidth_usage() -> Dictionary:
	"""获取带宽使用情况"""
	var total_sent = _network_stats["total_bytes_sent"]
	var total_received = _network_stats["total_bytes_received"]

	return {
		"sent_kb": float(total_sent) / 1024.0,
		"received_kb": float(total_received) / 1024.0,
		"total_kb": float(total_sent + total_received) / 1024.0
	}

# ==================== 日志管理 ====================

func get_logs(level_filter: String = "") -> Array:
	"""获取日志"""
	if level_filter.is_empty():
		return _log_buffer.duplicate()

	var filtered = []
	for log in _log_buffer:
		if log["level"] == level_filter:
			filtered.append(log)

	return filtered

func clear_logs() -> void:
	"""清空日志"""
	_log_buffer.clear()
	log_info("日志已清空", "Debugger")

func export_logs(filename: String = "network_debug.log") -> bool:
	"""导出日志到文件"""
	var content = ""

	for log in _log_buffer:
		var line = "[%d] [%s] %s: %s\n" % [
			log["timestamp"],
			log["level"],
			log["context"],
			log["message"]
		]
		content += line

	var file = FileAccess.open(filename, FileAccess.WRITE)
	if file == null:
		log_error("无法写入日志文件", "Debugger")
		return false

	file.store_string(content)
	log_info("日志已导出: %s" % filename, "Debugger")
	return true

# ==================== 打印报告 ====================

func print_network_report() -> void:
	"""打印网络统计报告"""
	print("\n╔════════════════════════════════════════╗")
	print("║ 📊 网络统计报告 ║")
	print("╚════════════════════════════════════════╝\n")

	var stats = get_network_stats()
	var bandwidth = get_bandwidth_usage()

	print("【消息统计】")
	print("发送消息数: %d" % stats["messages_sent"])
	print("接收消息数: %d" % stats["messages_received"])
	print("平均消息大小: %d字节" % stats["avg_message_size"])

	print("\n【数据统计】")
	print("发送数据: %.2f KB" % bandwidth["sent_kb"])
	print("接收数据: %.2f KB" % bandwidth["received_kb"])
	print("总计: %.2f KB" % bandwidth["total_kb"])

	print("\n【消息类型统计】")
	var msg_stats = get_message_stats()
	for msg_type in msg_stats.keys():
		var counts = msg_stats[msg_type]
		print(" %s: 发送%d, 接收%d" % [msg_type, counts["sent"], counts["received"]])

	print("\n【连接统计】")
	print("断开次数: %d" % stats["disconnections"])

	print("\n════════════════════════════════════════\n")

func print_message_history() -> void:
	"""打印消息历史"""
	print("\n╔════════════════════════════════════════╗")
	print("║ 📝 最近消息历史 (最多%d条) ║" % _max_history)
	print("╚════════════════════════════════════════╝\n")

	if _message_history.is_empty():
		print("无消息记录\n")
		return

	for i in range(_message_history.size() - 1, max(-1, _message_history.size() - 20), -1):
		var msg = _message_history[i]
		var direction = "→" if msg["direction"] == "SEND" else "←"
		print("[%s] %s %s (%d字节)" % [
			msg["timestamp"],
			direction,
			msg["type"],
			msg["size"]
		])

	print("\n════════════════════════════════════════\n")

func print_debug_info() -> void:
	"""打印完整调试信息"""
	print_network_report()
	print_message_history()

	print("\n╔════════════════════════════════════════╗")
	print("║ 📋 日志信息 ║")
	print("╚════════════════════════════════════════╝\n")

	print("总日志条数: %d" % _log_buffer.size())

	var error_count = 0
	var warn_count = 0
	for log in _log_buffer:
		if log["level"] == "ERROR":
			error_count += 1
		elif log["level"] == "WARN":
			warn_count += 1

	print("错误数: %d" % error_count)
	print("警告数: %d" % warn_count)

	print("\n════════════════════════════════════════\n")

# ==================== 配置 ====================

func set_log_level(level: int) -> void:
	"""设置日志级别 (0=DEBUG, 1=INFO, 2=WARN, 3=ERROR)"""
	_log_level = level
	log_info("日志级别已设置: %d" % level, "Debugger")

func enable_logging(enabled: bool) -> void:
	"""启用/禁用日志"""
	_enable_logging = enabled

func set_max_log_size(size: int) -> void:
	"""设置最大日志大小"""
	_max_log_size = size
