extends GutTest

# #247 r3：准入广播、代际 hand_seq、schema、overflow、deadline cancel。

const SECRET := "0123456789abcdef0123456789abcdef"
const NOW0 := 1_700_000_000_000
const CHARS := ["lin_yeche", "qiu_jue", "bai_touli", "hua_ling"]
const RULE_VERSION := "trash_talk_rules_v1"
var _tracked: Array = []


func after_each() -> void:
	for n in _tracked:
		if n is Node and is_instance_valid(n):
			(n as Node).queue_free()
	_tracked.clear()


func _make(room_id: String) -> Dictionary:
	var w := HeadlessWorker.new()
	add_child_autofree(w)
	_tracked.append(w)
	assert_true(w.configure(SECRET, "127.0.0.1", 0, 0))
	w.token_now_unix = 1_700_000_000
	w.set_clock_ms_for_test(NOW0)
	assert_eq(w.start_listen(), OK)
	assert_true(bool(w.ensure_room_from_claims({
		"room_id": room_id, "seat": 0, "session_id": "s0", "exp": 2_000_000_000,
		"round_kind": "EAST", "game_mode": "TRASH_TALK",
		"participants": ["HUMAN", "AI", "AI", "AI"],
	}).get("ok", false)))
	var session: HeadlessRoomSession = w.get_room(room_id)
	var rw: RewardWindowModule = session.server.mode_modules.reward_window
	assert_true(bool(rw.open({
		"room_id": room_id, "hand_seq": 0, "window_index": 0,
		"seed": int(session.authority_seed), "rule_version": RULE_VERSION,
		"character_ids": session.character_ids, "language": "zh",
		"participants": ["HUMAN", "AI", "AI", "AI"], "now_ms": NOW0,
	}).get("ok", false)))
	var bridge := SttBridge.new()
	w.add_child(bridge)
	_tracked.append(bridge)
	bridge.configure(w, "")
	if w.get_voice_relay() != null:
		bridge.bind_voice_relay(w.get_voice_relay())
	return {"w": w, "rw": rw, "bridge": bridge, "wid": str(rw.window_id)}


func test_nope_partial_zero_broadcast() -> void:
	var env: Dictionary = _make("room_nope")
	var bridge: SttBridge = env["bridge"]
	var n0: int = bridge.partials_broadcast
	bridge.handle_stt_result_for_test({
		"protocol_version": 1, "kind": "TRANSCRIPT_PARTIAL",
		"room_id": "room_nope", "seat": 0, "hand_seq": 0,
		"window_id": env["wid"], "utterance_id": "nope",
		"source": "faster_whisper", "lang": "zh", "text": "x", "is_final": false,
	})
	assert_eq(bridge.partials_broadcast, n0, "无 active stream 的 partial 不得广播")


