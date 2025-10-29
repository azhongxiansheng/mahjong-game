# 异步听牌检查器 - 在后台线程执行听牌检查
class_name AsyncTingChecker

var _pending_tasks: Array = []
const TASK_TIMEOUT_MS = 5000

# 异步检查听牌
func check_ting_async(hand: CardHand, callback: Callable) -> void:
	if hand == null:
		callback.call([])
		return
	
	var task = {
		"hand": hand,
		"callback": callback,
		"thread": null,
		"result": null,
		"completed": false,
		"start_time": Time.get_ticks_msec()
	}
	
	_pending_tasks.append(task)
	
	var thread = Thread.new(_execute_check)
	if thread:
		task["thread"] = thread
		thread.start.call_deferred("_on_thread_start", task)
	else:
		_execute_check_sync(task)

# 后台线程执行检查
func _execute_check(task: Dictionary) -> void:
	var hand = task["hand"]
	var result = WinChecker.check_can_hear(hand)
	
	task["result"] = result
	task["completed"] = true

# 线程开始回调
func _on_thread_start(task: Dictionary) -> void:
	_wait_for_task(task)

# 同步执行检查
func _execute_check_sync(task: Dictionary) -> void:
	var hand = task["hand"]
	var result = WinChecker.check_can_hear(hand)
	
	task["result"] = result
	task["completed"] = true
	
	call_deferred("_invoke_callback", task)

# 等待任务完成
func _wait_for_task(task: Dictionary) -> void:
	var start_time = Time.get_ticks_msec()
	
	while not task["completed"]:
		if Time.get_ticks_msec() - start_time > TASK_TIMEOUT_MS:
			print("[错误] 异步听牌检查超时!")
			task["result"] = []
			task["completed"] = true
			break
		
		OS.delay_msec(1)
	
	call_deferred("_invoke_callback", task)

# 在主线程调用回调
func _invoke_callback(task: Dictionary) -> void:
	if task["callback"].is_valid():
		var result = task["result"] if task["result"] != null else []
		task["callback"].call(result)
	
	_pending_tasks.erase(task)
	
	if task["thread"] != null:
		var thread: Thread = task["thread"]
		if thread.is_alive():
			thread.wait_to_finish()

# 获取待处理任务数
func get_pending_tasks() -> int:
	return _pending_tasks.size()

# 取消所有任务
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
