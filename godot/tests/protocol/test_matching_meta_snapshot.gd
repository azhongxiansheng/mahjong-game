extends GutTest

# #374：matching_meta 独立必需模块；STANDARD/TRASH_TALK 真实 registry + NBC 生产链。


func test_standard_and_trash_talk_register_matching_meta_required() -> void:
	var std := SnapshotModuleRegistry.make_standard()
	assert_true(std.is_standard_only())
	assert_true(std.has_module(MatchingMetaSnapshotProvider.MODULE_KEY))
	var p_std: SnapshotModuleProvider = std.provider_for(MatchingMetaSnapshotProvider.MODULE_KEY)
	assert_not_null(p_std)
	assert_true(p_std.is_required(), "matching_meta 在 STANDARD 必须 required")
	var tt := SnapshotModuleRegistry.make_trash_talk()
	assert_true(tt.is_trash_talk_registry())
	var p_tt: SnapshotModuleProvider = tt.provider_for(MatchingMetaSnapshotProvider.MODULE_KEY)
	assert_not_null(p_tt)
	assert_true(p_tt.is_required(), "matching_meta 在 TRASH_TALK 必须 required")


func test_matching_meta_round_trip_and_fail_closed() -> void:
	var prov := MatchingMetaSnapshotProvider.new()
	assert_true(prov.is_required())
	var ctx := {
		"character_ids": ["lin_yeche", "qiu_jue", "an_cheng", "bai_touli"],
		"participants": ["HUMAN", "AI", "AI", "AI"],
	}
	var payload: Variant = prov.serialize(ctx, 0)
	assert_true(typeof(payload) == TYPE_DICTIONARY)
	assert_true(prov.can_restore(payload, 0))
	var sink := _Sink.new()
	assert_true(prov.restore(payload, 0, sink))
	assert_true(sink.applied.has(MatchingMetaSnapshotProvider.MODULE_KEY))
	var bad := (payload as Dictionary).duplicate(true)
	bad["character_ids"] = ["lin_yeche", "qiu_jue", "an_cheng"]
	assert_false(prov.can_restore(bad, 0))
	assert_null(prov.serialize({
		"character_ids": ["lin_yeche", "qiu_jue", "an_cheng"],
		"participants": ["HUMAN", "AI", "AI", "AI"],
	}, 0), "长度错误序列化失败")
	var unk := (payload as Dictionary).duplicate(true)
	unk["character_ids"] = ["nope", "qiu_jue", "an_cheng", "bai_touli"]
	assert_false(prov.can_restore(unk, 0))
	assert_null(prov.serialize({
		"character_ids": ["nope", "qiu_jue", "an_cheng", "bai_touli"],
		"participants": ["HUMAN", "AI", "AI", "AI"],
	}, 0), "未知角色序列化失败")
	var extra := (payload as Dictionary).duplicate(true)
	extra["seed"] = 1
	assert_false(prov.can_restore(extra, 0))
	assert_null(prov.serialize({"state": null}, 0), "ctx 缺 roster 序列化失败")


func test_registry_required_missing_matching_meta_rejects_and_preserves_prior() -> void:
	var reg := SnapshotModuleRegistry.make_standard()
	var sink := _Sink.new()
	# 先成功提交完整 modules（含 matching_meta）
	var ok_mods := [
		_core_mod(0),
		MatchingMetaSnapshotProvider.fixture_module(
			["hua_ling", "lin_yeche", "qiu_jue", "an_cheng"]
		),
	]
	var r0: Dictionary = reg.restore_modules(ok_mods, 0, sink)
	assert_true(bool(r0.get("ok", false)), str(r0))
	assert_true(sink.applied.has(MatchingMetaSnapshotProvider.MODULE_KEY))
	var frozen: Dictionary = sink.capture_module_restore_state()
	# 缺 matching_meta：整份拒绝，保留先前状态
	var missing := [{"module_key": "core_table", "schema_version": 1, "payload": _core_mod(0)["payload"]}]
	var r1: Dictionary = reg.restore_modules(missing, 0, sink)
	assert_false(bool(r1.get("ok", false)))
	assert_eq(str(r1.get("code", "")), SnapshotModuleRegistry.ERR_REQUIRED_MISSING)
	assert_eq(JSON.stringify(sink.applied), JSON.stringify(frozen), "缺失 required 不得清掉先前 roster")
	# 非法 matching_meta：原子拒绝
	var bad_meta := MatchingMetaSnapshotProvider.fixture_module(["nope", "a", "b", "c"])
	var bad_mods := [_core_mod(0), bad_meta]
	var r2: Dictionary = reg.restore_modules(bad_mods, 0, sink)
	assert_false(bool(r2.get("ok", false)))
	assert_eq(JSON.stringify(sink.applied), JSON.stringify(frozen))


