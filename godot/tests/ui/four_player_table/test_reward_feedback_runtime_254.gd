extends GutTest

# E5-06 / #254 rework-5：真实 NBC 序列反馈、严格 USE、pending 不空转。

const PlayableScr = preload("res://ui/four_player_table/playable_table.gd")
const TableScr = preload("res://ui/four_player_table/four_player_table.gd")
const BalScr = preload("res://meta/reward_feedback_balance_fixtures.gd")
const DrawerScr = preload("res://ui/four_player_table/item_inventory_drawer.gd")
const ModelScr = preload("res://ui/four_player_table/seat_caption_model.gd")

const CHARS := [&"lin_yeche", &"qiu_jue", &"bai_touli", &"hua_ling"]
const PARTS := [&"HUMAN", &"AI", &"AI", &"AI"]
const VIEW_HASH := "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"


func _cfg_tt(seed: int = 11) -> GameSessionConfig:
	return GameSessionConfig.create_validated(
		GameSessionConfig.ROOM_PRACTICE, GameSessionConfig.ROUND_EAST,
		GameSessionConfig.MODE_TRASH_TALK, PARTS, CHARS, seed,
		"practice-254-r5-%d" % seed, "rv-254"
	)


func _pair() -> Array:
	var table = PlayableScr.new()
	add_child_autofree(table)
	var fpt = TableScr.new()
	table.add_child(fpt)
	table._table = fpt
	return [table, fpt]


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
	if table != null and is_instance_valid(table):
		if table.get("_public_reward_session") == sess:
			table._reward_sync_active = false
			if table.has_method("_disconnect_public_transcript"):
				table._disconnect_public_transcript()
			table._public_reward_session = null
	if sess != null and is_instance_valid(sess):
		sess.release()


func test_grant_then_snapshot_preserves_arrival_via_real_nbc() -> void:
	# 真实冻结 journal 本窗片段经 NBC+session 自动同步；SNAP 后仍保留「到账」
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

	# 先 ingest 到 SETTLED 之前 → 无到账
	var stopped_at_grant := false
	for raw in events:
		var d: Dictionary = raw
		var kind := String(d.get("kind", ""))
		if kind == "ITEM_GRANTED" and not stopped_at_grant:
			# 停在首个 grant 前，确认无到账
			for _i in range(3):
				await get_tree().process_frame
				table._sync_reward_feedback_if_advanced()
			assert_ne(fpt.reward_feedback_text(), "到账")
			stopped_at_grant = true
		var ne: NetworkedEvent = NetworkedEvent.from_dict(d)
		assert_not_null(ne, kind)
		assert_true(nbc.ingest_networked_event(ne), kind)
		await get_tree().process_frame
		table._sync_reward_feedback_if_advanced()

	var iid0 := String(BalScr.FULL_GRANT_INSTANCE_IDS["0"])
	assert_eq(fpt.reward_feedback_text(), "到账", "完整 commit 后须到账")
	assert_eq(fpt.inventory_count(), 1)
	assert_true(fpt.inventory_row_ids().has(iid0))
	# 再同步多帧（含 SNAP 视图恢复）不得吞到账
	for _j in range(5):
		await get_tree().process_frame
		table._sync_reward_feedback_if_advanced()
	assert_eq(fpt.reward_feedback_text(), "到账", "SNAP/视图恢复不得吞掉到账")
	_release_public_session(sess, table)


