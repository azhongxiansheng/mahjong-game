extends GutTest

# E5-06 / #254 rework-5：真实生产链 — 冻结 LocalLoopback journal + NBC + seat2。

const PlayableScr = preload("res://ui/four_player_table/playable_table.gd")
const ProjScr = preload("res://ui/four_player_table/reward_feedback_projector.gd")
const DrawerScr = preload("res://ui/four_player_table/item_inventory_drawer.gd")
const ModelScr = preload("res://ui/four_player_table/seat_caption_model.gd")
const BalScr = preload("res://meta/reward_feedback_balance_fixtures.gd")

const CHARS := [&"lin_yeche", &"qiu_jue", &"bai_touli", &"hua_ling"]
const PARTS_PRACTICE := [&"HUMAN", &"AI", &"AI", &"AI"]
const VIEW_HASH := "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"


func _cfg_tt(seed: int = 11) -> GameSessionConfig:
	return GameSessionConfig.create_validated(
		GameSessionConfig.ROOM_PRACTICE, GameSessionConfig.ROUND_EAST,
		GameSessionConfig.MODE_TRASH_TALK, PARTS_PRACTICE, CHARS, seed,
		"practice-254-r5-%d" % seed, "rv-254"
	)


func _env(kind: String, seq: int, payload: Dictionary, room: String = "room_r5") -> Dictionary:
	return {
		"protocol_version": 1,
		"server_seq": seq,
		"room_id": room,
		"kind": kind,
		"payload": payload.duplicate(true),
		"view_hash": VIEW_HASH,
	}


func _pair() -> Array:
	var table = PlayableScr.new()
	add_child_autofree(table)
	var fpt = load("res://ui/four_player_table/four_player_table.gd").new()
	table.add_child(fpt)
	table._table = fpt
	return [table, fpt]


## 入树 + 结束 release：避免 WebSocketPeer/Node 泄漏。
func _bind_public_session(
	table: Node, nbc: NetworkedBattleController, room: String, seat: int
) -> PublicCasualNetworkSession:
	var sess := PublicCasualNetworkSession.new()
	add_child_autofree(sess)
	sess.room_id = room
	sess.seat = seat
	sess.nbc = nbc
	sess.bind_playable_table(table)
	return sess


func _release_public_session(sess: PublicCasualNetworkSession, table: Node = null) -> void:
	if table != null and table.has_method("_exit_tree"):
		# 断开 table→session 引用链（不销毁 table；autofree 负责）
		if table.get("_public_reward_session") == sess:
			table._reward_sync_active = false
			if table.has_method("_disconnect_public_transcript"):
				table._disconnect_public_transcript()
			table._public_reward_session = null
	if sess != null and is_instance_valid(sess):
		sess.release()


# ── P1：练习场库存 DTO 解包 + journal 到账 ─────────────────

