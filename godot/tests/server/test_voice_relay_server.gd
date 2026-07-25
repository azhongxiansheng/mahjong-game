extends GutTest

# E4-02（#244）：真实 TCP/WebSocket 语音中继集成测试。
# 禁止 handle_*_for_test 冒充核心网络链路；绑定 127.0.0.1 动态端口。
# 网络端到端（公网）未验证。

const SECRET := "0123456789abcdef0123456789abcdef"

## 本用例创建的真实 peers / workers，after_each 确定性关闭，避免 orphan / ObjectDB 泄漏
var _tracked_peers: Array = []
var _tracked_workers: Array = []
## JOIN 后待 OPEN 的 RewardWindow（生产门控仅 OPEN 允许 PTT）
var _pending_rw_open: Dictionary = {}


func before_each() -> void:
	_tracked_peers.clear()
	_tracked_workers.clear()
	_pending_rw_open.clear()


func after_each() -> void:
	for p in _tracked_peers:
		if p is WebSocketPeer:
			var peer: WebSocketPeer = p as WebSocketPeer
			if peer.get_ready_state() != WebSocketPeer.STATE_CLOSED:
				peer.close()
	_tracked_peers.clear()
	for w in _tracked_workers:
		if w is HeadlessWorker and is_instance_valid(w):
			(w as HeadlessWorker).stop()
	_tracked_workers.clear()


func _mint_room_token(claims: Dictionary) -> String:
	var body := {
		"typ": "room",
		"room_id": str(claims["room_id"]),
		"seat": int(claims["seat"]),
		"session_id": str(claims["session_id"]),
		"exp": int(claims.get("exp", 9999999999)),
		"round_kind": str(claims.get("round_kind", "EAST")),
		"game_mode": str(claims.get("game_mode", "TRASH_TALK")),
		"participants": claims["participants"],
	}
	var raw: PackedByteArray = JSON.stringify(body).to_utf8_buffer()
	var payload_b64: String = Marshalls.raw_to_base64(raw)
	payload_b64 = payload_b64.replace("+", "-").replace("/", "_").rstrip("=")
	var signing := "v1.r.%s" % payload_b64
	var crypto := Crypto.new()
	var sig: PackedByteArray = crypto.hmac_digest(
		HashingContext.HASH_SHA256,
		SECRET.to_utf8_buffer(),
		signing.to_utf8_buffer()
	)
	var sig_b64: String = Marshalls.raw_to_base64(sig)
	sig_b64 = sig_b64.replace("+", "-").replace("/", "_").rstrip("=")
	return "%s.%s" % [signing, sig_b64]


func _claims(
	room: String,
	seat: int,
	sess: String,
	mode: String = "TRASH_TALK",
	parts: Array = ["HUMAN", "HUMAN", "HUMAN", "HUMAN"]
) -> Dictionary:
	return {
		"room_id": room,
		"seat": seat,
		"session_id": sess,
		"exp": 2_000_000_000,
		"round_kind": "EAST",
		"game_mode": mode,
		"participants": parts,
	}


func _pcm640(fill: int = 0x33) -> PackedByteArray:
	var p := PackedByteArray()
	p.resize(640)
	for i in range(640):
		p[i] = fill & 0xFF
	return p


func _make_worker_with_voice() -> HeadlessWorker:
	var w := HeadlessWorker.new()
	add_child_autofree(w)
	_tracked_workers.append(w)
	assert_true(w.configure(SECRET, "127.0.0.1", 0, 0))
	w.token_now_unix = 1_700_000_000
	var err: Error = w.start_listen()
	assert_eq(err, OK, "worker+voice listen")
	assert_true(w.is_listening())
	assert_not_null(w.get_voice_relay())
	assert_gt(w.get_voice_listen_port(), 0)
	return w


func _connect_client(port: int) -> WebSocketPeer:
	var peer := WebSocketPeer.new()
	var err: Error = peer.connect_to_url("ws://127.0.0.1:%d" % port)
	assert_eq(err, OK)
	_tracked_peers.append(peer)
	return peer


func _pump(w: HeadlessWorker, peers: Array, frames: int = 30) -> void:
	for _i in range(frames):
		w.poll()
		for p in peers:
			if p is WebSocketPeer:
				(p as WebSocketPeer).poll()
		await wait_process_frames(1)
	_ensure_reward_windows_open(w)


func _wait_open(w: HeadlessWorker, peers: Array, max_frames: int = 60) -> bool:
	for _i in range(max_frames):
		w.poll()
		var all_open := true
		for p in peers:
			(p as WebSocketPeer).poll()
			if (p as WebSocketPeer).get_ready_state() != WebSocketPeer.STATE_OPEN:
				all_open = false
		if all_open:
			return true
		await wait_process_frames(1)
	return false


func _recv_jsons(peer: WebSocketPeer) -> Array:
	var out: Array = []
	while peer.get_available_packet_count() > 0:
		var pkt: PackedByteArray = peer.get_packet()
		if peer.was_string_packet():
			var parsed: Variant = JSON.parse_string(pkt.get_string_from_utf8())
			if typeof(parsed) == TYPE_DICTIONARY:
				out.append(parsed)
	return out


func _recv_bins(peer: WebSocketPeer) -> Array:
	var out: Array = []
	while peer.get_available_packet_count() > 0:
		var pkt: PackedByteArray = peer.get_packet()
		if not peer.was_string_packet():
			out.append(pkt)
	return out


func _voice_join(peer: WebSocketPeer, claims: Dictionary) -> void:
	var token := _mint_room_token(claims)
	peer.send_text(JSON.stringify({
		"protocol_version": 1,
		"kind": "JOIN",
		"room_id": str(claims["room_id"]),
		"seat": int(claims["seat"]),
		"room_token": token,
	}))
	# TRASH_TALK：JOIN 后打开真实 RewardWindow（生产仅 OPEN 允许新 PTT）
	if str(claims.get("game_mode", "TRASH_TALK")) == "TRASH_TALK":
		_pending_rw_open[str(claims["room_id"])] = claims.duplicate(true)


