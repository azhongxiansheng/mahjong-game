# 异步听牌检查器
# 用于在后台线程执行听牌检查，不阻塞UI
#
# 用法:
#   var async_checker = AsyncTingChecker.new()
#   async_checker.check_ting_async(hand, func(result):
#       print("听牌结果: ", result)
#   )

extends Node
class_name AsyncTingChecker

# 正在进行的检查任务列表
var _pending_tasks: Array = []

# 任务超时时间 (毫秒)
const TASK_TIMEOUT_MS = 5000

# ========================
# 主要API方法
# ========================

# 异步检查听牌
# hand: 手牌
# callback: 完成时的回调函数 func(ting_cards: Array)
func check_ting_async(hand: CardHand, callback: Callable) -> void:
	if hand == null:
		callback.call([])
		return
	
	# 创建任务
	var task = {
		"hand": hand,
		"callback": callback,
		"thread": null,
		"result": null,
		"completed": false,
		"start_time": Time.get_ticks_msec()
	}
	
	_pending_tasks.append(task)
	
	# 在后台线程执行
	var thread = Thread.new(_execute_check)
	if thread:
		task["thread"] = thread
		thread.start.call_deferred("_on_thread_start", task)
	else:
		# 如果线程创建失败，直接在主线程执行
		_execute_check_sync(task)

# ========================
# 私有方法
# ========================

# 后台线程执行检查
func _execute_check(task: Dictionary) -> void:
	var hand = task["hand"]
	var result = WinChecker.check_can_hear(hand)
	
	# 存储结果并标记为完成
	task["result"] = result
	task["completed"] = true

# 线程开始回调
func _on_thread_start(task: Dictionary) -> void:
	# 等待线程完成
	_wait_for_task(task)

# 同步执行检查 (如果线程创建失败的备选方案)
func _execute_check_sync(task: Dictionary) -> void:
	var hand = task["hand"]
	var result = WinChecker.check_can_hear(hand)
	
	task["result"] = result
	task["completed"] = true
	
	# 立即调用回调
	call_deferred("_invoke_callback", task)

# 等待任务完成
func _wait_for_task(task: Dictionary) -> void:
	var start_time = Time.get_ticks_msec()
	
	# 轮询检查任务是否完成
	while not task["completed"]:
		# 检查超时
		if Time.get_ticks_msec() - start_time > TASK_TIMEOUT_MS:
			print("[错误] 异步听牌检查超时!")
			task["result"] = []
			task["completed"] = true
			break
		
		# 短暂睡眠以避免忙轮询
		OS.delay_msec(1)
	
	# 回到主线程调用回调
	call_deferred("_invoke_callback", task)

# 在主线程调用回调
func _invoke_callback(task: Dictionary) -> void:
	if task["callback"].is_valid():
		var result = task["result"] if task["result"] != null else []
		task["callback"].call(result)
	
	# 清理完成的任务
	_pending_tasks.erase(task)
	
	# 清理线程
	if task["thread"] != null:
		var thread: Thread = task["thread"]
		if thread.is_alive():
			thread.wait_to_finish()

# ========================
# 监控和调试方法
# ========================

# 获取当前待处理任务数
func get_pending_tasks() -> int:
	return _pending_tasks.size()

# 取消所有待处理任务
func cancel_all_tasks() -> void:
	for task in _pending_tasks:
		if task["thread"] != null and task["thread"].is_alive():
			task["thread"].wait_to_finish()
	_pending_tasks.clear()

# 打印任务状态
func print_status() -> void:
	print("\n=== 异步检查器状态 ===")
	print("待处理任务数: %d" % _pending_tasks.size())
	
	for i in range(_pending_tasks.size()):
		var task = _pending_tasks[i]
		var elapsed = Time.get_ticks_msec() - task["start_time"]
		var status = "完成" if task["completed"] else "进行中"
		print("  任务%d: %s (耗时: %dms)" % [i + 1, status, elapsed])
