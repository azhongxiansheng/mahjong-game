extends GutTest

# #252 Round 8：RewardWindowSnapshotProvider + TRASH_TALK registry 集成。
# 真实 LocalLoopback / HeadlessRoomSession / NBC 两阶段 restore；
# 不 mock 核心规则；不发 ITEM_GRANTED；网络 e2e 未验证。

const CHARS := [&"lin_yeche", &"qiu_jue", &"bai_touli", &"hua_ling"]
const PARTS := [&"HUMAN", &"AI", &"AI", &"AI"]
const SECRET := "0123456789abcdef0123456789abcdef"


func _cfg_tt(seed: int = 42) -> GameSessionConfig:
	return GameSessionConfig.create_validated(
		GameSessionConfig.ROOM_PRACTICE, GameSessionConfig.ROUND_EAST,
		GameSessionConfig.MODE_TRASH_TALK, PARTS, CHARS, seed, "rw-snap-tt", "rv-r8"
	)


func _cfg_std(seed: int = 7) -> GameSessionConfig:
	return GameSessionConfig.create_validated(
		GameSessionConfig.ROOM_PRACTICE, GameSessionConfig.ROUND_EAST,
		GameSessionConfig.MODE_STANDARD, PARTS, CHARS, seed, "rw-snap-std", "rv"
	)


func _module_keys_from_snap(payload: Dictionary) -> Array:
	var keys: Array = []
	for m in payload.get("modules", []):
		if typeof(m) == TYPE_DICTIONARY:
			keys.append(str((m as Dictionary).get("module_key", "")))
	return keys


func _find_module(payload: Dictionary, key: String) -> Dictionary:
	for m in payload.get("modules", []):
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var md: Dictionary = m
		if str(md.get("module_key", "")) == key:
			return md
	return {}


func _first_snapshot(server: LocalLoopbackServer, seat: int = 0) -> NetworkedEvent:
	for ne in server.event_journal(seat):
		if ne is NetworkedEvent and (ne as NetworkedEvent).kind == "ROOM_SNAPSHOT":
			return ne as NetworkedEvent
	return null


func _kinds(server: LocalLoopbackServer, seat: int = 0) -> Array:
	var out: Array = []
	for ne in server.event_journal(seat):
		if ne is NetworkedEvent:
			out.append((ne as NetworkedEvent).kind)
	return out


func _count(kinds: Array, kind: String) -> int:
	var n := 0
	for k in kinds:
		if String(k) == kind:
			n += 1
	return n


func test_make_trash_talk_registry_keys_stable_sorted() -> void:
	var reg := SnapshotModuleRegistry.make_trash_talk()
	assert_true(reg.is_trash_talk_registry())
	assert_false(reg.is_standard_only())
	var keys: Array = reg.registered_keys()
	assert_eq(keys.size(), 4)
	assert_eq(str(keys[0]), "core_table")
	assert_eq(str(keys[1]), "item_inventory")
	assert_eq(str(keys[2]), "reward_window")
	assert_eq(str(keys[3]), "viewer_next_draw")
	assert_eq(int(reg.provider_for("reward_window").schema_version()),
		RewardWindowModule.SCHEMA_VERSION)
	assert_eq(int(reg.provider_for("item_inventory").schema_version()),
		ItemInventoryModule.SCHEMA_VERSION)
	assert_eq(int(reg.provider_for("viewer_next_draw").schema_version()), 1)


func test_standard_registry_still_only_core_table() -> void:
	var reg := SnapshotModuleRegistry.make_standard()
	assert_true(reg.is_standard_only())
	assert_false(reg.has_module("reward_window"))
	assert_false(reg.has_module("viewer_next_draw"))


