extends GutTest

# #378 round-2：公共牌桌 TURN / CLAIM / ITEM_USE 命令闭环（真实 Worker WS）。
# 公网四客户端端到端未验证。

const PlayableScr := preload("res://ui/four_player_table/playable_table.gd")
const SECRET := "0123456789abcdef0123456789abcdef"
const CHARS := ["lin_yeche", "an_cheng", "bai_touli", "hua_ling"]


func _mint_token(
	room: String, seat: int, session_id: String, mode := "STANDARD",
	parts: Array = ["HUMAN", "AI", "HUMAN", "AI"]
) -> String:
	var body := {
		"typ": "room",
		"room_id": room,
		"seat": seat,
		"session_id": session_id,
		"exp": 2_000_000_000,
		"round_kind": "EAST",
		"game_mode": mode,
		"participants": parts,
		"character_ids": CHARS,
	}
	var payload := Marshalls.raw_to_base64(JSON.stringify(body).to_utf8_buffer())
	payload = payload.replace("+", "-").replace("/", "_").rstrip("=")
	var signing := "v1.r.%s" % payload
	var sig := Crypto.new().hmac_digest(
		HashingContext.HASH_SHA256, SECRET.to_utf8_buffer(), signing.to_utf8_buffer()
	)
	var sig_text := Marshalls.raw_to_base64(sig).replace("+", "-").replace("/", "_").rstrip("=")
	return "%s.%s" % [signing, sig_text]


func _new_worker(with_voice := false) -> HeadlessWorker:
	var w := HeadlessWorker.new()
	add_child_autofree(w)
	var voice_port := 0 if with_voice else -1
	assert_true(w.configure(SECRET, "127.0.0.1", 0, voice_port))
	w.token_now_unix = 1_700_000_000
	assert_eq(w.start_listen(), OK)
	return w


func _make_session(
	worker: HeadlessWorker,
	room: String,
	seat: int,
	session_id: String,
	mode := "STANDARD",
	parts: Array = ["HUMAN", "AI", "HUMAN", "AI"]
) -> PublicCasualNetworkSession:
	var sess := PublicCasualNetworkSession.new()
	add_child_autofree(sess)
	var assigned := {
		"worker": "ws://127.0.0.1:%d" % worker.get_listen_port(),
		"room_id": room,
		"seat": seat,
		"room_token": _mint_token(room, seat, session_id, mode, parts),
		"game_mode": mode,
	}
	if mode == "TRASH_TALK":
		assigned["voice_worker"] = "ws://127.0.0.1:%d" % worker.get_voice_listen_port()
	assert_true(sess.configure_from_assigned(assigned, session_id))
	if mode == "TRASH_TALK":
		var vp := VoicePortModule.new()
		sess.bind_voice_port_for_test(vp)
	return sess


func _poll_until(worker: HeadlessWorker, sessions: Array, done: Callable, max_frames := 240) -> bool:
	for _i in range(max_frames):
		worker.poll()
		for s in sessions:
			if s != null and is_instance_valid(s):
				s.poll()
				if s.has_method("ensure_ready_sent"):
					s.ensure_ready_sent()
		if done.call():
			return true
		await wait_process_frames(1)
	return false


func _pair_table() -> Node:
	var table = PlayableScr.new()
	add_child_autofree(table)
	await get_tree().process_frame
	if table._table == null:
		var fpt = load("res://ui/four_player_table/four_player_table.gd").new()
		table.add_child(fpt)
		table._table = fpt
		await get_tree().process_frame
	return table


func _release_table(table: Node, sess: PublicCasualNetworkSession = null) -> void:
	if table != null and is_instance_valid(table):
		table._reward_sync_active = false
		if table.has_method("_disconnect_public_command_signals"):
			table._disconnect_public_command_signals()
		if table.has_method("_disconnect_public_transcript"):
			table._disconnect_public_transcript()
		table._public_reward_session = null
	if sess != null and is_instance_valid(sess):
		sess.release()
	await wait_process_frames(2)


func _find_cid_for_seat(worker: HeadlessWorker, seat: int) -> int:
	for cid in range(1, 96):
		var b: Dictionary = worker.test_conn_binding(cid)
		if b.is_empty():
			continue
		if int(b.get("seat", -1)) != seat:
			continue
		if not bool(b.get("joined", false)):
			continue
		if bool(b.get("superseded", false)):
			continue
		return cid
	return -1


## JOIN 前预装固定 seed 房间（bootstrap 已完成、席位未 JOIN）；WS 客户端随后 JOIN/READY。
func _install_seeded_room(
	worker: HeadlessWorker,
	room: String,
	seed: int,
	parts: Array = ["HUMAN", "AI", "HUMAN", "AI"],
	mode := "STANDARD"
) -> HeadlessRoomSession:
	var hrs := HeadlessRoomSession.new()
	hrs.set_seed_override_for_test(seed)
	assert_true(hrs.bootstrap_from_claims({
		"room_id": room,
		"seat": 0,
		"session_id": "seed-bootstrap-%s" % room,
		"round_kind": "EAST",
		"game_mode": mode,
		"participants": parts,
		"character_ids": CHARS,
	}))
	var rooms: Dictionary = worker.get("_rooms") as Dictionary
	rooms[room] = hrs
	return hrs


func _grant_wall_collapse(server: LocalLoopbackServer, seat: int, window_id: String) -> String:
	var inv_mod: ItemInventoryModule = server.mode_modules.item_inventory
	var ns := inv_mod.match_namespace
	if ns.is_empty() and server.config != null:
		ns = str(server.config.session_id)
	if ns.is_empty():
		ns = str(server.get("_room_id"))
	var g: Dictionary = inv_mod.grant_for_seat({
		"seat": seat,
		"item_id": "wall_collapse_v1",
		"window_id": window_id,
		"hand_seq": 0,
		"score": 1,
		"rule_version": "rv",
		"assignment_version": "a1",
		"matched_rule_ids": [],
		"affinity_match": false,
		"match_namespace": ns,
	})
	assert_true(bool(g.get("ok", false)), "grant: %s" % str(g))
	return str((g.get("payload", {}) as Dictionary).get("item_instance_id", ""))


func _inventory_has_instance(sess: PublicCasualNetworkSession, iid: String) -> bool:
	if sess == null or sess.nbc == null:
		return false
	for raw in sess.nbc.get_item_inventory_view().get("items", []):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		if String((raw as Dictionary).get("item_instance_id", "")) == iid:
			return true
	return false


func _journal_has_item_event(
	sess: PublicCasualNetworkSession, kind: String, iid: String, cmd: String = ""
) -> bool:
	if sess == null or sess.nbc == null:
		return false
	for item in sess.nbc.get_event_journal():
		if not (item is NetworkedEvent):
			continue
		var ne: NetworkedEvent = item as NetworkedEvent
		if ne.kind != kind:
			continue
		if str(ne.payload.get("item_instance_id", "")) != iid:
			continue
		if not cmd.is_empty() and str(ne.payload.get("command_id", "")) != cmd:
			continue
		return true
	return false


func _find_turn_prompt(sess: PublicCasualNetworkSession) -> NetworkedEvent:
	if sess == null or sess.nbc == null:
		return null
	var last: NetworkedEvent = null
	for item in sess.nbc.get_event_journal():
		if not (item is NetworkedEvent):
			continue
		var ne: NetworkedEvent = item as NetworkedEvent
		if ne.kind == "ROOM_SNAPSHOT":
			last = null
			continue
		if ne.kind == "TURN_PROMPT" and int(ne.payload.get("seat", -1)) == sess.seat:
			last = ne
	return last


func _find_claim_window(sess: PublicCasualNetworkSession) -> NetworkedEvent:
	if sess == null or sess.nbc == null:
		return null
	var last: NetworkedEvent = null
	for item in sess.nbc.get_event_journal():
		if not (item is NetworkedEvent):
			continue
		var ne: NetworkedEvent = item as NetworkedEvent
		if ne.kind == "ROOM_SNAPSHOT":
			last = null
			continue
		if ne.kind == "CLAIM_WINDOW":
			last = ne
		elif ne.kind == "TURN_PROMPT":
			last = null
	return last


func _first_option(prompt: NetworkedEvent, kind: String) -> Dictionary:
	if prompt == null:
		return {}
	for a in prompt.payload.get("allowed_actions", []):
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if str(a.get("kind", "")) != kind:
			continue
		var opts: Array = a.get("payload_options", []) as Array
		if opts.is_empty() or typeof(opts[0]) != TYPE_DICTIONARY:
			return {}
		return (opts[0] as Dictionary).duplicate(true)
	return {}


func _options_of(prompt: NetworkedEvent, kind: String) -> Array:
	var out: Array = []
	if prompt == null:
		return out
	for a in prompt.payload.get("allowed_actions", []):
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if str(a.get("kind", "")) != kind:
			continue
		for op in a.get("payload_options", []):
			if typeof(op) == TYPE_DICTIONARY:
				out.append((op as Dictionary).duplicate(true))
	return out


func _build_action_from_offer(
	sess: PublicCasualNetworkSession,
	prompt: NetworkedEvent,
	kind: String,
	payload: Dictionary,
	cmd_id: String = "",
	client_seq: int = -1
) -> Action:
	var decision := str(prompt.payload.get("decision_id", ""))
	var hand_seq := int(prompt.payload.get("hand_seq", 0))
	var cid := cmd_id if not cmd_id.is_empty() else sess.allocate_command_id()
	var cseq := client_seq if client_seq >= 0 else sess.allocate_client_seq()
	return Action.from_dict({
		"protocol_version": ProtocolConstants.PROTOCOL_VERSION,
		"command_id": cid,
		"room_id": sess.room_id,
		"seat": sess.seat,
		"hand_seq": hand_seq,
		"decision_id": decision,
		"kind": kind,
		"payload": payload.duplicate(true),
		"client_seq": cseq,
	})


func _count_kind(journal: Array, kind: String) -> int:
	var n := 0
	for item in journal:
		if item is NetworkedEvent and (item as NetworkedEvent).kind == kind:
			n += 1
	return n


func _count_applied_cmd(journal: Array, cmd: String) -> int:
	var n := 0
	for item in journal:
		if not (item is NetworkedEvent):
			continue
		var ne: NetworkedEvent = item as NetworkedEvent
		if ne.kind != "ACTION_APPLIED":
			continue
		if str(ne.payload.get("causation_command_id", "")) == cmd:
			n += 1
	return n