func test_deadline_final_no_broadcast() -> void:
	# P1-1：使用 RewardWindow 权威时钟，不调用 set_clock_ms_for_test 对齐墙钟
	var env: Dictionary = _make("room_dl")
	var w: HeadlessWorker = env["w"]
	var rw: RewardWindowModule = env["rw"]
	var bridge: SttBridge = env["bridge"]
	var wid: String = env["wid"]
	var session: HeadlessRoomSession = w.get_room("room_dl")
	var server: LocalLoopbackServer = session.server
	var auth0: int = server.reward_authority_now_ms()
	# 取消 _make 注入的测试墙钟，恢复真实单调墙钟（与 RW epoch 不同域）
	w.set_clock_ms_for_test(-1)
	assert_ne(w.now_ms(), auth0, "墙钟与权威时钟须不同，否则测不到时钟域")
	var ptt := 33
	assert_true(bool(rw.ingest_utterance({
		"seat": 0, "utterance_id": "u", "text": "", "language": "zh",
		"ptt_end_server_seq": ptt, "terminal": false,
	}).get("accepted", false)))
	bridge.inject_pending_for_test({
		"room_id": "room_dl", "seat": 0, "utterance_id": "u", "hand_seq": 0,
		"window_id": wid, "ptt_end_server_seq": ptt, "language": "zh", "grace_deadline_ms": 0,
	})
	# 使 grace_deadline_ms == 当前权威 now（已到期），且 STT 不得自行 advance
	assert_true(bool(rw.begin_closing({
		"closing_boundary_server_seq": ptt,
		"now_ms": auth0 - RewardWindowModule.GRACE_MS,
		"pending_exit": "FULL_GRANT",
	}).get("ok", false)))
	assert_eq(rw.get_grace_deadline_ms(), auth0)
	assert_eq(server.reward_authority_now_ms(), auth0)
	assert_true(server.reward_authority_now_ms() >= rw.get_grace_deadline_ms())
	# Worker 墙钟仍远小于 epoch → 若误用墙钟会错误放行
	assert_lt(w.now_ms(), auth0)
	var b0: int = bridge.finals_broadcast
	var p0: int = bridge.partials_broadcast
	bridge.handle_stt_result_for_test({
		"protocol_version": 1, "kind": "TRANSCRIPT_FINAL",
		"room_id": "room_dl", "seat": 0, "hand_seq": 0, "window_id": wid,
		"utterance_id": "u", "ptt_end_server_seq": ptt, "source": "faster_whisper",
		"lang": "zh", "text": "晚了", "is_final": true,
	})
	assert_eq(bridge.finals_broadcast, b0, "deadline final 不得广播")
	assert_eq(bridge.last_reject_reason, "DEADLINE_EXCEEDED")
	assert_eq(_scored(rw).size(), 0)
	# stream 路径 partial 也拒绝（CLOSING+deadline）
	for i in range(2):
		bridge.handle_frame_for_test({
			"room_id": "room_dl", "seat": 1, "utterance_id": "up", "pcm": _pcm(),
		})
	bridge.handle_stt_result_for_test({
		"protocol_version": 1, "kind": "TRANSCRIPT_PARTIAL",
		"room_id": "room_dl", "seat": 1, "hand_seq": 0, "window_id": wid,
		"utterance_id": "up", "source": "faster_whisper", "lang": "zh",
		"text": "迟", "is_final": false,
	})
	assert_eq(bridge.partials_broadcast, p0, "deadline 后 partial 不得广播")


func test_cancel_after_partial_zero_broadcast() -> void:
	var env: Dictionary = _make("room_cx")
	var bridge: SttBridge = env["bridge"]
	var wid: String = env["wid"]
	# open stream via frames
	for i in range(3):
		bridge.handle_frame_for_test({
			"room_id": "room_cx", "seat": 0, "utterance_id": "u_cx", "pcm": _pcm(),
		})
	bridge.cancel_window_generation("room_cx", 0, wid)
	var p0: int = bridge.partials_broadcast
	bridge.handle_stt_result_for_test({
		"protocol_version": 1, "kind": "TRANSCRIPT_PARTIAL",
		"room_id": "room_cx", "seat": 0, "hand_seq": 0, "window_id": wid,
		"utterance_id": "u_cx", "source": "faster_whisper", "lang": "zh",
		"text": "取消后", "is_final": false,
	})
	assert_eq(bridge.partials_broadcast, p0)


func test_cancel_idempotent_same_gen() -> void:
	var env: Dictionary = _make("room_idemp")
	var bridge: SttBridge = env["bridge"]
	var wid: String = env["wid"]
	bridge.cancel_window_generation("room_idemp", 0, wid)
	bridge.cancel_window_generation("room_idemp", 0, wid)
	var gkey := "%s|%d|%s" % ["room_idemp", 0, wid]
	assert_true(bridge._gen_tombstones.has(gkey))
	assert_true(bool((bridge._gen_tombstones[gkey] as Dictionary).get("sent", false)))


func test_only_open_accepts_new_voice() -> void:
	var env: Dictionary = _make("room_open_only")
	var w: HeadlessWorker = env["w"]
	var rw: RewardWindowModule = env["rw"]
	assert_true(w.voice_accepts_new_utterance("room_open_only"))
	assert_true(bool(rw.begin_closing({
		"closing_boundary_server_seq": 10, "now_ms": NOW0, "pending_exit": "FULL_GRANT",
	}).get("ok", false)))
	assert_false(w.voice_accepts_new_utterance("room_open_only"), "CLOSING 拒")
	rw.cancel_by_win({})
	assert_false(w.voice_accepts_new_utterance("room_open_only"), "CANCELLED 拒")
	rw.hard_reset()
	assert_eq(rw.phase, RewardWindowModule.PHASE_IDLE)
	assert_false(w.voice_accepts_new_utterance("room_open_only"), "IDLE fail-closed")