func test_trash_talk_loopback_snapshot_has_core_and_reward_sorted() -> void:
	var server := LocalLoopbackServer.new(_cfg_tt(11), 0)
	assert_true(server.snapshot_registry.is_trash_talk_registry())
	assert_true(server.start())
	# start 顺序：首帧 SNAP（可能 IDLE）→ OPENED → PROMPT；再发一帧 SNAP 捕获 OPEN
	assert_true(server.publish_snapshot())
	var snap: NetworkedEvent = null
	for ne in server.event_journal(0):
		if ne is NetworkedEvent and (ne as NetworkedEvent).kind == "ROOM_SNAPSHOT":
			snap = ne as NetworkedEvent
	assert_not_null(snap)
	var keys: Array = _module_keys_from_snap(snap.payload)
	assert_eq(keys.size(), 3, "TRASH_TALK modules 恰 3")
	assert_eq(str(keys[0]), "core_table")
	assert_eq(str(keys[1]), "item_inventory")
	assert_eq(str(keys[2]), "reward_window")
	var sorted := keys.duplicate()
	sorted.sort()
	assert_eq(JSON.stringify(keys), JSON.stringify(sorted), "modules 稳定升序")
	var rw_mod: Dictionary = _find_module(snap.payload, "reward_window")
	assert_false(rw_mod.is_empty())
	assert_eq(int(rw_mod.get("schema_version", -1)), RewardWindowModule.SCHEMA_VERSION)
	var inv_mod: Dictionary = _find_module(snap.payload, "item_inventory")
	assert_false(inv_mod.is_empty())
	assert_eq(int(inv_mod.get("schema_version", -1)), ItemInventoryModule.SCHEMA_VERSION)
	var inv_pl: Dictionary = inv_mod.get("payload", {})
	assert_eq(int(inv_pl.get("seat", -1)), 0)
	assert_true(inv_pl.has("items"))
	assert_eq((inv_pl.get("items", []) as Array).size(), 0, "首窗 cold-start 零库存")
	var pl: Dictionary = rw_mod.get("payload", {})
	assert_eq(str(pl.get("phase", "")), "OPEN")
	assert_false(pl.has("seed"), "公开 payload 不得含 seed")
	assert_false(pl.has("match_seed"))
	assert_false(pl.has("_match_seed"))
	assert_false(pl.has("hand"))
	assert_false(pl.has("private_hand"))
	assert_true(pl.has("grace_deadline_at") or pl.has("window_id"))
	assert_false(str(pl.get("window_id", "")).is_empty())
	assert_eq(_count(_kinds(server), "ITEM_GRANTED"), 0)


func test_standard_loopback_snapshot_no_reward_window() -> void:
	var server := LocalLoopbackServer.new(_cfg_std(3), 0)
	assert_true(server.snapshot_registry.is_standard_only())
	assert_true(server.start())
	var snap: NetworkedEvent = _first_snapshot(server, 0)
	assert_not_null(snap)
	var keys: Array = _module_keys_from_snap(snap.payload)
	assert_eq(keys.size(), 1)
	assert_eq(str(keys[0]), "core_table")
	assert_true(_find_module(snap.payload, "reward_window").is_empty())
	assert_eq(_count(_kinds(server), "REWARD_WINDOW_OPENED"), 0)
	assert_eq(_count(_kinds(server), "ITEM_GRANTED"), 0)


