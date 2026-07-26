extends GutTest

const PLAYABLE_TABLE := preload("res://ui/four_player_table/playable_table.gd")


func _announces(parent: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child in parent.get_children():
		if child is CallAnnounce:
			result.append(child)
	return result


func _direct_color_rect_count(parent: Node) -> int:
	return parent.get_children().filter(
		func(child: Node): return child is ColorRect).size()


func test_confirmed_win_kind_uses_explicit_flags_with_reference_priority() -> void:
	assert_eq(PLAYABLE_TABLE._confirmed_win_announce_kind({
		"is_tsumo": true,
		"is_chankan": true,
	}), &"tsumo", "自摸优先级最高")
	assert_eq(PLAYABLE_TABLE._confirmed_win_announce_kind({
		"is_tsumo": false,
		"is_chankan": true,
	}), &"chankan", "抢杠必须显示独立文案")
	assert_eq(PLAYABLE_TABLE._confirmed_win_announce_kind({
		"is_tsumo": false,
		"is_chankan": false,
	}), &"ron")


func test_candidate_ron_does_not_mount_announce_before_confirmation() -> void:
	var table := PLAYABLE_TABLE.new()
	add_child_autofree(table)
	table._handle_event_dramatic(BattleEvent.make(&"RON_DECLARED", 1, null, {
		"discarder_seat": 0,
		"is_chankan": true,
	}))
	assert_eq(_announces(table).size(), 0,
		"候选荣和可能被技能取消，确认前不得播 CallAnnounce")


func test_confirmed_chankan_mounts_reference_announce() -> void:
	var table := PLAYABLE_TABLE.new()
	add_child_autofree(table)
	table._handle_event_dramatic(BattleEvent.make(&"WIN_DECLARED", 1, null, {
		"is_tsumo": false,
		"is_chankan": true,
	}))
	var mounted := _announces(table)
	assert_eq(mounted.size(), 1)
	if mounted.is_empty():
		return
	var main_text := mounted[0].get_node_or_null("MainText") as Label
	assert_not_null(main_text)
	assert_eq(main_text.text, "抢杠")


func test_riichi_keeps_local_announce_without_full_table_flash_or_shake() -> void:
	var table := PLAYABLE_TABLE.new()
	add_child_autofree(table)
	var color_rects_before := _direct_color_rect_count(table)
	var position_before := table.position
	table._handle_event_dramatic(BattleEvent.make(&"RIICHI_DECLARED", 1))
	assert_eq(_announces(table).size(), 1, "立直使用局部 call-announce")
	assert_eq(_direct_color_rect_count(table), color_rects_before,
		"立直不得全屏白闪")
	await wait_seconds(0.04)
	assert_eq(table.position, position_before, "立直不得整桌 ScreenShake")


func test_raw_haitei_houtei_events_do_not_mount_unconfirmed_effects() -> void:
	for event_type in [&"HAITEI", &"HOUTEI"]:
		var table := PLAYABLE_TABLE.new()
		add_child_autofree(table)
		var color_rects_before := _direct_color_rect_count(table)
		var position_before := table.position
		table._handle_event_dramatic(BattleEvent.make(event_type, 0))
		assert_eq(_direct_color_rect_count(table), color_rects_before,
			"%s 候选事件不得全屏闪" % event_type)
		assert_null(table.get_node_or_null("MomentBand"),
			"特殊役横幅只来自确认 WIN_DECLARED" )
		await wait_seconds(0.04)
		assert_eq(table.position, position_before,
			"%s 候选事件不得整桌震动" % event_type)
		table.queue_free()
		await get_tree().process_frame


func test_confirmed_special_yaku_mounts_safe_narrow_moment_band() -> void:
	var table := PLAYABLE_TABLE.new()
	add_child_autofree(table)
	table._handle_event_dramatic(BattleEvent.make(&"WIN_DECLARED", 0, null, {
		"is_tsumo": true,
		"yaku_names": [{"name": "海底捞月", "han": 1}],
	}))
	var band := table.get_node_or_null("MomentBand") as Control
	assert_not_null(band)
	if band == null:
		return
	assert_eq(band.position, Vector2(PlayableTable.MOMENT_BAND_X,
		PlayableTable.MOMENT_BAND_Y))
	assert_eq(band.size, Vector2(PlayableTable.MOMENT_BAND_W,
		PlayableTable.MOMENT_BAND_H))
	assert_lte(band.get_rect().end.y, TableLayout.ACTION_BAR_RECT.position.y)
	for public_zone in TableLayout.crowded_state_rects():
		assert_false(band.get_rect().intersects(public_zone, false),
			"特殊役窄带不得遮住最大牌河/副露")
	assert_eq(StringName(band.get_meta("variant")), &"haitei")
	var stripe := band.get_node_or_null("Stripe") as Control
	assert_not_null(stripe)
	if stripe != null:
		assert_eq(stripe.position.x, -PlayableTable.MOMENT_BAND_TRAVEL)
		assert_gte(PlayableTable.MOMENT_BAND_TRAVEL, band.size.x,
			"窄带须从自身边界外入场")
	var text := band.get_node_or_null("Stripe/Text") as Label
	assert_not_null(text)
	if text != null:
		assert_eq(text.text, "海底捞月")
		var font := text.label_settings.font as SystemFont
		assert_not_null(font, "moment-band 使用中文系统无衬线字体栈")
		if font != null:
			assert_eq(font.font_names, PackedStringArray([
				"PingFang SC", "Microsoft YaHei", "Hiragino Sans GB",
				"Source Han Sans SC", "Noto Sans SC"]))
			assert_eq(font.font_weight, 900)


func test_abortive_draw_has_no_uncontracted_flash_or_announce() -> void:
	var table := PLAYABLE_TABLE.new()
	add_child_autofree(table)
	var color_rects_before := table.get_children().filter(
		func(child: Node): return child is ColorRect).size()
	table._handle_event_dramatic(BattleEvent.make(&"ABORTIVE_DRAW", -1, null, {
		"reason": "kyuusyu_kyuuhai",
	}))
	var color_rects_after := table.get_children().filter(
		func(child: Node): return child is ColorRect).size()
	assert_eq(_announces(table).size(), 0)
	assert_eq(color_rects_after, color_rects_before,
		"途中流局不得保留自创红闪")


func test_yakuman_does_not_append_second_call_announce() -> void:
	var table := PLAYABLE_TABLE.new()
	add_child_autofree(table)
	table._handle_event_dramatic(BattleEvent.make(&"WIN_DECLARED", 1, null, {
		"is_tsumo": false,
		"is_chankan": false,
		"yakuman_multiplier": 1,
	}))
	assert_eq(_announces(table).size(), 1, "确认态只播基础荣和")
	await wait_seconds(0.6)
	assert_eq(_announces(table).size(), 1,
		"确认态不得在 500ms 后追加第二个役满 CallAnnounce")
