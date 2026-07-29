extends GutTest

# Issue #304：原创“结界舞台 HUD”产品契约。
# 这些断言只约束可读性、安全区与真实生产路径，不锁第三方像素布局。

const TABLE_SCENE := preload("res://ui/four_player_table/four_player_table.tscn")
const PLAYABLE_SCENE := preload("res://ui/four_player_table/playable_table.tscn")


func _overlaps(a: Rect2, b: Rect2) -> bool:
	return a.intersects(b, false)


func test_original_layout_defines_four_hud_safe_zones_and_fixed_ritual_band() -> void:
	assert_eq(TableLayout.SEAT_HUD_RECTS.size(), 4)
	for seat_id in range(4):
		var rect: Rect2 = TableLayout.SEAT_HUD_RECTS[seat_id]
		assert_true(Rect2(Vector2.ZERO, Vector2(1600, 900)).encloses(rect),
			"seat %d HUD 必须留在 1600×900" % seat_id)
	assert_eq(TableLayout.ACTION_BAR_RECT, Rect2(440, 680, 720, 78))
	assert_lte(TableLayout.ACTION_BAR_RECT.end.y, 758.0)
	assert_gte(TableLayout.HAND_SAFE_RECT.position.y, 778.0)
	assert_false(_overlaps(TableLayout.ACTION_BAR_RECT, TableLayout.HAND_SAFE_RECT))


func test_most_crowded_geometry_keeps_hud_rivers_melds_actions_and_result_clear() -> void:
	var crowded: Array[Rect2] = TableLayout.crowded_state_rects()
	assert_eq(crowded.size(), 4, "四席最大河/副露必须都有几何契约")
	for seat_id in range(4):
		var public_zone: Rect2 = crowded[seat_id]
		assert_false(_overlaps(public_zone, TableLayout.SEAT_HUD_RECTS[seat_id]),
			"seat %d 最大河/副露不得压 HUD" % seat_id)
		assert_false(_overlaps(public_zone, TableLayout.ACTION_BAR_RECT),
			"seat %d 最大河/副露不得压操作带" % seat_id)
	assert_false(_overlaps(TableLayout.RESULT_PANEL_RECT, TableLayout.HAND_SAFE_RECT))
	assert_false(_overlaps(TableLayout.RESULT_PANEL_RECT, TableLayout.ACTION_BAR_RECT))


func test_production_table_builds_original_stage_four_huds_and_ritual_band() -> void:
	var playable := PLAYABLE_SCENE.instantiate() as PlayableTable
	add_child_autofree(playable)
	await get_tree().process_frame
	assert_true(playable._table is FourPlayerTable)
	assert_null(playable._table.get_node_or_null("TableStage/BarrierField"))
	assert_not_null(playable._table.get_node_or_null("TableStage/TableRails"),
		"生产牌桌必须挂载参考项目的左右斜木沿")
	assert_eq(playable._table.seat_panels.size(), 4)
	for seat_id in range(4):
		var hud: Node = playable._table.seat_panels[seat_id].get_node_or_null("SeatHUD")
		assert_not_null(hud, "seat %d 应有悬浮 HUD" % seat_id)
	assert_not_null(playable._action_panel.get_node_or_null("RitualBand"))
	assert_false((playable._action_panel.get_node("RitualBand") as Control).visible,
		"无合法动作时不得显示空仪式带")
	assert_eq(playable._action_panel.position, TableLayout.ACTION_BAR_RECT.position)
	assert_eq(playable._action_panel.size, TableLayout.ACTION_BAR_RECT.size)
	playable._action_panel.enter_waiting_claim(true, true, true, true, 1)
	assert_true((playable._action_panel.get_node("RitualBand") as Control).visible)
	assert_true(playable._action_panel._label_status.text.contains("荣和/吃/碰/杠"))


func test_claim_candidate_cancel_uses_existing_production_signal() -> void:
	var playable := PLAYABLE_SCENE.instantiate() as PlayableTable
	add_child_autofree(playable)
	await get_tree().process_frame
	var choices: Array[Dictionary] = []
	playable._action_panel.player_action_chosen.connect(
		func(choice: Dictionary) -> void: choices.append(choice))
	playable._action_panel.enter_waiting_claim(true, true, true, true, 1)
	playable._action_panel._btn_skip.pressed.emit()
	await get_tree().process_frame
	assert_eq(choices, [{"action": "skip"}],
		"候选取消必须沿用原有业务 choice，不改协议")