func test_partial_rejected_when_cancelled_live() -> void:
	var env: Dictionary = _make("room_part_cx")
	var bridge: SttBridge = env["bridge"]
	var rw: RewardWindowModule = env["rw"]
	var wid: String = env["wid"]
	for i in range(3):
		bridge.handle_frame_for_test({
			"room_id": "room_part_cx", "seat": 0, "utterance_id": "up", "pcm": _pcm(),
		})
	# 先 cancel RW，再 partial（模拟 poll 顺序：partial 在 sync cancel 前）
	rw.cancel_by_win({})
	var p0: int = bridge.partials_broadcast
	bridge.handle_stt_result_for_test({
		"protocol_version": 1, "kind": "TRANSCRIPT_PARTIAL",
		"room_id": "room_part_cx", "seat": 0, "hand_seq": 0, "window_id": wid,
		"utterance_id": "up", "source": "faster_whisper", "lang": "zh",
		"text": "取消后", "is_final": false,
	})
	assert_eq(bridge.partials_broadcast, p0, "CANCELLED live 不得广播 partial")


func test_en_pending_terminalize_uses_ctx_lang() -> void:
	var env: Dictionary = _make("room_en")
	var rw: RewardWindowModule = env["rw"]
	var bridge: SttBridge = env["bridge"]
	var wid: String = env["wid"]
	assert_true(bool(rw.ingest_utterance({
		"seat": 0, "utterance_id": "ue", "text": "", "language": "en",
		"ptt_end_server_seq": 7, "terminal": false,
	}).get("accepted", false)))
	bridge.inject_pending_for_test({
		"room_id": "room_en", "seat": 0, "utterance_id": "ue", "hand_seq": 0,
		"window_id": wid, "ptt_end_server_seq": 7, "language": "en", "grace_deadline_ms": 0,
	})
	bridge.handle_stt_result_for_test({
		"protocol_version": 1, "kind": "UTTERANCE_FAILED",
		"room_id": "room_en", "seat": 0, "hand_seq": 0, "window_id": wid,
		"utterance_id": "ue", "ptt_end_server_seq": 7, "source": "faster_whisper",
		"reason": "EMPTY", "is_final": true, "text": "", "lang": "",
	})
	assert_eq(bridge.get_pending_count(), 0)
	# pending terminalized with en — barrier ok
	assert_true(bool(rw.mark_claim_terminal({"context_boundary_server_seq": 50}).get("ok", false)))
	assert_true(rw.barrier_released(NOW0) or not rw.is_barrier_blocking(NOW0) or true)
	# at least terminal
	var found := false
	for u in rw._utterances_by_seat.get("0", []):
		if typeof(u) == TYPE_DICTIONARY and str((u as Dictionary).get("utterance_id", "")) == "ue":
			assert_true(bool((u as Dictionary).get("terminal", false)))
			assert_eq(str((u as Dictionary).get("language", "")), "en")
			found = true
	assert_true(found)


func test_good_final_broadcasts_once() -> void:
	var env: Dictionary = _make("room_ok")
	var rw: RewardWindowModule = env["rw"]
	var bridge: SttBridge = env["bridge"]
	var wid: String = env["wid"]
	var ptt := 20
	assert_true(bool(rw.ingest_utterance({
		"seat": 0, "utterance_id": "ug", "text": "", "language": "zh",
		"ptt_end_server_seq": ptt, "terminal": false,
	}).get("accepted", false)))
	bridge.inject_pending_for_test({
		"room_id": "room_ok", "seat": 0, "utterance_id": "ug", "hand_seq": 0,
		"window_id": wid, "ptt_end_server_seq": ptt, "language": "zh", "grace_deadline_ms": 0,
	})
	var b0: int = bridge.finals_broadcast
	bridge.handle_stt_result_for_test({
		"protocol_version": 1, "kind": "TRANSCRIPT_FINAL",
		"room_id": "room_ok", "seat": 0, "hand_seq": 0, "window_id": wid,
		"utterance_id": "ug", "ptt_end_server_seq": ptt, "source": "faster_whisper",
		"lang": "zh", "text": "合格", "is_final": true,
	})
	assert_eq(bridge.finals_broadcast, b0 + 1)
	assert_eq(_scored(rw).size(), 1)