func _hand_clickable(table: Node) -> bool:
	if table == null or table._seat_panel_player == null:
		return false
	var sp = table._seat_panel_player
	if sp.has_method("is_hand_clickable"):
		return bool(sp.is_hand_clickable())
	# SeatPanel 常见字段
	if sp.get("_hand_clickable") != null:
		return bool(sp.get("_hand_clickable"))
	return false


func _action_buttons_disabled_or_hidden(table: Node) -> bool:
	var panel = table._action_panel
	if panel == null:
		return true
	# enter_idle 隐藏业务按钮
	for name in ["_btn_tsumo", "_btn_ron", "_btn_chi", "_btn_pon", "_btn_skip",
			"_btn_riichi", "_btn_ankan", "_btn_minkan"]:
		var b = panel.get(name)
		if b != null and b.visible and not b.disabled:
			return false
	return true


func _inventory_use_disabled(table: Node) -> bool:
	if table._table == null:
		return true
	if table._table.has_method("is_inventory_use_locked"):
		return bool(table._table.is_inventory_use_locked())
	return true


## 指定 instance 的 UseButton 是否可见且 enabled（use lock 已关且 can_request_use）。
func _inventory_use_button_enabled(table: Node, item_instance_id: String) -> bool:
	if table == null or table._table == null or table._table.item_inventory_drawer == null:
		return false
	if bool(table._table.is_inventory_use_locked()):
		return false
	var drawer = table._table.item_inventory_drawer
	var rows: Dictionary = drawer.get("_rows_by_id") as Dictionary
	if rows == null or not rows.has(item_instance_id):
		return false
	var cell: Control = rows[item_instance_id] as Control
	if cell == null or not is_instance_valid(cell):
		return false
	var ub := cell.find_child("UseButton", true, false) as Button
	if ub == null:
		return false
	return ub.visible and not ub.disabled


func _cmd_n(n: int) -> String:
	return "550e8400-e29b-41d4-a716-%012d" % n


func _drive_server_discards(server: LocalLoopbackServer, target: int, cmd_base: int = 5000) -> void:
	var rw: RewardWindowModule = server.mode_modules.reward_window
	var n: int = cmd_base
	var guard := 0
	while rw.discard_count < target:
		guard += 1
		assert_lt(guard, 200, "drive timeout discard=%d" % rw.discard_count)
		var bc: BattleController = server.get("_bc") as BattleController
		if bool(bc.get("_settled")):
			return
		for s in range(4):
			bc.decision_context_for_seat(s)
		var win = bc.get("_active_window")
		assert_true(win is DecisionWindow)
		var dw: DecisionWindow = win as DecisionWindow
		if dw.kind == DecisionWindow.KIND_CLAIM or dw.kind == DecisionWindow.KIND_ROB_KAN:
			var target_seat := -1
			for seat_i in dw.seats():
				var si: int = int(seat_i)
				if not dw.has_responded(si):
					target_seat = si
					break
			assert_gte(target_seat, 0)
			var ctx: DecisionContext = dw.context_for_seat(target_seat)
			var act: Action = Action.make_pass(
				target_seat, str(server.get("_room_id")), _cmd_n(n),
				str(ctx.decision_id), int(ctx.hand_seq), n
			)
			assert_eq(server.submit_action(act).status, "ACCEPTED")
			n += 1
			continue
		if dw.kind == DecisionWindow.KIND_TURN:
			var actor: int = int(dw.subject_seat)
			var tctx: DecisionContext = dw.context_for_seat(actor)
			var iid := -1
			for o in tctx.allowed_actions:
				if typeof(o) == TYPE_DICTIONARY and str(o.get("kind", "")) == "DISCARD":
					var opts: Array = o.get("payload_options", [])
					iid = int(opts[0]["tile_instance_id"])
					break
			assert_gt(iid, -1)
			var dact: Action = Action.discard(
				actor, iid, str(server.get("_room_id")), _cmd_n(n),
				str(tctx.decision_id), int(tctx.hand_seq), n
			)
			assert_eq(server.submit_action(dact).status, "ACCEPTED")
			n += 1


func _settle_after_24(server: LocalLoopbackServer) -> void:
	var rw: RewardWindowModule = server.mode_modules.reward_window
	var n := 9000
	var guard := 0
	while rw.phase == RewardWindowModule.PHASE_CLOSING and guard < 40:
		guard += 1
		var bc: BattleController = server.get("_bc") as BattleController
		if bool(bc.get("_settled")):
			return
		for s in range(4):
			bc.decision_context_for_seat(s)
		var win = bc.get("_active_window")
		if win is DecisionWindow:
			var dw: DecisionWindow = win as DecisionWindow
			if dw.kind == DecisionWindow.KIND_CLAIM or dw.kind == DecisionWindow.KIND_ROB_KAN:
				var target_seat := -1
				for seat_i in dw.seats():
					var si: int = int(seat_i)
					if not dw.has_responded(si):
						target_seat = si
						break
				assert_gte(target_seat, 0)
				var ctx: DecisionContext = dw.context_for_seat(target_seat)
				var act: Action = Action.make_pass(
					target_seat, str(server.get("_room_id")), _cmd_n(n),
					str(ctx.decision_id), int(ctx.hand_seq), n
				)
				assert_eq(server.submit_action(act).status, "ACCEPTED")
				n += 1
				continue
		if not rw.claim_is_terminal():
			assert_true(server.advance_reward_time(maxi(server._reward_now_ms() + 1, 1)))
			continue
		if not rw.barrier_released(server._reward_now_ms()):
			assert_true(server.advance_reward_time(int(rw._grace_deadline_ms)))
			continue
		assert_true(server.advance_reward_time(server._reward_now_ms() + 1))


# ── 1) API 暴露 ───────────────────────────────────────────────

func test_session_exposes_submit_action_and_result_signals() -> void:
	var sess := PublicCasualNetworkSession.new()
	add_child_autofree(sess)
	assert_true(sess.has_method("submit_action"))
	assert_true(sess.has_signal("command_accepted"))
	assert_true(sess.has_signal("command_rejected"))
	var fake := Action.make_pass(
		0, "room-x", "550e8400-e29b-41d4-a716-446655440001",
		"550e8400-e29b-41d4-a716-4466554400aa", 0, 1
	)
	assert_not_null(fake)
	assert_ne(sess.submit_action(fake), OK, "未 JOIN 不得提交")
	assert_false(sess.is_command_pending())


# ── 2) seat0 DISCARD 真实 WS ──────────────────────────────────

func test_real_worker_seat0_discard_via_submit_action() -> void:
	var worker := _new_worker()
	var room := "room-378-discard"
	var s0 := _make_session(worker, room, 0, "guest-378-s0")
	var s2 := _make_session(worker, room, 2, "guest-378-s2")
	assert_eq(s0.start(), OK)
	assert_eq(s2.start(), OK)
	assert_true(await _poll_until(worker, [s0, s2], func():
		return s0.has_committed_snapshot() and s2.has_committed_snapshot()))
	assert_true(await _poll_until(worker, [s0, s2], func(): return _find_turn_prompt(s0) != null))
	var prompt := _find_turn_prompt(s0)
	var disc_opt := _first_option(prompt, "DISCARD")
	assert_false(disc_opt.is_empty())
	var action := _build_action_from_offer(s0, prompt, "DISCARD", disc_opt)
	assert_not_null(action)
	var accepted: Array = []
	s0.command_accepted.connect(func(_cr): accepted.append(1))
	var before_seq := int(s0.nbc.current_seq())
	assert_eq(s0.submit_action(action), OK)
	assert_true(s0.is_command_pending())
	assert_true(await _poll_until(worker, [s0, s2], func(): return not accepted.is_empty()))
	assert_true(await _poll_until(worker, [s0, s2], func(): return int(s0.nbc.current_seq()) > before_seq))
	worker.stop()


# ── 3) seat2 UI ───────────────────────────────────────────────

func test_real_worker_seat2_ui_pass_or_discard() -> void:
	var worker := _new_worker()
	var room := "room-378-seat2"
	var s0 := _make_session(worker, room, 0, "guest-378-s0b")
	var s2 := _make_session(worker, room, 2, "guest-378-s2b")
	var table2: Node = await _pair_table()
	s2.bind_playable_table(table2)
	assert_eq(s0.start(), OK)
	assert_eq(s2.start(), OK)
	assert_true(await _poll_until(worker, [s0, s2], func():
		return s0.has_committed_snapshot() and s2.has_committed_snapshot()))
	var got_s2 := false
	for _round in range(8):
		var p0 := _find_turn_prompt(s0)
		if p0 != null:
			var opt := _first_option(p0, "DISCARD")
			if not opt.is_empty():
				var act0 := _build_action_from_offer(s0, p0, "DISCARD", opt)
				if act0 != null and s0.submit_action(act0) == OK:
					await _poll_until(worker, [s0, s2], func(): return not s0.is_command_pending(), 120)
		if _find_turn_prompt(s2) != null or _find_claim_window(s2) != null:
			got_s2 = true
			break
		await _poll_until(worker, [s0, s2], func(): return false, 20)
	assert_true(got_s2)
	table2.sync_public_table_projection()
	await get_tree().process_frame
	var attempts_before := int(table2.public_network_command_attempts())
	var claim := _find_claim_window(s2)
	var turn := _find_turn_prompt(s2)
	if claim != null and table2._action_panel != null:
		table2._action_panel.player_action_chosen.emit({"action": "skip"})
	elif turn != null:
		var dopt := _first_option(turn, "DISCARD")
		if not dopt.is_empty() and dopt.has("tile_instance_id"):
			table2._on_player_tile_clicked(int(dopt["tile_instance_id"]))
	assert_true(await _poll_until(worker, [s0, s2], func():
		return int(table2.public_network_command_attempts()) > attempts_before, 120))
	await _release_table(table2, s2)
	worker.stop()


# ── 4) 真实多 option DISCARD exact（生产 UI） ─────────────────

