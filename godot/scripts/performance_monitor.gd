class_name PerformanceMonitor
extends Node

# 性能指标
var fps: int = 0
var frame_time: float = 0.0
var memory_usage: float = 0.0
var draw_calls: int = 0

# 性能历史
var fps_history: Array = []
var frame_time_history: Array = []

const MAX_HISTORY = 60

func _process(_delta: float) -> void:
	"""每帧更新性能指标"""
	update_metrics()

func update_metrics() -> void:
	"""更新性能指标"""
	# FPS计算
	fps = int(Engine.get_frames_per_second())
	
	# 帧时间
	frame_time = Engine.get_process_frame_time() * 1000.0  # 转换为毫秒
	
	# 内存使用
	var memory_info = OS.get_static_memory_usage()
	memory_usage = float(memory_info) / (1024 * 1024)  # 转换为MB
	
	# 添加到历史
	add_to_history(fps, frame_time)
	
	# 性能检查
	check_performance()

func add_to_history(fps_val: int, frame_time_val: float) -> void:
	"""添加到历史记录"""
	fps_history.append(fps_val)
	frame_time_history.append(frame_time_val)
	
	# 限制历史大小
	if fps_history.size() > MAX_HISTORY:
		fps_history.pop_front()
		frame_time_history.pop_front()

func check_performance() -> void:
	"""检查性能"""
	# 检查FPS是否过低
	if fps < 30:
		print("⚠️ 性能警告: FPS低于30 (当前: ", fps, ")")
	
	# 检查帧时间是否过长
	if frame_time > 33.0:  # 30 FPS = 33ms
		print("⚠️ 性能警告: 帧时间过长 (", int(frame_time), "ms)")
	
	# 检查内存
	if memory_usage > 500.0:  # 500MB
		print("⚠️ 内存使用过高 (", int(memory_usage), "MB)")

func get_average_fps() -> int:
	"""获取平均FPS"""
	if fps_history.is_empty():
		return 0
	
	var total = 0
	for f in fps_history:
		total += f
	
	return total / fps_history.size()

func get_average_frame_time() -> float:
	"""获取平均帧时间"""
	if frame_time_history.is_empty():
		return 0.0
	
	var total = 0.0
	for t in frame_time_history:
		total += t
	
	return total / frame_time_history.size()

func print_performance_report() -> void:
	"""打印性能报告"""
	print("\n========== 性能报告 ==========")
	print("当前FPS: ", fps)
	print("平均FPS: ", get_average_fps())
	print("当前帧时间: ", int(frame_time), "ms")
	print("平均帧时间: ", int(get_average_frame_time()), "ms")
	print("内存使用: ", int(memory_usage), "MB")
	print("===============================\n")

func optimize_graphics() -> void:
	"""优化图形设置"""
	print("✓ 应用图形优化...")
	
	# 减少阴影质量
	RenderingServer.global_shader_parameter_set("shadow_quality", 0.5)
	
	# 禁用某些特效
	RenderingServer.global_shader_parameter_set("effects_enabled", false)
	
	print("✓ 图形优化已应用")

func enable_debug_mode() -> void:
	"""启用调试模式"""
	print("✓ 调试模式已启用")
	set_process(true)
