class_name GameDebug
extends Node

# 调试标志
var debug_enabled: bool = false
var show_fps: bool = false
var show_debug_info: bool = false

# 性能数据
var start_time: float = 0.0
var frame_count: int = 0
var fps_array: Array = []

func _ready() -> void:
	print("========== 游戏调试系统初始化 ==========")
	debug_enabled = true
	start_time = Time.get_ticks_msec()
	print("✓ 调试系统已启用")

func _process(_delta: float) -> void:
	if debug_enabled:
		frame_count += 1
		if frame_count % 60 == 0:  # 每60帧检查一次
			update_debug_info()

func update_debug_info() -> void:
	"""更新调试信息"""
	var current_time = Time.get_ticks_msec()
	var elapsed = (current_time - start_time) / 1000.0
	var current_fps = int(frame_count / elapsed)
	
	fps_array.append(current_fps)
	if fps_array.size() > 10:
		fps_array.pop_front()

func print_debug_info() -> void:
	"""打印调试信息"""
	print("\n========== 调试信息 ==========")
	print("帧数: ", frame_count)
	print("运行时间: ", int(Time.get_ticks_msec() - start_time), "ms")
	
	if fps_array.size() > 0:
		var avg_fps = 0
		for fps in fps_array:
			avg_fps += fps
		avg_fps /= fps_array.size()
		print("平均FPS: ", avg_fps)
	
	print("=============================\n")

func validate_game_state(game_integration: GameIntegration) -> bool:
	"""验证游戏状态"""
	print("\n========== 游戏状态验证 ==========")
	
	var is_valid = true
	
	# 检查手牌
	if game_integration.current_hand.size() < 13 or game_integration.current_hand.size() > 14:
		print("✗ 手牌数量异常: ", game_integration.current_hand.size())
		is_valid = false
	else:
		print("✓ 手牌数量正常: ", game_integration.current_hand.size())
	
	# 检查游戏状态
	if game_integration.is_game_running:
		print("✓ 游戏运行中")
	else:
		print("⚠ 游戏未运行")
	
	# 检查卡牌数据
	for i in range(game_integration.current_hand.size()):
		var card = game_integration.current_hand[i]
		if not ("suit" in card and "number" in card):
			print("✗ 卡牌数据不完整 (索引: ", i, ")")
			is_valid = false
	
	if is_valid:
		print("✓ 所有验证通过")
	
	print("==========================\n")
	return is_valid

func profile_function(func_name: String, callable_func: Callable) -> void:
	"""对函数进行性能分析"""
	var start = Time.get_ticks_usec()
	callable_func.call()
	var elapsed = (Time.get_ticks_usec() - start) / 1000.0
	
	print("[性能分析] ", func_name, " 耗时: ", int(elapsed), "ms")

func print_performance_stats() -> void:
	"""打印性能统计"""
	print("\n========== 性能统计 ==========")
	print("总帧数: ", frame_count)
	
	var memory = OS.get_static_memory_usage() / (1024 * 1024)
	print("内存使用: ", int(memory), "MB")
	
	print("===============================\n")

func enable_debug_visualization() -> void:
	"""启用调试可视化"""
	print("✓ 调试可视化已启用")
	show_debug_info = true

func disable_debug_visualization() -> void:
	"""禁用调试可视化"""
	print("✓ 调试可视化已禁用")
	show_debug_info = false

func toggle_fps_display() -> void:
	"""切换FPS显示"""
	show_fps = !show_fps
	if show_fps:
		print("✓ FPS显示已启用")
	else:
		print("✓ FPS显示已禁用")