func _ensure_reward_windows_open(w: HeadlessWorker) -> void:
	if _pending_rw_open.is_empty():
		return
	for rid in _pending_rw_open.keys():
		var claims: Dictionary = _pending_rw_open[rid] as Dictionary
		var session: HeadlessRoomSession = w.get_room(str(rid))
		if session == null or session.server == null or session.server.mode_modules == null:
			continue
		var rw: RewardWindowModule = session.server.mode_modules.reward_window
		if rw == null:
			continue
		if rw.phase == RewardWindowModule.PHASE_OPEN:
			continue
		if rw.phase != RewardWindowModule.PHASE_IDLE and rw.phase != RewardWindowModule.PHASE_SETTLED:
			continue
		if rw.phase == RewardWindowModule.PHASE_SETTLED:
			rw.hard_reset()
		var res: Dictionary = rw.open({
			"room_id": str(rid),
			"hand_seq": 0,
			"window_index": 0,
			"seed": int(session.authority_seed),
			"rule_version": "trash_talk_rules_v1",
			"character_ids": session.character_ids,
			"language": "zh",
			"participants": claims.get("participants", ["HUMAN", "HUMAN", "HUMAN", "HUMAN"]),
			"now_ms": 1_700_000_000_000,
		})
		assert_true(bool(res.get("ok", false)), "voice 测试须打开真实 RW: %s" % str(res))
	_pending_rw_open.clear()


func _ptt_ctrl(claims: Dictionary, kind: String, utt: String, extra: Dictionary = {}) -> Dictionary:
	var d := {
		"protocol_version": 1,
		"room_id": str(claims["room_id"]),
		"session_id": str(claims["session_id"]),
		"seat": int(claims["seat"]),
		"kind": kind,
		"utterance_id": utt,
	}
	for k in extra.keys():
		d[k] = extra[k]
	return d


func _ptt_start(peer: WebSocketPeer, claims: Dictionary, utt: String) -> void:
	peer.send_text(JSON.stringify(_ptt_ctrl(claims, "PTT_START", utt)))


func _encode_pcm(seat: int, utt: String, seq: int, fill: int = 0x55) -> PackedByteArray:
	return VoiceBinaryCodec.encode_frame({
		"protocol_version": 1,
		"seat": seat,
		"sample_format_code": 1,
		"channels": 1,
		"sample_rate": 16000,
		"frame_duration_ms": 20,
		"frame_seq": seq,
		"utterance_id": utt,
	}, _pcm640(fill))


func test_join_token_and_standard_reject() -> void:
	var w := _make_worker_with_voice()
	var vport: int = w.get_voice_listen_port()
	var peer := _connect_client(vport)
	assert_true(await _wait_open(w, [peer]))

	# STANDARD 硬拒绝
	var std_claims := _claims("room-std", 0, "sess-std", "STANDARD")
	_voice_join(peer, std_claims)
	await _pump(w, [peer], 20)
	var msgs: Array = _recv_jsons(peer)
	var saw_unauth := false
	for m in msgs:
		if str(m.get("kind", "")) == "ERROR" and str(m.get("code", "")) == "UNAUTHORIZED":
			saw_unauth = true
			assert_false(m.has("server_seq"), "ERROR 无 server_seq")
			assert_false(m.has("view_hash"), "ERROR 无 view_hash")
	assert_true(saw_unauth, "STANDARD 须拒绝")
	assert_false(w.get_voice_relay().has_room_voice_state("room-std"), "不得保留 STANDARD 语音状态")

	# 坏 token
	peer.send_text(JSON.stringify({
		"protocol_version": 1,
		"kind": "JOIN",
		"room_id": "room-bad",
		"seat": 0,
		"room_token": "v1.r.bad.sig",
	}))
	await _pump(w, [peer], 15)
	var msgs2: Array = _recv_jsons(peer)
	var bad_tok := false
	for m in msgs2:
		if str(m.get("kind", "")) == "ERROR" and str(m.get("code", "")) == "UNAUTHORIZED":
			bad_tok = true
	assert_true(bad_tok)

	# TRASH_TALK 合法 JOIN
	var peer2 := _connect_client(vport)
	assert_true(await _wait_open(w, [peer2]))
	var ok_claims := _claims("room-tt", 0, "sess-0")
	_voice_join(peer2, ok_claims)
	await _pump(w, [peer2], 20)
	var joined := false
	for m in _recv_jsons(peer2):
		if str(m.get("kind", "")) == "VOICE_JOINED":
			joined = true
	assert_true(joined, "TRASH_TALK JOIN 成功")
	assert_true(w.get_voice_relay().has_room_voice_state("room-tt"))


func test_two_client_pcm_loopback_and_voice_port_ingest() -> void:
	var w := _make_worker_with_voice()
	var vport: int = w.get_voice_listen_port()
	var c0 := _connect_client(vport)
	var c1 := _connect_client(vport)
	assert_true(await _wait_open(w, [c0, c1]))

	var cl0 := _claims("room-loop", 0, "sess-0")
	var cl1 := _claims("room-loop", 1, "sess-1")
	_voice_join(c0, cl0)
	_voice_join(c1, cl1)
	await _pump(w, [c0, c1], 25)
	assert_eq(w.get_voice_relay().room_voice_conn_count("room-loop"), 2)

	# 远端 VoicePort 绑定 seat1 + 公共 room/session（#243 契约）
	var vp := VoicePortModule.new()
	vp.bind_public_identity("room-loop", "sess-1", 1)
	assert_eq(vp.room_id(), "room-loop")
	assert_eq(vp.session_id(), "sess-1")
	assert_eq(vp.local_seat(), 1)

	_ptt_start(c0, cl0, "utt-loop-1")
	await _pump(w, [c0, c1], 10)
	var raw: PackedByteArray = _encode_pcm(0, "utt-loop-1", 0, 0x55)
	assert_false(raw.is_empty())
	c0.put_packet(raw)
	await _pump(w, [c0, c1], 30)

	var bins: Array = _recv_bins(c1)
	assert_gt(bins.size(), 0, "双端 PCM 环回：c1 应收二进制")
	var dec: Dictionary = VoiceBinaryCodec.decode_frame(bins[0])
	assert_false(dec.is_empty())
	assert_eq(int(dec["seat"]), 0)
	assert_eq(int(dec["frame_seq"]), 0)
	assert_eq((dec["pcm"] as PackedByteArray)[0], 0x55)

	# 不回送发送方
	var self_bins: Array = _recv_bins(c0)
	assert_eq(self_bins.size(), 0, "不得回送发送座位")

	# STT 挂点
	assert_gt(w.get_voice_relay().stt_frame_hook_count(), 0)

	# VoicePort ingest 契约（重建 room/session/seat）
	var rebuilt: Dictionary = VoiceBinaryCodec.to_voice_port_frame(dec, "room-loop", "sess-1")
	var ir: Dictionary = vp.ingest_remote_audio_frame(rebuilt)
	assert_true(bool(ir.get("ok", false)), "VoicePort ingest 应成功: %s" % str(ir))
	assert_eq(vp.remote_queue_size(0), 1)