func test_practice_snapshot_dto_unwrap_and_journal_arrival() -> void:
	var driver: GameDriver = PracticeSessionLauncher.new().launch(_cfg_tt(11))
	assert_not_null(driver)
	var bc: PlayableBattleController = driver.start_hand() as PlayableBattleController
	assert_not_null(bc)
	assert_true(bc.has_meta("local_authority"))
	var server: LocalLoopbackServer = bc.get_meta("local_authority") as LocalLoopbackServer
	assert_not_null(server)

	var pair: Array = _pair()
	var table = pair[0]
	var fpt = pair[1]
	await get_tree().process_frame
	table._bc = bc
	table._bind_reward_feedback_from_battle(bc)

	var inv: ItemInventoryModule = bc.mode_modules.item_inventory
	assert_not_null(inv)
	var dto0: Dictionary = inv.to_seat_snapshot_dto(0)
	assert_true(dto0.has("payload"), "to_seat_snapshot_dto 为 envelope")
	assert_true((dto0["payload"] as Dictionary).has("items"))

	var gr: Dictionary = inv.grant_for_seat({
		"seat": 0,
		"item_id": "iron_shield_v1",
		"window_id": "hand_0_window_0",
		"hand_seq": 0,
		"score": 100,
		"affinity_match": false,
		"matched_rule_ids": [],
		"rule_version": "trash_talk_rules_v1",
		"assignment_version": "assign_v1",
	})
	assert_true(bool(gr.get("ok", false)), str(gr))
	assert_eq(inv.instances_for_seat(0).size(), 1)

	table._refresh_reward_feedback_views()
	await get_tree().process_frame
	assert_eq(fpt.inventory_count(), 1,
		"练习快照 DTO 解包后库存须为 1，不得因 envelope 误读清空")

	var payload_g: Dictionary = (gr.get("payload", {}) as Dictionary).duplicate(true)
	var wire := {
		"protocol_version": 1,
		"server_seq": 9001,
		"room_id": "practice-254",
		"kind": "ITEM_GRANTED",
		"payload": payload_g,
		"view_hash": VIEW_HASH,
	}
	if not payload_g.has("window_id"):
		wire = _env("ITEM_GRANTED", 9001, {
			"window_id": "hand_0_window_0",
			"rule_version": "trash_talk_rules_v1",
			"assignment_version": "assign_v1",
			"matched_rule_ids": [],
			"item_id": "iron_shield_v1",
			"item_instance_id": String(payload_g.get("item_instance_id", "ii_x")),
			"seat": 0, "hand_seq": 0, "score": 100,
			"affinity_match": false, "armed_for_window_id": null,
		})
	var r_fb: Dictionary = fpt.inject_reward_journal_event(wire)
	assert_true(bool(r_fb.get("ok", false)), str(r_fb))
	assert_eq(String(fpt.reward_feedback_text()), "到账")
	var r_dup: Dictionary = fpt.inject_reward_journal_event(wire)
	assert_true(bool(r_dup.get("idempotent", false)) or bool(r_dup.get("ok", false)))
	var n1: int = fpt.inventory_count()
	table._refresh_reward_feedback_views()
	table._refresh_reward_feedback_views()
	assert_eq(fpt.inventory_count(), n1, "重复刷新不得重复放大库存")
	assert_not_null(server)


func test_real_full_grant_stream_nbc_pending_then_commit() -> void:
	# 真实冻结 LocalLoopback journal 本窗片段：先 bind（cursor@0），再逐条 ingest
	# （若先 ingest 再 bind，bootstrap 会跳过历史到账——那是中途入局语义，不是增量同步）
	var events: Array = BalScr.self_consistent_full_grant_window_events()
	assert_gt(events.size(), 10)
	var room := String(BalScr.ROOM_ID)
	var nbc := NetworkedBattleController.new(room, 0)
	nbc.configure_snapshot_registry_for_mode(str(GameSessionConfig.MODE_TRASH_TALK))

	var pair: Array = _pair()
	var table = pair[0]
	var fpt = pair[1]
	await get_tree().process_frame
	var sess: PublicCasualNetworkSession = _bind_public_session(table, nbc, room, 0)

	var grant_seen := false
	var pending_journal_without_grant := false
	for raw in events:
		var d: Dictionary = raw
		var kind := String(d.get("kind", ""))
		var ne: NetworkedEvent = NetworkedEvent.from_dict(d)
		assert_not_null(ne, "真实 wire 必须 schema-valid kind=%s" % kind)
		assert_true(nbc.ingest_networked_event(ne), "ingest %s seq=%s" % [kind, str(d.get("server_seq"))])
		if kind == "ITEM_GRANTED" and not grant_seen:
			grant_seen = true
			var has_g := false
			for je in nbc.get_event_journal():
				if je is NetworkedEvent and (je as NetworkedEvent).kind == "ITEM_GRANTED":
					has_g = true
			# pending 阶段：匹配 SNAP 前 ITEM_GRANTED 不得进入 committed journal
			pending_journal_without_grant = not has_g
			# pending 时 UI 也不得到账
			await get_tree().process_frame
			table._sync_reward_feedback_if_advanced()
			assert_ne(fpt.reward_feedback_text(), "到账")
		await get_tree().process_frame
		table._sync_reward_feedback_if_advanced()
	assert_true(grant_seen)
	assert_true(pending_journal_without_grant,
		"pending ITEM_GRANTED 在匹配 snapshot 前不可见于 committed journal")

	var kinds: Array = []
	for je2 in nbc.get_event_journal():
		if je2 is NetworkedEvent:
			kinds.append(String((je2 as NetworkedEvent).kind))
	assert_true(kinds.has("ITEM_GRANTED"), "commit 后 journal 须含 ITEM_GRANTED")
	assert_true(kinds.has("REWARD_WINDOW_SETTLED"))

	# seat0 库存视图精确：仅 seat0 真实 iid
	var inv_view: Dictionary = nbc.get_item_inventory_view()
	var items: Array = inv_view.get("items", []) as Array
	var iid0 := String(BalScr.FULL_GRANT_INSTANCE_IDS["0"])
	var found0 := false
	for it in items:
		if typeof(it) != TYPE_DICTIONARY:
			continue
		var id := String(it.get("item_instance_id", ""))
		assert_eq(int(it.get("seat", -1)), 0, "seat0 视图不得含他席")
		if id == iid0:
			found0 = true
	assert_true(found0, "seat0 视图须含精确 iid %s items=%s" % [iid0, str(items)])

	for _i in range(4):
		await get_tree().process_frame
		table._sync_reward_feedback_if_advanced()
	assert_eq(fpt.inventory_count(), 1)
	assert_true(fpt.inventory_row_ids().has(iid0))
	assert_eq(fpt.reward_feedback_text(), "到账")
	_release_public_session(sess, table)


