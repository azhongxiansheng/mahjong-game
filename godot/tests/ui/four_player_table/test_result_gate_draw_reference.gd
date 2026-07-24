extends GutTest

const PT_SCENE := preload("res://ui/four_player_table/playable_table.gd")

var _pt: PlayableTable


class DramaticSpy extends PlayableTable:
	var emote_calls: Array = []
	var voice_calls: Array = []
	var announce_calls: Array = []

	func _set_seat_emote(seat_id: int, emote: String) -> void:
		emote_calls.append([seat_id, emote])

	func _say_for_seat(seat_id: int, event_kind: String) -> void:
		voice_calls.append([seat_id, event_kind])

	func _play_call_announce(kind: StringName, seat_id: int) -> void:
		announce_calls.append([kind, seat_id])


class ReadySizeSpy extends PlayableTable:
	func _build_layout() -> void:
		pass


func before_each() -> void:
	_pt = PT_SCENE.new()
	add_child_autofree(_pt)


func _replace_hand(seat: Seat, ids: Array) -> void:
	seat.hand = Hand.new()
	for id in ids:
		seat.hand.add(Tile.new(int(id)))


func _prepare_reference_draw_state() -> PlayableBattleController:
	var bc := PlayableBattleController.new(20260720, 2)
	var called_chi := Tile.new(TileId.W3, false, Tile.NO_OWNER, 1001)
	var open_chi := Meld.make_chi([
		Tile.new(TileId.W2, false, Tile.NO_OWNER, 1000),
		called_chi,
		Tile.new(TileId.W4, false, Tile.NO_OWNER, 1002),
	], 3, 0, called_chi)
	bc.state.seats[0].melds = [open_chi]
	_replace_hand(bc.state.seats[0], [
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.S6, TileId.S7,
		TileId.W5, TileId.W5,
	])
	_replace_hand(bc.state.seats[1], [
		TileId.W1, TileId.W4, TileId.W7,
		TileId.T2, TileId.T5, TileId.T8,
		TileId.S3, TileId.S6, TileId.S9,
		TileId.E, TileId.S_WIND, TileId.HAKU, TileId.HATSU,
	])
	_replace_hand(bc.state.seats[2], [
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.CHUN,
	])
	_replace_hand(bc.state.seats[3], [
		TileId.W1, TileId.W4, TileId.W7,
		TileId.T2, TileId.T5, TileId.T8,
		TileId.S3, TileId.S6, TileId.S9,
		TileId.E, TileId.W_WIND, TileId.HAKU, TileId.CHUN,
	])
	return bc


func _flat_tile_slots(root: Node) -> Array:
	if root == null:
		return []
	return root.find_children("*", "Control", true, false).filter(
		func(node: Node) -> bool:
			return bool(node.get_meta("flat_meld_tile", false)))


func test_reference_result_gate_durations_are_3000_and_500ms() -> void:
	assert_true(_pt.has_method("_result_modal_gate_seconds"),
		"参考 modal 门控必须公开为可测纯 helper")
	if not _pt.has_method("_result_modal_gate_seconds"):
		return
	assert_eq(_pt.call("_result_modal_gate_seconds", true, "WIN_DECLARED"), 3.0)
	assert_eq(_pt.call("_result_modal_gate_seconds", false, "EXHAUSTIVE_DRAW"), 0.5)
	assert_eq(_pt.call("_result_modal_gate_seconds", false, "ABORTIVE_DRAW"), 0.5)
	assert_eq(_pt.call("_result_modal_gate_seconds", false, "NAGASHI_MANGAN"), 0.5,
		"公开 bundle 对所有非 win 的 ended 状态统一等待 500ms")


func test_ready_keeps_reference_1600x900_without_adding_overlay_height() -> void:
	var table := ReadySizeSpy.new()
	add_child_autofree(table)
	await get_tree().process_frame
	assert_eq(table.custom_minimum_size, Vector2(1600, 900),
		"操作条是 900px 舞台内 overlay，_ready 不得再加 72px")