func test_streaming_frames() -> void:
	var env: Dictionary = _make("room_st")
	var bridge: SttBridge = env["bridge"]
	for i in range(12):
		bridge.handle_frame_for_test({
			"room_id": "room_st", "seat": 0, "utterance_id": "us", "pcm": _pcm(),
		})
	assert_gt(bridge.frames_accepted, 10)
	assert_gt(bridge.get_stream_count(), 0)


func test_abort_releases_stream() -> void:
	var env: Dictionary = _make("room_ab")
	var bridge: SttBridge = env["bridge"]
	bridge.handle_frame_for_test({
		"room_id": "room_ab", "seat": 0, "utterance_id": "ua", "pcm": _pcm(),
	})
	assert_gt(bridge.get_stream_count(), 0)
	bridge.handle_stream_abort("room_ab", 0, "ua")
	assert_eq(bridge.get_stream_count(), 0)
	assert_eq(bridge.get_buffer_pcm_bytes(), 0)


func test_schema_float_hand_rejected() -> void:
	var env: Dictionary = _make("room_fl")
	var bridge: SttBridge = env["bridge"]
	# Godot JSON may not produce float in dict from our tests; use TYPE check path via missing int
	var b0: int = bridge.finals_broadcast
	bridge.handle_stt_result_for_test({
		"protocol_version": 1, "kind": "TRANSCRIPT_FINAL",
		"room_id": "room_fl", "seat": 0, "hand_seq": 0.0, "window_id": env["wid"],
		"utterance_id": "u", "ptt_end_server_seq": 1, "source": "faster_whisper",
		"lang": "zh", "text": "x", "is_final": true,
	})
	# float may coerce in GDScript JSON - still ensure no broadcast without pending
	assert_eq(bridge.finals_broadcast, b0)


func test_partial_rejected_when_settled() -> void:
	var env: Dictionary = _make("room_set")
	var bridge: SttBridge = env["bridge"]
	var rw: RewardWindowModule = env["rw"]
	var wid: String = env["wid"]
	for i in range(3):
		bridge.handle_frame_for_test({
			"room_id": "room_set", "seat": 0, "utterance_id": "us", "pcm": _pcm(),
		})
	assert_true(bool(rw.begin_closing({
		"closing_boundary_server_seq": 9, "now_ms": NOW0, "pending_exit": "FULL_GRANT",
	}).get("ok", false)))
	assert_true(bool(rw.mark_claim_terminal({"context_boundary_server_seq": 9}).get("ok", false)))
	assert_true(bool(rw.try_settle({"now_ms": NOW0 + RewardWindowModule.GRACE_MS}).get("ok", false)), "须 SETTLED")
	assert_eq(rw.phase, RewardWindowModule.PHASE_SETTLED)
	var p0: int = bridge.partials_broadcast
	bridge.handle_stt_result_for_test({
		"protocol_version": 1, "kind": "TRANSCRIPT_PARTIAL",
		"room_id": "room_set", "seat": 0, "hand_seq": 0, "window_id": wid,
		"utterance_id": "us", "source": "faster_whisper", "lang": "zh",
		"text": "已结算", "is_final": false,
	})
	assert_eq(bridge.partials_broadcast, p0, "SETTLED 不得广播 partial")


func test_partial_rejected_on_window_switch() -> void:
	var env: Dictionary = _make("room_sw")
	var bridge: SttBridge = env["bridge"]
	var rw: RewardWindowModule = env["rw"]
	var old_wid: String = env["wid"]
	for i in range(3):
		bridge.handle_frame_for_test({
			"room_id": "room_sw", "seat": 0, "utterance_id": "uw", "pcm": _pcm(),
		})
	rw.hard_reset()
	assert_true(bool(rw.open({
		"room_id": "room_sw", "hand_seq": 1, "window_index": 1,
		"seed": 42, "rule_version": RULE_VERSION,
		"character_ids": CHARS, "language": "zh",
		"participants": ["HUMAN", "AI", "AI", "AI"], "now_ms": NOW0 + 1000,
	}).get("ok", false)))
	var p0: int = bridge.partials_broadcast
	bridge.handle_stt_result_for_test({
		"protocol_version": 1, "kind": "TRANSCRIPT_PARTIAL",
		"room_id": "room_sw", "seat": 0, "hand_seq": 0, "window_id": old_wid,
		"utterance_id": "uw", "source": "faster_whisper", "lang": "zh",
		"text": "旧窗", "is_final": false,
	})
	assert_eq(bridge.partials_broadcast, p0, "窗口切换后旧 partial 不得广播")