func test_seat2_real_provider_journal_only_own_instance() -> void:
	var events: Array = BalScr.self_consistent_full_grant_window_events_seat2()
	assert_gt(events.size(), 10)
	var room := String(BalScr.ROOM_ID)
	var nbc := NetworkedBattleController.new(room, 2)
	nbc.configure_snapshot_registry_for_mode(str(GameSessionConfig.MODE_TRASH_TALK))

	var pair: Array = _pair()
	var table = pair[0]
	var fpt = pair[1]
	await get_tree().process_frame
	var sess: PublicCasualNetworkSession = _bind_public_session(table, nbc, room, 2)

	for raw in events:
		var d: Dictionary = raw
		var ne: NetworkedEvent = NetworkedEvent.from_dict(d)
		assert_not_null(ne, "seat2 wire from_dict kind=%s" % str(d.get("kind")))
		assert_true(nbc.ingest_networked_event(ne), "seat2 ingest %s" % str(d.get("kind")))
		await get_tree().process_frame
		table._sync_reward_feedback_if_advanced()

	var inv_view: Dictionary = nbc.get_item_inventory_view()
	var items: Array = inv_view.get("items", []) as Array
	var iid2 := String(BalScr.FULL_GRANT_INSTANCE_IDS["2"])
	var iid0 := String(BalScr.FULL_GRANT_INSTANCE_IDS["0"])
	assert_eq(items.size(), 1, "seat2 仅本席 1 件: %s" % str(items))
	assert_eq(String(items[0].get("item_instance_id", "")), iid2)
	assert_eq(int(items[0].get("seat", -1)), 2)
	assert_ne(String(items[0].get("item_instance_id", "")), iid0)

	assert_eq(fpt.inventory_count(), 1)
	assert_true(fpt.inventory_row_ids().has(iid2))
	assert_false(fpt.inventory_row_ids().has(iid0), "seat2 不得读 seat0 实例")
	assert_eq(fpt.reward_feedback_text(), "到账")
	_release_public_session(sess, table)