func test_real_worker_multi_discard_exact_via_ui() -> void:
	var worker := _new_worker()
	var room := "room-378-multi"
	var s0 := _make_session(worker, room, 0, "guest-378-m0")
	var s2 := _make_session(worker, room, 2, "guest-378-m2")
	var table: Node = await _pair_table()
	s0.bind_playable_table(table)
	assert_eq(s0.start(), OK)
	assert_eq(s2.start(), OK)
	assert_true(await _poll_until(worker, [s0, s2], func():
		return s0.has_committed_snapshot() and _find_turn_prompt(s0) != null))
	table.sync_public_table_projection()
	await get_tree().process_frame
	var prompt := _find_turn_prompt(s0)
	var opts := _options_of(prompt, "DISCARD")
	assert_gte(opts.size(), 2, "真实 TURN 须有多 DISCARD option")
	var chosen: Dictionary = opts[1] as Dictionary
	var iid := int(chosen["tile_instance_id"])
	var accepted: Array = []
	s0.command_accepted.connect(func(_cr): accepted.append(1))
	# 经真实手牌点击 → panel → public choice → submit
	table._on_player_tile_clicked(iid)
	assert_true(await _poll_until(worker, [s0, s2], func(): return not accepted.is_empty(), 120),
		"UI DISCARD 须 ACCEPTED")
	# 核对 committed ACTION_APPLIED：DISCARD resolved 含 tile.instance_id = 所选 option
	var saw := false
	for item in s0.nbc.get_event_journal():
		if not (item is NetworkedEvent):
			continue
		var ne: NetworkedEvent = item as NetworkedEvent
		if ne.kind != "ACTION_APPLIED":
			continue
		if str(ne.payload.get("action_kind", "")) != "DISCARD":
			continue
		var rp: Dictionary = ne.payload.get("resolved_payload", {})
		var tile_v: Dictionary = rp.get("tile", {}) as Dictionary
		assert_eq(int(tile_v.get("instance_id", -1)), iid,
			"committed tile.instance_id 须等于所选 exact DISCARD option")
		saw = true
		break
	assert_true(saw, "须有 DISCARD ACTION_APPLIED")
	await _release_table(table, s0)
	worker.stop()


# ── 5) ITEM_USE 真实接受 + 拒绝补充 ───────────────────────────

func test_item_use_reject_nonexistent_no_token_leak() -> void:
	var worker := _new_worker()
	var room := "room-378-item-rej"
	var s0 := _make_session(worker, room, 0, "guest-378-ir0")
	var s2 := _make_session(worker, room, 2, "guest-378-ir2")
	assert_eq(s0.start(), OK)
	assert_eq(s2.start(), OK)
	assert_true(await _poll_until(worker, [s0, s2], func():
		return s0.has_committed_snapshot() and _find_turn_prompt(s0) != null))
	var prompt := _find_turn_prompt(s0)
	assert_false(_options_of(prompt, "ITEM_USE").size() > 0, "offer 不得含 ITEM_USE")
	var act := Action.item_use(
		0, "inst-not-exist-378", room, s0.allocate_command_id(),
		str(prompt.payload.get("decision_id", "")), int(prompt.payload.get("hand_seq", 0)),
		s0.allocate_client_seq()
	)
	var rejected: Array = []
	s0.command_rejected.connect(func(code, _c, _m): rejected.append(code))
	assert_eq(s0.submit_action(act), OK)
	assert_true(await _poll_until(worker, [s0, s2], func(): return not rejected.is_empty(), 120))
	assert_false(JSON.stringify(rejected).contains(s0.room_token))
	worker.stop()


func test_item_use_real_inventory_accept_via_ws() -> void:
	# TRASH_TALK：grant 两张 wall_collapse → 重连拉齐 → 库存 UI USE(WS)
	# → matching ACCEPTED → 客户端 committed ITEM_APPLIED/CONSUMED + ROOM_SNAPSHOT
	# → 目标 instance 消失，另一同 item_id instance 保留
	var worker := _new_worker(true)
	var room := "room-378-item-ok"
	var parts := ["HUMAN", "AI", "AI", "AI"]
	var s0 := _make_session(worker, room, 0, "guest-378-io0", "TRASH_TALK", parts)
	assert_eq(s0.start(), OK)
	assert_true(await _poll_until(worker, [s0], func(): return s0.has_committed_snapshot(), 300))
	var hrs: HeadlessRoomSession = worker.get_room(room)
	assert_not_null(hrs)
	var server: LocalLoopbackServer = hrs.server
	var iid_use := _grant_wall_collapse(server, 0, "w-378-a")
	var iid_keep := _grant_wall_collapse(server, 0, "w-378-b")
	assert_false(iid_use.is_empty())
	assert_false(iid_keep.is_empty())
	assert_ne(iid_use, iid_keep)
	server.publish_snapshot()
	s0.close_connection_for_test()
	for _i in range(40):
		s0.poll()
		if s0.get("_recovering"):
			break
		await wait_process_frames(1)
	assert_eq(s0.retry_reconnect(), OK)
	assert_true(await _poll_until(worker, [s0], func(): return s0.has_committed_snapshot(), 240))
	var table: Node = await _pair_table()
	s0.bind_playable_table(table)
	table.sync_public_table_projection()
	await get_tree().process_frame
	assert_true(await _poll_until(worker, [s0], func():
		return _inventory_has_instance(s0, iid_use) and _inventory_has_instance(s0, iid_keep)
	, 180), "库存须投影两张精确 instance")
	assert_true(await _poll_until(worker, [s0], func(): return _find_turn_prompt(s0) != null, 180))
	var prompt := _find_turn_prompt(s0)
	assert_not_null(prompt)
	assert_eq(_options_of(prompt, "ITEM_USE").size(), 0, "TURN offer 不得含 ITEM_USE")
	var accepted: Array = []
	var accepted_cmd := [""]
	var inv_n_before := (s0.nbc.get_item_inventory_view().get("items", []) as Array).size()
	var seq_before := int(s0.nbc.current_seq())
	assert_false(s0.nbc.resync_required(), "USE 前不得 resync seq=%d" % seq_before)
	# 分离 CR 与业务事件：ACCEPTED 回调时尚未 committed
	worker.set_hold_event_broadcast_for_test(true)
	var lock_at_accept := [false]
	var inv_at_accept := [-1]
	var busy_at_accept := [false]
	s0.command_accepted.connect(func(cr):
		accepted.append(1)
		if cr != null:
			accepted_cmd[0] = str(cr.command_id)
		inv_at_accept[0] = (s0.nbc.get_item_inventory_view().get("items", []) as Array).size()
		lock_at_accept[0] = bool(table._public_input_locked)
		busy_at_accept[0] = s0.is_awaiting_authority_commit()
		# 当场严格：库存未乐观减少；UI/出口仍忙
		assert_eq(inv_at_accept[0], inv_n_before, "ACCEPTED 瞬间库存张数不得乐观减少")
		assert_true(_inventory_has_instance(s0, iid_use), "ACCEPTED 瞬间目标 instance 仍须在库存")
		assert_true(lock_at_accept[0], "ACCEPTED 瞬间 UI 须仍锁定")
		assert_true(busy_at_accept[0], "ACCEPTED 瞬间 session 须 awaiting_committed")
		assert_true(_action_buttons_disabled_or_hidden(table), "ACCEPTED 瞬间动作栏须锁")
		assert_true(_inventory_use_disabled(table), "ACCEPTED 瞬间 Use 须 disabled")
	)
	var attempts0 := int(table.public_network_command_attempts())
	table._on_inventory_use_requested(iid_use)
	assert_gt(int(table.public_network_command_attempts()), attempts0, "须经 session 唯一出口提交")
	assert_true(await _poll_until(worker, [s0], func(): return not accepted.is_empty(), 180),
		"须 matching command_accepted")
	assert_true(ProtocolUuid.is_canonical_v4(accepted_cmd[0]))
	assert_eq(inv_at_accept[0], inv_n_before)
	assert_true(s0.is_awaiting_authority_commit(), "CR 后、事件前须 awaiting_committed")
	# 重复点击/二次 submit 不得形成新命令
	var mid_attempts := int(table.public_network_command_attempts())
	table._on_inventory_use_requested(iid_keep)
	table._on_player_tile_clicked(1)
	table._action_panel.player_action_chosen.emit({"action": "tsumo"})
	assert_eq(int(table.public_network_command_attempts()), mid_attempts)
	assert_eq(s0.submit_action(Action.item_use(
		0, iid_keep, room, s0.allocate_command_id(),
		str(prompt.payload.get("decision_id", "")), int(prompt.payload.get("hand_seq", 0)),
		s0.allocate_client_seq()
	)), ERR_BUSY, "awaiting_committed 时 submit_action 须 ERR_BUSY")
	# 释放业务事件 → committed 闭环
	worker.set_hold_event_broadcast_for_test(false)
	assert_true(await _poll_until(worker, [s0], func():
		if not _journal_has_item_event(s0, "ITEM_APPLIED", iid_use, accepted_cmd[0]):
			return false
		if not _journal_has_item_event(s0, "ITEM_CONSUMED", iid_use, accepted_cmd[0]):
			return false
		if int(s0.nbc.current_seq()) <= seq_before:
			return false
		if _inventory_has_instance(s0, iid_use):
			return false
		if not _inventory_has_instance(s0, iid_keep):
			return false
		if s0.is_awaiting_authority_commit():
			return false
		return true
	, 300), "客户端须 committed ITEM_* + SNAP 库存闭环并解除 awaiting")
	# #378 R5：committed 后无新 prompt 也须解除 UI 自锁（不得永久“命令处理中”）
	table.sync_public_table_projection()
	await get_tree().process_frame
	assert_false(s0.is_awaiting_authority_commit())
	assert_false(s0.is_command_pending())
	assert_false(table._public_input_locked,
		"ITEM_USE committed 后 UI 须解锁（不依赖新 TURN/CLAIM）")
	assert_false(_inventory_use_disabled(table),
		"committed 后 inventory use lock 须 false")
	assert_null(server.mode_modules.item_inventory.find_instance(iid_use),
		"权威模块目标 instance 须消失")
	assert_not_null(server.mode_modules.item_inventory.find_instance(iid_keep),
		"权威模块其它 instance 须保留")
	var still_has_use := _inventory_has_instance(s0, iid_use)
	var still_has_keep := _inventory_has_instance(s0, iid_keep)
	assert_false(still_has_use, "客户端库存目标 instance 须消失")
	assert_true(still_has_keep, "客户端库存其它同 item_id instance 须保留")
	# 剩余 iid_keep 的真实 UseButton 须 enabled
	assert_true(table._table != null and table._table.item_inventory_drawer != null)
	table._table.open_inventory_drawer()
	await get_tree().process_frame
	assert_true(_inventory_use_button_enabled(table, iid_keep),
		"remaining iid_keep 的 UseButton 须 enabled")
	# SNAP 折叠旧 TURN 后，原 decision 的 disc 不得再经 UI 提交
	var did_before := str(prompt.payload.get("decision_id", ""))
	var dv_after: Dictionary = table.get_public_decision_view()
	var did_after := str(dv_after.get("decision_id", ""))
	assert_true(did_after.is_empty() or did_after != did_before,
		"SNAP 后旧 decision_id 不得仍为可操作权威 decision")
	var att_after := int(table.public_network_command_attempts())
	var old_disc: Dictionary = _first_option(prompt, "DISCARD")
	table._on_player_tile_clicked(int(old_disc.get("tile_instance_id", -1)))
	assert_eq(int(table.public_network_command_attempts()), att_after,
		"旧 decision 不可操作，不得增加 network attempts")
	assert_true(_journal_has_item_event(s0, "ITEM_APPLIED", iid_use, accepted_cmd[0]))
	assert_true(_journal_has_item_event(s0, "ITEM_CONSUMED", iid_use, accepted_cmd[0]))
	assert_false(JSON.stringify(s0.nbc.get_item_inventory_view()).contains(s0.room_token))
	assert_false(JSON.stringify(s0.nbc.get_event_journal()).contains(s0.room_token))
	await _release_table(table, s0)
	worker.stop()