func test_nbc_round_trip_restores_reward_window_public_fields() -> void:
	var server := LocalLoopbackServer.new(_cfg_tt(19), 0)
	assert_true(server.start())
	var rw: RewardWindowModule = server.mode_modules.reward_window
	assert_not_null(rw)
	assert_eq(String(rw.phase), "OPEN")
	# 开窗后新鲜 SNAP 含 OPEN 公共投影
	assert_true(server.publish_snapshot())
	var expect_phase := String(rw.phase)
	var expect_wid := str(rw.window_id)
	var expect_grace := str(rw.grace_deadline_at)
	var expect_closing = rw.closing_boundary_server_seq
	var expect_context = rw.context_boundary_server_seq
	var expect_exit = rw.window_exit

	var snap: NetworkedEvent = null
	for ne in server.event_journal(0):
		if ne is NetworkedEvent and (ne as NetworkedEvent).kind == "ROOM_SNAPSHOT":
			snap = ne as NetworkedEvent
	assert_not_null(snap)
	var room: String = str(server.get("_room_id"))
	var nbc := NetworkedBattleController.new(room, 0)
	nbc.configure_snapshot_registry_for_mode(str(GameSessionConfig.MODE_TRASH_TALK))
	assert_true(nbc.snapshot_registry.is_trash_talk_registry())
	assert_true(
		nbc.ingest_networked_event(snap),
		"ROOM_SNAPSHOT 须成功 restore err=%s" % nbc.last_snapshot_error()
	)
	assert_false(nbc.resync_required())
	var view: Dictionary = nbc.get_reward_window_view()
	assert_false(view.is_empty(), "须有 reward_window 公共投影")
	assert_eq(str(view.get("phase", "")), expect_phase)
	assert_eq(str(view.get("window_id", "")), expect_wid)
	assert_eq(str(view.get("grace_deadline_at", "")), expect_grace)
	assert_eq(view.get("closing_boundary_server_seq", null), expect_closing)
	assert_eq(view.get("context_boundary_server_seq", null), expect_context)
	assert_eq(view.get("window_exit", null), expect_exit)
	# 增量序号：next = snapshot + 1
	assert_eq(nbc.expected_next_server_seq(), int(snap.payload["next_server_seq"]))
	assert_eq(_count(_kinds(server), "ITEM_GRANTED"), 0)


func test_idle_first_snapshot_also_restores_zero_secrets() -> void:
	# start 首帧 SNAP 在 OPENED 前，phase=IDLE；仍须可原子 restore
	var server := LocalLoopbackServer.new(_cfg_tt(41), 0)
	assert_true(server.start())
	var snap: NetworkedEvent = _first_snapshot(server, 0)
	assert_not_null(snap)
	var pl: Dictionary = _find_module(snap.payload, "reward_window").get("payload", {})
	assert_eq(str(pl.get("phase", "")), "IDLE")
	var nbc := NetworkedBattleController.new(str(server.get("_room_id")), 0)
	nbc.configure_snapshot_registry_for_mode("TRASH_TALK")
	assert_true(
		nbc.ingest_networked_event(snap),
		"IDLE 首帧须 restore err=%s" % nbc.last_snapshot_error()
	)
	var view: Dictionary = nbc.get_reward_window_view()
	assert_eq(str(view.get("phase", "")), "IDLE")
	assert_false(view.has("seed"))
	assert_eq(_count(_kinds(server), "ITEM_GRANTED"), 0)


func test_bad_reward_window_payload_zero_apply_keeps_prev() -> void:
	var server := LocalLoopbackServer.new(_cfg_tt(23), 0)
	assert_true(server.start())
	var good: NetworkedEvent = _first_snapshot(server, 0)
	assert_not_null(good)
	var room: String = str(server.get("_room_id"))
	var nbc := NetworkedBattleController.new(room, 0)
	nbc.configure_snapshot_registry_for_mode(str(GameSessionConfig.MODE_TRASH_TALK))
	assert_true(nbc.ingest_networked_event(good))
	var prev_rw: Dictionary = nbc.get_reward_window_view()
	var prev_core: Dictionary = nbc.get_core_table_view()
	var prev_seq: int = nbc.current_seq()
	assert_false(prev_rw.is_empty())
	assert_false(prev_core.is_empty())

	# 构造坏 reward_window payload：缺 phase，schema 仍匹配
	var bad_payload: Dictionary = good.payload.duplicate(true)
	var mods: Array = []
	for m in bad_payload["modules"]:
		var md: Dictionary = (m as Dictionary).duplicate(true)
		if str(md.get("module_key", "")) == "reward_window":
			var pl: Dictionary = (md["payload"] as Dictionary).duplicate(true)
			pl.erase("phase")
			md["payload"] = pl
		mods.append(md)
	bad_payload["modules"] = mods
	var bad_seq: int = prev_seq + 5
	bad_payload["snapshot_server_seq"] = bad_seq
	bad_payload["next_server_seq"] = bad_seq + 1
	var vh: String = ProtocolViewCodec.compute_view_hash(bad_payload)
	var bad_ne: NetworkedEvent = NetworkedEvent.make(
		"ROOM_SNAPSHOT", bad_seq, room, bad_payload, vh
	)
	assert_not_null(bad_ne)
	assert_false(nbc.ingest_networked_event(bad_ne), "坏 reward_window 须整份拒绝")
	assert_eq(nbc.current_seq(), prev_seq, "零应用：seq 不变")
	assert_eq(
		JSON.stringify(nbc.get_reward_window_view()),
		JSON.stringify(prev_rw),
		"零应用：reward_window 投影不变"
	)
	assert_eq(
		JSON.stringify(nbc.get_core_table_view()),
		JSON.stringify(prev_core),
		"零应用：core_table 投影不变"
	)
	assert_false(nbc.last_snapshot_error().is_empty())