func test_exhaustive_draw_uses_real_snapshot_and_mounts_after_500ms() -> void:
	var bc := _prepare_reference_draw_state()
	bc.events = [BattleEvent.make(&"EXHAUSTIVE_DRAW", -1)]
	_pt._bc = bc

	assert_true(_pt.has_method("_build_exhaustive_draw_snapshots"),
		"普通流局必须在状态切换前构造真实查听快照")
	if _pt.has_method("_build_exhaustive_draw_snapshots"):
		var snapshots: Array = _pt.call("_build_exhaustive_draw_snapshots")
		assert_eq(snapshots.size(), 4)
		var seats: Array[int] = []
		for snapshot in snapshots:
			seats.append(int(snapshot["seat"]))
		assert_eq(seats, [2, 3, 0, 1], "必须从庄家起顺时针排序")
		assert_true(bool(snapshots[0]["tenpai"]))
		assert_false(bool(snapshots[1]["tenpai"]))
		assert_true(bool(snapshots[2]["tenpai"]))
		assert_false(bool(snapshots[3]["tenpai"]))
		assert_eq(int(snapshots[0]["payment"]), 1500)
		assert_eq(int(snapshots[1]["payment"]), -1500)
		assert_eq(String(snapshots[2]["winKind"]), "")
		assert_true(snapshots[2]["hand"][0] is Tile,
			"快照须保留真实 Tile，不得只拼假文本")
		assert_eq(snapshots[2]["melds"].size(), 1)
		assert_ne(snapshots[2]["melds"][0], bc.state.seats[0].melds[0],
			"meld 必须复制成快照，不能留下一局会突变的活引用")

	_pt._show_hand_result_overlay({"last_event": "EXHAUSTIVE_DRAW"})
	await wait_seconds(0.30)
	assert_null(_pt.get_node_or_null("ResultOverlay"),
		"普通流局 500ms 前不得挂载 modal")
	await wait_seconds(0.30)
	var overlay := _pt.get_node_or_null("ResultOverlay") as Control
	assert_not_null(overlay, "普通流局 500ms 后必须挂载 modal")
	if overlay == null:
		return
	var panel := overlay.get_node("ResultModal") as Panel
	assert_eq((panel.get_node("ResultTitle") as Label).text, "流局")
	assert_eq((panel.get_node("ResultSubtitle") as Label).text, "查听")
	var list := panel.get_node_or_null("DrawResultList") as VBoxContainer
	assert_not_null(list, "普通流局必须显示四家查听列表")
	if list != null:
		assert_eq(list.get_theme_constant("separation"), 10,
			".modal__draw-list 必须使用 10px gap")
		assert_eq(list.get_child_count(), 4)
		assert_eq(int(list.get_child(0).get_meta("seat_id")), 2)
		assert_eq((list.get_child(0).get_node("Tag") as Label).text, "听")
		assert_eq((list.get_child(0).get_node("Payment") as Label).text, "+1500")
		assert_eq((list.get_child(1).get_node("Tag") as Label).text, "不听")
		assert_eq((list.get_child(1).get_node("Payment") as Label).text, "-1500")
		var draw_tiles := list.get_child(2).get_node_or_null("Tiles") as HFlowContainer
		assert_not_null(draw_tiles,
			".modal__draw-tiles 必须是可换行的 HFlowContainer")
		if draw_tiles != null:
			assert_eq(draw_tiles.get_theme_constant("h_separation"), 6)
			assert_eq(draw_tiles.get_theme_constant("v_separation"), 6)
			var hand_tiles := draw_tiles.get_children().filter(
				func(node: Node) -> bool:
					return String(node.get_meta("result_role", "")) == "hand")
			assert_eq(hand_tiles.size(), 10,
				"副露家仍须按真实暗手数量展示 tile--sm 等价牌图")
			for tile in hand_tiles:
				assert_eq(tile.custom_minimum_size, Vector2(30, 40),
					"普通流局使用 generic .tile--sm 30×40")
			var flat_melds := draw_tiles.get_node_or_null("FlatMelds")
			assert_not_null(flat_melds,
				"vP 必须在暗手后调用 flat meld 渲染")
			if flat_melds != null:
				var slots := _flat_tile_slots(flat_melds)
				assert_eq(slots.size(), 3)
				assert_eq(slots.map(func(slot: Control):
					return int(slot.get_meta("tile_id"))),
					[TileId.W3, TileId.W2, TileId.W4],
					"flat chi 必须按 nV 把真实 called_tile 插到首位")
				assert_eq(slots.map(func(slot: Control):
					return bool(slot.get_meta("horizontal"))),
					[true, false, false])
				assert_eq(slots[0].get_meta("visual_size"), Vector2(40, 30))
				var called_face := slots[0].get_node_or_null("Face") as Control
				assert_not_null(called_face)
				if called_face != null:
					assert_eq(called_face.custom_minimum_size, Vector2(30, 40))
					assert_eq(called_face.rotation_degrees, -90.0)
	var button := panel.find_children("*", "Button", true, false)[0] as Button
	button.pressed.emit()
	await get_tree().process_frame