func test_four_seat_broadcast_no_cross_room() -> void:
	var w := _make_worker_with_voice()
	var vport: int = w.get_voice_listen_port()
	var peers: Array = []
	for i in range(4):
		peers.append(_connect_client(vport))
	assert_true(await _wait_open(w, peers))
	for i in range(4):
		_voice_join(peers[i], _claims("room-4", i, "sess-%d" % i))
	# 跨房
	var other := _connect_client(vport)
	assert_true(await _wait_open(w, [other]))
	_voice_join(other, _claims("room-other", 0, "sess-x"))
	await _pump(w, peers + [other], 30)

	var cl0 := _claims("room-4", 0, "sess-0")
	_ptt_start(peers[0], cl0, "utt-4")
	await _pump(w, peers + [other], 10)
	(peers[0] as WebSocketPeer).put_packet(_encode_pcm(0, "utt-4", 1, 0x66))
	await _pump(w, peers + [other], 30)

	for i in range(1, 4):
		var bins: Array = _recv_bins(peers[i])
		assert_gt(bins.size(), 0, "席 %d 应收到广播" % i)
	var cross: Array = _recv_bins(other)
	assert_eq(cross.size(), 0, "跨房不得收到")
	assert_eq(_recv_bins(peers[0]).size(), 0, "发送席不回送")


func test_backpressure_drop_old_and_reject_dup_reorder() -> void:
	var w := _make_worker_with_voice()
	var relay: VoiceRelayServer = w.get_voice_relay()
	relay.outbound_queue_capacity = 3
	relay.outbound_send_budget_per_poll = 1
	var vport: int = w.get_voice_listen_port()
	var c0 := _connect_client(vport)
	var c1 := _connect_client(vport)
	assert_true(await _wait_open(w, [c0, c1]))
	var cl0 := _claims("room-bp", 0, "s0")
	var cl1 := _claims("room-bp", 1, "s1")
	_voice_join(c0, cl0)
	_voice_join(c1, cl1)
	await _pump(w, [c0, c1], 20)
	_ptt_start(c0, cl0, "utt-bp")
	await _pump(w, [c0, c1], 8)

	# 重复帧
	var raw0: PackedByteArray = _encode_pcm(0, "utt-bp", 5, 1)
	c0.put_packet(raw0)
	c0.put_packet(raw0)  # dup
	await _pump(w, [c0, c1], 15)
	var bins1: Array = _recv_bins(c1)
	assert_eq(bins1.size(), 1, "重复帧只广播一次")

	# 倒序拒绝
	c0.put_packet(_encode_pcm(0, "utt-bp", 3, 2))
	await _pump(w, [c0, c1], 10)
	assert_eq(_recv_bins(c1).size(), 0, "倒序不广播")

	# 跳帧允许
	c0.put_packet(_encode_pcm(0, "utt-bp", 9, 3))
	await _pump(w, [c0, c1], 10)
	assert_gt(_recv_bins(c1).size(), 0, "跳帧允许")

	# 慢接收多轮：暂停读 c1，持续多轮突发 → 应用队列与 peer 缓冲均有界
	_recv_bins(c1)
	var cid1: int = relay.conn_id_for_seat("room-bp", 1)
	assert_gt(cid1, 0)
	relay.peer_flush_high_water = 256
	relay.peer_outbound_buffer_size = 1024
	var max_app_q := 0
	var max_peer_buf := 0
	var drops0: int = relay.conn_outbound_dropped_count(cid1)
	for round_i in range(5):
		for i in range(15):
			c0.put_packet(_encode_pcm(0, "utt-bp", 10 + round_i * 20 + i, 0x10 + i))
		for _j in range(6):
			w.poll()
			c0.poll()
			# 故意不 poll c1，保持慢读
		max_app_q = maxi(max_app_q, relay.conn_outbound_queue_size(cid1))
		max_peer_buf = maxi(max_peer_buf, relay.conn_peer_outbound_buffered(cid1))
	assert_lte(max_app_q, 3, "出站应用队列有界")
	assert_gt(relay.conn_outbound_dropped_count(cid1), drops0, "多轮慢读须持续 drop-old")
	assert_lte(max_peer_buf, relay.peer_outbound_buffer_size, "peer outbound buffered 有界")
	# 他席仍可 JOIN 语音
	var c2 := _connect_client(vport)
	assert_true(await _wait_open(w, [c2]))
	_voice_join(c2, _claims("room-bp", 2, "s2"))
	await _pump(w, [c0, c2], 20)
	assert_eq(relay.room_voice_conn_count("room-bp"), 3)
	# 牌局通道仍可及时 JOIN（同进程）
	var gpeer := _connect_client(w.get_listen_port())
	assert_true(await _wait_open(w, [gpeer]))
	var gclaims := _claims("room-bp-game", 0, "gs0")
	gpeer.send_text(JSON.stringify({
		"protocol_version": 1,
		"kind": "JOIN",
		"room_id": "room-bp-game",
		"seat": 0,
		"room_token": _mint_room_token(gclaims),
	}))
	await _pump(w, [gpeer, c0], 20)
	assert_not_null(w.get_room("room-bp-game"), "语音背压不得阻塞牌局")

	# 恢复读
	await _pump(w, [c0, c1, c2], 50)
	var late: Array = _recv_bins(c1)
	assert_gt(late.size(), 0)


func test_disconnect_clears_buffers() -> void:
	var w := _make_worker_with_voice()
	var vport: int = w.get_voice_listen_port()
	var c0 := _connect_client(vport)
	assert_true(await _wait_open(w, [c0]))
	_voice_join(c0, _claims("room-dc", 0, "s0"))
	await _pump(w, [c0], 15)
	var cldc := _claims("room-dc", 0, "s0")
	_ptt_start(c0, cldc, "utt-dc")
	await _pump(w, [c0], 8)
	c0.put_packet(_encode_pcm(0, "utt-dc", 0))
	await _pump(w, [c0], 10)
	assert_true(w.get_voice_relay().has_room_voice_state("room-dc"))
	c0.close()
	await _pump(w, [c0], 20)
	assert_false(w.get_voice_relay().has_room_voice_state("room-dc"), "断线清房间语音状态")