func test_nbc_missing_matching_meta_keeps_prior_roster_standard_and_trash_talk() -> void:
	for mode in ["STANDARD", "TRASH_TALK"]:
		var room := "room-meta-%s" % mode
		var chars := ["lin_yeche", "qiu_jue", "an_cheng", "bai_touli"]
		var s := HeadlessRoomSession.new()
		s.set_seed_override_for_test(3)
		assert_true(s.bootstrap_from_claims({
			"room_id": room,
			"seat": 0,
			"session_id": "sess-0",
			"round_kind": "EAST",
			"game_mode": mode,
			"participants": ["HUMAN", "AI", "AI", "AI"],
			"character_ids": chars,
			"expires_at_unix": 9999999999,
		}))
		assert_true(bool(s.join(0, "sess-0")["ok"]))
		assert_true(bool(s.ready(0, "sess-0")["ok"]))
		assert_true(s.is_started())
		var nbc := NetworkedBattleController.new(room, 0)
		nbc.configure_snapshot_registry_for_mode(mode)
		var journal: Array = s.event_journal(0)
		var good_ne: NetworkedEvent = null
		for e in journal:
			if e is NetworkedEvent and (e as NetworkedEvent).kind == "ROOM_SNAPSHOT":
				good_ne = e as NetworkedEvent
				break
		assert_not_null(good_ne, "须有 ROOM_SNAPSHOT mode=%s" % mode)
		assert_true(nbc.ingest_networked_event(good_ne),
			"%s %s" % [mode, nbc.last_snapshot_error()])
		var meta0: Dictionary = nbc.get_matching_meta_view()
		assert_eq(str(meta0.get("character_ids", [])[0]), "lin_yeche")
		# 从真实 SNAP 剥掉 matching_meta，保留其余合法模块 → 结构仍过 wire，restore 因 required 拒绝
		var stripped_mods: Array = []
		for m in good_ne.payload.get("modules", []):
			if str(m.get("module_key", "")) == MatchingMetaSnapshotProvider.MODULE_KEY:
				continue
			stripped_mods.append((m as Dictionary).duplicate(true))
		assert_lt(stripped_mods.size(), (good_ne.payload.get("modules", []) as Array).size())
		var bad_payload := {
			"snapshot_server_seq": int(good_ne.server_seq) + 10,
			"next_server_seq": int(good_ne.server_seq) + 11,
			"seat_view": 0,
			"modules": stripped_mods,
		}
		var ne_bad: NetworkedEvent = _room_snapshot(room, int(good_ne.server_seq) + 10, bad_payload)
		assert_not_null(ne_bad, "剥离 matching_meta 后结构仍须可过 wire 校验 mode=%s" % mode)
		assert_false(nbc.ingest_networked_event(ne_bad), "缺 matching_meta 必须拒绝 mode=%s" % mode)
		var meta1: Dictionary = nbc.get_matching_meta_view()
		assert_eq(str(meta1.get("character_ids", [])[0]), "lin_yeche",
			"拒绝后不得清空先前 roster mode=%s" % mode)