func test_abortive_draw_uses_reference_title_reason_note_and_500ms_gate() -> void:
	var bc := PlayableBattleController.new(20260720)
	bc.events = [BattleEvent.make(&"ABORTIVE_DRAW", -1, null, {
		"reason": "suufon_renda",
	})]
	_pt._bc = bc
	_pt._show_hand_result_overlay({"last_event": "ABORTIVE_DRAW"})
	await wait_seconds(0.30)
	assert_null(_pt.get_node_or_null("ResultOverlay"),
		"途中流局同样必须等待完整 500ms")
	await wait_seconds(0.30)
	var overlay := _pt.get_node_or_null("ResultOverlay") as Control
	assert_not_null(overlay)
	if overlay == null:
		return
	var panel := overlay.get_node("ResultModal") as Panel
	assert_eq((panel.get_node("ResultTitle") as Label).text, "中途流局")
	assert_eq((panel.get_node("ResultSubtitle") as Label).text, "四风连打")
	assert_eq((panel.get_node("AbortiveDrawNote") as Label).text,
		"本局不查听、不结算；报听棒结转下一局。")
	var button := panel.find_children("*", "Button", true, false)[0] as Button
	button.pressed.emit()
	await get_tree().process_frame


func test_nagashi_mangan_shows_real_payments_after_500ms() -> void:
	var bc := PlayableBattleController.new(20260720, 0)
	bc.events = [BattleEvent.make(&"NAGASHI_MANGAN", 1, null, {
		"winner_seat": 1,
	})]
	_pt._bc = bc
	_pt._show_hand_result_overlay({"last_event": "NAGASHI_MANGAN"})
	await wait_seconds(0.30)
	assert_null(_pt.get_node_or_null("ResultOverlay"),
		"流し满贯也是非 win ended，500ms 前不得挂载")
	await wait_seconds(0.30)
	var overlay := _pt.get_node_or_null("ResultOverlay") as Control
	assert_not_null(overlay)
	if overlay == null:
		return
	var panel := overlay.get_node("ResultModal") as Panel
	assert_eq((panel.get_node("ResultTitle") as Label).text, "流し満貫")
	var detail := panel.get_node_or_null("ResultDetail") as Label
	assert_true(detail == null or not detail.visible,
		"付分结果不得再显示‘无人胡牌（流局）’正文")
	var score_list := panel.get_node_or_null("ScoreDeltaList") as VBoxContainer
	assert_not_null(score_list, "确定前必须解释实际发生的四家满贯支付")
	if score_list != null:
		_pt._skip_result_animations()
		var dealer := score_list.get_node("ScoreDeltaSeat0") as Control
		var winner := score_list.get_node("ScoreDeltaSeat1") as Control
		assert_eq((dealer.get_node("After") as Label).text, "21000")
		assert_eq((dealer.get_node("Delta") as Label).text, "-4000")
		assert_eq((winner.get_node("After") as Label).text, "33000")
		assert_eq((winner.get_node("Delta") as Label).text, "+8000")
	var button := panel.find_children("*", "Button", true, false)[0] as Button
	assert_eq(button.text, "确定")
	button.pressed.emit()
	await get_tree().process_frame


func test_result_gate_exits_with_table_without_orphan_modal() -> void:
	var bc := PlayableBattleController.new(20260720)
	bc.events = [BattleEvent.make(&"ABORTIVE_DRAW", -1, null, {
		"reason": "suufon_renda",
	})]
	_pt._bc = bc
	_pt._show_hand_result_overlay({"last_event": "ABORTIVE_DRAW"})
	await wait_seconds(0.10)
	_pt.queue_free()
	await get_tree().process_frame
	await wait_seconds(0.55)
	assert_null(get_tree().root.find_child("ResultOverlay", true, false),
		"牌桌退出时子 Timer 必须自然取消，不能迟到挂载孤儿 modal")


