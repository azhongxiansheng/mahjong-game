extends GutTest

# SettingsManager.fullscreen 持久化测试。
# Headless 环境 DisplayServer 调用走 _apply_fullscreen 的 has_feature 检查会
# 早返,所以测试只验数据流 + signal,不验真实窗口切换。


func _sm() -> Node:
	return get_tree().root.get_node("/root/SettingsManager")


func before_each() -> void:
	_sm().set_fullscreen(false)


func test_default_false() -> void:
	assert_false(_sm().fullscreen)


func test_set_true() -> void:
	_sm().set_fullscreen(true)
	assert_true(_sm().fullscreen)


func test_set_false() -> void:
	_sm().set_fullscreen(true)
	_sm().set_fullscreen(false)
	assert_false(_sm().fullscreen)


func test_emits_signal() -> void:
	var sm = _sm()
	watch_signals(sm)
	sm.set_fullscreen(true)
	assert_signal_emitted(sm, "settings_changed")


# Round-trip 持久化
func test_persistence_round_trip() -> void:
	var sm = _sm()
	sm.set_fullscreen(true)
	sm.fullscreen = false  # 清内存伪装重启
	sm._load_from_disk()
	assert_true(sm.fullscreen)
	sm.set_fullscreen(false)  # cleanup
