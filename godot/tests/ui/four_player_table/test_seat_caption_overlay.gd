extends GutTest

# E4-04 / #246：覆盖层几何、穿透、header、partial 省略、Timer 过期、安全区。

const OverlayScr := preload("res://ui/four_player_table/seat_caption_overlay.gd")
const ModelScr := preload("res://ui/four_player_table/seat_caption_model.gd")
const TableScr := preload("res://ui/four_player_table/four_player_table.gd")


func _rects_intersect(a: Rect2, b: Rect2) -> bool:
	return a.intersects(b)


func _safe_action() -> Rect2:
	return Rect2(
		(TableLayout.TABLE_W - 720.0) / 2.0,
		TableLayout.ACTION_BAR_Y,
		720.0,
		TableLayout.ACTION_BAR_H
	)


func _safe_ptt() -> Rect2:
	return Rect2(TableLayout.TABLE_W - 176.0, 820.0, 160.0, 40.0)


func test_four_player_table_auto_creates_caption_overlay() -> void:
	var table = TableScr.new()
	add_child_autofree(table)
	await get_tree().process_frame
	var ov = table.get_node_or_null("SeatCaptionOverlay")
	assert_not_null(ov, "FourPlayerTable 必须自动创建字幕覆盖层")
	assert_eq(ov.mouse_filter, Control.MOUSE_FILTER_IGNORE)


func test_production_expiry_timer_exists_runs_and_clears_slot() -> void:
	var ov = OverlayScr.new()
	add_child_autofree(ov)
	await get_tree().process_frame
	var timer: Timer = ov.expiry_timer()
	assert_not_null(timer, "必须有 CaptionExpiryTimer")
	assert_eq(timer.name, "CaptionExpiryTimer")
	assert_false(timer.one_shot)
	assert_false(timer.is_stopped(), "生产 timer 应运行")
	assert_true(timer.timeout.is_connected(ov._on_caption_expiry_timeout))

	var t0: int = Time.get_ticks_msec()
	assert_true(bool(ov.ingest_caption({
		"seat": 0, "utterance_id": "live_utt", "text": "临时",
		"kind": "partial", "source": "local_mic", "lang": "zh",
		# 不传 now_ms → 墙钟；随后用强制 tick 模拟过期
	}).get("ok", false)))
	assert_true(ov.slot_control(0).visible)
	# 不真实 sleep：直接走 timeout 同路径，墙钟 + 超过 partial TTL
	ov.force_expiry_tick_for_test(t0 + ModelScr.TTL_PARTIAL_MS + 10)
	assert_false(ov.slot_control(0).visible, "timeout 路径必须清槽")
	assert_eq(ov.body_label(0).text, "")


func test_exit_tree_frees_timer() -> void:
	var ov = OverlayScr.new()
	add_child(ov)
	await get_tree().process_frame
	var timer: Timer = ov.expiry_timer()
	assert_not_null(timer)
	ov.free()
	await get_tree().process_frame
	assert_false(is_instance_valid(timer), "退出树不得残留 timer")