func test_candidate_win_events_do_not_change_character_before_confirmation() -> void:
	var table := DramaticSpy.new()
	add_child_autofree(table)
	table._handle_event_dramatic(BattleEvent.make(&"TSUMO_DECLARED", 0))
	table._handle_event_dramatic(BattleEvent.make(&"RON_DECLARED", 2, null, {
		"discarder_seat": 1,
	}))
	assert_eq(table.emote_calls, [],
		"候选自摸/荣和仍可被取消，不得提前切人物 emote")
	assert_eq(table.voice_calls, [],
		"候选自摸/荣和不得提前播 winning/upset 台词")
	assert_eq(table.announce_calls, [],
		"候选态同样不得提前挂载 CallAnnounce")


func test_confirmed_win_changes_winner_and_losers_once() -> void:
	var table := DramaticSpy.new()
	add_child_autofree(table)
	table._handle_event_dramatic(BattleEvent.make(&"WIN_DECLARED", 2, null, {
		"is_tsumo": true,
	}))
	assert_eq(table.announce_calls, [[&"tsumo", 2]])
	assert_eq(table.emote_calls, [
		[2, "winning"],
		[0, "upset"], [1, "upset"], [3, "upset"],
	], "确认后的 WIN_DECLARED 才一次性切换四家人物状态")
	assert_eq(table.voice_calls, [
		[2, "winning"],
		[0, "upset"], [1, "upset"], [3, "upset"],
	], "确认后的 WIN_DECLARED 才播放 winning/upset 台词")


func test_flat_meld_slots_cover_pon_open_kan_ankan_and_added_kan() -> void:
	assert_true(_pt.has_method("_build_flat_result_melds"),
		"win/draw 必须共用 flat:true 副露 helper")
	if not _pt.has_method("_build_flat_result_melds"):
		return
	var pon_called := Tile.new(TileId.T5, false, Tile.NO_OWNER, 2001)
	var pon := Meld.make_pon([
		Tile.new(TileId.T5, false, Tile.NO_OWNER, 2000),
		pon_called,
		Tile.new(TileId.T5, false, Tile.NO_OWNER, 2002),
	], 2, 0, pon_called)
	var kan_called := Tile.new(TileId.S7, false, Tile.NO_OWNER, 2010)
	var minkan := Meld.make_minkan([
		kan_called,
		Tile.new(TileId.S7, false, Tile.NO_OWNER, 2011),
		Tile.new(TileId.S7, false, Tile.NO_OWNER, 2012),
		Tile.new(TileId.S7, false, Tile.NO_OWNER, 2013),
	], 1, 0, kan_called)
	var ankan := Meld.make_ankan([
		Tile.new(TileId.HAKU, false, Tile.NO_OWNER, 2020),
		Tile.new(TileId.HAKU, false, Tile.NO_OWNER, 2021),
		Tile.new(TileId.HAKU, false, Tile.NO_OWNER, 2022),
		Tile.new(TileId.HAKU, false, Tile.NO_OWNER, 2023),
	])
	var added_called := Tile.new(TileId.E, false, Tile.NO_OWNER, 2030)
	var added := Meld.make_added_kan([
		added_called,
		Tile.new(TileId.E, false, Tile.NO_OWNER, 2031),
		Tile.new(TileId.E, false, Tile.NO_OWNER, 2032),
		Tile.new(TileId.E, false, Tile.NO_OWNER, 2033),
	], 3, 0, added_called)
	var flat = _pt.call("_build_flat_result_melds",
		[pon, minkan, ankan, added], Vector2(30, 40), "FlatMelds") as Control
	_pt.add_child(flat)
	assert_eq(flat.get_child_count(), 4)

	var pon_slots := _flat_tile_slots(flat.get_child(0))
	assert_eq(pon_slots.size(), 3)
	assert_eq(pon_slots.map(func(slot: Control):
		return bool(slot.get_meta("horizontal"))), [false, true, false])

	var minkan_slots := _flat_tile_slots(flat.get_child(1))
	assert_eq(minkan_slots.size(), 4)
	assert_eq(minkan_slots.map(func(slot: Control):
		return bool(slot.get_meta("horizontal"))), [false, false, false, true])

	var ankan_slots := _flat_tile_slots(flat.get_child(2))
	assert_eq(ankan_slots.size(), 4)
	assert_eq(ankan_slots.map(func(slot: Control):
		return bool(slot.get_meta("face_down"))), [false, true, true, false],
		"暗杠固定中间两张牌背")
	assert_eq(ankan_slots.filter(func(slot: Control):
		return slot.get_node_or_null("Back") != null).size(), 2)
	assert_eq((ankan_slots[1].get_node("Back") as Control).custom_minimum_size,
		Vector2(30, 40))

	var added_slots := _flat_tile_slots(flat.get_child(3))
	assert_eq(added_slots.size(), 4,
		"加杠三张主布局 + called tile 上叠一张")
	assert_eq(added_slots.filter(func(slot: Control):
		return bool(slot.get_meta("horizontal"))).size(), 2)
	assert_eq(added_slots.filter(func(slot: Control):
		return bool(slot.get_meta("stacked_above"))).size(), 1)
	assert_eq(flat.get_child(3).get_child_count(), 3,
		"叠牌必须放进 called tile stack，不得占第四个 flex slot")