func test_game_channel_rejects_binary_isolation() -> void:
	var w := _make_worker_with_voice()
	var gport: int = w.get_listen_port()
	var vport: int = w.get_voice_listen_port()
	assert_ne(gport, vport, "牌局与语音必须不同端口")

	# 1) 牌局通道：未 JOIN 直接送二进制 → COMMAND_REJECTED + 断开
	var peer := _connect_client(gport)
	assert_true(await _wait_open(w, [peer]))
	var raw: PackedByteArray = VoiceBinaryCodec.encode_frame({
		"protocol_version": 1, "seat": 0, "sample_format_code": 1, "channels": 1,
		"sample_rate": 16000, "frame_duration_ms": 20, "frame_seq": 0,
		"utterance_id": "x",
	}, _pcm640())
	assert_false(raw.is_empty())
	peer.put_packet(raw)
	var saw_reject := false
	for _i in range(40):
		w.poll()
		peer.poll()
		for m in _recv_jsons(peer):
			if str(m.get("kind", "")) == "ERROR" and str(m.get("code", "")) == "COMMAND_REJECTED":
				if str(m.get("message", "")).findn("binary") >= 0:
					saw_reject = true
		var st: int = peer.get_ready_state()
		if st == WebSocketPeer.STATE_CLOSING or st == WebSocketPeer.STATE_CLOSED:
			saw_reject = true
			break
		if saw_reject:
			break
		await wait_process_frames(1)
	assert_true(saw_reject, "牌局通道须拒绝 binary")

	# 2) 同进程语音端口仍接受合法 JOIN（通道隔离）
	var vpeer := _connect_client(vport)
	assert_true(await _wait_open(w, [vpeer]))
	_voice_join(vpeer, _claims("room-iso-v", 0, "s0"))
	await _pump(w, [vpeer], 25)
	var joined := false
	for m in _recv_jsons(vpeer):
		if str(m.get("kind", "")) == "VOICE_JOINED":
			joined = true
	assert_true(joined, "语音端口不受牌局 binary 拒绝影响")


func test_forged_ptt_end_no_stt_no_seq() -> void:
	var w := _make_worker_with_voice()
	var vport: int = w.get_voice_listen_port()
	var c0 := _connect_client(vport)
	assert_true(await _wait_open(w, [c0]))
	var cl := _claims("room-fg", 0, "s0")
	_voice_join(c0, cl)
	await _pump(w, [c0], 20)
	var room: HeadlessRoomSession = w.get_room("room-fg")
	assert_not_null(room)
	var seq_before: int = room.current_server_seq()
	var stt_end_before: int = w.get_voice_relay().stt_ptt_end_hook_count()
	var stt_frame_before: int = w.get_voice_relay().stt_frame_hook_count()

	# 有音频后伪造 END：仍不得权威 seq / STT END
	c0.send_text(JSON.stringify(_ptt_ctrl(cl, "PTT_START", "utt-forge-audio")))
	await _pump(w, [c0], 8)
	var frame_raw: PackedByteArray = VoiceBinaryCodec.encode_frame({
		"protocol_version": 1, "seat": 0, "utterance_id": "utt-forge-audio",
		"frame_seq": 0, "sample_format_code": 1, "channels": 1,
		"sample_rate": 16000, "frame_duration_ms": 20,
	}, _pcm640(0x55))
	assert_false(frame_raw.is_empty())
	c0.put_packet(frame_raw)
	await _pump(w, [c0], 10)
	assert_gt(w.get_voice_relay().stt_frame_hook_count(), stt_frame_before, "合法帧可进 hook")
	var ends_after_frames: int = w.get_voice_relay().stt_ptt_end_hook_count()
	c0.send_text(JSON.stringify(_ptt_ctrl(cl, "PTT_END", "utt-forge-audio", {"server_seq": 99})))
	await _pump(w, [c0], 20)
	var saw_forgery_audio := false
	for m in _recv_jsons(c0):
		if str(m.get("kind", "")) == "ERROR" and str(m.get("code", "")) == "FORGERY_REJECTED":
			saw_forgery_audio = true
	assert_true(saw_forgery_audio, "有帧后伪造 END 仍拒")
	assert_eq(w.get_voice_relay().stt_ptt_end_hook_count(), ends_after_frames, "伪造 END 不得进 STT END")
	assert_eq(room.current_server_seq(), seq_before, "伪造不得分配序号")

	c0.send_text(JSON.stringify(_ptt_ctrl(cl, "PTT_END", "utt-forge", {"server_seq": 99})))
	await _pump(w, [c0], 20)
	var saw_forgery := false
	for m in _recv_jsons(c0):
		if str(m.get("kind", "")) == "ERROR" and str(m.get("code", "")) == "FORGERY_REJECTED":
			saw_forgery = true
			assert_false(m.has("server_seq"))
			assert_false(m.has("view_hash"))
	assert_true(saw_forgery)
	assert_eq(room.current_server_seq(), seq_before, "伪造不得分配序号")
	assert_eq(w.get_voice_relay().stt_ptt_end_hook_count(), ends_after_frames, "伪造不得送 STT END")
	# #247：伪造 utterance 不得进入 RewardWindow 累计
	if room.server != null and room.server.mode_modules != null:
		var rw: RewardWindowModule = room.server.mode_modules.reward_window
		if rw != null:
			var snap: Dictionary = rw.capture_state()
			var by_seat: Dictionary = snap.get("_utterances_by_seat", {}) as Dictionary
			for sk in by_seat.keys():
				for u in by_seat[sk]:
					if typeof(u) == TYPE_DICTIONARY:
						assert_ne(str(u.get("utterance_id", "")), "utt-forge")
						assert_ne(str(u.get("utterance_id", "")), "utt-forge-audio")

	c0.send_text(JSON.stringify(_ptt_ctrl(cl, "PTT_END", "utt-forge2", {"server_seq_ref": 1})))
	await _pump(w, [c0], 15)
	var saw2 := false
	for m in _recv_jsons(c0):
		if str(m.get("code", "")) == "FORGERY_REJECTED":
			saw2 = true
	assert_true(saw2)

	# 其它权威字段
	c0.send_text(JSON.stringify(_ptt_ctrl(cl, "PTT_END", "utt-forge3", {
		"closing_boundary_server_seq": 1,
	})))
	await _pump(w, [c0], 12)
	var saw3 := false
	for m in _recv_jsons(c0):
		if str(m.get("code", "")) == "FORGERY_REJECTED":
			saw3 = true
	assert_true(saw3)
	c0.send_text(JSON.stringify(_ptt_ctrl(cl, "PTT_END", "utt-forge4", {
		"grace_deadline_at": 1,
	})))
	await _pump(w, [c0], 12)
	var saw4 := false
	for m in _recv_jsons(c0):
		if str(m.get("code", "")) == "FORGERY_REJECTED":
			saw4 = true
	assert_true(saw4)