func test_four_seats_matching_meta_payload_identical_from_authority() -> void:
	var chars := ["hua_ling", "lin_yeche", "qiu_jue", "an_cheng"]
	var s := HeadlessRoomSession.new()
	s.set_seed_override_for_test(11)
	assert_true(s.bootstrap_from_claims({
		"room_id": "room-4seat-meta",
		"seat": 0,
		"session_id": "sess-0",
		"round_kind": "EAST",
		"game_mode": "STANDARD",
		"participants": ["HUMAN", "AI", "AI", "AI"],
		"character_ids": chars,
		"expires_at_unix": 9999999999,
	}))
	assert_true(bool(s.join(0, "h0")["ok"]))
	assert_true(bool(s.ready(0, "h0")["ok"]))
	assert_true(s.is_started())
	var metas: Array = []
	for seat in range(4):
		var snap: Dictionary = s.server._build_room_snapshot_payload(seat, 1)
		assert_false(snap.is_empty(), "seat %d snap" % seat)
		var found: Dictionary = {}
		for m in snap.get("modules", []):
			if str(m.get("module_key", "")) == MatchingMetaSnapshotProvider.MODULE_KEY:
				found = m.get("payload", {})
		assert_false(found.is_empty(), "seat %d 须有 matching_meta" % seat)
		metas.append(JSON.stringify(found))
		for i in range(4):
			assert_eq(str(found.get("character_ids", [])[i]), chars[i],
				"seat %d roster[%d]" % [seat, i])
	for seat in range(1, 4):
		assert_eq(metas[seat], metas[0], "四席 matching_meta payload 必须字节级一致")


func test_headless_snapshot_includes_matching_meta_not_core_table_keys() -> void:
	var s := HeadlessRoomSession.new()
	s.set_seed_override_for_test(11)
	var claims := {
		"room_id": "room-meta",
		"seat": 0,
		"session_id": "sess-0",
		"round_kind": "EAST",
		"game_mode": "STANDARD",
		"participants": ["HUMAN", "AI", "AI", "AI"],
		"character_ids": ["hua_ling", "lin_yeche", "qiu_jue", "an_cheng"],
		"expires_at_unix": 9999999999,
	}
	assert_true(s.bootstrap_from_claims(claims))
	assert_true(bool(s.join(0, "h0")["ok"]))
	assert_true(bool(s.ready(0, "h0")["ok"]))
	assert_true(s.is_started())
	assert_true(s.server.snapshot_registry.is_standard_only())
	var snap: Dictionary = s.server._build_room_snapshot_payload(0, 1)
	assert_false(snap.is_empty())
	var keys: Array = []
	var meta_payload: Dictionary = {}
	for m in snap.get("modules", []):
		keys.append(str(m.get("module_key", "")))
		if str(m.get("module_key", "")) == MatchingMetaSnapshotProvider.MODULE_KEY:
			meta_payload = m.get("payload", {})
	assert_true(MatchingMetaSnapshotProvider.MODULE_KEY in keys)
	assert_true(CoreTableSnapshotProvider.MODULE_KEY in keys)
	assert_eq(str(meta_payload.get("character_ids", [])[0]), "hua_ling")
	for m in snap.get("modules", []):
		if str(m.get("module_key", "")) == CoreTableSnapshotProvider.MODULE_KEY:
			var core: Dictionary = m.get("payload", {})
			assert_false(core.has("character_ids"), "core_table 不得含 character_ids")