# ── 6) 幂等 / 拒绝 ────────────────────────────────────────────

func test_idempotent_retry_and_fingerprint_conflict() -> void:
	# 固定 seed 确保多 DISCARD option，无条件异指纹 → 精确 COMMAND_ID_CONFLICT
	var worker := _new_worker()
	var room := "room-378-idemp"
	var parts := ["HUMAN", "AI", "HUMAN", "AI"]
	_install_seeded_room(worker, room, 2, parts)
	var s0 := _make_session(worker, room, 0, "guest-378-id0", "STANDARD", parts)
	var s2 := _make_session(worker, room, 2, "guest-378-id2", "STANDARD", parts)
	assert_eq(s0.start(), OK)
	assert_eq(s2.start(), OK)
	assert_true(await _poll_until(worker, [s0, s2], func():
		return s0.has_committed_snapshot() and _find_turn_prompt(s0) != null, 300))
	var prompt := _find_turn_prompt(s0)
	assert_not_null(prompt)
	var opts := _options_of(prompt, "DISCARD")
	assert_gte(opts.size(), 2, "seed=2 须有 ≥2 DISCARD option 以测异指纹")
	var cmd := s0.allocate_command_id()
	var act1 := _build_action_from_offer(s0, prompt, "DISCARD", opts[0], cmd, 1)
	assert_eq(s0.submit_action(act1), OK)
	assert_true(await _poll_until(worker, [s0, s2], func():
		return not s0.is_command_pending() and not s0.is_awaiting_authority_commit()
	, 180))
	var applied_before := _count_applied_cmd(s0.nbc.get_event_journal(), cmd)
	assert_gte(applied_before, 1)
	# 同指纹重试：不新增 ACTION_APPLIED
	assert_eq(s0.submit_action(act1), OK, "同指纹重试")
	assert_true(await _poll_until(worker, [s0, s2], func():
		return not s0.is_command_pending() and not s0.is_awaiting_authority_commit()
	, 120))
	assert_eq(_count_applied_cmd(s0.nbc.get_event_journal(), cmd), applied_before)
	# 异指纹同 command_id：必须稳定 COMMAND_ID_CONFLICT（无宽松集合）
	var rej: Array = []
	s0.command_rejected.connect(func(code, _c, _m): rej.append(str(code)))
	var act_c := _build_action_from_offer(s0, prompt, "DISCARD", opts[1], cmd, 2)
	assert_not_null(act_c)
	assert_eq(s0.submit_action(act_c), OK)
	assert_true(await _poll_until(worker, [s0, s2], func(): return not rej.is_empty(), 120),
		"异指纹须被拒绝")
	assert_eq(str(rej[0]), "COMMAND_ID_CONFLICT", "异指纹须精确 COMMAND_ID_CONFLICT")
	assert_eq(_count_applied_cmd(s0.nbc.get_event_journal(), cmd), applied_before)
	worker.stop()


func test_reject_restores_authority_decision_not_optimistic() -> void:
	var worker := _new_worker()
	var room := "room-378-reject"
	var s0 := _make_session(worker, room, 0, "guest-378-rj0")
	var s2 := _make_session(worker, room, 2, "guest-378-rj2")
	var table: Node = await _pair_table()
	s0.bind_playable_table(table)
	assert_eq(s0.start(), OK)
	assert_eq(s2.start(), OK)
	assert_true(await _poll_until(worker, [s0, s2], func():
		return s0.has_committed_snapshot() and _find_turn_prompt(s0) != null))
	table.sync_public_table_projection()
	await get_tree().process_frame
	var dv_before: Dictionary = table.get_public_decision_view()
	var prompt := _find_turn_prompt(s0)
	var bad := Action.discard(
		0, 0, room, s0.allocate_command_id(),
		"550e8400-e29b-41d4-a716-446655440099",
		int(prompt.payload.get("hand_seq", 0)), s0.allocate_client_seq()
	)
	var rej: Array = []
	s0.command_rejected.connect(func(code, _c, _m): rej.append(code))
	assert_eq(s0.submit_action(bad), OK)
	assert_true(await _poll_until(worker, [s0, s2], func(): return not rej.is_empty(), 120))
	table.sync_public_table_projection()
	await get_tree().process_frame
	assert_eq(str(table.get_public_decision_view().get("decision_id", "")),
		str(dv_before.get("decision_id", "")))
	assert_false(table._public_input_locked, "ERROR 后须解锁")
	await _release_table(table, s0)
	worker.stop()


# ── 7) ACCEPTED 不乐观 ────────────────────────────────────────

func test_accepted_does_not_optimistically_mutate_table() -> void:
	var worker := _new_worker()
	var room := "room-378-opt"
	var s0 := _make_session(worker, room, 0, "guest-378-opt0")
	var s2 := _make_session(worker, room, 2, "guest-378-opt2")
	var table: Node = await _pair_table()
	s0.bind_playable_table(table)
	assert_eq(s0.start(), OK)
	assert_eq(s2.start(), OK)
	assert_true(await _poll_until(worker, [s0, s2], func():
		return s0.has_committed_snapshot() and _find_turn_prompt(s0) != null))
	table.sync_public_table_projection()
	await get_tree().process_frame
	var hand_before := 0
	if table._table != null and table._table.seat_panels.size() > 0:
		for s in table._table.seat_panels[0].get("_hand_slots"):
			if s != null and is_instance_valid(s):
				hand_before += 1
	var prompt := _find_turn_prompt(s0)
	var act := _build_action_from_offer(s0, prompt, "DISCARD", _first_option(prompt, "DISCARD"))
	var hand_at := [-1]
	s0.command_accepted.connect(func(_cr):
		var n := 0
		if table._table != null and table._table.seat_panels.size() > 0:
			for s2b in table._table.seat_panels[0].get("_hand_slots"):
				if s2b != null and is_instance_valid(s2b):
					n += 1
		hand_at[0] = n
	)
	assert_eq(s0.submit_action(act), OK)
	assert_true(await _poll_until(worker, [s0, s2], func(): return hand_at[0] >= 0, 120))
	assert_eq(hand_at[0], hand_before, "ACCEPTED 瞬间不得乐观改手牌")
	await _release_table(table, s0)
	worker.stop()


# ── 8) 断线 pending 真实重试（P1-1/P1-2） ─────────────────────

func test_disconnect_pending_retry_same_decision() -> void:
	# 确定性正例：submit 后、Worker poll 前 simulate_disconnect，重连同 decision 原 cmd 重试一次
	var worker := _new_worker()
	var room := "room-378-retry"
	var s0 := _make_session(worker, room, 0, "guest-378-rt0")
	var s2 := _make_session(worker, room, 2, "guest-378-rt2")
	assert_eq(s0.start(), OK)
	assert_eq(s2.start(), OK)
	assert_true(await _poll_until(worker, [s0, s2], func():
		return s0.has_committed_snapshot() and _find_turn_prompt(s0) != null))
	var prompt := _find_turn_prompt(s0)
	assert_not_null(prompt)
	var disc := _first_option(prompt, "DISCARD")
	assert_false(disc.is_empty())
	var decision_id := str(prompt.payload.get("decision_id", ""))
	var hand_seq := int(prompt.payload.get("hand_seq", 0))
	var act := _build_action_from_offer(s0, prompt, "DISCARD", disc)
	var cmd := act.command_id
	var payload_json := JSON.stringify(act.payload)
	var gen_before := s0.get_connection_generation()
	var cid0 := _find_cid_for_seat(worker, 0)
	assert_gt(cid0, 0, "须定位 seat0 真实 WS cid")
	# 公开入口提交形成 pending
	assert_eq(s0.submit_action(act), OK)
	assert_true(s0.is_command_pending())
	# 关键：submit 后、任何 worker.poll 前断开，避免消费 queued Action
	worker.simulate_disconnect_for_test(cid0)
	var reconnected := [0]
	s0.reconnecting.connect(func(_c, _m): reconnected[0] += 1)
	# 仅 poll 客户端，避免 worker 在断线窗口 tick lease/AI
	var saw_re := false
	for _i in range(90):
		s0.poll()
		if reconnected[0] > 0:
			saw_re = true
			break
		await wait_process_frames(1)
	assert_true(saw_re, "客户端须进入 reconnecting")
	assert_true(s0.is_awaiting_pending_retry() or s0.is_command_pending(),
		"断线后须保留 pending 以待重试")
	assert_ne(s0.submit_action(act), OK, "旧代际/恢复窗口不得提交")
	assert_eq(s0.retry_reconnect(), OK)
	assert_gt(s0.get_connection_generation(), gen_before, "重连 generation 须增加")
	# 新 prompt 须与原 pending 的 room/seat/hand_seq/decision_id 完全一致
	assert_true(await _poll_until(worker, [s0, s2], func():
		if not s0.has_committed_snapshot():
			return false
		var p2 := _find_turn_prompt(s0)
		if p2 == null:
			return false
		return str(p2.payload.get("decision_id", "")) == decision_id \
			and int(p2.payload.get("hand_seq", -1)) == hand_seq \
			and int(p2.payload.get("seat", -1)) == 0
	, 300), "重连后须出现同 decision 的新 TURN_PROMPT")
	var p_match := _find_turn_prompt(s0)
	assert_not_null(p_match)
	assert_eq(str(p_match.payload.get("decision_id", "")), decision_id)
	assert_eq(int(p_match.payload.get("hand_seq", -1)), hand_seq)
	assert_eq(s0.room_id, room)
	assert_eq(s0.seat, 0)
	# 自动重试后恰好一次 ACTION_APPLIED
	assert_true(await _poll_until(worker, [s0, s2], func():
		return _count_applied_cmd(s0.nbc.get_event_journal(), cmd) >= 1
	, 300), "原 command_id 须被安全重试并产生业务事件")
	assert_eq(_count_applied_cmd(s0.nbc.get_event_journal(), cmd), 1,
		"同 command_id 恰好一次 ACTION_APPLIED")
	for item in s0.nbc.get_event_journal():
		if not (item is NetworkedEvent):
			continue
		var ne: NetworkedEvent = item as NetworkedEvent
		if ne.kind != "ACTION_APPLIED":
			continue
		if str(ne.payload.get("causation_command_id", "")) != cmd:
			continue
		var tile: Dictionary = (ne.payload.get("resolved_payload", {}) as Dictionary).get("tile", {})
		var expect_iid := int((JSON.parse_string(payload_json) as Dictionary).get("tile_instance_id", -2))
		assert_eq(int(tile.get("instance_id", -1)), expect_iid, "重试 payload 须与原 exact option 一致")
	assert_false(s0.is_command_pending())
	worker.stop()


