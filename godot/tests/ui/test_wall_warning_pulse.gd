extends GutTest

# CenterInfoPanel 牌墙 ≤10 时启脉冲 tween;>10 时停。商业 polish。

const CENTER := preload("res://ui/four_player_table/center_info_panel.tscn")


func _make_panel() -> CenterInfoPanel:
	var p: CenterInfoPanel = CENTER.instantiate()
	add_child_autofree(p)
	return p


# 初始(70 → 50)不应启脉冲
func test_high_wall_no_pulse() -> void:
	var p := _make_panel()
	await get_tree().process_frame
	p.set_wall_remaining(70)
	p.set_wall_remaining(50)
	assert_true(p._wall_pulse_tween == null or not p._wall_pulse_tween.is_valid(),
		"wall>10 不应启脉冲")


# 跌进警戒区(70 → 10)启脉冲
func test_low_wall_starts_pulse() -> void:
	var p := _make_panel()
	await get_tree().process_frame
	p.set_wall_remaining(70)
	p.set_wall_remaining(10)
	assert_true(p._wall_pulse_tween != null and p._wall_pulse_tween.is_valid(),
		"wall≤10 应启脉冲")


# 已在脉冲(10 → 5)不应重新创建 tween
func test_continued_low_wall_keeps_tween() -> void:
	var p := _make_panel()
	await get_tree().process_frame
	p.set_wall_remaining(10)
	var t1 = p._wall_pulse_tween
	p.set_wall_remaining(5)
	var t2 = p._wall_pulse_tween
	assert_eq(t1, t2, "持续在警戒区不应重启 tween")


# 出警戒区(5 → 70 新局)停脉冲,modulate.a 复 1.0
func test_exit_warning_kills_pulse() -> void:
	var p := _make_panel()
	await get_tree().process_frame
	p.set_wall_remaining(5)
	assert_true(p._wall_pulse_tween != null and p._wall_pulse_tween.is_valid())
	p.set_wall_remaining(70)
	assert_true(p._wall_pulse_tween == null or not p._wall_pulse_tween.is_valid(),
		"出警戒区应 kill tween")
	assert_eq(p._label_wall.modulate.a, 1.0, "modulate.a 应复 1.0")


# 边界:刚好 11 不触发
func test_threshold_boundary_11_no_pulse() -> void:
	var p := _make_panel()
	await get_tree().process_frame
	p.set_wall_remaining(11)
	assert_true(p._wall_pulse_tween == null or not p._wall_pulse_tween.is_valid())


# 边界:刚好 10 触发
func test_threshold_boundary_10_pulse() -> void:
	var p := _make_panel()
	await get_tree().process_frame
	p.set_wall_remaining(10)
	assert_true(p._wall_pulse_tween != null and p._wall_pulse_tween.is_valid())