func test_mode_isolation_standard_zero_ability_trash_talk_uses_roster() -> void:
	var chars := ["lin_yeche", "qiu_jue", "an_cheng", "bai_touli"]
	var std_cfg := GameSessionConfig.create_validated(
		GameSessionConfig.ROOM_PUBLIC_CASUAL,
		GameSessionConfig.ROUND_EAST,
		GameSessionConfig.MODE_STANDARD,
		[&"HUMAN", &"AI", &"AI", &"AI"],
		chars,
		1,
		"room-std",
		"riichi-v1"
	)
	assert_not_null(std_cfg)
	var std_bundle := ModeModuleBundle.from_config(std_cfg)
	assert_not_null(std_bundle)
	assert_true(std_bundle.is_standard())
	assert_eq(std_bundle.character_ability_slots.size(), 0)
	assert_null(std_bundle.item_inventory)

	var tt_cfg := GameSessionConfig.create_validated(
		GameSessionConfig.ROOM_PUBLIC_CASUAL,
		GameSessionConfig.ROUND_EAST,
		GameSessionConfig.MODE_TRASH_TALK,
		[&"HUMAN", &"AI", &"AI", &"AI"],
		chars,
		1,
		"room-tt",
		"riichi-v1"
	)
	assert_not_null(tt_cfg)
	var tt_bundle := ModeModuleBundle.from_config(tt_cfg)
	assert_not_null(tt_bundle)
	assert_true(tt_bundle.is_trash_talk())
	assert_eq(tt_bundle.character_ability_slots.size(), 4)
	for i in range(4):
		var slot: CharacterAbilitySlot = tt_bundle.character_ability_slots[i]
		assert_eq(String(slot.character_id), chars[i])
		assert_false(slot.armed)


func test_worker_bootstrap_standard_zero_slot_trash_talk_four_slots() -> void:
	var chars := ["lin_yeche", "qiu_jue", "an_cheng", "bai_touli"]
	for mode in ["STANDARD", "TRASH_TALK"]:
		var s := HeadlessRoomSession.new()
		s.set_seed_override_for_test(5)
		assert_true(s.bootstrap_from_claims({
			"room_id": "room-mode-%s" % mode,
			"seat": 0,
			"session_id": "sess-0",
			"round_kind": "EAST",
			"game_mode": mode,
			"participants": ["HUMAN", "AI", "AI", "AI"],
			"character_ids": chars,
			"expires_at_unix": 9999999999,
		}))
		assert_not_null(s.config)
		assert_not_null(s.server)
		assert_not_null(s.server.mode_modules)
		if mode == "STANDARD":
			assert_true(s.server.mode_modules.is_standard())
			assert_eq(s.server.mode_modules.character_ability_slots.size(), 0)
			assert_null(s.server.mode_modules.item_inventory)
		else:
			assert_true(s.server.mode_modules.is_trash_talk())
			assert_eq(s.server.mode_modules.character_ability_slots.size(), 4)
			assert_not_null(s.server.mode_modules.item_inventory)
			for i in range(4):
				assert_eq(String(s.server.mode_modules.character_ability_slots[i].character_id), chars[i])


func test_reconnect_snapshot_restores_same_roster() -> void:
	var chars := ["qiu_jue", "lin_yeche", "yuan_xi", "ji_shu"]
	var s := HeadlessRoomSession.new()
	s.set_seed_override_for_test(7)
	assert_true(s.bootstrap_from_claims({
		"room_id": "room-rc-meta",
		"seat": 0,
		"session_id": "human-0",
		"round_kind": "EAST",
		"game_mode": "STANDARD",
		"participants": ["HUMAN", "AI", "AI", "AI"],
		"character_ids": chars,
		"expires_at_unix": 9999999999,
	}))
	assert_true(bool(s.join(0, "human-0")["ok"]))
	assert_true(bool(s.ready(0, "human-0")["ok"]))
	assert_true(s.is_started())
	var frozen: Array = s.character_ids.duplicate()
	# 重复 JOIN/READY 不改身份
	assert_true(bool(s.join(0, "human-0", 2, 1)["ok"]))
	assert_true(bool(s.ready(0, "human-0")["ok"]))
	for i in range(4):
		assert_eq(String(s.character_ids[i]), String(frozen[i]))
	# resync snapshot 含相同 matching_meta
	var prep: Dictionary = s.prepare_reconnect_delivery(0)
	assert_true(bool(prep.get("ok", false)), str(prep))
	var events: Array = s.events_since(0, 0)
	var last_snap: NetworkedEvent = null
	for e in events:
		if e is NetworkedEvent and (e as NetworkedEvent).kind == "ROOM_SNAPSHOT":
			last_snap = e
	assert_not_null(last_snap)
	var meta: Dictionary = {}
	for m in last_snap.payload.get("modules", []):
		if str(m.get("module_key", "")) == MatchingMetaSnapshotProvider.MODULE_KEY:
			meta = m.get("payload", {})
	assert_false(meta.is_empty())
	for i in range(4):
		assert_eq(str(meta.get("character_ids", [])[i]), String(frozen[i]))