func test_reconnect_decision_mismatch_drops_pending() -> void:
	# 确定性负例：submit A → poll 前断线 → 权威用另一 command 消费 decision A 并推进到 B
	# → 重连收到 B → decision_mismatch 丢弃，原 command_id 零 ACTION_APPLIED
	var worker := _new_worker()
	var room := "room-378-mismatch"
	var parts := ["HUMAN", "AI", "HUMAN", "AI"]
	_install_seeded_room(worker, room, 2, parts)
	var s0 := _make_session(worker, room, 0, "guest-378-mm0", "STANDARD", parts)
	var s2 := _make_session(worker, room, 2, "guest-378-mm2", "STANDARD", parts)
	assert_eq(s0.start(), OK)
	assert_eq(s2.start(), OK)
	assert_true(await _poll_until(worker, [s0, s2], func():
		return s0.has_committed_snapshot() and _find_turn_prompt(s0) != null, 300))
	var prompt_a := _find_turn_prompt(s0)
	assert_not_null(prompt_a)
	var disc_a := _first_option(prompt_a, "DISCARD")
	assert_false(disc_a.is_empty())
	var act_a := _build_action_from_offer(s0, prompt_a, "DISCARD", disc_a)
	assert_not_null(act_a)
	var cmd_a := act_a.command_id
	var decision_a := act_a.decision_id
	var hand_a := act_a.hand_seq
	var gen_before := s0.get_connection_generation()
	var cid0 := _find_cid_for_seat(worker, 0)
	assert_gt(cid0, 0)
	var dropped: Array = []
	s0.command_pending_dropped.connect(func(reason): dropped.append(str(reason)))
	var accepted_a: Array = []
	s0.command_accepted.connect(func(cr):
		if cr != null and str(cr.command_id) == cmd_a:
			accepted_a.append(1)
	)
	# 1) 公开入口 submit，Worker poll 前断线
	assert_eq(s0.submit_action(act_a), OK)
	assert_true(s0.is_command_pending())
	worker.simulate_disconnect_for_test(cid0)
	var saw_re := false
	for _i in range(90):
		s0.poll()
		if s0.get("_recovering"):
			saw_re = true
			break
		await wait_process_frames(1)
	assert_true(saw_re, "须进入 reconnecting")
	assert_true(s0.is_awaiting_pending_retry() or s0.is_command_pending(),
		"断线后须保留 pending 待匹配")
	assert_eq(_count_applied_cmd(s0.nbc.get_event_journal(), cmd_a), 0)
	# 2) 断线期间权威用另一 command 消费 decision A，并推进到 seat0 新 decision B
	var hrs: HeadlessRoomSession = worker.get_room(room)
	assert_not_null(hrs)
	var server: LocalLoopbackServer = hrs.server
	assert_not_null(server)
	var bc: BattleController = server.get("_bc") as BattleController
	assert_not_null(bc)
	for s in range(4):
		bc.decision_context_for_seat(s)
	var win0 = bc.get("_active_window")
	assert_true(win0 is DecisionWindow, "断线时须仍有 decision 窗")
	var dw0: DecisionWindow = win0 as DecisionWindow
	assert_eq(dw0.kind, DecisionWindow.KIND_TURN)
	assert_eq(int(dw0.subject_seat), 0)
	var tctx0: DecisionContext = dw0.context_for_seat(0)
	assert_not_null(tctx0)
	assert_eq(str(tctx0.decision_id), decision_a)
	var iid_side := -1
	for o in tctx0.allowed_actions:
		if typeof(o) == TYPE_DICTIONARY and str(o.get("kind", "")) == "DISCARD":
			iid_side = int((o.get("payload_options", [{}]) as Array)[0].get("tile_instance_id", -1))
			break
	assert_gte(iid_side, 0)
	var side_cmd := _cmd_n(88001)
	assert_ne(side_cmd, cmd_a)
	var side_act := Action.discard(
		0, iid_side, room, side_cmd, decision_a, hand_a, 88001
	)
	var side_cr: CommandResult = server.submit_action(side_act)
	assert_eq(side_cr.status, "ACCEPTED", "权威 side 须 ACCEPTED 消费 decision A: %s" % side_cr.error_code)
	# 推进至 seat0 再次有 TURN/CLAIM（decision B）
	var decision_b := ""
	var hand_b := -1
	for step in range(48):
		for s2i in range(4):
			bc.decision_context_for_seat(s2i)
		var w = bc.get("_active_window")
		if w is DecisionWindow:
			var dw: DecisionWindow = w as DecisionWindow
			if dw.kind == DecisionWindow.KIND_TURN and int(dw.subject_seat) == 0:
				var ctxb: DecisionContext = dw.context_for_seat(0)
				if ctxb != null and str(ctxb.decision_id) != decision_a:
					decision_b = str(ctxb.decision_id)
					hand_b = int(ctxb.hand_seq)
					break
			if dw.kind == DecisionWindow.KIND_CLAIM or dw.kind == DecisionWindow.KIND_ROB_KAN:
				# 全席 PASS 推进
				for si in dw.seats():
					var sxi: int = int(si)
					if dw.has_responded(sxi):
						continue
					var ctxp: DecisionContext = dw.context_for_seat(sxi)
					var pass_a := Action.make_pass(
						sxi, room, _cmd_n(89000 + step * 10 + sxi),
						str(ctxp.decision_id), int(ctxp.hand_seq), 89000 + step * 10 + sxi
					)
					_authority_submit(server, pass_a)
				continue
			if dw.kind == DecisionWindow.KIND_TURN:
				var actor: int = int(dw.subject_seat)
				if actor == 0:
					continue
				var tctx: DecisionContext = dw.context_for_seat(actor)
				var iid := -1
				for o2 in tctx.allowed_actions:
					if typeof(o2) == TYPE_DICTIONARY and str(o2.get("kind", "")) == "DISCARD":
						iid = int((o2.get("payload_options", [{}]) as Array)[0].get("tile_instance_id", -1))
						break
				if iid < 0:
					break
				var dact := Action.discard(
					actor, iid, room, _cmd_n(90000 + step),
					str(tctx.decision_id), int(tctx.hand_seq), 90000 + step
				)
				_authority_submit(server, dact)
		await wait_process_frames(1)
		if not decision_b.is_empty():
			break
	assert_false(decision_b.is_empty(), "须推进到 seat0 新 decision B")
	assert_true(decision_b != decision_a or hand_b != hand_a,
		"B 的 decision_id 或 hand_seq 须与 A 不同")
	# 3) 重连：应 mismatch drop
	assert_eq(s0.retry_reconnect(), OK)
	assert_gt(s0.get_connection_generation(), gen_before)
	assert_true(await _poll_until(worker, [s0, s2], func():
		return not dropped.is_empty() or (
			not s0.is_command_pending() and not s0.is_awaiting_pending_retry()
			and _find_turn_prompt(s0) != null
		)
	, 300), "重连后须处理 mismatch")
	assert_true(dropped.has("decision_mismatch"),
		"须 command_pending_dropped reason=decision_mismatch got=%s" % str(dropped))
	var mismatch_n := 0
	for r in dropped:
		if str(r) == "decision_mismatch":
			mismatch_n += 1
	assert_eq(mismatch_n, 1, "decision_mismatch 恰好一次")
	assert_false(s0.is_command_pending())
	assert_false(s0.is_awaiting_pending_retry())
	assert_true(accepted_a.is_empty(), "原 command_id 不得 matching ACCEPTED")
	assert_eq(_count_applied_cmd(s0.nbc.get_event_journal(), cmd_a), 0,
		"原 command_id A 的 ACTION_APPLIED 须为 0")
	# #378 R6：新代际已 JOIN 且 prompt B 在场、pending 已清后，旧 Action A 必须
	# 本地入口 submit OK → 真实 WS → Worker 对过期 decision 精确 COMMAND_REJECTED。
	# 不得用本地 ERR 三选一或条件分支掩盖未 JOIN/未 OPEN/busy 未清等回归。
	assert_false(s0.is_command_pending())
	assert_false(s0.is_awaiting_pending_retry())
	assert_false(s0.is_awaiting_authority_commit())
	assert_not_null(_find_turn_prompt(s0), "再提交前须已有新代际权威 prompt B")
	var stale_rej: Array = []
	var stale_acc: Array = []
	s0.command_rejected.connect(func(code, cmd, _m):
		if str(cmd) == cmd_a:
			stale_rej.append(str(code))
	)
	s0.command_accepted.connect(func(cr):
		if cr != null and str(cr.command_id) == cmd_a:
			stale_acc.append(1)
	)
	assert_eq(s0.submit_action(act_a), OK,
		"新代际恢复后旧 Action A 须本地入口 OK 并经 WS 发出")
	assert_true(await _poll_until(worker, [s0, s2], func():
		return not stale_rej.is_empty()
	, 180), "旧 Action A 须收到 matching command_id 的 Worker 拒绝")
	assert_eq(stale_rej.size(), 1, "旧 Action A 须恰好一次拒绝")
	assert_eq(str(stale_rej[0]), "COMMAND_REJECTED",
		"过期 decision 须精确 COMMAND_REJECTED，got=%s" % str(stale_rej))
	assert_true(stale_acc.is_empty(), "旧 Action A 不得 matching ACCEPTED")
	assert_eq(_count_applied_cmd(s0.nbc.get_event_journal(), cmd_a), 0,
		"原 command_id A 始终 0 次 ACTION_APPLIED")
	assert_false(s0.is_command_pending())
	assert_false(s0.is_awaiting_pending_retry())
	assert_false(s0.is_awaiting_authority_commit())
	worker.stop()




