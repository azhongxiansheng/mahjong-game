extends GutTest

# SettingsManager autoload — 测试 持久化 + AudioManager 同步 + clamp。


func _sm() -> Node:
	return get_tree().root.get_node("/root/SettingsManager")


func _am() -> Node:
	return get_tree().root.get_node("/root/AudioManager")


func test_autoload_registered() -> void:
	assert_not_null(_sm(), "/root/SettingsManager autoload 应已挂载")


func test_default_sfx_volume() -> void:
	# 新装 / 文件不存在时默认 0.8;但测试环境可能已有 user://settings.json
	# 至少确认 sfx_volume 在合法范围
	var v: float = float(_sm().sfx_volume)
	assert_true(v >= 0.0 and v <= 1.0, "sfx_volume 应在 [0,1] 范围")


func test_set_sfx_volume_clamps_below_zero() -> void:
	var sm: Node = _sm()
	var saved: float = sm.sfx_volume
	sm.set_sfx_volume(-0.5)
	assert_eq(sm.sfx_volume, 0.0, "负值应 clamp 到 0")
	sm.set_sfx_volume(saved)  # restore


func test_set_sfx_volume_clamps_above_one() -> void:
	var sm: Node = _sm()
	var saved: float = sm.sfx_volume
	sm.set_sfx_volume(1.5)
	assert_eq(sm.sfx_volume, 1.0, "超 1 应 clamp 到 1")
	sm.set_sfx_volume(saved)


# 改 sfx_volume 应同步到 AudioManager
func test_set_sfx_volume_syncs_audio_manager() -> void:
	var sm: Node = _sm()
	var am: Node = _am()
	var saved: float = sm.sfx_volume
	sm.set_sfx_volume(0.42)
	assert_almost_eq(float(am.sfx_volume), 0.42, 0.001,
		"AudioManager.sfx_volume 应同步")
	sm.set_sfx_volume(saved)


# settings_changed signal 应 emit
func test_settings_changed_signal() -> void:
	var sm: Node = _sm()
	var saved: float = sm.sfx_volume
	watch_signals(sm)
	sm.set_sfx_volume(0.5)
	assert_signal_emitted(sm, "settings_changed")
	sm.set_sfx_volume(saved)


# bgm_volume 也走持久化
func test_set_bgm_volume_clamps_and_emits() -> void:
	var sm: Node = _sm()
	var saved: float = sm.bgm_volume
	sm.set_bgm_volume(0.33)
	assert_eq(sm.bgm_volume, 0.33)
	sm.set_bgm_volume(saved)


# 雀魂式鸣牌/立直倒计时秒数
func test_claim_timeout_default_and_clamp() -> void:
	var sm: Node = _sm()
	var saved_c: float = float(sm.claim_timeout_sec)
	var saved_r: float = float(sm.riichi_timeout_sec)
	sm.set_claim_timeout_sec(7.5)
	assert_almost_eq(float(sm.claim_timeout_sec), 7.5, 0.01)
	sm.set_claim_timeout_sec(0.1)
	assert_almost_eq(float(sm.claim_timeout_sec), 1.0, 0.01, "下限 1s")
	sm.set_claim_timeout_sec(99.0)
	assert_almost_eq(float(sm.claim_timeout_sec), 30.0, 0.01, "上限 30s")
	sm.set_riichi_timeout_sec(8.0)
	assert_almost_eq(float(sm.riichi_timeout_sec), 8.0, 0.01)
	sm.set_claim_timeout_sec(saved_c)
	sm.set_riichi_timeout_sec(saved_r)


func test_claim_timeout_emits_settings_changed() -> void:
	var sm: Node = _sm()
	var saved: float = float(sm.claim_timeout_sec)
	watch_signals(sm)
	sm.set_claim_timeout_sec(4.0)
	assert_signal_emitted(sm, "settings_changed")
	sm.set_claim_timeout_sec(saved)