## #374 round-3：真实公共牌桌生产链（禁止测试内直接 bind_character_ids 自证）。
## PublicCasualNetworkSession.bind_playable_table → bind_public_casual_session
## → committed matching_meta → _bind_public_matching_meta_characters → presentation seam。
func test_public_production_chain_binds_roster_via_session_for_both_modes() -> void:
	var chars := ["lin_yeche", "qiu_jue", "an_cheng", "bai_touli"]
	for mode in ["STANDARD", "TRASH_TALK"]:
		var room := "room-prod-chain-%s" % mode
		var s := HeadlessRoomSession.new()
		s.set_seed_override_for_test(9)
		assert_true(s.bootstrap_from_claims({
			"room_id": room,
			"seat": 0,
			"session_id": "sess-0",
			"round_kind": "EAST",
			"game_mode": mode,
			"participants": ["HUMAN", "AI", "AI", "AI"],
			"character_ids": chars,
			"expires_at_unix": 9999999999,
		}))
		assert_true(bool(s.join(0, "sess-0")["ok"]))
		assert_true(bool(s.ready(0, "sess-0")["ok"]))
		assert_true(s.is_started())
		# 权威 Worker 侧模式隔离
		if mode == "STANDARD":
			assert_eq(s.server.mode_modules.character_ability_slots.size(), 0)
			assert_null(s.server.mode_modules.item_inventory)
		else:
			assert_eq(s.server.mode_modules.character_ability_slots.size(), 4)
			assert_not_null(s.server.mode_modules.item_inventory)
			for i in range(4):
				assert_eq(
					String(s.server.mode_modules.character_ability_slots[i].character_id),
					chars[i]
				)

		var nbc := NetworkedBattleController.new(room, 0)
		nbc.configure_snapshot_registry_for_mode(mode)
		var got_snap := false
		for e in s.event_journal(0):
			if e is NetworkedEvent and (e as NetworkedEvent).kind == "ROOM_SNAPSHOT":
				assert_true(
					nbc.ingest_networked_event(e as NetworkedEvent),
					"%s %s" % [mode, nbc.last_snapshot_error()]
				)
				got_snap = true
				break
		assert_true(got_snap, "须有 committed ROOM_SNAPSHOT mode=%s" % mode)
		var meta: Dictionary = nbc.get_matching_meta_view()
		assert_eq((meta.get("character_ids", []) as Array).size(), 4)

		# 生产入口：session.bind_playable_table → table.bind_public_casual_session
		var table := PlayableTable.new()
		add_child_autofree(table)
		var sess := PublicCasualNetworkSession.new()
		add_child_autofree(sess)
		sess.room_id = room
		sess.seat = 0
		sess.game_mode = mode
		sess.nbc = nbc
		# 禁止测试直接调用 bind_character_ids / _bind_public_matching_meta_characters
		sess.bind_playable_table(table)
		await get_tree().process_frame
		# bootstrap 路径已 sync；再显式推进一次生产 sync 环
		if table.has_method("_sync_reward_feedback_if_advanced"):
			table._sync_reward_feedback_if_advanced()
		await get_tree().process_frame

		var bound: Array = table.presentation_character_ids()
		assert_eq(bound.size(), 4, "生产链须把四席 roster 写入 presentation mode=%s" % mode)
		for i in range(4):
			assert_eq(str(bound[i]), chars[i], "presentation seat %d mode=%s" % [i, mode])
			assert_eq(str(meta.get("character_ids", [])[i]), chars[i])

		# 清理 session→table 引用，避免 autofree 泄漏
		if table.get("_public_reward_session") == sess:
			table._reward_sync_active = false
			if table.has_method("_disconnect_public_transcript"):
				table._disconnect_public_transcript()
			table._public_reward_session = null
		if sess.has_method("release"):
			sess.release()