func _authority_submit(server: LocalLoopbackServer, act: Action) -> CommandResult:
	# HUMAN 席走 submit_action；配置 AI 席走 process_internal（require_human 会拒 AI）
	if act == null:
		return null
	var parts: Array = server.get("_participants") as Array
	var seat: int = int(act.seat)
	if seat >= 0 and seat < parts.size() and str(parts[seat]) == "HUMAN":
		return server.submit_action(act)
	var res: ActionResolution = server.process_internal_action(act, ActionSource.AI)
	if res != null and res.accepted:
		return CommandResult.from_dict({
			"protocol_version": ProtocolConstants.PROTOCOL_VERSION,
			"command_id": act.command_id,
			"status": "ACCEPTED",
			"server_seq": server.current_server_seq(),
			"error_code": "",
		})
	return CommandResult.from_dict({
		"protocol_version": ProtocolConstants.PROTOCOL_VERSION,
		"command_id": act.command_id,
		"status": "REJECTED",
		"server_seq": 0,
		"error_code": str(res.error_code) if res != null else "INVALID_ACTION",
	})


func test_real_worker_multi_claim_chi_exact_via_ui() -> void:
	# seed=5：约 3 步后 seat2 出现多 CHI option；先点 CHI 再选 exact companions
	var worker := _new_worker()
	var room := "room-378-claim-multi"
	var parts := ["HUMAN", "AI", "HUMAN", "AI"]
	_install_seeded_room(worker, room, 5, parts)
	var s0 := _make_session(worker, room, 0, "guest-378-cm0", "STANDARD", parts)
	var s2 := _make_session(worker, room, 2, "guest-378-cm2", "STANDARD", parts)
	var table2: Node = await _pair_table()
	s2.bind_playable_table(table2)
	assert_eq(s0.start(), OK)
	assert_eq(s2.start(), OK)
	assert_true(await _poll_until(worker, [s0, s2], func():
		return s0.has_committed_snapshot() and s2.has_committed_snapshot(), 240))
	var hrs: HeadlessRoomSession = worker.get_room(room)
	assert_not_null(hrs)
	var server: LocalLoopbackServer = hrs.server
	var server_has_multi_chi := false
	for step in range(40):
		var bc: BattleController = server.get("_bc") as BattleController
		if bc == null or bool(bc.get("_settled")):
			break
		for s in range(4):
			bc.decision_context_for_seat(s)
		var win = bc.get("_active_window")
		if not (win is DecisionWindow):
			await wait_process_frames(1)
			continue
		var dw: DecisionWindow = win as DecisionWindow
		if dw.kind == DecisionWindow.KIND_CLAIM or dw.kind == DecisionWindow.KIND_ROB_KAN:
			var seat2_has_multi := false
			var ctx2_live: DecisionContext = dw.context_for_seat(2)
			if ctx2_live != null and not dw.has_responded(2):
				for o_chk in ctx2_live.allowed_actions:
					if typeof(o_chk) == TYPE_DICTIONARY and str(o_chk.get("kind", "")) == "CHI":
						if (o_chk.get("payload_options", []) as Array).size() >= 2:
							seat2_has_multi = true
			if seat2_has_multi:
				server_has_multi_chi = true
				# 其它席 PASS（AI 用 process_internal），保留 seat2
				for seat_i2 in dw.seats():
					var si2: int = int(seat_i2)
					if si2 == 2 or dw.has_responded(si2):
						continue
					var ctx_p: DecisionContext = dw.context_for_seat(si2)
					var act_p2 := Action.make_pass(
						si2, room, _cmd_n(3000 + step * 10 + si2),
						str(ctx_p.decision_id), int(ctx_p.hand_seq), 3000 + step * 10 + si2
					)
					var cr_p: CommandResult = _authority_submit(server, act_p2)
					assert_eq(cr_p.status, "ACCEPTED", "PASS seat%d: %s" % [si2, cr_p.error_code])
				break
			# 非目标：全席 PASS 推进
			for seat_i3 in dw.seats():
				var si3: int = int(seat_i3)
				if dw.has_responded(si3):
					continue
				var ctx3: DecisionContext = dw.context_for_seat(si3)
				var act_p3 := Action.make_pass(
					si3, room, _cmd_n(3100 + step * 10 + si3),
					str(ctx3.decision_id), int(ctx3.hand_seq), 3100 + step * 10 + si3
				)
				_authority_submit(server, act_p3)
			continue
		if dw.kind == DecisionWindow.KIND_TURN:
			var actor: int = int(dw.subject_seat)
			var tctx: DecisionContext = dw.context_for_seat(actor)
			var iid := -1
			for o in tctx.allowed_actions:
				if typeof(o) == TYPE_DICTIONARY and str(o.get("kind", "")) == "DISCARD":
					iid = int((o.get("payload_options", [{}]) as Array)[0].get("tile_instance_id", -1))
					break
			if iid < 0:
				break
			var dact := Action.discard(
				actor, iid, room, _cmd_n(4000 + step),
				str(tctx.decision_id), int(tctx.hand_seq), 4000 + step
			)
			_authority_submit(server, dact)
		await wait_process_frames(1)
	assert_true(server_has_multi_chi, "权威侧须出现 seat2 多 CHI")
	# seat2 重连拉齐 CLAIM_WINDOW（权威推进不经该席 WS）
	s2.close_connection_for_test()
	for _j in range(40):
		worker.poll()
		s2.poll()
		if s2.get("_recovering"):
			break
		await wait_process_frames(1)
	assert_eq(s2.retry_reconnect(), OK)
	assert_true(await _poll_until(worker, [s0, s2], func():
		var cw2 := _find_claim_window(s2)
		return cw2 != null and _options_of(cw2, "CHI").size() >= 2
	, 300), "seat2 须有真实多 CHI CLAIM offer")
	table2.sync_public_table_projection()
	await get_tree().process_frame
	var claim := _find_claim_window(s2)
	assert_not_null(claim)
	var chi_opts2 := _options_of(claim, "CHI")
	assert_gte(chi_opts2.size(), 2, "须多 CHI payload_options")
	var chosen: Dictionary = chi_opts2[0] as Dictionary
	var comps: Array = chosen.get("companion_tile_instance_ids", []) as Array
	assert_eq(comps.size(), 2)
	var c0 := int(comps[0])
	var c1 := int(comps[1])
	assert_ne(c0, c1)
	var accepted: Array = []
	var accepted_cmd := [""]
	var rejected: Array = []
	s2.command_accepted.connect(func(cr):
		accepted.append(1)
		if cr != null:
			accepted_cmd[0] = str(cr.command_id)
	)
	s2.command_rejected.connect(func(code, cmd, msg):
		rejected.append("%s|%s|%s" % [str(code), str(cmd), str(msg)])
	)
	var attempts0 := int(table2.public_network_command_attempts())
	table2._action_panel.player_action_chosen.emit({"action": "chi"})
	await get_tree().process_frame
	assert_eq(str(table2.get("_public_pick_kind")), "CHI", "多 CHI 须进入候选选择")
	table2._on_player_tile_clicked(c1)
	assert_eq((table2.get("_public_pick_selected") as Array).size(), 1, "第一张 companion 须入选")
	table2._on_player_tile_clicked(c0)
	assert_gt(int(table2.public_network_command_attempts()), attempts0,
		"第二张 companion 后须经 session 提交")
	assert_true(await _poll_until(worker, [s0, s2], func():
		return not accepted.is_empty() or not rejected.is_empty()
	, 240), "多 CHI exact 须 ACCEPTED 或显式 REJECTED: %s" % str(rejected))
	assert_true(rejected.is_empty(), "多 CHI 不得被拒绝: %s" % str(rejected))
	assert_false(accepted.is_empty(), "多 CHI exact 须经 UI→session 被 ACCEPTED")
	assert_true(ProtocolUuid.is_canonical_v4(accepted_cmd[0]))
	assert_true(await _poll_until(worker, [s0, s2], func():
		for item in s2.nbc.get_event_journal():
			if not (item is NetworkedEvent):
				continue
			var ne: NetworkedEvent = item as NetworkedEvent
			if ne.kind != "ACTION_APPLIED":
				continue
			if str(ne.payload.get("action_kind", "")) != "CHI":
				continue
			if str(ne.payload.get("causation_command_id", "")) == accepted_cmd[0]:
				return true
		return false
	, 240), "须有 CHI ACTION_APPLIED 对应 command_id")
	await _release_table(table2, s2)
	worker.stop()


func test_empty_command_id_error_does_not_consume_pending() -> void:
	var worker := _new_worker()
	var room := "room-378-err"
	var s0 := _make_session(worker, room, 0, "guest-378-e0")
	var s2 := _make_session(worker, room, 2, "guest-378-e2")
	assert_eq(s0.start(), OK)
	assert_eq(s2.start(), OK)
	assert_true(await _poll_until(worker, [s0, s2], func():
		return s0.has_committed_snapshot() and _find_turn_prompt(s0) != null))
	var prompt := _find_turn_prompt(s0)
	var act := _build_action_from_offer(s0, prompt, "DISCARD", _first_option(prompt, "DISCARD"))
	assert_eq(s0.submit_action(act), OK)
	assert_true(s0.is_command_pending())
	# 注入空 command_id ERROR（无 server_seq/view_hash）
	var err_body := {
		"protocol_version": 1,
		"room_id": room,
		"kind": "ERROR",
		"request_id": null,
		"command_id": null,
		"code": "ROOM_FAILED",
		"message": "noise",
	}
	s0.ingest_authority_wire_for_test(JSON.stringify(err_body))
	assert_true(s0.is_command_pending(), "空 command_id ERROR 不得消费 pending")
	# 匹配 command_id 的拒绝才清除
	var err_match := err_body.duplicate(true)
	err_match["command_id"] = act.command_id
	err_match["code"] = "COMMAND_REJECTED"
	var rej: Array = []
	s0.command_rejected.connect(func(code, _c, _m): rej.append(code))
	s0.ingest_authority_wire_for_test(JSON.stringify(err_match))
	assert_false(s0.is_command_pending())
	assert_false(rej.is_empty())
	assert_false(JSON.stringify(err_match).contains(s0.room_token))
	worker.stop()


