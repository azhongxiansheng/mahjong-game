extends SceneTree

# #240 round-2 smoke 入口：挂 Node 驱动 WS + NBC + Action 链。
# 环境变量：SMOKE_WS_URL SMOKE_ROOM_ID SMOKE_SEAT SMOKE_ROOM_TOKEN SMOKE_IS_ACTOR
# 网络端到端未验证。

func _initialize() -> void:
	var runner := SmokeClientRunner.new()
	root.add_child(runner)


class SmokeClientRunner extends Node:
	var _peer: WebSocketPeer = WebSocketPeer.new()
	var _nbc: NetworkedBattleController = null
	var _seat: int = 0
	var _room_id: String = ""
	var _token: String = ""
	var _url: String = ""
	var _is_actor: bool = false
	var _phase: String = "connect"
	var _ticks: int = 0
	var _got_snapshot: bool = false
	var _got_action_applied: bool = false
	var _saw_aa_wire: bool = false
	var _sent_bad: bool = false
	var _sent_good: bool = false
	var _bad_error_ok: bool = false
	var _accepted_ok: bool = false
	var _seq_at_bad: int = -1
	var _prompt_meta: Dictionary = {}

	func _ready() -> void:
		_url = OS.get_environment("SMOKE_WS_URL")
		_room_id = OS.get_environment("SMOKE_ROOM_ID")
		_token = OS.get_environment("SMOKE_ROOM_TOKEN")
		_seat = int(OS.get_environment("SMOKE_SEAT"))
		_is_actor = OS.get_environment("SMOKE_IS_ACTOR") == "1"
		if _url.is_empty() or _room_id.is_empty() or _token.is_empty():
			push_error("missing SMOKE_* env")
			get_tree().quit(2)
			return
		_nbc = NetworkedBattleController.new(_room_id, _seat)
		var err: Error = _peer.connect_to_url(_url)
		if err != OK:
			push_error("connect_to_url failed err=%s" % error_string(err))
			get_tree().quit(3)
			return
		print("smoke_client seat=%d connecting actor=%s" % [_seat, str(_is_actor)])

	func _process(_delta: float) -> void:
		_peer.poll()
		_ticks += 1
		if _ticks > 12000:
			push_error("smoke timeout phase=%s snap=%s aa=%s" % [
				_phase, str(_got_snapshot), str(_got_action_applied),
			])
			get_tree().quit(4)
			return
		var st: int = _peer.get_ready_state()
		if st == WebSocketPeer.STATE_CLOSED:
			if _phase != "done":
				push_error("ws closed early phase=%s" % _phase)
				get_tree().quit(5)
			return
		if st != WebSocketPeer.STATE_OPEN:
			return
		if _phase == "connect":
			_send({
				"protocol_version": 1,
				"kind": "JOIN",
				"room_id": _room_id,
				"seat": _seat,
				"room_token": _token,
			})
			_phase = "joined"
			return
		if _phase == "joined":
			_send({
				"protocol_version": 1,
				"kind": "READY",
				"room_id": _room_id,
				"seat": _seat,
			})
			_phase = "ready"
		while _peer.get_available_packet_count() > 0:
			var pkt: PackedByteArray = _peer.get_packet()
			if not _peer.was_string_packet():
				push_error("unexpected binary")
				get_tree().quit(7)
				return
			_on_message(pkt.get_string_from_utf8())
		_try_act()
		_maybe_finish()

	func _on_message(text: String) -> void:
		var msg: Variant = JSON.parse_string(text)
		if typeof(msg) != TYPE_DICTIONARY:
			return
		var d: Dictionary = msg
		var kind: String = str(d.get("kind", ""))
		if kind == "ERROR":
			if d.has("server_seq") or d.has("view_hash"):
				push_error("ERROR must not carry server_seq/view_hash")
				get_tree().quit(8)
				return
			var code: String = str(d.get("code", ""))
			if _sent_bad and not _bad_error_ok and code == "COMMAND_REJECTED":
				if _nbc.current_seq() != _seq_at_bad:
					push_error("NBC seq advanced on domain reject")
					get_tree().quit(9)
					return
				_bad_error_ok = true
				print("smoke_client seat=%d bad_action ERROR ok" % _seat)
				return
			if not (_sent_bad and code == "COMMAND_REJECTED"):
				push_error("unexpected ERROR code=%s phase=%s" % [code, _phase])
				get_tree().quit(6)
			return
		if str(d.get("status", "")) == "ACCEPTED":
			_accepted_ok = true
			print("smoke_client seat=%d ACCEPTED" % _seat)
			return
		var ne: NetworkedEvent = null
		var dec = load("res://protocol/json_transport_decoder.gd")
		if dec != null:
			ne = dec.decode_event(text)
		if ne == null:
			ne = NetworkedEvent.from_dict(d)
		if ne == null:
			return
		# 每条权威事件必须被现有 NBC 真正驱动；ingest false 立即失败（#240 round-3）
		if not _nbc.ingest_networked_event(ne):
			push_error("NBC ingest failed kind=%s seq=%d seat=%d" % [
				ne.kind, ne.server_seq, _seat,
			])
			get_tree().quit(10)
			return
		if ne.kind == "ACTION_APPLIED":
			# AA 可能先 pending（view 将变），下一 ROOM_SNAPSHOT 才 journal 提交
			_saw_aa_wire = true
			print("smoke_client seat=%d ACTION_APPLIED seq=%d (ingested)" % [_seat, ne.server_seq])
		if ne.kind == "ROOM_SNAPSHOT":
			_got_snapshot = true
			print("smoke_client seat=%d ROOM_SNAPSHOT seq=%d nbc=%d" % [
				_seat, ne.server_seq, _nbc.current_seq(),
			])
			if _saw_aa_wire and not _got_action_applied:
				var has_aa := false
				for e in _nbc.get_event_journal():
					if e is NetworkedEvent and (e as NetworkedEvent).kind == "ACTION_APPLIED":
						has_aa = true
						break
				if not has_aa:
					push_error("NBC journal missing ACTION_APPLIED after snapshot commit")
					get_tree().quit(11)
					return
				_got_action_applied = true
				print("smoke_client seat=%d ACTION_APPLIED in NBC journal" % _seat)
		if ne.kind == "TURN_PROMPT" and int(ne.payload.get("seat", -1)) == _seat:
			_prompt_meta = _extract_discard_meta(ne)

	func _try_act() -> void:
		if not _is_actor:
			return
		if not _got_snapshot:
			return
		if _prompt_meta.is_empty():
			return
		if not _sent_bad:
			_seq_at_bad = _nbc.current_seq()
			_send({
				"protocol_version": 1,
				"command_id": "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
				"room_id": _room_id,
				"seat": _seat,
				"hand_seq": int(_prompt_meta["hand_seq"]),
				"decision_id": "dddddddd-dddd-4ddd-8ddd-dddddddddddd",
				"kind": "DISCARD",
				"payload": {"tile_instance_id": int(_prompt_meta["tile_instance_id"])},
				"client_seq": 1,
			})
			_sent_bad = true
			return
		if _sent_bad and _bad_error_ok and not _sent_good:
			_send({
				"protocol_version": 1,
				"command_id": "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee",
				"room_id": _room_id,
				"seat": _seat,
				"hand_seq": int(_prompt_meta["hand_seq"]),
				"decision_id": str(_prompt_meta["decision_id"]),
				"kind": "DISCARD",
				"payload": {"tile_instance_id": int(_prompt_meta["tile_instance_id"])},
				"client_seq": 2,
			})
			_sent_good = true

	func _maybe_finish() -> void:
		if _is_actor:
			if _got_snapshot and _bad_error_ok and _accepted_ok and _got_action_applied:
				print("SMOKE_ACTOR_OK seat=%d ACTION_APPLIED" % _seat)
				_phase = "done"
				_peer.close()
				get_tree().quit(0)
		else:
			if _got_snapshot and _got_action_applied:
				print("SMOKE_OBSERVER_OK seat=%d ACTION_APPLIED" % _seat)
				_phase = "done"
				_peer.close()
				get_tree().quit(0)

	func _extract_discard_meta(prompt: NetworkedEvent) -> Dictionary:
		var p: Dictionary = prompt.payload
		for o in p.get("allowed_actions", []):
			if typeof(o) != TYPE_DICTIONARY:
				continue
			if str(o.get("kind", "")) != "DISCARD":
				continue
			var opts: Array = o.get("payload_options", [])
			if opts.is_empty():
				continue
			return {
				"seat": int(p["seat"]),
				"hand_seq": int(p["hand_seq"]),
				"decision_id": str(p["decision_id"]),
				"tile_instance_id": int(opts[0]["tile_instance_id"]),
			}
		return {}

	func _send(obj: Dictionary) -> void:
		_peer.send_text(JSON.stringify(obj))
