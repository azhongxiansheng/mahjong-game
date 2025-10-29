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

	# 使用 call_deferred 在后台执行
	call_deferred("_execute_check_deferred", task)

# 在后台执行检查 (通过 call_deferred)
func _execute_check_deferred(task: Dictionary) -> void:
	var hand = task["hand"]
	var result = WinChecker.check_can_hear(hand)

	task["result"] = result
	task["completed"] = true

	call_deferred("_invoke_callback", task)

# 在主线程调用回调
func _invoke_callback(task: Dictionary) -> void:
	if task["callback"].is_valid():
		var result = task["result"] if task["result"] != null else []
		task["callback"].call(result)

	_pending_tasks.erase(task)

# 获取待处理任务数
func get_pending_tasks() -> int:
	return _pending_tasks.size()

# 取消所有任务
func cancel_all_tasks() -> void:
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
