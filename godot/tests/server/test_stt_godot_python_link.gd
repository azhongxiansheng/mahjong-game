extends GutTest

# #247 r4：本机 Godot SttServiceClient/Bridge → 真实 Python STT listener（small/CPU int8/VAD）。
# 可跳过：环境无 python venv 或 STT_E2E=0。
# 网络公网 e2e 未验证。

const SECRET := "0123456789abcdef0123456789abcdef"
const NOW0 := 1_700_000_000_000
const RULE_VERSION := "trash_talk_rules_v1"

var _py_pid: int = -1
var _worker: HeadlessWorker = null
var _bridge: SttBridge = null


func after_each() -> void:
	if _bridge != null and is_instance_valid(_bridge):
		_bridge.stop()
	if _worker != null and is_instance_valid(_worker):
		_worker.stop()
	if _py_pid > 0:
		OS.kill(_py_pid)
		_py_pid = -1


func test_godot_bridge_to_python_real_model_en() -> void:
	if str(OS.get_environment("STT_E2E")).strip_edges() == "0":
		pending("STT_E2E=0")
		return
	var py := _find_python()
	if py.is_empty():
		pending("no python3.11 stt venv")
		return
	var fixture := _fixture_path("en_jfk_16k.wav")
	if not FileAccess.file_exists(fixture):
		pending("missing en fixture")
		return
	var port := _pick_port()
	var stt_root := _stt_root()
	var helper := stt_root.path_join("scripts/run_godot_e2e_helper.sh")
	_py_pid = OS.create_process("/bin/zsh", ["-c", "STT_PORT=%d STT_PYTHON='%s' '%s'" % [port, py, helper]], false)
	assert_gt(_py_pid, 0, "start python stt")
	# 等待端口
	await _wait_port(port, 90.0)
	_worker = HeadlessWorker.new()
	add_child_autofree(_worker)
	assert_true(_worker.configure(SECRET, "127.0.0.1", 0, 0, "ws://127.0.0.1:%d" % port))
	_worker.token_now_unix = 1_700_000_000
	_worker.set_clock_ms_for_test(NOW0)
	assert_eq(_worker.start_listen(), OK)
	assert_true(bool(_worker.ensure_room_from_claims({
		"room_id": "room_e2e", "seat": 0, "session_id": "s0", "exp": 2_000_000_000,
		"round_kind": "EAST", "game_mode": "TRASH_TALK",
		"participants": ["HUMAN", "AI", "AI", "AI"],
			"character_ids": ["lin_yeche", "an_cheng", "bai_touli", "hua_ling"],
}).get("ok", false)))
	var session: HeadlessRoomSession = _worker.get_room("room_e2e")
	var rw: RewardWindowModule = session.server.mode_modules.reward_window
	assert_true(bool(rw.open({
		"room_id": "room_e2e", "hand_seq": 0, "window_index": 0,
		"seed": int(session.authority_seed), "rule_version": RULE_VERSION,
				"participants": ["HUMAN", "AI", "AI", "AI"], "now_ms": NOW0,
				"character_ids": session.character_ids, "language": "en",
	}).get("ok", false)))
	_bridge = _worker.get_stt_bridge()
	assert_not_null(_bridge)
	# 等 STT client 连上
	for _i in range(200):
		_worker.poll()
		if _bridge._client != null and _bridge._client.is_stt_open():
			break
		await wait_process_frames(1)
	assert_true(_bridge._client != null and _bridge._client.is_stt_open(), "client open")
	var pcm: PackedByteArray = _load_wav_pcm16(fixture)
	assert_gt(pcm.size(), 640)
	var utt := "utt_e2e"
	var off := 0
	var fseq := 0
	while off + 640 <= pcm.size():
		var chunk := pcm.slice(off, off + 640)
		_bridge.handle_frame_for_test({
			"room_id": "room_e2e", "seat": 0, "utterance_id": utt, "pcm": chunk,
		})
		off += 640
		fseq += 1
		if fseq % 20 == 0:
			_worker.poll()
			await wait_process_frames(1)
	var auth: Dictionary = _worker.allocate_ptt_end_authority("room_e2e", 0, "s0", utt)
	assert_true(bool(auth.get("ok", false)), str(auth))
	var ptt: int = int(auth.get("server_seq", 0))
	_bridge.handle_ptt_end_for_test({
		"room_id": "room_e2e", "seat": 0, "utterance_id": utt, "server_seq": ptt,
	})
	var deadline := Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < deadline:
		_worker.poll()
		if _bridge.get_pending_count() == 0 and _bridge.finals_ingested > 0:
			break
		await wait_process_frames(1)
	assert_gt(_bridge.finals_ingested, 0, "应摄入 final")
	var texts: Array = []
	for u in rw._utterances_by_seat.get("0", []):
		if typeof(u) == TYPE_DICTIONARY:
			var t := String((u as Dictionary).get("text", "")).strip_edges()
			if not t.is_empty():
				texts.append(t)
	assert_gt(texts.size(), 0)
	var joined := " ".join(texts).to_lower()
	assert_true(joined.contains("ask") or joined.contains("country") or joined.contains("fellow"),
		"识别摘要: %s" % joined)


func _find_python() -> String:
	var candidates := [
		"/tmp/mahjong-stt-venv-247/bin/python",
		OS.get_environment("HOME") + "/.codex/worktrees/fd33/mahjong-game/services/stt/.venv/bin/python",
		"/usr/bin/python3.11",
		"/opt/homebrew/bin/python3.11",
	]
	for c in candidates:
		if FileAccess.file_exists(c):
			return c
	return ""


func _stt_root() -> String:
	return ProjectSettings.globalize_path("res://").path_join("..").path_join("services/stt").simplify_path()


func _fixture_path(name: String) -> String:
	return _stt_root().path_join("fixtures").path_join(name)


func _pick_port() -> int:
	# 动态：用 0 由 python 选不便；固定高端口
	return 19100 + (Time.get_ticks_msec() % 500)


func _wait_port(port: int, secs: float) -> void:
	var until := Time.get_ticks_msec() + int(secs * 1000)
	while Time.get_ticks_msec() < until:
		var peer := WebSocketPeer.new()
		var err := peer.connect_to_url("ws://127.0.0.1:%d" % port)
		if err == OK:
			for _i in range(30):
				peer.poll()
				if peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
					peer.close()
					return
				await wait_process_frames(1)
			peer.close()
		await wait_process_frames(5)


func _load_wav_pcm16(path: String) -> PackedByteArray:
	# 最小 WAV：跳过 44 字节头（本仓库 fixture 为标准 PCM16 mono 16k）
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return PackedByteArray()
	var all: PackedByteArray = f.get_buffer(f.get_length())
	f.close()
	if all.size() <= 44:
		return PackedByteArray()
	return all.slice(44)