func test_headless_session_resync_restores_same_window_deadline() -> void:
	# 真实 HeadlessRoomSession → LocalLoopbackServer；resync 交付同一 phase/deadline
	var session := HeadlessRoomSession.new()
	session.set_seed_override_for_test(31)
	var claims := {
		"room_id": "room-rw-resync",
		"round_kind": "EAST",
		"game_mode": "TRASH_TALK",
		"participants": ["HUMAN", "AI", "AI", "AI"],
		"session_id": "sess-rw-resync",
		"seat": 0,
		"exp": 2_000_000_000,
	}
	assert_true(session.bootstrap_from_claims(claims))
	var j0: Dictionary = session.join(0, "sess-rw-resync", 1, 1)
	assert_true(bool(j0.get("ok", false)), "join seat0")
	var ready: Dictionary = session.ready(0, "sess-rw-resync")
	assert_true(bool(ready.get("ok", false)) or session.is_started())
	if not session.is_started():
		var start_code: String = session.try_start_if_ready()
		assert_true(session.is_started(), "须 start: %s" % start_code)
	var server: LocalLoopbackServer = session.server
	assert_not_null(server)
	assert_true(server.snapshot_registry.is_trash_talk_registry())
	var rw: RewardWindowModule = server.mode_modules.reward_window
	assert_not_null(rw)
	var expect_phase := String(rw.phase)
	var expect_wid := str(rw.window_id)
	var expect_grace := str(rw.grace_deadline_at)
	var expect_g_ms: int = int(rw.get("_grace_deadline_ms"))
	var seq_before: int = server.current_server_seq()

	var prep: Dictionary = session.prepare_reconnect_delivery(0)
	assert_true(bool(prep.get("ok", false)), "resync 须成功: %s" % str(prep))
	var events: Array = session.events_since(0, seq_before)
	assert_gt(events.size(), 0, "resync 须有新事件")
	var first: NetworkedEvent = events[0] as NetworkedEvent
	assert_not_null(first)
	assert_eq(first.kind, "ROOM_SNAPSHOT")
	var keys: Array = _module_keys_from_snap(first.payload)
	assert_eq(str(keys[0]), "core_table")
	assert_eq(str(keys[1]), "item_inventory")
	assert_eq(str(keys[2]), "reward_window")
	var rw_mod: Dictionary = _find_module(first.payload, "reward_window")
	var pl: Dictionary = rw_mod.get("payload", {})
	assert_eq(str(pl.get("phase", "")), expect_phase)
	assert_eq(str(pl.get("window_id", "")), expect_wid)
	assert_eq(str(pl.get("grace_deadline_at", "")), expect_grace)
	assert_eq(int(pl.get("grace_deadline_ms", -1)), expect_g_ms)

	var nbc := NetworkedBattleController.new(str(claims["room_id"]), 0)
	nbc.configure_snapshot_registry_for_mode("TRASH_TALK")
	assert_true(nbc.ingest_networked_event(first))
	var view: Dictionary = nbc.get_reward_window_view()
	assert_eq(str(view.get("phase", "")), expect_phase)
	assert_eq(str(view.get("window_id", "")), expect_wid)
	assert_eq(str(view.get("grace_deadline_at", "")), expect_grace)
	assert_eq(int(view.get("grace_deadline_ms", -1)), expect_g_ms)
	# 增量连续：期望下一条 = next_server_seq
	assert_eq(nbc.expected_next_server_seq(), int(first.payload["next_server_seq"]))
	for ne in events:
		if ne is NetworkedEvent and (ne as NetworkedEvent).kind != "ROOM_SNAPSHOT":
			assert_gte(
				int((ne as NetworkedEvent).server_seq),
				int(first.payload["next_server_seq"]),
				"增量不得回放 snapshot 前历史"
			)
	assert_eq(_count(_kinds(server), "ITEM_GRANTED"), 0)