func test_applied_consumed_snapshot_preserves_apply_banner() -> void:
	var fpt = TableScr.new()
	add_child_autofree(fpt)
	await get_tree().process_frame
	fpt.begin_reward_display_source("fb|apply", 0)
	var iid := "ii_session_bal_254_r5_hand_0_window_0_s0_wall_peek_v1"
	var grant := {
		"protocol_version": 1, "server_seq": 1, "room_id": "r",
		"kind": "ITEM_GRANTED",
		"payload": {
			"window_id": "hand_0_window_0", "rule_version": "trash_talk_rules_v1",
			"assignment_version": "assign_v1", "matched_rule_ids": [],
			"item_id": "wall_peek_v1", "item_instance_id": iid,
			"seat": 0, "hand_seq": 0, "score": 0,
			"affinity_match": false, "armed_for_window_id": null,
		},
		"view_hash": VIEW_HASH,
	}
	var applied := {
		"protocol_version": 1, "server_seq": 2, "room_id": "r",
		"kind": "ITEM_APPLIED",
		"payload": {
			"seat": 0, "item_id": "wall_peek_v1", "item_instance_id": iid,
			"effect_id": "wall_peek_v1",
			"command_id": "550e8400-e29b-41d4-a716-846655440099",
		},
		"view_hash": VIEW_HASH,
	}
	var consumed := {
		"protocol_version": 1, "server_seq": 3, "room_id": "r",
		"kind": "ITEM_CONSUMED",
		"payload": {
			"seat": 0, "item_id": "wall_peek_v1", "item_instance_id": iid,
			"command_id": "550e8400-e29b-41d4-a716-846655440099",
		},
		"view_hash": VIEW_HASH,
	}
	assert_true(bool(fpt.inject_reward_journal_event(grant, "fb|apply").get("ok", false)))
	assert_true(bool(fpt.inject_reward_journal_event(applied, "fb|apply").get("ok", false)))
	assert_true(String(fpt.reward_feedback_text()).contains("发动"))
	assert_true(bool(fpt.inject_reward_journal_event(consumed, "fb|apply").get("ok", false)))
	assert_true(String(fpt.reward_feedback_text()).contains("发动"),
		"ITEM_CONSUMED 不得覆盖发动文案: %s" % fpt.reward_feedback_text())
	fpt.apply_reward_views({"phase": "OPEN", "prize_pool": [], "discard_count": 0}, {
		"seat": 0, "items": [],
	})
	assert_true(String(fpt.reward_feedback_text()).contains("发动"))


func test_practice_publish_grant_auto_sync_arrival() -> void:
	# bind/bootstrap 后发布新事件自然前进；不得直接改 cursor/bootstrapped
	var driver: GameDriver = PracticeSessionLauncher.new().launch(_cfg_tt(11))
	assert_not_null(driver)
	var bc: PlayableBattleController = driver.start_hand() as PlayableBattleController
	assert_not_null(bc)
	var server: LocalLoopbackServer = bc.get_meta("local_authority") as LocalLoopbackServer
	assert_not_null(server)
	var pair: Array = _pair()
	var table = pair[0]
	var fpt = pair[1]
	await get_tree().process_frame
	table._bc = bc
	table._bind_reward_feedback_from_battle(bc)
	# 仅验证 bootstrap 后 cursor 已就位（只读）
	assert_true(table._reward_bootstrapped)
	var head0: int = table._peek_reward_journal_head_seq()
	assert_eq(table._reward_journal_cursor, head0)

	var inv: ItemInventoryModule = bc.mode_modules.item_inventory
	var gr: Dictionary = inv.grant_for_seat({
		"seat": 0, "item_id": "wall_peek_v1",
		"window_id": "hand_0_window_0", "hand_seq": 0, "score": 1,
		"affinity_match": false, "matched_rule_ids": [],
		"rule_version": "trash_talk_rules_v1", "assignment_version": "assign_v1",
	})
	assert_true(bool(gr.get("ok", false)), str(gr))
	var payload: Dictionary = (gr["payload"] as Dictionary).duplicate(true)
	var pub_ok: bool = server.try_publish_business_event("ITEM_GRANTED", payload)
	assert_true(pub_ok, "权威必须成功发布 ITEM_GRANTED")
	for _i in range(8):
		await get_tree().process_frame
		table._sync_reward_feedback_if_advanced()
	assert_eq(fpt.inventory_count(), 1)
	assert_eq(fpt.reward_feedback_text(), "到账")
	assert_gt(table._peek_reward_journal_head_seq(), head0)