# ── 9) pending 真实 UI 锁（手牌/按钮/库存） ───────────────────

func test_pending_locks_hand_actions_inventory_via_ui() -> void:
	var worker := _new_worker()
	var room := "room-378-lock"
	var s0 := _make_session(worker, room, 0, "guest-378-lk0")
	var s2 := _make_session(worker, room, 2, "guest-378-lk2")
	var table: Node = await _pair_table()
	s0.bind_playable_table(table)
	assert_eq(s0.start(), OK)
	assert_eq(s2.start(), OK)
	assert_true(await _poll_until(worker, [s0, s2], func():
		return s0.has_committed_snapshot() and _find_turn_prompt(s0) != null))
	table.sync_public_table_projection()
	await get_tree().process_frame
	if table._table != null and table._table.item_inventory_drawer != null:
		table._table.open_inventory_drawer()
		table._table.item_inventory_drawer.set_instances([{
			"item_instance_id": "ii_lock_probe",
			"item_id": "wall_collapse_v1",
			"display_name": "probe",
			"status": "held",
		}])
	var prompt := _find_turn_prompt(s0)
	var opts := _options_of(prompt, "DISCARD")
	assert_false(opts.is_empty())
	var iid := int(opts[0]["tile_instance_id"])
	var hand_before := 0
	if table._table != null and table._table.seat_panels.size() > 0:
		for s in table._table.seat_panels[0].get("_hand_slots"):
			if s != null and is_instance_valid(s):
				hand_before += 1
	worker.set_hold_event_broadcast_for_test(true)
	var attempts := int(table.public_network_command_attempts())
	table._on_player_tile_clicked(iid)
	assert_gt(int(table.public_network_command_attempts()), attempts)
	assert_true(table._public_input_locked, "submit 后 UI 须锁定")
	assert_true(s0.is_command_pending())
	assert_true(_action_buttons_disabled_or_hidden(table), "动作按钮须隐藏/禁用")
	assert_true(_inventory_use_disabled(table), "库存 Use 须 disabled")
	var mid := int(table.public_network_command_attempts())
	table._action_panel.player_action_chosen.emit({"action": "tsumo"})
	table._on_inventory_use_requested("ii_lock_probe")
	table._on_player_tile_clicked(iid)
	assert_eq(int(table.public_network_command_attempts()), mid)
	assert_eq(s0.submit_action(_build_action_from_offer(
		s0, prompt, "DISCARD", opts[0])), ERR_BUSY)
	# ACCEPTED 但事件 hold：严格 awaiting_committed + UI 锁 + 手牌未乐观变化
	assert_true(await _poll_until(worker, [s0, s2], func():
		return s0.is_awaiting_authority_commit()
	, 180), "hold 下 CR 后须进入 awaiting_authority_commit")
	assert_true(s0.is_awaiting_authority_commit(), "ACCEPTED→committed 前 session 须 awaiting")
	assert_true(table._public_input_locked, "ACCEPTED→committed 前 UI 须锁定")
	assert_true(_action_buttons_disabled_or_hidden(table), "awaiting 期间动作栏须锁")
	assert_true(_inventory_use_disabled(table), "awaiting 期间 Use 须 disabled")
	var hand_mid := 0
	if table._table != null and table._table.seat_panels.size() > 0:
		for s2b in table._table.seat_panels[0].get("_hand_slots"):
			if s2b != null and is_instance_valid(s2b):
				hand_mid += 1
	assert_eq(hand_mid, hand_before, "ACCEPTED→committed 前手牌不得乐观变化")
	var mid2 := int(table.public_network_command_attempts())
	table._on_player_tile_clicked(iid)
	table._action_panel.player_action_chosen.emit({"action": "tsumo"})
	assert_eq(int(table.public_network_command_attempts()), mid2, "awaiting 期间重复点击不得增 attempts")
	assert_eq(s0.submit_action(_build_action_from_offer(
		s0, prompt, "DISCARD", opts[0])), ERR_BUSY, "awaiting_committed 时出口仍 BUSY")
	worker.set_hold_event_broadcast_for_test(false)
	assert_true(await _poll_until(worker, [s0, s2], func():
		return not s0.is_command_pending() and not s0.is_awaiting_authority_commit()
	, 240), "committed 后须解除 awaiting")
	table.sync_public_table_projection()
	await get_tree().process_frame
	# #378 R5：committed 后 UI 不得永久锁死（按新权威 decision/idle 恢复）
	assert_false(s0.is_awaiting_authority_commit())
	assert_false(s0.is_command_pending())
	assert_false(table._public_input_locked, "committed 后 UI 输入锁须解除")
	assert_false(_inventory_use_disabled(table), "committed 后库存 Use 须解锁")
	# 旧 disc decision 已消费：原 iid 不得再增加 attempts（新 prompt 若存在则 option 集已变）
	var att_post := int(table.public_network_command_attempts())
	var dv_post: Dictionary = table.get_public_decision_view()
	var did_post := str(dv_post.get("decision_id", ""))
	var did_old := str(prompt.payload.get("decision_id", ""))
	if did_post.is_empty() or did_post != did_old:
		table._on_player_tile_clicked(iid)
		assert_eq(int(table.public_network_command_attempts()), att_post,
			"旧 decision 消费后原 disc 不得再提交")
	else:
		# 同 decision 不应发生在 DISCARD 消费后；若发生则失败
		assert_true(false, "DISCARD committed 后 decision_id 不得仍为旧值")
	await _release_table(table, s0)
	worker.stop()


func test_wrong_seat_and_stale_decision_stable_error_no_token() -> void:
	var worker := _new_worker()
	var room := "room-378-stable-err"
	var s0 := _make_session(worker, room, 0, "guest-378-se0")
	var s2 := _make_session(worker, room, 2, "guest-378-se2")
	assert_eq(s0.start(), OK)
	assert_eq(s2.start(), OK)
	assert_true(await _poll_until(worker, [s0, s2], func():
		return s0.has_committed_snapshot() and _find_turn_prompt(s0) != null))
	var prompt := _find_turn_prompt(s0)
	var disc := _first_option(prompt, "DISCARD")
	assert_false(disc.is_empty())
	# 错席：seat2 session 提交 seat0 Action → 唯一出口稳定拒绝（ERR_INVALID_PARAMETER）
	var wrong_seat := Action.discard(
		0, int(disc.get("tile_instance_id", -1)), room, s2.allocate_command_id(),
		str(prompt.payload.get("decision_id", "")), int(prompt.payload.get("hand_seq", 0)),
		s2.allocate_client_seq()
	)
	assert_eq(s2.submit_action(wrong_seat), ERR_INVALID_PARAMETER,
		"绑定 seat2 提交 seat0 Action 须稳定 ERR_INVALID_PARAMETER")
	assert_false(s2.is_command_pending())
	assert_eq(_count_applied_cmd(s2.nbc.get_event_journal(), wrong_seat.command_id), 0)
	# 过期 decision：伪造 decision_id → Worker 稳定 COMMAND_REJECTED（非宽松集合）
	var stale_rej: Array = []
	s0.command_rejected.connect(func(code, _c, _m): stale_rej.append(str(code)))
	var stale := Action.discard(
		0, int(disc.get("tile_instance_id", -1)), room, s0.allocate_command_id(),
		"550e8400-e29b-41d4-a716-446655440099",
		int(prompt.payload.get("hand_seq", 0)), s0.allocate_client_seq()
	)
	assert_eq(s0.submit_action(stale), OK)
	assert_true(await _poll_until(worker, [s0, s2], func(): return not stale_rej.is_empty(), 120))
	assert_eq(stale_rej.size(), 1, "过期 decision 须恰好一次拒绝")
	assert_eq(str(stale_rej[0]), "COMMAND_REJECTED", "过期 decision 须精确 COMMAND_REJECTED")
	assert_false(JSON.stringify(stale_rej).contains(s0.room_token))
	assert_false(JSON.stringify(s0.nbc.get_event_journal()).contains(s0.room_token))
	assert_false(JSON.stringify(s2.nbc.get_event_journal()).contains(s2.room_token))
	worker.stop()


func _last_view_hash(sess: PublicCasualNetworkSession) -> String:
	if sess == null or sess.nbc == null:
		return ""
	var vh := ""
	for item in sess.nbc.get_event_journal():
		if item is NetworkedEvent:
			vh = str((item as NetworkedEvent).view_hash)
	return vh


func _tile_dict(tile_id: int, copy_index: int) -> Dictionary:
	return {
		"instance_id": TileId.ALL.find(tile_id) * 4 + copy_index,
		"tile_id": tile_id,
		"is_red_dora": false,
		"owner_seat": copy_index,
	}