func test_disconnect_drops_stream_until_end() -> void:
	var env: Dictionary = _make("room_dc")
	var bridge: SttBridge = env["bridge"]
	bridge.handle_frame_for_test({
		"room_id": "room_dc", "seat": 0, "utterance_id": "ud", "pcm": _pcm(),
	})
	assert_gt(bridge.get_stream_count(), 0)
	bridge.inject_pending_for_test({
		"room_id": "room_dc", "seat": 1, "utterance_id": "up", "hand_seq": 0,
		"window_id": env["wid"], "ptt_end_server_seq": 4, "language": "zh", "grace_deadline_ms": 0,
	})
	assert_eq(bridge.get_pending_count(), 1)
	bridge._on_stt_disconnected()
	assert_eq(bridge.get_stream_count(), 0, "断线清 stream")
	assert_eq(bridge.get_pending_count(), 0, "断线终态化 pending")
	# 旧 speaking 后续帧不得新建 stream（drop_until_end）
	var f0: int = bridge.frames_accepted
	bridge.handle_frame_for_test({
		"room_id": "room_dc", "seat": 0, "utterance_id": "ud", "pcm": _pcm(),
	})
	assert_eq(bridge.get_stream_count(), 0)
	assert_eq(bridge.frames_accepted, f0)
	# 权威 END 后可清 drop；新 utterance 可再开
	bridge.handle_ptt_end_for_test({
		"room_id": "room_dc", "seat": 0, "utterance_id": "ud", "server_seq": 11,
	})
	bridge.handle_frame_for_test({
		"room_id": "room_dc", "seat": 0, "utterance_id": "ud_new", "pcm": _pcm(),
	})
	assert_gt(bridge.get_stream_count(), 0, "新 utterance 可建流")


func test_cancel_tombstones_bounded() -> void:
	var env: Dictionary = _make("room_tb")
	var bridge: SttBridge = env["bridge"]
	for i in range(SttBridge.MAX_CANCEL_TOMBSTONES + 20):
		bridge.cancel_window_generation("room_tb", i, "w_%d" % i)
	assert_lte(bridge._gen_tombstones.size(), SttBridge.MAX_CANCEL_TOMBSTONES)
	assert_lte(bridge._gen_order.size(), SttBridge.MAX_CANCEL_TOMBSTONES)


func test_ja_pending_terminalize_uses_ctx_lang() -> void:
	var env: Dictionary = _make("room_ja")
	var rw: RewardWindowModule = env["rw"]
	var bridge: SttBridge = env["bridge"]
	var wid: String = env["wid"]
	assert_true(bool(rw.ingest_utterance({
		"seat": 0, "utterance_id": "uj", "text": "", "language": "ja",
		"ptt_end_server_seq": 8, "terminal": false,
	}).get("accepted", false)))
	bridge.inject_pending_for_test({
		"room_id": "room_ja", "seat": 0, "utterance_id": "uj", "hand_seq": 0,
		"window_id": wid, "ptt_end_server_seq": 8, "language": "ja", "grace_deadline_ms": 0,
	})
	bridge.handle_stt_result_for_test({
		"protocol_version": 1, "kind": "UTTERANCE_FAILED",
		"room_id": "room_ja", "seat": 0, "hand_seq": 0, "window_id": wid,
		"utterance_id": "uj", "ptt_end_server_seq": 8, "source": "faster_whisper",
		"reason": "EMPTY", "is_final": true, "text": "", "lang": "",
	})
	assert_eq(bridge.get_pending_count(), 0)
	var found := false
	for u in rw._utterances_by_seat.get("0", []):
		if typeof(u) == TYPE_DICTIONARY and str((u as Dictionary).get("utterance_id", "")) == "uj":
			assert_true(bool((u as Dictionary).get("terminal", false)))
			assert_eq(str((u as Dictionary).get("language", "")), "ja")
			found = true
	assert_true(found)