func test_item_use_button_precise_instance() -> void:
	var driver: GameDriver = PracticeSessionLauncher.new().launch(_cfg_tt(13))
	assert_not_null(driver)
	var bc: PlayableBattleController = driver.start_hand() as PlayableBattleController
	assert_not_null(bc)
	var server: LocalLoopbackServer = bc.get_meta("local_authority") as LocalLoopbackServer
	var inv: ItemInventoryModule = bc.mode_modules.item_inventory
	var g_a: Dictionary = inv.grant_for_seat({
		"seat": 0, "item_id": "wall_peek_v1",
		"window_id": "hand_0_window_0", "hand_seq": 0, "score": 1,
		"affinity_match": false, "matched_rule_ids": [],
		"rule_version": "trash_talk_rules_v1", "assignment_version": "assign_v1",
	})
	var g_b: Dictionary = inv.grant_for_seat({
		"seat": 0, "item_id": "wall_peek_v1",
		"window_id": "hand_0_window_1", "hand_seq": 0, "score": 1,
		"affinity_match": false, "matched_rule_ids": [],
		"rule_version": "trash_talk_rules_v1", "assignment_version": "assign_v1",
	})
	assert_true(bool(g_a.get("ok", false)) and bool(g_b.get("ok", false)))
	var iid_a := String((g_a["payload"] as Dictionary)["item_instance_id"])
	var iid_b := String((g_b["payload"] as Dictionary)["item_instance_id"])
	assert_ne(iid_a, iid_b)

	var pair: Array = _pair()
	var table = pair[0]
	var fpt = pair[1]
	await get_tree().process_frame
	table._bc = bc
	table._bind_reward_feedback_from_battle(bc)
	table._refresh_reward_feedback_views()
	fpt.open_inventory_drawer()
	await get_tree().process_frame
	var drawer = fpt.get_node("ItemInventoryDrawer")
	assert_not_null(drawer)
	drawer.set_instances(fpt._reward_feedback_projector.local_inventory_instances())
	await get_tree().process_frame
	var row: Control = drawer._rows_by_id.get(iid_a, null)
	assert_not_null(row, "抽屉必须有目标 iid 行")
	var btn: Button = row.find_child("UseButton", true, false) as Button
	assert_not_null(btn)
	assert_false(btn.disabled)
	btn.pressed.emit()
	await get_tree().process_frame
	table._sync_reward_feedback_if_advanced()
	# 精确：iid_a 已消耗，iid_b 仍在
	assert_null(inv.find_instance(iid_a), "USE 后目标实例须移除")
	assert_not_null(inv.find_instance(iid_b), "同 item_id 另一实例须保留")
	var applied := false
	var consumed := false
	var saw_snap_after := false
	var last_applied_seq := -1
	var last_consumed_seq := -1
	for ne2 in server.event_journal(0):
		if not (ne2 is NetworkedEvent):
			continue
		var e: NetworkedEvent = ne2 as NetworkedEvent
		if e.kind == "ITEM_APPLIED" and String(e.payload.get("item_instance_id", "")) == iid_a:
			applied = true
			last_applied_seq = int(e.server_seq)
		if e.kind == "ITEM_CONSUMED" and String(e.payload.get("item_instance_id", "")) == iid_a:
			consumed = true
			last_consumed_seq = int(e.server_seq)
		if e.kind == "ROOM_SNAPSHOT" and last_consumed_seq > 0 and int(e.server_seq) > last_consumed_seq:
			saw_snap_after = true
	assert_true(applied, "journal 须含目标 iid 的 ITEM_APPLIED")
	assert_true(consumed, "journal 须含目标 iid 的 ITEM_CONSUMED")
	assert_true(saw_snap_after or last_consumed_seq > last_applied_seq,
		"须完成 APPLIED→CONSUMED 事务（及后续 SNAP）")
	# 严格：库存精确 1 且 banner 含「发动」（删除 or 放水）
	assert_eq(fpt.inventory_count(), 1, "USE 后库存须精确为 1")
	assert_true(String(fpt.reward_feedback_text()).contains("发动"),
		"完整事务后 banner 须仍为发动: %s" % fpt.reward_feedback_text())
	# 再 refresh（SNAP 视图）不得吞发动
	table._refresh_reward_feedback_views()
	assert_true(String(fpt.reward_feedback_text()).contains("发动"))
	assert_eq(fpt.inventory_count(), 1)