## 分层：公开 ingress 驱动 PlayableTable 先动作再 exact 实体；在 worker.poll 前捕获完整 Action payload。
func test_public_ui_exact_payload_pon_kan_riichi_via_ingress() -> void:
	var worker := _new_worker()
	var room := "room-378-exact-payload"
	var s0 := _make_session(worker, room, 0, "guest-378-ep0")
	var s2 := _make_session(worker, room, 2, "guest-378-ep2")
	var table: Node = await _pair_table()
	s0.bind_playable_table(table)
	assert_eq(s0.start(), OK)
	assert_eq(s2.start(), OK)
	assert_true(await _poll_until(worker, [s0, s2], func():
		return s0.has_committed_snapshot() and s0.nbc.current_seq() > 0, 240))
	var vh := _last_view_hash(s0)
	assert_eq(vh.length(), 64)
	var seq0 := int(s0.nbc.current_seq())
	var did := "550e8400-e29b-41d4-a716-4466554400aa"
	var t0 := _tile_dict(TileId.W1, 0)
	var t1 := _tile_dict(TileId.W2, 0)
	var t2 := _tile_dict(TileId.W3, 0)
	var t3 := _tile_dict(TileId.W4, 0)
	var p0 := _tile_dict(TileId.W5, 0)
	var p1 := _tile_dict(TileId.W5, 1)
	var p2 := _tile_dict(TileId.W5, 2)
	var a0 := _tile_dict(TileId.S1, 0)
	var a1 := _tile_dict(TileId.S1, 1)
	var a2 := _tile_dict(TileId.S1, 2)
	var a3 := _tile_dict(TileId.S1, 3)
	var added := _tile_dict(TileId.HAKU, 0)
	var claim_pay := {
		"hand_seq": 0,
		"decision_id": did,
		"discarded_by_seat": 1,
		"discarded_tile": _tile_dict(TileId.W5, 3),
		"allowed_actions": [
			{"kind": "PASS", "payload_options": [{}]},
			{"kind": "PON", "payload_options": [
				{"companion_tile_instance_ids": [int(p0["instance_id"]), int(p1["instance_id"])]},
				{"companion_tile_instance_ids": [int(p1["instance_id"]), int(p2["instance_id"])]},
			]},
			{"kind": "KAN", "payload_options": [{
				"kan_kind": "MINKAN",
				"companion_tile_instance_ids": [
					int(p0["instance_id"]), int(p1["instance_id"]), int(p2["instance_id"]),
				],
			}]},
			{"kind": "RON", "payload_options": [{}]},
		],
	}
	var ne_claim := NetworkedEvent.make("CLAIM_WINDOW", seq0 + 1, room, claim_pay, vh)
	assert_not_null(ne_claim)
	s0.ingest_authority_wire_for_test(JSON.stringify(ne_claim.to_dict()))
	table.sync_public_table_projection()
	await get_tree().process_frame
	# multi PON：先动作再 exact companions；在 worker.poll 前严格捕获 pending
	var att_pon0 := int(table.public_network_command_attempts())
	table._action_panel.player_action_chosen.emit({"action": "pon"})
	await get_tree().process_frame
	assert_eq(str(table.get("_public_pick_kind")), "PON")
	table._on_player_tile_clicked(int(p0["instance_id"]))
	table._on_player_tile_clicked(int(p1["instance_id"]))
	assert_gt(int(table.public_network_command_attempts()), att_pon0, "PON exact 须经 session 出口")
	assert_true(s0.is_command_pending(), "poll 前须仍 pending 以捕获完整 payload")
	var pend_pon: Action = s0.get_pending_action()
	assert_not_null(pend_pon)
	assert_eq(str(pend_pon.kind), "PON")
	assert_eq(
		JSON.stringify(Action.normalize_payload("PON", pend_pon.payload)),
		JSON.stringify(Action.normalize_payload("PON", {
			"companion_tile_instance_ids": [int(p0["instance_id"]), int(p1["instance_id"])],
		}))
	)
	# 消化 CR（权威必拒 fixture decision），清空出口
	assert_true(await _poll_until(worker, [s0, s2], func():
		return not s0.is_command_pending() and not s0.is_awaiting_authority_commit()
	, 120))
	# 同 journal decision 仍在：仅 sync 重投，不得重复 ingest 同一 server_seq
	table.sync_public_table_projection()
	await get_tree().process_frame
	# 直接提交路径：emit 后同步捕获 pending（不得 await process_frame，否则 _process 自动 poll 会清 pending）
	var att_mk0 := int(table.public_network_command_attempts())
	table._action_panel.player_action_chosen.emit({"action": "minkan"})
	assert_gt(int(table.public_network_command_attempts()), att_mk0, "MINKAN 单候选须直接提交")
	assert_true(s0.is_command_pending(), "emit 同步后、_process 前须 pending")
	var pend_mk: Action = s0.get_pending_action()
	assert_not_null(pend_mk)
	assert_eq(str(pend_mk.kind), "KAN")
	assert_eq(str(pend_mk.payload.get("kan_kind", "")), "MINKAN")
	assert_eq(
		JSON.stringify(Action.normalize_payload("KAN", pend_mk.payload)),
		JSON.stringify(Action.normalize_payload("KAN", {
			"kan_kind": "MINKAN",
			"companion_tile_instance_ids": [
				int(p0["instance_id"]), int(p1["instance_id"]), int(p2["instance_id"]),
			],
		}))
	)
	assert_true(await _poll_until(worker, [s0, s2], func():
		return not s0.is_command_pending() and not s0.is_awaiting_authority_commit()
	, 120))
	table.sync_public_table_projection()
	await get_tree().process_frame
	var act_ron: Action = table.build_public_action_from_choice({"action": "ron"})
	assert_not_null(act_ron, "RON 单候选须可构造")
	assert_eq(str(act_ron.kind), "RON")
	var act_pass_claim: Action = table.build_public_action_from_choice({"action": "pass"})
	assert_not_null(act_pass_claim, "CLAIM PASS 单候选须可构造")
	assert_eq(str(act_pass_claim.kind), "PASS")
	# TURN multi RIICHI + ANKAN + ADDED_KAN + TSUMO + DECLARE_ABORTIVE_DRAW
	var seq1 := int(s0.nbc.current_seq())
	var vh1 := _last_view_hash(s0)
	assert_eq(vh1.length(), 64, "TURN 前须有有效 view_hash")
	var turn_did := "550e8400-e29b-41d4-a716-4466554400bb"
	var turn_pay := {
		"hand_seq": 0,
		"decision_id": turn_did,
		"seat": 0,
		"hand": [t0, t1, t2, t3, a0, a1, a2, a3, added],
		"last_drawn_tile_instance_id": int(t0["instance_id"]),
		"allowed_actions": [
			{"kind": "DISCARD", "payload_options": [
				{"tile_instance_id": int(t0["instance_id"])},
				{"tile_instance_id": int(t1["instance_id"])},
			]},
			{"kind": "RIICHI", "payload_options": [
				{"tile_instance_id": int(t0["instance_id"])},
				{"tile_instance_id": int(t1["instance_id"])},
			]},
			{"kind": "KAN", "payload_options": [
				{
					"kan_kind": "ANKAN",
					"tile_instance_ids": [
						int(a0["instance_id"]), int(a1["instance_id"]),
						int(a2["instance_id"]), int(a3["instance_id"]),
					],
				},
				{
					"kan_kind": "ADDED_KAN",
					"meld_id": 1,
					"added_tile_instance_id": int(added["instance_id"]),
				},
			]},
			{"kind": "TSUMO", "payload_options": [{}]},
			{"kind": "DECLARE_ABORTIVE_DRAW", "payload_options": [
				{"reason": "KYUUSYU_KYUUHAI"},
			]},
		],
	}
	var ne_turn := NetworkedEvent.make("TURN_PROMPT", seq1 + 1, room, turn_pay, vh1)
	assert_not_null(ne_turn)
	s0.ingest_authority_wire_for_test(JSON.stringify(ne_turn.to_dict()))
	table.sync_public_table_projection()
	await get_tree().process_frame
	# RIICHI multi exact：进 pick 可 await；点选提交后同步捕获
	var att_r0 := int(table.public_network_command_attempts())
	table._action_panel.player_action_chosen.emit({"action": "riichi"})
	await get_tree().process_frame
	assert_eq(str(table.get("_public_pick_kind")), "RIICHI")
	table._on_player_tile_clicked(int(t1["instance_id"]))
	assert_gt(int(table.public_network_command_attempts()), att_r0)
	assert_true(s0.is_command_pending())
	var pend_r: Action = s0.get_pending_action()
	assert_not_null(pend_r)
	assert_eq(str(pend_r.kind), "RIICHI")
	assert_eq(int(pend_r.payload.get("tile_instance_id", -1)), int(t1["instance_id"]))
	assert_true(await _poll_until(worker, [s0, s2], func():
		return not s0.is_command_pending() and not s0.is_awaiting_authority_commit()
	, 120))
	# ANKAN：按 kan_kind 过滤后单候选直接提交
	table.sync_public_table_projection()
	await get_tree().process_frame
	var att_k0 := int(table.public_network_command_attempts())
	table._action_panel.player_action_chosen.emit({"action": "ankan"})
	assert_gt(int(table.public_network_command_attempts()), att_k0, "ANKAN 须经 session 出口")
	assert_true(s0.is_command_pending())
	var pend_k: Action = s0.get_pending_action()
	assert_not_null(pend_k)
	assert_eq(str(pend_k.kind), "KAN")
	assert_eq(str(pend_k.payload.get("kan_kind", "")), "ANKAN")
	assert_eq(
		JSON.stringify(Action.normalize_payload("KAN", pend_k.payload)),
		JSON.stringify(Action.normalize_payload("KAN", {
			"kan_kind": "ANKAN",
			"tile_instance_ids": [
				int(a0["instance_id"]), int(a1["instance_id"]),
				int(a2["instance_id"]), int(a3["instance_id"]),
			],
		}))
	)
	assert_true(await _poll_until(worker, [s0, s2], func():
		return not s0.is_command_pending() and not s0.is_awaiting_authority_commit()
	, 120))
	# ADDED_KAN 精确 payload
	table.sync_public_table_projection()
	await get_tree().process_frame
	var att_ak0 := int(table.public_network_command_attempts())
	table._action_panel.player_action_chosen.emit({"action": "added_kan"})
	assert_gt(int(table.public_network_command_attempts()), att_ak0, "ADDED_KAN 须经 session 出口")
	assert_true(s0.is_command_pending())
	var pend_ak: Action = s0.get_pending_action()
	assert_not_null(pend_ak)
	assert_eq(str(pend_ak.kind), "KAN")
	assert_eq(str(pend_ak.payload.get("kan_kind", "")), "ADDED_KAN")
	assert_eq(int(pend_ak.payload.get("meld_id", -1)), 1)
	assert_eq(int(pend_ak.payload.get("added_tile_instance_id", -1)), int(added["instance_id"]))
	assert_true(await _poll_until(worker, [s0, s2], func():
		return not s0.is_command_pending() and not s0.is_awaiting_authority_commit()
	, 120))
	# TSUMO / DECLARE_ABORTIVE_DRAW 单候选公开构造
	table.sync_public_table_projection()
	await get_tree().process_frame
	var act_tsumo: Action = table.build_public_action_from_choice({"action": "tsumo"})
	assert_not_null(act_tsumo, "TSUMO 单候选须可构造")
	assert_eq(str(act_tsumo.kind), "TSUMO")
	var act_abort: Action = table.build_public_action_from_choice({"action": "kyuusyu_yes"})
	assert_not_null(act_abort, "DECLARE_ABORTIVE_DRAW 单候选须可构造")
	assert_eq(str(act_abort.kind), "DECLARE_ABORTIVE_DRAW")
	assert_eq(str(act_abort.payload.get("reason", "")), "KYUUSYU_KYUUHAI")
	await _release_table(table, s0)
	worker.stop()