func test_provider_serialize_rejects_seed_leak() -> void:
	var p := RewardWindowSnapshotProvider.new()
	var fake := RewardWindowModule.new()
	# 正常 open 后 payload 不应含 seed（seed 仅服务端 capture_state）
	var open_r: Dictionary = fake.open({
		"seed": 99,
		"hand_seq": 0,
		"window_index": 0,
		"rule_version": TrashTalkRuleCatalog.rule_version(),
		"room_id": "r-provider",
		"character_ids": ["lin_yeche", "qiu_jue", "bai_touli", "hua_ling"],
		"language": "zh",
		"participants": ["HUMAN", "AI", "AI", "AI"],
	})
	assert_true(bool(open_r.get("ok", false)), "open 须成功: %s" % str(open_r))
	var good: Variant = p.serialize({"reward_window": fake}, 0)
	assert_true(typeof(good) == TYPE_DICTIONARY)
	assert_false((good as Dictionary).has("seed"))
	assert_false((good as Dictionary).has("match_seed"))
	assert_false((good as Dictionary).has("_match_seed"))
	# can_restore 坏 schema
	assert_false(p.can_restore({"phase": "NOPE"}, 0))
	assert_false(p.can_restore(null, 0))
	# 权威 ctx 缺失 → serialize null
	assert_eq(p.serialize({}, 0), null)
	assert_eq(p.serialize({"reward_window": null}, 1), null)



# ---- Round 9：AA 后 SNAP 含动作后 RW 投影；step_ai 计入弃牌 ----

func _cmd9(n: int) -> String:
	return "550e8400-e29b-41d4-a716-%012d" % n


func _last_aa_and_snap(server: LocalLoopbackServer, seat: int = 0) -> Dictionary:
	var last_aa: NetworkedEvent = null
	var last_snap: NetworkedEvent = null
	for ne in server.event_journal(seat):
		if not (ne is NetworkedEvent):
			continue
		var e: NetworkedEvent = ne as NetworkedEvent
		if e.kind == "ACTION_APPLIED":
			last_aa = e
			last_snap = null
		elif e.kind == "ROOM_SNAPSHOT" and last_aa != null and last_snap == null:
			if int(e.server_seq) == int(last_aa.server_seq) + 1:
				last_snap = e
	return {"aa": last_aa, "snap": last_snap}


func _rw_payload_from_snap(snap: NetworkedEvent) -> Dictionary:
	if snap == null:
		return {}
	return _find_module(snap.payload, "reward_window").get("payload", {})