func test_legal_ptt_end_gets_authority_server_seq() -> void:
	var w := _make_worker_with_voice()
	var vport: int = w.get_voice_listen_port()
	var c0 := _connect_client(vport)
	var c1 := _connect_client(vport)
	assert_true(await _wait_open(w, [c0, c1]))
	var cl0 := _claims("room-ptt", 0, "s0")
	var cl1 := _claims("room-ptt", 1, "s1")
	_voice_join(c0, cl0)
	_voice_join(c1, cl1)
	await _pump(w, [c0, c1], 20)
	var room: HeadlessRoomSession = w.get_room("room-ptt")
	assert_not_null(room)
	var seq0: int = room.current_server_seq()

	c0.send_text(JSON.stringify(_ptt_ctrl(cl0, "PTT_START", "utt-ok")))
	await _pump(w, [c0, c1], 10)
	c0.send_text(JSON.stringify(_ptt_ctrl(cl0, "PTT_END", "utt-ok")))
	await _pump(w, [c0, c1], 20)

	var auth_seq := -1
	for m in _recv_jsons(c0):
		if str(m.get("kind", "")) == "PTT_END" and m.has("server_seq"):
			auth_seq = int(m["server_seq"])
	assert_gt(auth_seq, seq0, "合法 PTT_END 须推进权威序号")
	assert_eq(room.current_server_seq(), auth_seq)
	assert_gt(w.get_voice_relay().stt_ptt_end_hook_count(), 0)

	# 他席收到权威 PTT_END
	var other_got := false
	for m in _recv_jsons(c1):
		if str(m.get("kind", "")) == "PTT_END" and int(m.get("server_seq", -1)) == auth_seq:
			other_got = true
	assert_true(other_got, "他席应收到权威 PTT_END")


func test_worker_stop_clears_voice() -> void:
	var w := _make_worker_with_voice()
	var vport: int = w.get_voice_listen_port()
	var c0 := _connect_client(vport)
	assert_true(await _wait_open(w, [c0]))
	_voice_join(c0, _claims("room-stop", 0, "s0"))
	await _pump(w, [c0], 15)
	assert_true(w.get_voice_relay().has_room_voice_state("room-stop"))
	w.stop()
	assert_null(w.get_voice_relay())


func test_voice_relay_client_and_port_production_chain() -> void:
	# VoicePortModule → VoiceRelayClient → 真实 WS → VoiceRelayServer → 对端 VoicePort.ingest
	var w := _make_worker_with_voice()
	var vport: int = w.get_voice_listen_port()
	var url := "ws://127.0.0.1:%d" % vport

	var vp0 := VoicePortModule.new()
	vp0.set_capture_backend(VoicePortModule.CaptureBackend.FIXTURE)
	vp0.bind_public_identity("room-prod", "sess-0", 0)
	var vp1 := VoicePortModule.new()
	vp1.bind_public_identity("room-prod", "sess-1", 1)

	var cli0 := VoiceRelayClient.new()
	var cli1 := VoiceRelayClient.new()
	add_child_autofree(cli0)
	add_child_autofree(cli1)
	cli0.bind_voice_port(vp0)
	cli1.bind_voice_port(vp1)

	var tok0 := _mint_room_token(_claims("room-prod", 0, "sess-0"))
	var tok1 := _mint_room_token(_claims("room-prod", 1, "sess-1"))
	assert_eq(cli0.connect_voice(url, "room-prod", 0, "sess-0", tok0), OK)
	assert_eq(cli1.connect_voice(url, "room-prod", 1, "sess-1", tok1), OK)

	for _i in range(50):
		w.poll()
		cli0.poll()
		cli1.poll()
		if cli0.is_joined() and cli1.is_joined():
			break
		await wait_process_frames(1)
	assert_true(cli0.is_joined())
	assert_true(cli1.is_joined())
	assert_eq(vp0.room_id(), "room-prod")
	assert_eq(vp0.local_seat(), 0)

	# 生产路径经 VoiceRelayClient JOIN，不走 _voice_join；仍须显式打开真实 RW（OPEN-only 门控）
	_pending_rw_open["room-prod"] = _claims("room-prod", 0, "sess-0")
	_ensure_reward_windows_open(w)
	assert_true(w.voice_accepts_new_utterance("room-prod"), "room-prod 须 PHASE_OPEN")

	assert_true(vp0.press_ptt())
	var stereo := PackedVector2Array()
	for i in range(320):
		stereo.append(Vector2(0.2, 0.2))
	vp0.feed_capture_samples(stereo, 16000)
	assert_gt(vp0.outbound_queue_size(), 0)
	# 出站帧经 client 发送（信号已触发 encode）；再 pop 清队列亦可
	while vp0.outbound_queue_size() > 0:
		vp0.pop_outbound_frame()

	for _i in range(40):
		w.poll()
		cli0.poll()
		cli1.poll()
		if vp1.remote_queue_size(0) > 0:
			break
		await wait_process_frames(1)
	assert_gt(vp1.remote_queue_size(0), 0, "对端 VoicePort 应收远端 PCM")
	var rf: Dictionary = vp1.pop_remote_frame(0)
	assert_eq(int(rf.get("seat", -1)), 0)
	assert_eq(String(rf.get("room_id", "")), "room-prod")
	assert_eq((rf.get("pcm", PackedByteArray()) as PackedByteArray).size(), 640)

	vp0.release_ptt()
	for _i in range(30):
		w.poll()
		cli0.poll()
		cli1.poll()
		await wait_process_frames(1)
	assert_gt(w.get_voice_relay().stt_ptt_end_hook_count(), 0)