func test_new_hand_same_room_seq_reuse_shows_arrival() -> void:
	var fpt = TableScr.new()
	add_child_autofree(fpt)
	await get_tree().process_frame
	var wire := {
		"protocol_version": 1, "server_seq": 3, "room_id": "same_room",
		"kind": "ITEM_GRANTED",
		"payload": {
			"window_id": "hand_0_window_0", "rule_version": "trash_talk_rules_v1",
			"assignment_version": "assign_v1", "matched_rule_ids": [],
			"item_id": "wall_peek_v1",
			"item_instance_id": "ii_a",
			"seat": 0, "hand_seq": 0, "score": 0,
			"affinity_match": false, "armed_for_window_id": null,
		},
		"view_hash": VIEW_HASH,
	}
	fpt.begin_reward_display_source("practice|same_room|seat0|hand0", 0)
	assert_true(bool(fpt.inject_reward_journal_event(wire, "practice|same_room|seat0|hand0").get("ok", false)))
	assert_eq(fpt.reward_feedback_text(), "到账")
	fpt.begin_reward_display_source("practice|same_room|seat0|hand1", 0)
	var r2: Dictionary = fpt.inject_reward_journal_event(wire, "practice|same_room|seat0|hand1")
	assert_true(bool(r2.get("ok", false)), str(r2))
	assert_false(bool(r2.get("idempotent", false)), "新 hand 同 seq 不得误去重")
	assert_eq(fpt.reward_feedback_text(), "到账")


func test_pending_does_not_spam_apply() -> void:
	# 真实 NBC：先 ingest 会 pending 的 ITEM_GRANTED，多帧 apply count 不变；
	# 再 ingest 匹配 snapshot，恰好同步并显示到账/精确 iid。
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

	# 喂到首个 ITEM_GRANTED（含该 grant），此时应 pending
	var fed_grant := false
	for raw in events:
		var d: Dictionary = raw
		var kind := String(d.get("kind", ""))
		var ne: NetworkedEvent = NetworkedEvent.from_dict(d)
		assert_not_null(ne, kind)
		assert_true(nbc.ingest_networked_event(ne), kind)
		if kind == "ITEM_GRANTED":
			fed_grant = true
			break
	assert_true(fed_grant)
	# pending 时 journal 无 ITEM_GRANTED
	var has_g := false
	for je in nbc.get_event_journal():
		if je is NetworkedEvent and (je as NetworkedEvent).kind == "ITEM_GRANTED":
			has_g = true
	assert_false(has_g, "pending 阶段 committed journal 不得含 ITEM_GRANTED")

	table._bootstrap_reward_display()
	var c0: int = table.get_reward_apply_count()
	for _i in range(10):
		await get_tree().process_frame
		table._sync_reward_feedback_if_advanced()
	var c1: int = table.get_reward_apply_count()
	assert_eq(c1, c0, "pending 无 committed 前进时不得每帧 rebuild")
	assert_ne(fpt.reward_feedback_text(), "到账")

	# 继续 ingest 至流结束（含匹配 SNAP）→ 恰好同步
	var resume := false
	for raw2 in events:
		var d2: Dictionary = raw2
		if not resume:
			if String(d2.get("kind", "")) == "ITEM_GRANTED":
				resume = true
			continue
		var ne2: NetworkedEvent = NetworkedEvent.from_dict(d2)
		assert_not_null(ne2)
		assert_true(nbc.ingest_networked_event(ne2))
	for _j in range(6):
		await get_tree().process_frame
		table._sync_reward_feedback_if_advanced()
	var iid0 := String(BalScr.FULL_GRANT_INSTANCE_IDS["0"])
	assert_eq(fpt.reward_feedback_text(), "到账")
	assert_true(fpt.inventory_row_ids().has(iid0))
	assert_eq(fpt.inventory_count(), 1)
	var c2: int = table.get_reward_apply_count()
	assert_gt(c2, c1, "commit 后须发生有限次 apply")
	# 再空转不得持续增长
	for _k in range(8):
		await get_tree().process_frame
		table._sync_reward_feedback_if_advanced()
	assert_eq(table.get_reward_apply_count(), c2, "commit 完成后空转不得 rebuild")
	_release_public_session(sess, table)


