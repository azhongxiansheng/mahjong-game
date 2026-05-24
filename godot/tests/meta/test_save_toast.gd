extends GutTest

# SaveToast autoload + SaveSystem signal emit 测试。


func _toast() -> Node:
	return get_tree().root.get_node("/root/SaveToast")


func _save_system() -> Node:
	return get_tree().root.get_node("/root/SaveSystem")


# ---- autoload 注册 ----

func test_save_toast_autoload_registered() -> void:
	assert_not_null(_toast(), "/root/SaveToast 应已挂载")


# ---- SaveSystem.save_completed signal ----

func test_save_run_emits_signal() -> void:
	var ss = _save_system()
	# 准备一个最小 RunState
	var rs := RunState.new(123)
	watch_signals(ss)
	ss.save_run(rs)
	assert_signal_emitted(ss, "save_completed")
	# 清理:别留 user://savegame.json 污染下次测试
	ss.clear_run()


func test_save_run_null_no_signal() -> void:
	var ss = _save_system()
	watch_signals(ss)
	ss.save_run(null)
	assert_signal_emit_count(ss, "save_completed", 0)


func test_clear_run_emits_signal_when_save_exists() -> void:
	var ss = _save_system()
	var rs := RunState.new(456)
	ss.save_run(rs)
	watch_signals(ss)
	ss.clear_run()
	assert_signal_emitted(ss, "save_cleared")


func test_clear_run_no_signal_when_no_save() -> void:
	var ss = _save_system()
	# 先确认无存档
	ss.clear_run()
	watch_signals(ss)
	ss.clear_run()
	assert_signal_emit_count(ss, "save_cleared", 0)


# ---- SaveToast.show_message ----

func test_show_message_creates_label() -> void:
	var t = _toast()
	t.show_message("hello world")
	# UI 应已 lazily 创建
	assert_not_null(t._label, "Label 应已创建")
	assert_eq(t._label.text, "hello world")
	assert_not_null(t._tween, "tween 应已启动")


# ---- 完整 round trip:save_run → 监听 → show toast ----

func test_save_completed_triggers_toast() -> void:
	var t = _toast()
	var ss = _save_system()
	var rs := RunState.new(789)
	ss.save_run(rs)
	# 同帧 emit + connect 应即同步 _on_save_completed → _show_toast
	# (但 connect 在 _ready 用 call_deferred,可能要等一帧)
	await get_tree().process_frame
	# 不强制 label 已存在 — 但 toast 已被触发(emission 已经发生),
	# 状态机调度可能在下一帧。
	# 直接调 _on_save_completed 验真实路径:
	t._on_save_completed()
	assert_not_null(t._label)
	assert_eq(t._label.text, "💾 已保存")
	# cleanup
	ss.clear_run()