func test_ptt_state_machine_and_idempotent_end() -> void:
	var w := _make_worker_with_voice()
	var vport: int = w.get_voice_listen_port()
	var c0 := _connect_client(vport)
	assert_true(await _wait_open(w, [c0]))
	var cl := _claims("room-sm", 0, "s0")
	_voice_join(c0, cl)
	await _pump(w, [c0], 15)

	c0.put_packet(_encode_pcm(0, "u-x", 0))
	await _pump(w, [c0], 12)
	var no_start := false
	for m in _recv_jsons(c0):
		if str(m.get("code", "")) == "COMMAND_REJECTED" and str(m.get("message", "")).contains("ptt start"):
			no_start = true
	assert_true(no_start)

	_ptt_start(c0, cl, "u1")
	await _pump(w, [c0], 8)
	_ptt_start(c0, cl, "u2")
	await _pump(w, [c0], 8)
	var dup_start := false
	for m in _recv_jsons(c0):
		if str(m.get("code", "")) == "COMMAND_REJECTED" and str(m.get("message", "")).contains("already speaking"):
			dup_start = true
	assert_true(dup_start)

	c0.put_packet(_encode_pcm(0, "wrong", 0))
	await _pump(w, [c0], 8)
	var bad_utt := false
	for m in _recv_jsons(c0):
		if str(m.get("message", "")).contains("utterance mismatch"):
			bad_utt = true
	assert_true(bad_utt)

	c0.send_text(JSON.stringify(_ptt_ctrl(cl, "PTT_END", "u1", {"foo": 1})))
	await _pump(w, [c0], 8)
	var extra := false
	for m in _recv_jsons(c0):
		if str(m.get("code", "")) == "COMMAND_REJECTED":
			extra = true
	assert_true(extra)

	var room: HeadlessRoomSession = w.get_room("room-sm")
	var seq0: int = room.current_server_seq()
	var stt0: int = w.get_voice_relay().stt_ptt_end_hook_count()
	c0.send_text(JSON.stringify(_ptt_ctrl(cl, "PTT_END", "u1")))
	await _pump(w, [c0], 15)
	var auth_seq := -1
	for m in _recv_jsons(c0):
		if str(m.get("kind", "")) == "PTT_END" and m.has("server_seq"):
			auth_seq = int(m["server_seq"])
	assert_gt(auth_seq, seq0)
	assert_eq(w.get_voice_relay().stt_ptt_end_hook_count(), stt0 + 1)

	c0.send_text(JSON.stringify(_ptt_ctrl(cl, "PTT_END", "u1")))
	await _pump(w, [c0], 12)
	var replay_seq := -1
	for m in _recv_jsons(c0):
		if str(m.get("kind", "")) == "PTT_END" and m.has("server_seq"):
			replay_seq = int(m["server_seq"])
	assert_eq(replay_seq, auth_seq)
	assert_eq(room.current_server_seq(), auth_seq)
	assert_eq(w.get_voice_relay().stt_ptt_end_hook_count(), stt0 + 1)


func test_cross_channel_seq_bridge_no_permanent_gap() -> void:
	# 真实 WS 建房 + 真实 journal/NBC + 真实语音 WS 的 PTT_END 序号协调
	var w := _make_worker_with_voice()
	var vport: int = w.get_voice_listen_port()
	var gport: int = w.get_listen_port()
	var cl := _claims("room-gap", 0, "sess-gap", "TRASH_TALK", ["HUMAN", "AI", "AI", "AI"])

	var gpeer := _connect_client(gport)
	assert_true(await _wait_open(w, [gpeer]))
	gpeer.send_text(JSON.stringify({
		"protocol_version": 1,
		"kind": "JOIN",
		"room_id": "room-gap",
		"seat": 0,
		"room_token": _mint_room_token(cl),
	}))
	await _pump(w, [gpeer], 20)
	gpeer.send_text(JSON.stringify({
		"protocol_version": 1,
		"kind": "READY",
		"room_id": "room-gap",
		"seat": 0,
	}))
	await _pump(w, [gpeer], 40)
	var session: HeadlessRoomSession = w.get_room("room-gap")
	assert_not_null(session)
	assert_true(session.is_started(), "真实 READY 后房间须启动")

	var nbc := NetworkedBattleController.new("room-gap", 0)
	nbc.configure_snapshot_registry_for_mode("TRASH_TALK")
	var bridge := AuthoritySeqBridge.new()
	bridge.bind_networked_controller(nbc)
	# 消费权威 journal（与 WS 下发同源；避免测试 peer 缓冲丢失）
	var journal: Array = session.event_journal(0)
	assert_gt(journal.size(), 0, "开局须有业务事件")
	# 从最后一条 ROOM_SNAPSHOT 恢复投影，再按序消费后续（TRASH 模块契约）
	var last_snap: NetworkedEvent = null
	for e in journal:
		if e is NetworkedEvent and (e as NetworkedEvent).kind == "ROOM_SNAPSHOT":
			last_snap = e as NetworkedEvent
	assert_not_null(last_snap, "须有 ROOM_SNAPSHOT")
	assert_true(nbc.ingest_networked_event(last_snap), "快照须可应用")
	for e2 in journal:
		if not (e2 is NetworkedEvent):
			continue
		var ne2: NetworkedEvent = e2 as NetworkedEvent
		if int(ne2.server_seq) <= int(last_snap.server_seq):
			continue
		assert_true(nbc.ingest_networked_event(ne2), "快照后增量须可应用 kind=%s seq=%d" % [ne2.kind, ne2.server_seq])
	var seq_after_snap: int = nbc.current_seq()
	assert_gt(seq_after_snap, 0)
	assert_eq(seq_after_snap, session.current_server_seq(), "NBC 须追上权威序号")
	assert_false(nbc.resync_required())

	# 真实语音 WS：PTT_END 占用下一权威序号
	var vpeer := _connect_client(vport)
	assert_true(await _wait_open(w, [vpeer]))
	_voice_join(vpeer, cl)
	await _pump(w, [vpeer, gpeer], 20)
	_ptt_start(vpeer, cl, "utt-gap")
	await _pump(w, [vpeer, gpeer], 8)
	vpeer.send_text(JSON.stringify(_ptt_ctrl(cl, "PTT_END", "utt-gap")))
	await _pump(w, [vpeer, gpeer], 20)
	var ptt_seq := -1
	for m in _recv_jsons(vpeer):
		if str(m.get("kind", "")) == "PTT_END" and m.has("server_seq"):
			ptt_seq = int(m["server_seq"])
	assert_eq(ptt_seq, seq_after_snap + 1, "PTT_END 应紧接当前权威序号")
	assert_eq(session.current_server_seq(), ptt_seq)

	# 顺序 A：先侧通道再牌局
	assert_true(bool(bridge.on_side_channel_authority_seq(ptt_seq).get("ok", false)))
	assert_eq(nbc.current_seq(), ptt_seq)
	assert_false(nbc.resync_required())

	# 发布下一条真实 ROOM_SNAPSHOT（同源 LocalLoopbackServer）
	assert_true(session.server.publish_snapshot(), "发布后续快照")
	var after_events: Array = session.events_since(0, ptt_seq)
	assert_gt(after_events.size(), 0, "须有后续业务事件")
	for e2 in after_events:
		var rr2: Dictionary = bridge.on_game_networked_event(e2)
		assert_true(bool(rr2.get("ok", false)), "后续业务事件: %s" % str(rr2))
	assert_gt(nbc.current_seq(), ptt_seq)
	assert_false(nbc.resync_required(), "不得因 PTT 序号永久 resync")

	# 顺序 B：side 先 hold 高序号，再补低序号 side 填洞（不依赖 SNAPSHOT hold）
	var nbc_b := NetworkedBattleController.new("room-gap", 0)
	nbc_b.configure_snapshot_registry_for_mode("TRASH_TALK")
	var bridge_b := AuthoritySeqBridge.new()
	bridge_b.bind_networked_controller(nbc_b)
	assert_true(nbc_b.ingest_networked_event(last_snap))
	for e3 in journal:
		if not (e3 is NetworkedEvent):
			continue
		var ne3: NetworkedEvent = e3 as NetworkedEvent
		if int(ne3.server_seq) <= int(last_snap.server_seq):
			continue
		assert_true(nbc_b.ingest_networked_event(ne3))
	var base_b: int = nbc_b.current_seq()
	assert_eq(base_b, seq_after_snap)
	assert_eq(str(bridge_b.on_side_channel_authority_seq(base_b + 2).get("reason", "")), "HELD_SIDE")
	assert_eq(bridge_b.held_side_count(), 1)
	assert_true(bool(bridge_b.on_side_channel_authority_seq(base_b + 1).get("ok", false)))
	assert_eq(bridge_b.held_side_count(), 0)
	assert_eq(nbc_b.current_seq(), base_b + 2)
	assert_false(nbc_b.resync_required())