func test_exit_tree_stops_sync() -> void:
	var pair: Array = _pair()
	var table = pair[0]
	await get_tree().process_frame
	var sess := PublicCasualNetworkSession.new()
	add_child_autofree(sess)
	sess.room_id = "x"
	sess.seat = 0
	table.bind_public_casual_session(sess)
	assert_true(table._reward_sync_active)
	table._exit_tree()
	assert_false(table._reward_sync_active)
	assert_null(table._public_reward_session)
	sess.release()


func test_caption_exact_affinity_hardcoded() -> void:
	var m: Dictionary = BalScr.gold_multilingual_inputs()
	var row: Dictionary = m["seats"]["0"]
	var acc: Dictionary = TextAnalyzer.accumulate_window({
		"rule_version": "trash_talk_rules_v1",
		"window_id": "w",
		"seat": 0,
		"character_id": "qiu_jue",
		"language": "zh",
		"utterances": [{
			"utterance_id": "u",
			"text": String(row["text"]),
			"language": "zh",
		}],
	})
	assert_eq(JSON.stringify(acc.get("matched_rule_ids", [])),
		JSON.stringify(row["matched_rule_ids"]))
	assert_eq(int((acc.get("affinity", {}) as Dictionary).get("PASSION", -1)), 220)


func test_snapshot_only_settlement_messages() -> void:
	# 使用真实流 SETTLED wire；无 grant 时 SNAP 恢复不得吞掉「分配完成」文案
	var fpt = TableScr.new()
	add_child_autofree(fpt)
	await get_tree().process_frame
	fpt.begin_reward_display_source("snap|only", 0)
	var settled_wire: Dictionary = {}
	for raw in BalScr.self_consistent_full_grant_window_events():
		if String((raw as Dictionary).get("kind", "")) == "REWARD_WINDOW_SETTLED":
			settled_wire = raw
			break
	assert_false(settled_wire.is_empty(), "真实流须含 SETTLED")
	var ne: NetworkedEvent = NetworkedEvent.from_dict(settled_wire)
	assert_not_null(ne, "真实 SETTLED 必须 schema-valid")
	assert_true(bool(fpt.inject_reward_journal_event(ne, "snap|only").get("ok", false)))
	assert_eq(fpt.reward_feedback_text(), "分配完成，等待到账事件")
	var pool: Array = BalScr.FULL_GRANT_PRIZE_POOL.duplicate()
	var asg: Dictionary = BalScr.FULL_GRANT_ASSIGNMENT.duplicate(true)
	# SNAP-only 视图恢复不得清空该文案
	fpt.apply_reward_views({
		"phase": "SETTLED", "window_exit": "FULL_GRANT",
		"prize_pool": pool, "assignment": asg, "discard_count": 24,
	}, {"seat": 0, "items": []})
	assert_eq(fpt.reward_feedback_text(), "分配完成，等待到账事件")
