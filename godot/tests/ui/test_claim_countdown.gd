extends GutTest

# 雀魂式鸣牌响应倒计时：超时自动 skip

const ACTION_PANEL := preload("res://ui/four_player_table/player_action_panel.tscn")


func test_claim_starts_countdown() -> void:
	var p: PlayerActionPanel = ACTION_PANEL.instantiate()
	add_child_autofree(p)
	await get_tree().process_frame
	p.enter_waiting_claim(true, false, false, false, 1)
	assert_true(p.is_countdown_active(), "鸣牌窗口应启动倒计时")
	assert_gt(p.get_countdown_remaining(), 0.0)


func test_claim_timeout_emits_skip() -> void:
	var p: PlayerActionPanel = ACTION_PANEL.instantiate()
	add_child_autofree(p)
	await get_tree().process_frame
	p.CLAIM_TIMEOUT_SEC = 0.05
	var box: Array = [{}]  # lambda 捕获需可变容器
	p.player_action_chosen.connect(func(c): box[0] = c)
	p.enter_waiting_claim(true, false, true, false, 2)
	await get_tree().create_timer(0.15).timeout
	assert_eq(String(box[0].get("action", "")), "skip", "超时应自动见逃")
	assert_false(p.is_countdown_active())


func test_button_press_cancels_countdown() -> void:
	var p: PlayerActionPanel = ACTION_PANEL.instantiate()
	add_child_autofree(p)
	await get_tree().process_frame
	p.CLAIM_TIMEOUT_SEC = 5.0
	var box: Array = [{}]
	p.player_action_chosen.connect(func(c): box[0] = c)
	p.enter_waiting_claim(true, false, false, false, 1)
	p._on_btn_ron()
	assert_eq(String(box[0].get("action", "")), "ron")
	assert_false(p.is_countdown_active(), "点按钮后倒计时应停")


func test_idle_stops_countdown() -> void:
	var p: PlayerActionPanel = ACTION_PANEL.instantiate()
	add_child_autofree(p)
	await get_tree().process_frame
	p.enter_waiting_claim(false, true, false, false, 3)
	assert_true(p.is_countdown_active())
	p.enter_idle("等待 AI…")
	assert_false(p.is_countdown_active())