func test_voice_client_join_once_and_release() -> void:
	var w := _make_worker_with_voice()
	var vport: int = w.get_voice_listen_port()
	var url := "ws://127.0.0.1:%d" % vport
	var cl := _claims("room-cli", 0, "sess-cli")
	var vp := VoicePortModule.new()
	vp.set_capture_backend(VoicePortModule.CaptureBackend.FIXTURE)
	vp.bind_public_identity("room-cli", "sess-cli", 0)
	var cli := VoiceRelayClient.new()
	add_child_autofree(cli)
	cli.bind_voice_port(vp)
	assert_eq(cli.connect_voice(url, "room-cli", 0, "sess-cli", _mint_room_token(cl)), OK)
	var errs: Array = []
	cli.error_received.connect(func(m: Dictionary): errs.append(m.duplicate(true)))
	for _i in range(40):
		w.poll()
		cli.poll()
		if cli.is_joined():
			break
		await wait_process_frames(1)
	assert_true(cli.is_joined())
	assert_true(cli.join_sent())
	# 再 poll 多帧：不得尾随 already joined
	for _i in range(15):
		w.poll()
		cli.poll()
		await wait_process_frames(1)
	for e in errs:
		assert_false(str(e.get("message", "")).contains("already joined"), "不得尾随 already joined")
	assert_true(vp.press_ptt())
	cli.disconnect_voice()
	assert_false(vp.is_ptt_pressed())
	assert_eq(vp.outbound_queue_size(), 0)
	assert_false(cli.is_joined())