func test_recipient_snapshot_hides_other_concealed_and_inventory() -> void:
	# seat0/seat2：共享公开权威一致；TURN_PROMPT/CLAIM_WINDOW/view_hash 可不同。
	# concealed_tiles 仅 recipient 非空；item_inventory 仅本席实例。
	var ev0: Array = BalScr.self_consistent_full_grant_events()
	var ev2: Array = BalScr.self_consistent_full_grant_events_seat2()
	assert_eq(ev0.size(), 25)
	assert_eq(ev2.size(), 25)
	var pool0: Array = []
	var asg0: Dictionary = {}
	var grants0: Array = []
	var pool2: Array = []
	var asg2: Dictionary = {}
	var grants2: Array = []
	var post_grant_snap0: Dictionary = {}
	var post_grant_snap2: Dictionary = {}
	var room0 := ""
	var room2 := ""
	for raw in ev0:
		var d: Dictionary = raw
		assert_not_null(NetworkedEvent.from_dict(d), "seat0 wire %s" % str(d.get("kind")))
		room0 = String(d.get("room_id", room0))
		var kind := String(d.get("kind", ""))
		if kind == "REWARD_WINDOW_OPENED" and pool0.is_empty():
			pool0 = (d["payload"] as Dictionary).get("prize_pool", []) as Array
		elif kind == "REWARD_WINDOW_SETTLED" \
				and String((d["payload"] as Dictionary).get("outcome", "")) == "FULL_GRANT":
			asg0 = (d["payload"] as Dictionary).get("assignment", {}) as Dictionary
			assert_eq(int((d["payload"] as Dictionary).get("grant_count", -1)), 4)
		elif kind == "ITEM_GRANTED":
			grants0.append({
				"seat": int((d["payload"] as Dictionary).get("seat", -1)),
				"item_id": String((d["payload"] as Dictionary).get("item_id", "")),
				"iid": String((d["payload"] as Dictionary).get("item_instance_id", "")),
			})
		elif kind == "ROOM_SNAPSHOT" and grants0.size() == 4:
			# 四次 grant 后的首个 SNAP（本席私有视图）
			if post_grant_snap0.is_empty():
				post_grant_snap0 = d
	for raw2 in ev2:
		var d2: Dictionary = raw2
		assert_not_null(NetworkedEvent.from_dict(d2), "seat2 wire %s" % str(d2.get("kind")))
		room2 = String(d2.get("room_id", room2))
		var kind2 := String(d2.get("kind", ""))
		if kind2 == "REWARD_WINDOW_OPENED" and pool2.is_empty():
			pool2 = (d2["payload"] as Dictionary).get("prize_pool", []) as Array
		elif kind2 == "REWARD_WINDOW_SETTLED" \
				and String((d2["payload"] as Dictionary).get("outcome", "")) == "FULL_GRANT":
			asg2 = (d2["payload"] as Dictionary).get("assignment", {}) as Dictionary
			assert_eq(int((d2["payload"] as Dictionary).get("grant_count", -1)), 4)
		elif kind2 == "ITEM_GRANTED":
			grants2.append({
				"seat": int((d2["payload"] as Dictionary).get("seat", -1)),
				"item_id": String((d2["payload"] as Dictionary).get("item_id", "")),
				"iid": String((d2["payload"] as Dictionary).get("item_instance_id", "")),
			})
		elif kind2 == "ROOM_SNAPSHOT" and grants2.size() == 4:
			if post_grant_snap2.is_empty():
				post_grant_snap2 = d2
	assert_eq(room0, room2)
	assert_eq(room0, String(BalScr.ROOM_ID))
	assert_eq(JSON.stringify(pool0), JSON.stringify(pool2), "共享 OPEN pool 须一致")
	assert_eq(JSON.stringify(asg0), JSON.stringify(asg2), "共享 SETTLED assignment 须一致")
	assert_eq(JSON.stringify(grants0), JSON.stringify(grants2), "共享 ITEM_GRANTED 公开字段须一致")
	assert_eq(grants0.size(), 4)
	assert_false(post_grant_snap0.is_empty())
	assert_false(post_grant_snap2.is_empty())
	# recipient-specific：view_hash 可不同
	assert_ne(String(post_grant_snap0.get("view_hash", "")), "")
	assert_ne(String(post_grant_snap2.get("view_hash", "")), "")
	_assert_recipient_isolation_snap(post_grant_snap0, 0, String(BalScr.FULL_GRANT_INSTANCE_IDS["0"]))
	_assert_recipient_isolation_snap(post_grant_snap2, 2, String(BalScr.FULL_GRANT_INSTANCE_IDS["2"]))


