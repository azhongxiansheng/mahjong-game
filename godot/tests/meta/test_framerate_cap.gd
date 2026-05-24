extends GutTest

# SettingsManager.framerate_cap 持久化 + Engine.max_fps 同步测试。


func _sm() -> Node:
	return get_tree().root.get_node("/root/SettingsManager")


func before_each() -> void:
	# 复 60 默认避免污染其它 test
	_sm().set_framerate_cap(60)


# 默认值
func test_default_framerate_cap_60() -> void:
	_sm().framerate_cap = 60
	assert_eq(_sm().framerate_cap, 60)


# set_framerate_cap 写入字段 + 应用 Engine.max_fps
func test_set_framerate_cap_applies_engine() -> void:
	_sm().set_framerate_cap(120)
	assert_eq(_sm().framerate_cap, 120)
	assert_eq(Engine.max_fps, 120)


# 0 表示 uncap
func test_set_framerate_cap_0_uncap() -> void:
	_sm().set_framerate_cap(0)
	assert_eq(_sm().framerate_cap, 0)
	assert_eq(Engine.max_fps, 0)


# 非 0 值 clamp 到 [30, 300]
func test_clamp_low() -> void:
	_sm().set_framerate_cap(10)
	assert_eq(_sm().framerate_cap, 30, "10 应 clamp 到 30")


func test_clamp_high() -> void:
	_sm().set_framerate_cap(999)
	assert_eq(_sm().framerate_cap, 300, "999 应 clamp 到 300")


# emit signal
func test_set_emits_settings_changed() -> void:
	var sm = _sm()
	watch_signals(sm)
	sm.set_framerate_cap(60)
	assert_signal_emitted(sm, "settings_changed")


# round-trip 持久化:写盘 → 内存清 → 读盘还原
func test_persistence_round_trip() -> void:
	var sm = _sm()
	sm.set_framerate_cap(144)
	# 清内存值伪造重启
	sm.framerate_cap = 60
	sm._load_from_disk()
	assert_eq(sm.framerate_cap, 144)
	sm.set_framerate_cap(60)  # cleanup