## 全 HUMAN：按 BC active window PASS/DISCARD 一次；返回是否推进了弃牌。
func _step_one_human_action(server: LocalLoopbackServer, n: int) -> Dictionary:
	var bc: BattleController = server.get("_bc") as BattleController
	for s in range(4):
		bc.decision_context_for_seat(s)
	var win = bc.get("_active_window")
	if win == null or not (win is DecisionWindow):
		return {"ok": false, "discarded": false, "n": n}
	var dw: DecisionWindow = win as DecisionWindow
	if dw.kind == DecisionWindow.KIND_CLAIM or dw.kind == DecisionWindow.KIND_ROB_KAN:
		var target_seat := -1
		for seat_i in dw.seats():
			var si: int = int(seat_i)
			if not dw.has_responded(si):
				target_seat = si
				break
		if target_seat < 0:
			return {"ok": false, "discarded": false, "n": n}
		var ctx: DecisionContext = dw.context_for_seat(target_seat)
		var act: Action = Action.make_pass(
			target_seat, str(server.get("_room_id")), _cmd9(n),
			str(ctx.decision_id), int(ctx.hand_seq), n
		)
		var cr: CommandResult = server.submit_action(act)
		return {
			"ok": cr.status == "ACCEPTED",
			"discarded": false,
			"n": n + 1,
			"code": cr.error_code,
		}
	if dw.kind == DecisionWindow.KIND_TURN:
		var actor: int = int(dw.subject_seat)
		var tctx: DecisionContext = dw.context_for_seat(actor)
		var iid := -1
		for o in tctx.allowed_actions:
			if typeof(o) == TYPE_DICTIONARY and str(o.get("kind", "")) == "DISCARD":
				var opts: Array = o.get("payload_options", [])
				if not opts.is_empty():
					iid = int(opts[0]["tile_instance_id"])
				break
		if iid < 0:
			return {"ok": false, "discarded": false, "n": n}
		var dact: Action = Action.discard(
			actor, iid, str(server.get("_room_id")), _cmd9(n),
			str(tctx.decision_id), int(tctx.hand_seq), n
		)
		var dcr: CommandResult = server.submit_action(dact)
		return {
			"ok": dcr.status == "ACCEPTED",
			"discarded": dcr.status == "ACCEPTED",
			"n": n + 1,
			"code": dcr.error_code,
		}
	return {"ok": false, "discarded": false, "n": n}


func test_action_snapshot_reward_window_matches_post_action_state() -> void:
	var cfg := GameSessionConfig.create_validated(
		GameSessionConfig.ROOM_PUBLIC_CASUAL, GameSessionConfig.ROUND_EAST,
		GameSessionConfig.MODE_TRASH_TALK,
		[&"HUMAN", &"HUMAN", &"HUMAN", &"HUMAN"],
		CHARS, 17, "rw-snap-post", "rv-r9"
	)
	var server := LocalLoopbackServer.new(cfg, 0)
	assert_true(server.start())
	var rw: RewardWindowModule = server.mode_modules.reward_window
	assert_not_null(rw)
	assert_eq(String(rw.phase), "OPEN")
	var open_snap: NetworkedEvent = null
	for ne in server.event_journal(0):
		if ne is NetworkedEvent and (ne as NetworkedEvent).kind == "ROOM_SNAPSHOT":
			open_snap = ne as NetworkedEvent
	assert_eq(str(_rw_payload_from_snap(open_snap).get("phase", "")), "OPEN")

	var n := 100
	var discards_done := 0
	var guard := 0
	while discards_done < 3 and guard < 40:
		guard += 1
		var before: int = rw.discard_count
		var step: Dictionary = _step_one_human_action(server, n)
		n = int(step["n"])
		assert_true(bool(step["ok"]), "动作须 ACCEPTED code=%s" % str(step.get("code", "")))
		if not bool(step["discarded"]):
			continue
		discards_done += 1
		assert_eq(rw.discard_count, before + 1)
		var pair: Dictionary = _last_aa_and_snap(server, 0)
		var aa: NetworkedEvent = pair["aa"]
		var snap: NetworkedEvent = pair["snap"]
		assert_not_null(aa)
		assert_not_null(snap)
		assert_eq(aa.view_hash, snap.view_hash, "AA.view_hash 须等于紧随 SNAP")
		assert_eq(snap.view_hash, ProtocolViewCodec.compute_view_hash(snap.payload))
		var pl: Dictionary = _rw_payload_from_snap(snap)
		assert_eq(int(pl.get("discard_count", -1)), rw.discard_count)
		assert_eq(str(pl.get("phase", "")), String(rw.phase))
		var found_aa := false
		for ev in pl.get("public_events", []):
			if typeof(ev) != TYPE_DICTIONARY:
				continue
			if str(ev.get("kind", "")) == "ACTION_APPLIED" \
					and int(ev.get("server_seq", -1)) == int(aa.server_seq):
				found_aa = true
				break
		assert_true(found_aa, "public_events 须含当前 ACTION_APPLIED")
	assert_eq(discards_done, 3)
	assert_eq(_count(_kinds(server), "ITEM_GRANTED"), 0)