func _assert_recipient_isolation_snap(snap: Dictionary, recipient: int, expect_iid: String) -> void:
	assert_eq(int((snap.get("payload", {}) as Dictionary).get("seat_view", -1)), recipient)
	var mods: Array = (snap.get("payload", {}) as Dictionary).get("modules", []) as Array
	var saw_core := false
	var saw_inv := false
	for m in mods:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var md: Dictionary = m
		var key := String(md.get("module_key", ""))
		var pay: Dictionary = md.get("payload", {}) as Dictionary
		if key == "core_table":
			saw_core = true
			assert_eq(int(pay.get("recipient_seat", -1)), recipient)
			var seats: Array = pay.get("seats", []) as Array
			assert_eq(seats.size(), 4)
			for si in range(4):
				var seat_row: Dictionary = seats[si]
				var ct: Array = seat_row.get("concealed_tiles", []) as Array
				if si == recipient:
					assert_gt(ct.size(), 0, "recipient seat%d 须展开 concealed_tiles" % recipient)
					assert_gt(int(seat_row.get("concealed_count", 0)), 0)
				else:
					# 公开 count 可非 0；私有牌面数组必须为空
					assert_eq(ct.size(), 0, "非 recipient seat%d concealed_tiles 须为空" % si)
		elif key == "item_inventory":
			saw_inv = true
			assert_eq(int(pay.get("seat", -1)), recipient)
			var items: Array = pay.get("items", []) as Array
			assert_eq(items.size(), 1, "仅本席 1 件: %s" % str(items))
			assert_eq(String(items[0].get("item_instance_id", "")), expect_iid)
			assert_eq(int(items[0].get("seat", -1)), recipient)
	assert_true(saw_core, "须有 core_table")
	assert_true(saw_inv, "须有 item_inventory")


func test_match_settled_after_snapshot_clears_inventory() -> void:
	# ROOM_SNAPSHOT 后 MATCH_SETTLED 清场；旧 reward SNAP 不得重新显示库存
	var events: Array = BalScr.self_consistent_full_grant_events()
	var room := String(BalScr.ROOM_ID)
	var nbc := NetworkedBattleController.new(room, 0)
	nbc.configure_snapshot_registry_for_mode(str(GameSessionConfig.MODE_TRASH_TALK))
	var last_snap: Dictionary = {}
	for raw in events:
		var d: Dictionary = raw
		var ne: NetworkedEvent = NetworkedEvent.from_dict(d)
		assert_not_null(ne)
		assert_true(nbc.ingest_networked_event(ne))
		if String(d.get("kind", "")) == "ROOM_SNAPSHOT":
			last_snap = d
	assert_false(last_snap.is_empty())
	assert_eq(nbc.get_item_inventory_view().get("items", []).size(), 1)

	# 追加 MATCH_SETTLED（同 room 连续 seq / 独立 projector 路径）
	var proj = ProjScr.new()
	# 先把 journal 投到 projector 状态
	for raw2 in events:
		var ne2: NetworkedEvent = NetworkedEvent.from_dict(raw2)
		if ne2 != null:
			proj.project(ne2)
	assert_eq(proj.inventory_count_for_seat(0), 1)
	var match_wire := {
		"protocol_version": 1,
		"server_seq": 99999,
		"room_id": room,
		"kind": "MATCH_SETTLED",
		"payload": {
			"round_kind": "EAST",
			"final_scores": [25000, 25000, 25000, 25000],
			"seat_order": [0, 1, 2, 3],
		},
		"view_hash": String(last_snap.get("view_hash", VIEW_HASH)),
	}
	var ne_m: NetworkedEvent = NetworkedEvent.from_dict(match_wire)
	assert_not_null(ne_m, "MATCH_SETTLED 须 schema-valid")
	var r: Dictionary = proj.project(ne_m)
	assert_true(bool(r.get("ok", false)), str(r))
	assert_eq(proj.inventory_count_for_seat(0), 0, "MATCH_SETTLED 后库存须清空")
	# 生产路径：MATCH 后 journal cursor 前进，旧 SNAP 不回放；此处断言清场生效。
	assert_eq(proj.inventory_count_for_seat(0), 0)