func test_slot_geometry_four_edges_and_mouse_filter_ignore() -> void:
	var ov = OverlayScr.new()
	add_child_autofree(ov)
	await get_tree().process_frame
	assert_eq(ov.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	for seat in range(4):
		var slot: Control = ov.slot_control(seat)
		assert_not_null(slot, "seat %d 槽" % seat)
		assert_eq(slot.mouse_filter, Control.MOUSE_FILTER_IGNORE)
		assert_eq(slot.rotation_degrees, 0.0, "字幕不随座位旋转")
		var r: Rect2 = ov.slot_rect(seat)
		assert_gt(r.size.x, 0.0)
		assert_gt(r.size.y, 0.0)
		assert_true(r.position.x >= 0.0 and r.end.x <= TableLayout.TABLE_W + 0.5)
		assert_true(r.position.y >= 0.0 and r.end.y <= TableLayout.TABLE_H + 0.5)

	assert_lt(ov.slot_rect(2).position.y, ov.slot_rect(0).position.y)
	assert_lt(ov.slot_rect(3).position.x, ov.slot_rect(1).position.x)


func test_slots_and_banner_avoid_all_hand_hosts_action_ptt() -> void:
	var ov = OverlayScr.new()
	add_child_autofree(ov)
	await get_tree().process_frame
	var safes: Array = []
	for seat in range(4):
		safes.append(TableLayout.HAND_HOST_RECTS[seat])
	safes.append(_safe_action())
	safes.append(_safe_ptt())
	var banner: Rect2 = ov.banner_rect()
	for seat in range(4):
		var r: Rect2 = ov.slot_rect(seat)
		for s in safes:
			assert_false(_rects_intersect(r, s),
				"seat %d 槽 %s 不得与安全区 %s 相交" % [seat, str(r), str(s)])
		assert_false(_rects_intersect(r, banner),
			"seat %d 槽不得与 banner 相交" % seat)
	for s in safes:
		assert_false(_rects_intersect(banner, s),
			"banner %s 不得与安全区 %s 相交" % [str(banner), str(s)])
	assert_true(banner.position.x >= 0.0 and banner.end.x <= TableLayout.TABLE_W)
	assert_true(banner.position.y >= 0.0 and banner.end.y <= TableLayout.TABLE_H)


func test_header_seat_source_lang_and_partial_ellipsis() -> void:
	var ov = OverlayScr.new()
	add_child_autofree(ov)
	await get_tree().process_frame
	ov.apply_display(0, {
		"seat": 0,
		"text": "听牌了",
		"kind": "partial",
		"source": "local_mic",
		"source_label": "本地麦克风",
		"lang": "zh",
		"header": ModelScr.header_text(0, "本地麦克风", "zh"),
		"is_mic": true,
		"is_partial": true,
	})
	await get_tree().process_frame
	assert_eq(ov.source_label_node(0).text, "座位 0｜本地麦克风｜中")
	assert_eq(ov.body_label(0).text, "听牌了…")
	assert_lt(ov.body_label(0).modulate.a, 0.99)
	# 模型原文不被装饰污染（apply 只改 Label）
	assert_ne(ov.body_label(0).text, "听牌了")

	# 已有省略号不重复
	ov.apply_display(0, {
		"seat": 0, "text": "已有…", "kind": "partial",
		"source_label": "本地麦克风", "lang": "zh",
		"header": "座位 0｜本地麦克风｜中", "is_partial": true,
	})
	assert_eq(ov.body_label(0).text, "已有…")

	ov.apply_display(1, {
		"seat": 1, "text": "final solid", "kind": "final",
		"source": "server_stt", "source_label": "服务端转写", "lang": "en",
		"header": ModelScr.header_text(1, "服务端转写", "en"),
		"is_partial": false,
	})
	assert_eq(ov.source_label_node(1).text, "座位 1｜服务端转写｜EN")
	assert_eq(ov.body_label(1).text, "final solid")
	assert_eq(ov.body_label(1).modulate.a, 1.0)

	ov.apply_display(2, {
		"seat": 2, "text": "AI line", "kind": "final",
		"source": "ai_text", "source_label": "AI 文本", "lang": "ja",
		"header": ModelScr.header_text(2, "AI 文本", "ja"),
		"is_partial": false, "is_mic": false,
	})
	assert_eq(ov.source_label_node(2).text, "座位 2｜AI 文本｜日")
	assert_false(ov.source_label_node(2).text.contains("麦克"))


func test_inject_via_four_player_table_updates_display_only() -> void:
	var table = TableScr.new()
	add_child_autofree(table)
	await get_tree().process_frame
	var res: Dictionary = table.inject_caption_display({
		"seat": 2,
		"utterance_id": "utt_top",
		"text": "対家発声",
		"kind": "TRANSCRIPT_FINAL",
		"source": "faster_whisper",
		"lang": "ja",
	})
	assert_true(bool(res.get("ok", false)), str(res))
	var ov = table.get_node("SeatCaptionOverlay")
	assert_true(ov.slot_control(2).visible)
	assert_true(String(ov.source_label_node(2).text).contains("座位 2"))
	assert_true(String(ov.source_label_node(2).text).contains("服务端转写"))
	assert_true(String(ov.source_label_node(2).text).contains("日"))
	assert_null(table.get_node_or_null("PttButton"))
	assert_null(table.get_node_or_null("RewardWindowModule"))


func test_inject_ai_caption_from_real_selector() -> void:
	var table = TableScr.new()
	add_child_autofree(table)
	await get_tree().process_frame
	var ai_line: Variant = TrashTalkAiLineSelector.select_ai_line({
		"rule_version": "trash_talk_rules_v1",
		"has_first_discard": true,
		"seed": 42, "hand_seq": 1, "window_id": "hand_1_window_0",
		"seat": 2, "discard_server_seq": 17,
		"character_id": "lin_yeche", "language": "zh",
		"public_context_tags": [],
	})
	assert_not_null(ai_line, "真实 selector 应返回 line")
	# 即使输入夹带麦克风源，包装器必须强制 AI
	(ai_line as Dictionary)["source"] = "local_mic"
	(ai_line as Dictionary)["kind"] = "partial"
	var res: Dictionary = table.inject_ai_caption_display(ai_line, {"now_ms": 1000})
	assert_true(bool(res.get("ok", false)), str(res))
	var ov = table.get_node("SeatCaptionOverlay")
	assert_true(ov.slot_control(2).visible)
	var header: String = ov.source_label_node(2).text
	assert_true(header.contains("AI 文本"), header)
	assert_false(header.contains("麦克"), header)
	assert_true(header.contains("座位 2"), header)
	assert_true(header.contains("中"), header)
	# 通用注入对真实 selector 输出（无 kind/source）会失败
	var bare: Variant = TrashTalkAiLineSelector.select_ai_line({
		"rule_version": "trash_talk_rules_v1",
		"has_first_discard": true,
		"seed": 12345, "hand_seq": 0, "window_id": "w_en",
		"seat": 3, "discard_server_seq": 3,
		"character_id": "qiu_jue", "language": "en",
	})
	assert_not_null(bare)
	var bare_copy: Dictionary = (bare as Dictionary).duplicate(true)
	bare_copy.erase("kind")
	bare_copy.erase("source")
	var rejected: Dictionary = table.inject_caption_display(bare_copy)
	assert_false(bool(rejected.get("ok", false)), "裸 AI 输出不得直接走通用注入")


func test_standard_path_no_unexpected_voice_or_reward_nodes() -> void:
	var table = TableScr.new()
	add_child_autofree(table)
	await get_tree().process_frame
	table.inject_caption_display({
		"seat": 0, "utterance_id": "u", "text": "x", "kind": "partial",
		"source": "local_mic", "lang": "zh",
	})
	assert_null(table.get_node_or_null("VoiceCapturePipeline"))
	assert_null(table.get_node_or_null("VoicePlaybackRouter"))
	assert_null(table.get_node_or_null("PttButton"))
	assert_null(table.get_node_or_null("RewardPoolPanel"))
	assert_null(table.get_node_or_null("ItemInventoryPanel"))