func test_24th_discard_snapshot_already_closing() -> void:
	var cfg := GameSessionConfig.create_validated(
		GameSessionConfig.ROOM_PUBLIC_CASUAL, GameSessionConfig.ROUND_EAST,
		GameSessionConfig.MODE_TRASH_TALK,
		[&"HUMAN", &"HUMAN", &"HUMAN", &"HUMAN"],
		CHARS, 29, "rw-snap-24", "rv-r9"
	)
	var server := LocalLoopbackServer.new(cfg, 0)
	assert_true(server.start())
	var rw: RewardWindowModule = server.mode_modules.reward_window
	var n := 2000
	var guard := 0
	while rw.discard_count < 24 and guard < 120:
		guard += 1
		if bool(server.get("_bc").get("_settled")):
			break
		var step: Dictionary = _step_one_human_action(server, n)
		n = int(step["n"])
		assert_true(bool(step["ok"]), "驱动失败 code=%s dc=%d" % [str(step.get("code", "")), rw.discard_count])
	assert_eq(rw.discard_count, 24)
	assert_eq(String(rw.phase), "CLOSING")
	var pair: Dictionary = _last_aa_and_snap(server, 0)
	var aa: NetworkedEvent = pair["aa"]
	var snap: NetworkedEvent = pair["snap"]
	assert_not_null(aa)
	assert_not_null(snap)
	assert_eq(str(aa.payload.get("action_kind", "")), "DISCARD")
	var pl: Dictionary = _rw_payload_from_snap(snap)
	assert_eq(str(pl.get("phase", "")), "CLOSING", "第 24 弃 SNAP 须已是 CLOSING")
	assert_eq(int(pl.get("discard_count", -1)), 24)
	assert_eq(int(pl.get("closing_boundary_server_seq", -1)), int(aa.server_seq))
	var kinds: Array = _kinds(server)
	var idx_aa := -1
	var idx_close := -1
	for i in range(kinds.size()):
		if String(kinds[i]) == "ACTION_APPLIED" and i > idx_aa:
			# 找到触发 CLOSING 的 AA：其后紧邻 SNAP 后有 CLOSING
			idx_aa = i
	idx_close = kinds.find("REWARD_WINDOW_CLOSING")
	assert_gt(idx_close, -1)
	# CLOSING 必须在某次 AA 之后
	assert_gt(idx_close, 0)
	assert_eq(_count(kinds, "REWARD_WINDOW_CLOSING"), 1)
	assert_eq(_count(kinds, "ITEM_GRANTED"), 0)