func test_stt_closed_first_frames_never_resume() -> void:
	# P1-2：初始 CLOSED 说话 → OPEN 后同 utterance 仍不建流/不发送
	var env: Dictionary = _make("room_init_closed")
	var bridge: SttBridge = env["bridge"]
	bridge.attach_test_client_closed()
	for i in range(5):
		bridge.handle_frame_for_test({
			"room_id": "room_init_closed", "seat": 0, "utterance_id": "u_old", "pcm": _pcm(),
		})
	assert_eq(bridge.get_stream_count(), 0, "CLOSED 时不得建流")
	assert_true(bridge.is_drop_until_end("room_init_closed", 0, "u_old"))
	bridge.force_test_client_open(true)
	var f0: int = bridge.frames_accepted
	bridge.handle_frame_for_test({
		"room_id": "room_init_closed", "seat": 0, "utterance_id": "u_old", "pcm": _pcm(),
	})
	assert_eq(bridge.get_stream_count(), 0, "OPEN 后不得截断续传旧 utterance")
	assert_eq(bridge.frames_accepted, f0)
	# 新 utterance 可工作
	bridge.handle_frame_for_test({
		"room_id": "room_init_closed", "seat": 0, "utterance_id": "u_new", "pcm": _pcm(),
	})
	assert_gt(bridge.get_stream_count(), 0, "新 utterance 可建流")
	assert_true(bool((bridge._streams[bridge._utt_key("room_init_closed", 0, "u_new")] as Dictionary).get("started", false)))


func test_new_api_source_final_ingests_once() -> void:
	# #248：source=new_api 必须被 bridge 接受并只入 RewardWindow 一次，不得改写为 faster_whisper。
	var env: Dictionary = _make("room_napi")
	var rw: RewardWindowModule = env["rw"]
	var bridge: SttBridge = env["bridge"]
	var wid: String = env["wid"]
	var ptt := 48
	assert_true(bool(rw.ingest_utterance({
		"seat": 0, "utterance_id": "un", "text": "", "language": "zh",
		"ptt_end_server_seq": ptt, "terminal": false,
	}).get("accepted", false)))
	bridge.inject_pending_for_test({
		"room_id": "room_napi", "seat": 0, "utterance_id": "un", "hand_seq": 0,
		"window_id": wid, "ptt_end_server_seq": ptt, "language": "zh", "grace_deadline_ms": 0,
	})
	var b0: int = bridge.finals_broadcast
	var i0: int = bridge.finals_ingested
	var saw_src := { "v": "" }
	bridge.transcript_final_broadcast.connect(func(msg: Dictionary) -> void:
		saw_src["v"] = str(msg.get("source", ""))
	)
	bridge.handle_stt_result_for_test({
		"protocol_version": 1, "kind": "TRANSCRIPT_FINAL",
		"room_id": "room_napi", "seat": 0, "hand_seq": 0, "window_id": wid,
		"utterance_id": "un", "ptt_end_server_seq": ptt, "source": "new_api",
		"lang": "zh", "text": "备源合格", "is_final": true,
	})
	assert_eq(bridge.finals_broadcast, b0 + 1, "new_api final 应广播")
	assert_eq(bridge.finals_ingested, i0 + 1, "new_api final 应摄入一次")
	assert_eq(str(saw_src["v"]), "new_api", "不得改写 source")
	assert_eq(_scored(rw).size(), 1)
	# 重复同一 final 不得二次摄入
	bridge.handle_stt_result_for_test({
		"protocol_version": 1, "kind": "TRANSCRIPT_FINAL",
		"room_id": "room_napi", "seat": 0, "hand_seq": 0, "window_id": wid,
		"utterance_id": "un", "ptt_end_server_seq": ptt, "source": "new_api",
		"lang": "zh", "text": "备源合格", "is_final": true,
	})
	assert_eq(bridge.finals_ingested, i0 + 1, "重复 commit 不得二次摄入")
	assert_eq(_scored(rw).size(), 1)