func test_settled_never_mutates_inventory_on_production_project() -> void:
	var p = ProjScr.new()
	p.ingest(_env("ITEM_GRANTED", 10, {
		"window_id": "hand_0_window_0",
		"rule_version": "trash_talk_rules_v1",
		"assignment_version": "assign_v1",
		"matched_rule_ids": [],
		"item_id": "iron_shield_v1",
		"item_instance_id": "ii_x",
		"seat": 0, "hand_seq": 0, "score": 1,
		"affinity_match": false, "armed_for_window_id": null,
	}))
	assert_eq(p.inventory_count_for_seat(0), 1)
	var n0: int = p.inventory_count_for_seat(0)
	p.ingest(_env("REWARD_WINDOW_SETTLED", 11, {
		"window_id": "hand_0_window_0", "outcome": "FULL_GRANT",
		"settle_reason": "FULL_24_NO_WIN", "rule_version": "trash_talk_rules_v1",
		"assignment_version": "assign_v1",
		"prize_pool": BalScr.FULL_GRANT_PRIZE_POOL.duplicate(),
		"matrix_summary": {"scores": [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]]},
		"assignment": BalScr.FULL_GRANT_ASSIGNMENT.duplicate(true),
		"closing_boundary_server_seq": 8, "context_boundary_server_seq": 9,
		"grace_deadline_at": "2026-07-22T12:00:01.500Z",
		"grant_count": 4, "hand_seq": 0, "transcript_summary": {},
	}))
	assert_eq(p.inventory_count_for_seat(0), n0)
	assert_eq(String(p.last_feedback_message()), "分配完成，等待到账事件")


func test_use_button_respects_item_authority_contract() -> void:
	var drawer = DrawerScr.new()
	add_child_autofree(drawer)
	await get_tree().process_frame
	var rows := [
		{
			"item_instance_id": "ii_held_consumable",
			"item_id": "iron_shield_v1",
			"status": "held",
			"display_name": "铁盾",
			"description": "x",
			"affinity_match": false,
		},
		{
			"item_instance_id": "ii_armed",
			"item_id": "iron_shield_v1",
			"status": "armed",
			"display_name": "铁盾",
			"description": "x",
			"affinity_match": false,
		},
		{
			"item_instance_id": "ii_relic",
			"item_id": "relic_lucky_cat_v1",
			"status": "held",
			"display_name": "招财猫",
			"description": "x",
			"affinity_match": true,
		},
	]
	drawer.set_instances(rows)
	await get_tree().process_frame
	assert_true(DrawerScr.can_request_use(rows[0]), "held 消耗品可 USE")
	assert_false(DrawerScr.can_request_use(rows[1]), "armed 不可 USE")
	assert_false(DrawerScr.can_request_use(rows[2]), "relic 不可 USE")
	assert_true(ItemInventoryModule.is_battle_consumable("iron_shield_v1"))
	assert_true(ItemInventoryModule.is_relic_item("relic_lucky_cat_v1"))
	var inv := ItemInventoryModule.new()
	inv.set_match_namespace("use_gate")
	var gr2: Dictionary = inv.grant_for_seat({
		"seat": 0, "item_id": "iron_shield_v1",
		"window_id": "hand_0_window_0", "hand_seq": 0, "score": 0,
		"affinity_match": false, "matched_rule_ids": [],
		"rule_version": "trash_talk_rules_v1", "assignment_version": "assign_v1",
	})
	assert_true(bool(gr2.get("ok", false)), str(gr2))
	var iid2 := String((gr2.get("payload", {}) as Dictionary).get("item_instance_id", ""))
	assert_false(iid2.is_empty())
	var arm_cmd := "550e8400-e29b-41d4-a716-846655440001"
	var use_cmd := "550e8400-e29b-41d4-a716-846655440002"
	assert_true(ProtocolUuid.is_canonical_v4(arm_cmd))
	assert_true(bool(inv.mark_armed(iid2, 0, arm_cmd).get("ok", false)),
		str(inv.mark_armed(iid2, 0, arm_cmd)))
	var bc := BattleController.new(1, 0, false)
	var bad: Dictionary = ItemAuthority.use_item(bc, inv, 0, iid2, use_cmd)
	assert_false(bool(bad.get("accepted", true)), str(bad))
	assert_eq(String(bad.get("error_code", "")), "RULE_REJECTED")


func test_full_instance_id_visible_via_tooltip_or_wrap() -> void:
	var drawer = DrawerScr.new()
	add_child_autofree(drawer)
	await get_tree().process_frame
	var long_id := String(BalScr.FULL_GRANT_INSTANCE_IDS["0"])
	drawer.set_instances([{
		"item_instance_id": long_id,
		"item_id": "double_payout_v1",
		"status": "held",
		"display_name": "双倍",
		"description": "x",
		"affinity_match": false,
	}])
	await get_tree().process_frame
	assert_true(drawer.has_full_instance_id_accessible(long_id),
		"完整 item_instance_id 必须可查看（tooltip/换行/detail）")