func test_draw_tag_uses_reference_pill_styles_including_win() -> void:
	var panel := Control.new()
	_pt.add_child(panel)
	var list := _pt._build_draw_result_list(panel, [
		{"seat": 0, "tenpai": true, "winKind": "", "payment": 0,
			"hand": [], "melds": []},
		{"seat": 1, "tenpai": false, "winKind": "", "payment": 0,
			"hand": [], "melds": []},
		{"seat": 2, "tenpai": false, "winKind": "ron", "payment": 0,
			"hand": [], "melds": []},
	])
	var tenpai_tag := list.get_child(0).get_node("Tag") as Label
	var noten_tag := list.get_child(1).get_node("Tag") as Label
	var win_tag := list.get_child(2).get_node("Tag") as Label
	var tenpai_style := tenpai_tag.get_theme_stylebox("normal") as StyleBoxFlat
	var noten_style := noten_tag.get_theme_stylebox("normal") as StyleBoxFlat
	var win_style := win_tag.get_theme_stylebox("normal") as StyleBoxFlat
	assert_not_null(tenpai_style)
	assert_not_null(noten_style)
	assert_not_null(win_style)
	if tenpai_style != null:
		assert_eq(tenpai_style.bg_color, Color("6bc06b2e"))
		assert_eq(tenpai_style.border_color, Color("6bc06b66"))
		assert_eq(tenpai_style.corner_radius_top_left, 999)
	if noten_style != null:
		assert_eq(noten_style.bg_color, Color("d97a7a24"))
		assert_eq(noten_style.border_color, Color("d97a7a52"))
	if win_style != null:
		assert_eq(win_tag.text, "荣和")
		assert_eq(win_style.bg_color, Color("d4b05c2e"))
		assert_eq(win_style.border_color, Color("d4b05c66"))


func test_riichi_han_does_not_guess_reference_total_fan_effects() -> void:
	var bc := PlayableBattleController.new(20260720)
	var win := BattleEvent.make(&"WIN_DECLARED", 0, null, {
		"han": 3,
		"yakuman_multiplier": 0,
	})
	bc.events = [win]
	_pt._bc = bc
	var color_rects_before := _pt.get_children().filter(
		func(child: Node) -> bool: return child is ColorRect).size()

	_pt._show_hand_result_overlay({"last_event": "WIN_DECLARED"})
	await get_tree().process_frame

	assert_eq(_pt.get_children().filter(
		func(child: Node) -> bool: return child is WinBurst).size(), 0,
		"没有等价 totalFan 时不得把日麻 han 猜成参考 burst 分级")
	assert_eq(_pt.get_children().filter(
		func(child: Node) -> bool: return child is ColorRect).size(),
		color_rects_before,
		"普通确认和牌只播 CallAnnounce，不得追加自定义全屏白闪")
	_pt.queue_free()
	await get_tree().process_frame