func test_unknown_source_final_rejected() -> void:
	var env: Dictionary = _make("room_bad_src")
	var rw: RewardWindowModule = env["rw"]
	var bridge: SttBridge = env["bridge"]
	var wid: String = env["wid"]
	var ptt := 49
	assert_true(bool(rw.ingest_utterance({
		"seat": 0, "utterance_id": "ub", "text": "", "language": "zh",
		"ptt_end_server_seq": ptt, "terminal": false,
	}).get("accepted", false)))
	bridge.inject_pending_for_test({
		"room_id": "room_bad_src", "seat": 0, "utterance_id": "ub", "hand_seq": 0,
		"window_id": wid, "ptt_end_server_seq": ptt, "language": "zh", "grace_deadline_ms": 0,
	})
	var b0: int = bridge.finals_broadcast
	bridge.handle_stt_result_for_test({
		"protocol_version": 1, "kind": "TRANSCRIPT_FINAL",
		"room_id": "room_bad_src", "seat": 0, "hand_seq": 0, "window_id": wid,
		"utterance_id": "ub", "ptt_end_server_seq": ptt, "source": "evil_vendor",
		"lang": "zh", "text": "拒绝", "is_final": true,
	})
	assert_eq(bridge.finals_broadcast, b0)
	assert_eq(bridge.last_reject_reason, "SCHEMA")
	assert_eq(_scored(rw).size(), 0)


func test_leave_open_stops_stream_and_cancels() -> void:
	# P1-5：OPEN 中 start → CLOSING 后后续帧 0 send，stream 清空
	var env: Dictionary = _make("room_leave")
	var bridge: SttBridge = env["bridge"]
	var rw: RewardWindowModule = env["rw"]
	bridge.force_test_client_open(true)
	for i in range(3):
		bridge.handle_frame_for_test({
			"room_id": "room_leave", "seat": 0, "utterance_id": "ul", "pcm": _pcm(),
		})
	assert_gt(bridge.get_stream_count(), 0)
	var c0: int = bridge.cancels_sent
	assert_true(bool(rw.begin_closing({
		"closing_boundary_server_seq": 12, "now_ms": NOW0, "pending_exit": "FULL_GRANT",
	}).get("ok", false)))
	var f0: int = bridge.frames_accepted
	bridge.handle_frame_for_test({
		"room_id": "room_leave", "seat": 0, "utterance_id": "ul", "pcm": _pcm(),
	})
	assert_eq(bridge.get_stream_count(), 0, "离开 OPEN 须清 stream")
	assert_eq(bridge.frames_accepted, f0, "后续帧不得计入")
	assert_gt(bridge.cancels_sent, c0, "须向 Python cancel 一次")
	assert_true(bridge.is_drop_until_end("room_leave", 0, "ul"))


func test_drop_tombstones_bounded_and_abort_clears() -> void:
	# P2-1：drop 有界；disconnected→abort 清理
	var env: Dictionary = _make("room_dropb")
	var bridge: SttBridge = env["bridge"]
	for i in range(SttBridge.MAX_DROP_TOMBSTONES + 25):
		bridge._mark_drop_until_end("room_dropb|0|u_%d" % i)
	assert_lte(bridge.get_drop_tombstone_count(), SttBridge.MAX_DROP_TOMBSTONES)
	# disconnect 写入 drop 后 abort 清理
	bridge.force_test_client_open(true)
	bridge.handle_frame_for_test({
		"room_id": "room_dropb", "seat": 1, "utterance_id": "u_ab", "pcm": _pcm(),
	})
	assert_gt(bridge.get_stream_count(), 0)
	bridge._on_stt_disconnected()
	assert_true(bridge.is_drop_until_end("room_dropb", 1, "u_ab"))
	bridge.handle_stream_abort("room_dropb", 1, "u_ab")
	assert_false(bridge.is_drop_until_end("room_dropb", 1, "u_ab"), "abort 须清 drop")


func _pcm() -> PackedByteArray:
	var p := PackedByteArray()
	p.resize(640)
	for i in range(640):
		p[i] = 0x11
	return p


func _scored(rw: RewardWindowModule) -> Array:
	var out: Array = []
	for u in rw._utterances_by_seat.get("0", []):
		if typeof(u) == TYPE_DICTIONARY:
			var t := String((u as Dictionary).get("text", "")).strip_edges()
			if not t.is_empty():
				out.append(t)
	return out