func test_public_casual_session_wires_voice_from_assigned() -> void:
	var w := _make_worker_with_voice()
	# 真实 bundle.voice_port（非 session 自建）
	var intent := SessionIntent.new(&"PRACTICE", &"EAST", &"TRASH_TALK", &"lin_yeche")
	var conv = GameSessionConfig.from_intent(intent, 3, "guest-1", "rv-pub", {})
	assert_true(conv.ok)
	var bundle := ModeModuleBundle.from_config(conv.config)
	assert_not_null(bundle.voice_port)
	assert_ne(bundle.voice_port.capture_backend(), VoicePortModule.CaptureBackend.FIXTURE)

	# 1 HUMAN + 3 AI：单席 READY 即可 start
	var pub_claims := _claims("room-pub", 0, "guest-1", "TRASH_TALK", ["HUMAN", "AI", "AI", "AI"])
	var assigned := {
		"status": "assigned",
		"worker": "ws://127.0.0.1:%d" % w.get_listen_port(),
		"voice_worker": "ws://127.0.0.1:%d" % w.get_voice_listen_port(),
		"room_id": "room-pub",
		"seat": 0,
		"room_token": _mint_room_token(pub_claims),
		"game_mode": "TRASH_TALK",
	}
	var sess := PublicCasualNetworkSession.new()
	add_child_autofree(sess)
	assert_true(sess.configure_from_assigned(assigned, "guest-1"))
	assert_true(sess.bind_mode_modules(bundle))
	# 生产不强制 fixture；测试可显式切 FIXTURE
	bundle.voice_port.set_capture_backend(VoicePortModule.CaptureBackend.FIXTURE)
	assert_eq(sess.start(), OK)
	assert_true(sess.is_voice_enabled())
	assert_eq(sess.voice_port, bundle.voice_port)
	for _i in range(80):
		w.poll()
		sess.poll()
		sess.ensure_ready_sent()
		await wait_process_frames(1)
		if sess.is_voice_joined() and sess.is_game_ready_sent():
			break
	assert_true(sess.is_voice_joined())
	assert_true(sess.is_game_ready_sent())
	# 真实 Worker 房间须 is_started（JOIN+READY）
	for _j in range(40):
		w.poll()
		sess.poll()
		await wait_process_frames(1)
		var rs: HeadlessRoomSession = w.get_room("room-pub")
		if rs != null and rs.is_started():
			break
	var room_pub: HeadlessRoomSession = w.get_room("room-pub")
	assert_not_null(room_pub)
	assert_true(room_pub.is_started(), "JOIN→READY 后 Worker 房间须 started")

	# 缺 voice_worker 拒绝
	var bad := assigned.duplicate()
	bad["voice_worker"] = ""
	var sess_bad := PublicCasualNetworkSession.new()
	assert_false(sess_bad.configure_from_assigned(bad, "guest-1"))
	sess_bad.free()

	# seat 4 拒绝
	var bad_seat := assigned.duplicate()
	bad_seat["seat"] = 4
	var sess_bad_seat := PublicCasualNetworkSession.new()
	assert_false(sess_bad_seat.configure_from_assigned(bad_seat, "guest-1"))
	sess_bad_seat.free()

	# STANDARD + TRASH bundle 拒绝
	var assigned_std := {
		"worker": "ws://127.0.0.1:%d" % w.get_listen_port(),
		"room_id": "room-std2",
		"seat": 0,
		"room_token": _mint_room_token(_claims("room-std2", 0, "g2", "STANDARD")),
		"game_mode": "STANDARD",
	}
	var sess_mm := PublicCasualNetworkSession.new()
	assert_true(sess_mm.configure_from_assigned(assigned_std, "g2"))
	assert_false(sess_mm.bind_mode_modules(bundle), "STANDARD 不得绑定 TRASH bundle")
	sess_mm.free()

	# TRASH + STANDARD bundle 拒绝
	var std_intent := SessionIntent.new(&"PRACTICE", &"EAST", &"STANDARD", &"lin_yeche")
	var std_conv = GameSessionConfig.from_intent(std_intent, 1, "g2", "rv", {})
	var std_bundle := ModeModuleBundle.from_config(std_conv.config)
	assert_false(sess.bind_mode_modules(std_bundle), "TRASH 不得绑定 STANDARD bundle")

	# STANDARD 正常无语音
	var w2 := _make_worker_with_voice()
	assigned_std["worker"] = "ws://127.0.0.1:%d" % w2.get_listen_port()
	var sess2 := PublicCasualNetworkSession.new()
	add_child_autofree(sess2)
	assert_true(sess2.configure_from_assigned(assigned_std, "g2"))
	assert_true(sess2.bind_mode_modules(std_bundle))
	assert_eq(sess2.start(), OK)
	assert_false(sess2.is_voice_enabled())
	assert_null(sess2.voice_port)

	# release 后继续 poll Worker：房间语音连接/状态须释放
	var relay: VoiceRelayServer = w.get_voice_relay()
	assert_true(relay.has_room_voice_state("room-pub"), "joined 后须有房间语音状态")
	assert_eq(relay.room_voice_conn_count("room-pub"), 1)
	sess.release()
	assert_false(sess.is_voice_joined())
	assert_false(sess.is_voice_enabled())
	for _k in range(40):
		w.poll()
		await wait_process_frames(1)
		if not relay.has_room_voice_state("room-pub") and relay.room_voice_conn_count("room-pub") == 0:
			break
	assert_eq(relay.room_voice_conn_count("room-pub"), 0, "release 后房间语音连接数须为 0")
	assert_false(relay.has_room_voice_state("room-pub"), "release 后房间语音状态须清空")
	sess2.release()


func test_ptt_completed_id_reuse_and_bounded_cache() -> void:
	var w := _make_worker_with_voice()
	var vport: int = w.get_voice_listen_port()
	var c0 := _connect_client(vport)
	assert_true(await _wait_open(w, [c0]))
	var cl := _claims("room-cache", 0, "s0")
	_voice_join(c0, cl)
	await _pump(w, [c0], 15)
	var relay: VoiceRelayServer = w.get_voice_relay()
	var cid: int = relay.conn_id_for_seat("room-cache", 0)
	assert_gt(cid, 0)
	var stt0: int = relay.stt_ptt_end_hook_count()
	var room: HeadlessRoomSession = w.get_room("room-cache")
	var seq0: int = room.current_server_seq()
	# 超过 64 次完整 PTT 周期
	for i in range(VoiceRelayServer.MAX_COMPLETED_PTT_ENDS + 2):
		var utt := "utt-c-%d" % i
		_ptt_start(c0, cl, utt)
		await _pump(w, [c0], 2)
		c0.send_text(JSON.stringify(_ptt_ctrl(cl, "PTT_END", utt)))
		await _pump(w, [c0], 3)
		# 重复 END 不二次 STT/seq
		var stt_mid: int = relay.stt_ptt_end_hook_count()
		var seq_mid: int = room.current_server_seq()
		c0.send_text(JSON.stringify(_ptt_ctrl(cl, "PTT_END", utt)))
		await _pump(w, [c0], 2)
		assert_eq(relay.stt_ptt_end_hook_count(), stt_mid, "重复 END 不送 STT")
		assert_eq(room.current_server_seq(), seq_mid, "重复 END 不分配序号")
	assert_lte(relay.conn_completed_ptt_count(cid), VoiceRelayServer.MAX_COMPLETED_PTT_ENDS)
	assert_eq(room.current_server_seq() - seq0, VoiceRelayServer.MAX_COMPLETED_PTT_ENDS + 2)
	assert_eq(relay.stt_ptt_end_hook_count() - stt0, VoiceRelayServer.MAX_COMPLETED_PTT_ENDS + 2)
	# 最旧 ID（utt-c-0）已被 FIFO 淘汰，可重新 START
	_recv_jsons(c0)
	_ptt_start(c0, cl, "utt-c-0")
	await _pump(w, [c0], 6)
	var old_ok := true
	for m in _recv_jsons(c0):
		if str(m.get("code", "")) == "COMMAND_REJECTED" and str(m.get("message", "")).contains("completed"):
			old_ok = false
	assert_true(old_ok, "淘汰后最旧 ID 可重新 START")
	# 结束本轮 speaking，再测缓存内较新 ID
	c0.send_text(JSON.stringify(_ptt_ctrl(cl, "PTT_END", "utt-c-0")))
	await _pump(w, [c0], 6)
	_recv_jsons(c0)
	# 仍在缓存的较新 ID 继续拒绝（utt-c-65 = MAX+1 应仍在 64 窗口内）
	var recent := "utt-c-%d" % (VoiceRelayServer.MAX_COMPLETED_PTT_ENDS + 1)
	_ptt_start(c0, cl, recent)
	await _pump(w, [c0], 6)
	var recent_rej := false
	for m in _recv_jsons(c0):
		if str(m.get("code", "")) == "COMMAND_REJECTED" and str(m.get("message", "")).contains("completed"):
			recent_rej = true
	assert_true(recent_rej, "缓存内 ID 仍拒绝 START")