## —— helpers ——

func _core_mod(seat: int) -> Dictionary:
	return {
		"module_key": "core_table",
		"schema_version": 1,
		"payload": _core_payload(seat),
	}


func _core_payload(seat: int) -> Dictionary:
	var tile := {
		"instance_id": seat,
		"tile_id": TileId.E,
		"is_red_dora": false,
		"owner_seat": seat,
	}
	var seats: Array = []
	for s in range(4):
		seats.append({
			"seat": s,
			"seat_wind": [TileId.E, TileId.S_WIND, TileId.W_WIND, TileId.N][s],
			"score": 25000,
			"concealed_tiles": [tile] if s == seat else [],
			"concealed_count": 1 if s == seat else 13,
			"last_drawn_tile_instance_id": -1,
			"river": [],
			"melds": [],
			"riichi_declared": false,
			"riichi_double": false,
			"riichi_discard_index": -1,
		})
	return {
		"recipient_seat": seat,
		"hand_seq": 0,
		"dealer_seat": 0,
		"current_seat": 0,
		"phase": "DRAW",
		"round_wind": TileId.E,
		"hand_number": 1,
		"honba": 0,
		"riichi_sticks": 0,
		"live_wall_count": 70,
		"dora_indicators": [{
			"instance_id": 4,
			"tile_id": TileId.W5,
			"is_red_dora": true,
			"owner_seat": 0,
		}],
		"seats": seats,
	}


func _item_inv_mod(seat: int) -> Dictionary:
	return {
		"module_key": "item_inventory",
		"schema_version": ItemInventoryModule.SCHEMA_VERSION,
		"payload": {
			"seat": seat,
			"items": [],
			"active_window_id": null,
			"pending_window_id": null,
		},
	}


func _reward_window_mod(_seat: int) -> Dictionary:
	# 最小 IDLE 合法 payload 不在此强制；若 schema 拒绝则用真实 LocalLoopback 路径覆盖 TRASH_TALK
	return {
		"module_key": "reward_window",
		"schema_version": RewardWindowModule.SCHEMA_VERSION,
		"payload": {
			"module_key": "reward_window",
			"schema_version": RewardWindowModule.SCHEMA_VERSION,
			"phase": "IDLE",
			"hand_seq": 0,
			"window_index": 0,
			"window_id": "",
			"discard_count": 0,
			"grace_deadline_at": "",
			"grace_deadline_ms": -1,
			"claim_is_terminal": false,
			"room_id": "room-rw",
			"character_ids": ["lin_yeche", "qiu_jue", "an_cheng", "bai_touli"],
			"language": "zh",
			"participants": ["HUMAN", "AI", "AI", "AI"],
			"assignment": {},
			"transcript_summary": {},
		},
	}


func _snapshot_payload(seat: int, modules: Array) -> Dictionary:
	return {
		"snapshot_server_seq": 1,
		"next_server_seq": 2,
		"seat_view": seat,
		"modules": modules,
	}


func _room_snapshot(room: String, seq: int, payload: Dictionary) -> NetworkedEvent:
	var p := payload.duplicate(true)
	p["snapshot_server_seq"] = seq
	p["next_server_seq"] = seq + 1
	var vh: String = ProtocolViewCodec.compute_view_hash(p)
	return NetworkedEvent.make("ROOM_SNAPSHOT", seq, room, p, vh)


class _Sink extends RefCounted:
	var applied: Dictionary = {}

	func apply_restored_module(module_key: String, _sv: int, payload: Dictionary, _seat: int) -> bool:
		applied[module_key] = payload.duplicate(true)
		return true

	func capture_module_restore_state() -> Dictionary:
		return applied.duplicate(true)

	func restore_module_restore_state(prev: Variant) -> void:
		applied = {}
		if typeof(prev) == TYPE_DICTIONARY:
			applied = (prev as Dictionary).duplicate(true)
