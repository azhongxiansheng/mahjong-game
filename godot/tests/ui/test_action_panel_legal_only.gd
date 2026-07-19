extends GutTest

# 操作栏：仅显示合法动作（气泡式），非法按钮不可见

const ACTION_PANEL := preload("res://ui/four_player_table/player_action_panel.tscn")


func _count_visible(p: PlayerActionPanel) -> int:
	var n := 0
	for btn in [p._btn_riichi, p._btn_tsumo, p._btn_ron, p._btn_chi, p._btn_pon,
			p._btn_minkan, p._btn_kyuusyu, p._btn_ankan, p._btn_added_kan,
			p._btn_consumable, p._btn_skip]:
		if btn != null and btn.visible:
			n += 1
	return n


func test_claim_only_shows_legal_buttons() -> void:
	var p: PlayerActionPanel = ACTION_PANEL.instantiate()
	add_child_autofree(p)
	await get_tree().process_frame
	p.enter_waiting_claim(true, false, true, false, 2)
	assert_true(p._btn_ron.visible)
	assert_true(p._btn_pon.visible)
	assert_true(p._btn_skip.visible)
	assert_false(p._btn_chi.visible)
	assert_false(p._btn_minkan.visible)
	assert_false(p._btn_tsumo.visible)
	assert_eq(_count_visible(p), 3, "荣+碰+跳过 = 3")


func test_discard_no_actions_hides_bar() -> void:
	var p: PlayerActionPanel = ACTION_PANEL.instantiate()
	add_child_autofree(p)
	await get_tree().process_frame
	p.enter_waiting_discard(false, false, false, false)
	assert_eq(_count_visible(p), 0)
	assert_false(p._bg.visible, "无合法按钮时底栏隐藏")
	assert_true(p._label_status.visible)


func test_riichi_confirm_shows_two() -> void:
	var p: PlayerActionPanel = ACTION_PANEL.instantiate()
	add_child_autofree(p)
	await get_tree().process_frame
	p.enter_waiting_riichi_confirm()
	assert_true(p._btn_riichi.visible)
	assert_true(p._btn_skip.visible)
	assert_eq(_count_visible(p), 2)