func test_step_ai_once_counts_discard_and_syncs_snapshot() -> void:
	# 真实 HeadlessRoomSession：lease 超时 AI 接管后 step_ai_once 计入弃牌
	var session := HeadlessRoomSession.new()
	session.set_seed_override_for_test(37)
	var claims := {
		"room_id": "room-ai-rw",
		"round_kind": "EAST",
		"game_mode": "TRASH_TALK",
		"participants": ["HUMAN", "AI", "AI", "AI"],
		"session_id": "sess-ai-rw",
		"seat": 0,
		"exp": 2_000_000_000,
	}
	assert_true(session.bootstrap_from_claims(claims))
	assert_true(bool(session.join(0, "sess-ai-rw", 1, 1).get("ok", false)))
	session.ready(0, "sess-ai-rw")
	if not session.is_started():
		session.try_start_if_ready()
	assert_true(session.is_started())
	var server: LocalLoopbackServer = session.server
	var rw: RewardWindowModule = server.mode_modules.reward_window
	assert_not_null(rw)
	var dc0: int = rw.discard_count
	# 与 #241 测试一致：session 席位字典 + server 双写 AI 接管
	session._seats[0]["ai_control"] = true
	session._seats[0]["lease_deadline_ms"] = -1
	server.set_seat_ai_control(0, true)
	assert_true(session.has_ai_controlled_seat())
	assert_true(server.is_seat_ai_controlled(0))
	assert_false(server.is_effectively_human(0))
	var advanced_discard := false
	for _i in range(100):
		var r: Dictionary = session.step_ai_once()
		assert_true(bool(r.get("ok", false)), "step_ai 须 ok: %s" % str(r))
		if rw.discard_count > dc0:
			advanced_discard = true
			break
		if bool(r.get("settled", false)):
			break
	assert_true(advanced_discard, "AI 接管后至少一次真实弃牌计入 discard_count")
	assert_eq(rw.discard_count, dc0 + 1)
	var pair: Dictionary = _last_aa_and_snap(server, 0)
	var aa: NetworkedEvent = pair["aa"]
	var snap: NetworkedEvent = pair["snap"]
	assert_not_null(aa)
	assert_not_null(snap)
	assert_eq(str(aa.payload.get("action_kind", "")), "DISCARD")
	var pl: Dictionary = _rw_payload_from_snap(snap)
	assert_eq(int(pl.get("discard_count", -1)), rw.discard_count,
		"step_ai SNAP 投影 discard_count 须同步")
	assert_eq(aa.view_hash, snap.view_hash)
	var dc1: int = rw.discard_count
	# 再步进：不得对同一 fingerprint 双计数
	for _j in range(5):
		session.step_ai_once()
	assert_gte(rw.discard_count, dc1)
	assert_eq(_count(_kinds(server), "ITEM_GRANTED"), 0)
	# public_events 中同一 server_seq 的 ACTION_APPLIED 至多一条
	var seen_seq: Dictionary = {}
	for ev in rw.get("_public_events") as Array:
		if typeof(ev) != TYPE_DICTIONARY:
			continue
		if str(ev.get("kind", "")) != "ACTION_APPLIED":
			continue
		var sq: int = int(ev.get("server_seq", -1))
		assert_false(seen_seq.has(sq), "同 seq 不得双 append public ACTION_APPLIED")
		seen_seq[sq] = true


func test_action_publish_fail_rolls_back_rw_and_flags() -> void:
	var server := LocalLoopbackServer.new(_cfg_tt(53), 0)
	assert_true(server.start())
	var rw: RewardWindowModule = server.mode_modules.reward_window
	var frozen_dc: int = rw.discard_count
	var frozen_phase := String(rw.phase)
	var frozen_seq: int = server.current_server_seq()
	var frozen_pe: int = rw.public_events_count()
	var frozen_hs: bool = bool(server.get("_hand_settled_emitted"))
	server.fail_next_action_publish_for_test()
	var step: Dictionary = _step_one_human_action(server, 901)
	assert_false(bool(step["ok"]), "publish fail 须拒绝")
	assert_eq(rw.discard_count, frozen_dc, "失败须回滚 discard_count")
	assert_eq(String(rw.phase), frozen_phase)
	assert_eq(server.current_server_seq(), frozen_seq)
	assert_eq(rw.public_events_count(), frozen_pe, "失败须回滚 public_events")
	assert_eq(bool(server.get("_hand_settled_emitted")), frozen_hs)
	assert_eq(_count(_kinds(server), "ITEM_GRANTED"), 0)