func test_real_playable_table_keeps_real_tile_texture_and_red_dora_contract() -> void:
	var playable := PLAYABLE_SCENE.instantiate() as PlayableTable
	add_child_autofree(playable)
	var bc := BattleController.new(42, 0, false, TileId.E)
	playable._table.bind_battle_state(bc.state, 0, 4)
	await get_tree().process_frame
	var player := playable._table.seat_panels[0] as SeatPanel
	assert_gt(player._hand_slots.size(), 0)
	var tile := player._hand_slots[0].get_node("Tile") as CardTileBack
	assert_not_null(tile)
	assert_eq(tile.modulate, Color.WHITE)
	assert_not_null(tile._face_atlas_tex, "生产手牌必须加载真实牌面纹理")
	assert_eq(CardTileBack.tile_id_to_atlas_key(TileId.W5, true), "0m")
	assert_eq(CardTileBack.tile_id_to_atlas_key(TileId.T5, true), "0p")
	assert_eq(CardTileBack.tile_id_to_atlas_key(TileId.S5, true), "0s")


func test_tile_candidate_selected_and_disabled_states_are_not_color_only() -> void:
	var tile := CardTileBack.new()
	add_child_autofree(tile)
	tile.set_face_up(TileId.W5)
	tile.set_clickable(true)
	await get_tree().process_frame
	var candidate := tile.get_node_or_null("CandidateBrackets") as Control
	assert_not_null(candidate)
	assert_true(candidate.visible)
	tile.set_lifted(true)
	var selected := tile.get_node_or_null("SelectedSeal") as Control
	assert_not_null(selected)
	assert_true(selected.visible)
	tile.set_dim(true)
	var disabled := tile.get_node_or_null("DisabledHatch") as Control
	assert_not_null(disabled)
	assert_true(disabled.visible)
	assert_eq(tile.modulate, Color.WHITE, "状态覆盖层不得染牌面")


func test_furiten_and_riichi_use_text_shape_and_position_not_color_alone() -> void:
	var table := TABLE_SCENE.instantiate() as FourPlayerTable
	add_child_autofree(table)
	await get_tree().process_frame
	var player := table.seat_panels[0] as SeatPanel
	player.set_furiten(true)
	player.set_riichi(true)
	await get_tree().process_frame
	var furiten := player.get_node_or_null("SeatHUD/StatusRow/FuritenBadge") as Control
	var riichi := player.get_node_or_null("SeatHUD/StatusRow/RiichiBadge") as Control
	assert_not_null(furiten)
	assert_not_null(riichi)
	if furiten == null or riichi == null:
		return
	assert_true((furiten.get_node("Label") as Label).text.contains("振听"))
	assert_true((riichi.get_node("Label") as Label).text.contains("立直"))
	assert_ne(furiten.position, riichi.position, "危险与宣告状态还须用位置区分")


func test_call_announce_safe_bands_do_not_cover_rivers_hand_or_actions() -> void:
	assert_false(CallAnnounce.WIN_SAFE_RECT.intersects(TableLayout.HAND_SAFE_RECT))
	assert_false(CallAnnounce.WIN_SAFE_RECT.intersects(TableLayout.ACTION_BAR_RECT))
	assert_lte(CallAnnounce.WIN_SAFE_RECT.end.y, 676.0,
		"高冲击窄带必须停在固定操作带上方")
	assert_lte(CallAnnounce.WIN_SAFE_RECT.size.x, 500.0)
	for public_zone in TableLayout.crowded_state_rects():
		assert_false(CallAnnounce.WIN_SAFE_RECT.intersects(public_zone, false),
			"和牌窄带不得遮住最大牌河/副露")
	for seat_id in range(4):
		var anchor: Vector2 = CallAnnounce.SEAT_LAYOUT[seat_id][0]
		var mark_rect := Rect2(anchor - CallAnnounce.CALL_MARK_SIZE / 2.0,
			CallAnnounce.CALL_MARK_SIZE)
		for public_zone in TableLayout.crowded_state_rects():
			assert_false(mark_rect.intersects(public_zone, false),
				"seat %d 普通鸣牌印记不得遮住最大牌河/副露" % seat_id)
		assert_false(mark_rect.intersects(TableLayout.ACTION_BAR_RECT, false))
		assert_false(mark_rect.intersects(TableLayout.HAND_SAFE_RECT, false))
	var host := Control.new()
	add_child_autofree(host)
	var avatar := load("res://assets/roguelike/characters/char_lingye.png") as Texture2D
	var call := CallAnnounce.play(host, &"pon", 1, avatar)
	assert_not_null(call)
	await get_tree().process_frame
	var avatar_node := call.get_node_or_null("Avatar") as TextureRect
	assert_not_null(avatar_node)
	if avatar_node != null:
		assert_lte(avatar_node.size.x, 48.0, "吃碰杠只保留短促席位印记")
		assert_lte(avatar_node.size.y, 48.0, "普通鸣牌不得展开角色大图")