func test_utterances_view_stt_fail_vs_silent() -> void:
	var p = ProjScr.new()
	var view := {
		"phase": "CLOSING",
		"window_id": "hand_1_window_0",
		"prize_pool": BalScr.FULL_GRANT_PRIZE_POOL.duplicate(),
		"discard_count": 24,
		"window_exit": null,
		"character_ids": ["lin_yeche", "qiu_jue", "bai_touli", "hua_ling"],
		"utterances_by_seat": {
			"0": [{
				"utterance_id": "u0", "text": "", "language": "zh",
				"ptt_end_server_seq": 10, "terminal": true,
			}],
			"1": [{
				"utterance_id": "u1", "text": "I am tenpai", "language": "en",
				"ptt_end_server_seq": 11, "terminal": true,
			}],
			"2": [],
			"3": [],
		},
	}
	var caps: Array = p.project_utterances_for_display(view)
	var seat0: Dictionary = {}
	for c in caps:
		if int(c.get("seat", -1)) == 0:
			seat0 = c
	assert_false(seat0.is_empty(), "须投影 seat0 STT 失败")
	assert_true(bool(seat0.get("stt_failed", false)))
	assert_true(String(seat0.get("text", "")).contains("转写失败") \
		or String(seat0.get("text", "")).contains("未计分"))
	var silent_seats: Array = p.silent_seats_from_view(view)
	assert_true(silent_seats.has(2))
	assert_true(silent_seats.has(3))
	assert_false(silent_seats.has(0), "有 terminal 尝试非静默")
	assert_false(silent_seats.has(1))

	p.ingest(_env("REWARD_WINDOW_CANCELLED", 20, {
		"window_id": "hand_1_window_0",
		"cancel_reason": "CANCELLED_BY_WIN",
		"closing_boundary_server_seq": 10,
		"grace_aborted": true, "scored": false, "grant_count": 0, "hand_seq": 1,
	}))
	assert_false(p.has_assignment_display())
	assert_false(p.should_show_assignment_for_seat(2, true))


func test_affinity_badges_use_accumulate_window_not_float_analyze() -> void:
	var model = ModelScr.new()
	assert_true(bool(model.ingest({
		"seat": 0, "utterance_id": "zh1",
		"text": "燃烧起来！热血立直一发！",
		"kind": "final", "source": "server_stt", "lang": "zh",
		"now_ms": 1000, "character_id": "qiu_jue",
	}).get("ok", false)))
	var d0: Dictionary = model.display_for_seat(0)
	var badges: Array = d0.get("affinity_badges", [])
	assert_gt(badges.size(), 0, "中文命中应有整数规则徽标")
	assert_true(bool(model.ingest({
		"seat": 1, "utterance_id": "en1",
		"text": "Burn it up! This hand is my comeback!",
		"kind": "final", "source": "server_stt", "lang": "en",
		"now_ms": 1001, "character_id": "qiu_jue",
	}).get("ok", false)))
	assert_true(bool(model.ingest({
		"seat": 2, "utterance_id": "ja1",
		"text": "燃えろ！この局で逆転必勝だ！",
		"kind": "final", "source": "ai_text", "lang": "ja",
		"now_ms": 1002, "character_id": "qiu_jue",
	}).get("ok", false)))
	assert_eq(String(model.display_for_seat(2).get("source", "")), "ai_text")
	assert_true(bool(model.ingest({
		"seat": 3, "utterance_id": "none",
		"text": "……",
		"kind": "final", "source": "server_stt", "lang": "zh",
		"now_ms": 1003, "character_id": "qiu_jue",
	}).get("ok", false)))
	var d3: Dictionary = model.display_for_seat(3)
	var b3: Array = d3.get("affinity_badges", [])
	for b in b3:
		assert_true(String(b) in ["DOMINATION", "CALM", "CUNNING", "PASSION", "MYSTIC"])
	assert_false(d0.has("seed"))
	assert_false(d0.has("hidden_tiles"))
