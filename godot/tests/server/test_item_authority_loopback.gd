extends GutTest

# E5-05 / #253：LocalLoopback 真实路径 — FULL_GRANT / ITEM_USE / 快照。
# settle 路径对齐 #252 test_production_drive_to_24_closing_settle_order。

const CHARS := [&"lin_yeche", &"qiu_jue", &"bai_touli", &"hua_ling"]
const PARTS := [&"HUMAN", &"AI", &"AI", &"AI"]
const PARTS_ALL_HUMAN := [&"HUMAN", &"HUMAN", &"HUMAN", &"HUMAN"]


func _cfg_tt_all_human(seed: int = 11) -> GameSessionConfig:
	return GameSessionConfig.create_validated(
		GameSessionConfig.ROOM_PUBLIC_CASUAL, GameSessionConfig.ROUND_EAST,
		GameSessionConfig.MODE_TRASH_TALK, PARTS_ALL_HUMAN, CHARS, seed,
		"item-auth-tt", "rv-253"
	)


func _cfg_std(seed: int = 7) -> GameSessionConfig:
	return GameSessionConfig.create_validated(
		GameSessionConfig.ROOM_PRACTICE, GameSessionConfig.ROUND_EAST,
		GameSessionConfig.MODE_STANDARD, PARTS, CHARS, seed,
		"item-auth-std", "rv"
	)


func _cmd(n: int) -> String:
	return "550e8400-e29b-41d4-a716-%012d" % n


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


func _events(server: LocalLoopbackServer, seat: int = 0) -> Array:
	return server.event_journal(seat)


func _drive_until_discard_count(server: LocalLoopbackServer, target: int, cmd_base: int = 1000) -> void:
	var rw: RewardWindowModule = server.mode_modules.reward_window
	assert_not_null(rw)
	var n: int = cmd_base
	var guard := 0
	while rw.discard_count < target:
		guard += 1
		assert_lt(guard, 150, "驱动超时 discard=%d" % rw.discard_count)
		var bc: BattleController = server.get("_bc") as BattleController
		assert_not_null(bc)
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
				target_seat, str(server.get("_room_id")), _cmd(n),
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
				actor, iid, str(server.get("_room_id")), _cmd(n),
				str(tctx.decision_id), int(tctx.hand_seq), n
			)
			assert_eq(server.submit_action(dact).status, "ACCEPTED")
			n += 1


## 对齐 #252：24 弃后 CLAIM 全 PASS + grace → FULL_GRANT settle。
func _settle_after_24(server: LocalLoopbackServer) -> void:
	var rw: RewardWindowModule = server.mode_modules.reward_window
	var n := 9000
	var guard := 0
	while rw.phase == RewardWindowModule.PHASE_CLOSING and guard < 40:
		guard += 1
		var bc: BattleController = server.get("_bc") as BattleController
		assert_not_null(bc)
		if bool(bc.get("_settled")):
			assert_true(false, "24 弃 FULL_GRANT 路径不得已和牌 settled")
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
					target_seat, str(server.get("_room_id")), _cmd(n),
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
	assert_ne(rw.phase, RewardWindowModule.PHASE_CLOSING)


func test_cold_start_first_window_unarmed_zero_inventory() -> void:
	var server := LocalLoopbackServer.new(_cfg_tt_all_human(42), 0)
	assert_true(server.start())
	assert_eq(server.mode_modules.item_inventory.instance_count(), 0)
	for slot in server.mode_modules.character_ability_slots:
		assert_false((slot as CharacterAbilitySlot).armed)
	assert_eq(_count(_kinds(server), "CHARACTER_ABILITY_ARMED"), 0)
	assert_eq(_count(_kinds(server), "ITEM_GRANTED"), 0)


func test_full_grant_emits_four_item_granted_seat_order() -> void:
	var server := LocalLoopbackServer.new(_cfg_tt_all_human(11), 0)
	assert_true(server.start())
	_drive_until_discard_count(server, 24, 2000)
	_settle_after_24(server)
	var kinds: Array = _kinds(server)
	assert_eq(_count(kinds, "REWARD_WINDOW_SETTLED"), 1)
	assert_eq(_count(kinds, "ITEM_GRANTED"), 4)
	var seats: Array = []
	var insts: Array = []
	for ne in _events(server):
		if ne is NetworkedEvent and (ne as NetworkedEvent).kind == "ITEM_GRANTED":
			var p: Dictionary = (ne as NetworkedEvent).payload
			seats.append(int(p["seat"]))
			insts.append(str(p["item_instance_id"]))
			assert_true(p.has("window_id"))
			assert_true(p.has("rule_version"))
			assert_true(p.has("assignment_version"))
			assert_true(p.has("matched_rule_ids"))
			assert_true(typeof(p["affinity_match"]) == TYPE_BOOL)
			assert_true(p.has("item_id"))
			assert_true(p.has("score"))
	assert_eq(seats, [0, 1, 2, 3])
	assert_eq(insts.size(), 4)
	var seen := {}
	for iid in insts:
		assert_false(seen.has(iid), "instance_id 必须唯一")
		seen[iid] = true
	assert_eq(server.mode_modules.item_inventory.instance_count(), 4)
	# SETTLED 后紧随 4 grant 再可能 DISARM/OPEN
	var seq_kinds: Array = []
	var after_settle := false
	for ne2 in _events(server):
		if not (ne2 is NetworkedEvent):
			continue
		var k := (ne2 as NetworkedEvent).kind
		if k == "REWARD_WINDOW_SETTLED":
			after_settle = true
			seq_kinds.append(k)
			continue
		if after_settle and k in ["ITEM_GRANTED", "CHARACTER_ABILITY_DISARMED", "REWARD_WINDOW_OPENED", "CHARACTER_ABILITY_ARMED"]:
			seq_kinds.append(k)
	assert_eq(seq_kinds[0], "REWARD_WINDOW_SETTLED")
	assert_eq(seq_kinds[1], "ITEM_GRANTED")
	assert_eq(seq_kinds[2], "ITEM_GRANTED")
	assert_eq(seq_kinds[3], "ITEM_GRANTED")
	assert_eq(seq_kinds[4], "ITEM_GRANTED")


func test_standard_rejects_item_use_mode_forbidden() -> void:
	var server := LocalLoopbackServer.new(_cfg_std(3), 0)
	assert_true(server.start())
	var act: Action = Action.item_use(
		0, "ii_x", str(server.get("_room_id")),
		_cmd(1), _cmd(2), 0, 1
	)
	var cr: CommandResult = server.submit_action(act)
	assert_eq(cr.status, "REJECTED")
	assert_eq(cr.error_code, "MODE_FORBIDDEN")


func test_item_use_immediate_consumable_emits_applied_and_consumed_no_echo() -> void:
	var server := LocalLoopbackServer.new(_cfg_tt_all_human(11), 0)
	assert_true(server.start())
	_drive_until_discard_count(server, 24, 2000)
	_settle_after_24(server)
	assert_eq(server.mode_modules.item_inventory.instance_count(), 4)
	# 优先找即时结算消耗品（wall_peek / wall_collapse）
	var seat_use := -1
	var target_iid := ""
	var target_item := ""
	for s in range(4):
		for inst in server.mode_modules.item_inventory.instances_for_seat(s):
			var ii: ItemInstance = inst as ItemInstance
			if ConsumableFactory.is_immediate_on_use(StringName(ii.item_id)):
				seat_use = s
				target_iid = ii.item_instance_id
				target_item = ii.item_id
				break
		if not target_iid.is_empty():
			break
	if target_iid.is_empty():
		# 无即时件：延迟件 USE 应武装且零 APPLIED
		for s2 in range(4):
			for inst2 in server.mode_modules.item_inventory.instances_for_seat(s2):
				var ii2: ItemInstance = inst2 as ItemInstance
				if ItemInventoryModule.is_battle_consumable(ii2.item_id):
					seat_use = s2
					target_iid = ii2.item_instance_id
					target_item = ii2.item_id
					break
			if not target_iid.is_empty():
				break
	assert_ne(target_iid, "", "奖池须含 battle consumable")
	var bc: BattleController = server.get("_bc") as BattleController
	for ss in range(4):
		bc.decision_context_for_seat(ss)
	var ctx: DecisionContext = bc.decision_context_for_seat(seat_use)
	assert_not_null(ctx, "须有 decision 才能 ITEM_USE")
	var before := server.mode_modules.item_inventory.instance_count()
	var applied_before := _count(_kinds(server), "ITEM_APPLIED")
	var act: Action = Action.item_use(
		seat_use, target_iid, str(server.get("_room_id")),
		_cmd(99001), str(ctx.decision_id), int(ctx.hand_seq), 99001
	)
	var cr: CommandResult = server.submit_action(act)
	assert_eq(cr.status, "ACCEPTED", "code=%s seat=%d item=%s" % [cr.error_code, seat_use, target_item])
	assert_eq(_count(_kinds(server), "ITEM_USE"), 0, "不得有 ITEM_USE 回声")
	if ConsumableFactory.is_immediate_on_use(StringName(target_item)):
		assert_eq(server.mode_modules.item_inventory.instance_count(), before - 1)
		assert_gte(_count(_kinds(server), "ITEM_APPLIED"), applied_before + 1)
		assert_gte(_count(_kinds(server), "ITEM_CONSUMED"), 1)
	else:
		# 延迟：仍持有 armed 实例
		assert_eq(server.mode_modules.item_inventory.instance_count(), before)
		var inst_a: ItemInstance = server.mode_modules.item_inventory.find_instance(target_iid)
		assert_not_null(inst_a)
		assert_eq(inst_a.status, ItemInstance.STATUS_ARMED)
		assert_eq(_count(_kinds(server), "ITEM_APPLIED"), applied_before)
	# 幂等同 command
	var cr2: CommandResult = server.submit_action(act)
	assert_eq(cr2.status, "ACCEPTED")


func test_snapshot_includes_item_inventory_seat_view() -> void:
	var server := LocalLoopbackServer.new(_cfg_tt_all_human(11), 0)
	assert_true(server.start())
	assert_true(server.publish_snapshot())
	var snap: NetworkedEvent = null
	for ne in server.event_journal(0):
		if ne is NetworkedEvent and (ne as NetworkedEvent).kind == "ROOM_SNAPSHOT":
			snap = ne as NetworkedEvent
	assert_not_null(snap)
	var keys: Array = []
	for m in snap.payload.get("modules", []):
		keys.append(str(m.get("module_key", "")))
	assert_true(keys.has("item_inventory"))
	assert_true(keys.has("reward_window"))
	assert_true(keys.has("core_table"))


## P1-1：即时 ITEM_USE → journal 含 APPLIED/CONSUMED + 匹配 ROOM_SNAPSHOT；NBC 原子 ingest 后 core+inventory 一致。
func test_item_use_immediate_emits_matching_snapshot_nbc_atomic() -> void:
	var server := LocalLoopbackServer.new(_cfg_tt_all_human(11), 0)
	assert_true(server.start())
	_drive_until_discard_count(server, 24, 3000)
	_settle_after_24(server)
	var seat_use := -1
	var target_iid := ""
	var target_item := ""
	for s in range(4):
		for inst in server.mode_modules.item_inventory.instances_for_seat(s):
			var ii: ItemInstance = inst as ItemInstance
			if ii.item_id == "wall_peek_v1" or ii.item_id == "wall_collapse_v1":
				seat_use = s
				target_iid = ii.item_instance_id
				target_item = ii.item_id
				break
		if not target_iid.is_empty():
			break
	if target_iid.is_empty():
		# 奖池未分到即时件：强制注入再 USE
		var inv: ItemInventoryModule = server.mode_modules.item_inventory
		var g: Dictionary = inv.grant_for_seat({
			"seat": 0, "item_id": "wall_collapse_v1",
			"window_id": "hand_0_window_force", "hand_seq": 0, "score": 0,
			"rule_version": "rv", "assignment_version": "av",
			"matched_rule_ids": [], "affinity_match": false,
			"match_namespace": str(server.get("_room_id")),
		})
		assert_true(bool(g.get("ok", false)), str(g))
		seat_use = 0
		target_iid = str(g["payload"]["item_instance_id"])
		target_item = "wall_collapse_v1"
	var bc: BattleController = server.get("_bc") as BattleController
	var wall_before: int = bc.state.wall.live_wall_size()
	for ss in range(4):
		bc.decision_context_for_seat(ss)
	var ctx: DecisionContext = bc.decision_context_for_seat(seat_use)
	assert_not_null(ctx)
	var seq0: int = int(server.get("_server_seq"))
	var inv_before_view = server.mode_modules.item_inventory.instance_count()
	var act: Action = Action.item_use(
		seat_use, target_iid, str(server.get("_room_id")),
		_cmd(88001), str(ctx.decision_id), int(ctx.hand_seq), 88001
	)
	var cr: CommandResult = server.submit_action(act)
	assert_eq(cr.status, "ACCEPTED", "code=%s item=%s" % [cr.error_code, target_item])
	# 终态：APPLIED + CONSUMED + ROOM_SNAPSHOT 连续且 view_hash 对齐
	var journal: Array = server.event_journal(seat_use)
	var applied_ne: NetworkedEvent = null
	var consumed_ne: NetworkedEvent = null
	var snap_ne: NetworkedEvent = null
	for i in range(journal.size() - 1, -1, -1):
		var ne: NetworkedEvent = journal[i] as NetworkedEvent
		if ne == null:
			continue
		if ne.kind == "ROOM_SNAPSHOT" and snap_ne == null and int(ne.server_seq) > seq0:
			snap_ne = ne
		elif ne.kind == "ITEM_CONSUMED" and consumed_ne == null and int(ne.server_seq) > seq0:
			consumed_ne = ne
		elif ne.kind == "ITEM_APPLIED" and applied_ne == null and int(ne.server_seq) > seq0:
			applied_ne = ne
	assert_not_null(applied_ne, "须发 ITEM_APPLIED")
	assert_not_null(consumed_ne, "须发 ITEM_CONSUMED")
	assert_not_null(snap_ne, "即时 USE 后须匹配 ROOM_SNAPSHOT")
	assert_eq(applied_ne.view_hash, snap_ne.view_hash, "APPLIED 与 SNAP 同终态 hash")
	assert_eq(consumed_ne.view_hash, snap_ne.view_hash, "CONSUMED 与 SNAP 同终态 hash")
	assert_eq(int(consumed_ne.server_seq), int(applied_ne.server_seq) + 1)
	assert_eq(int(snap_ne.server_seq), int(consumed_ne.server_seq) + 1)
	if target_item == "wall_collapse_v1":
		assert_eq(bc.state.wall.live_wall_size(), maxi(0, wall_before - 10))
	assert_eq(server.mode_modules.item_inventory.instance_count(), inv_before_view - 1)
	# NBC 原子路径：committed 停在 APPLIED-1；异 hash 双事件 pending；终态 SNAP 一次提交
	var nbc := NetworkedBattleController.new(str(server.get("_room_id")), seat_use)
	nbc.configure_snapshot_registry_for_mode(str(GameSessionConfig.MODE_TRASH_TALK))
	nbc.set("_current_seq", int(applied_ne.server_seq) - 1)
	nbc.set("_view_hash", "0".repeat(64))
	nbc.set("_applied_modules", {})
	var mid_inv := JSON.stringify(nbc.get_item_inventory_view())
	assert_true(nbc.ingest_networked_event(applied_ne), "APPLIED 进 pending")
	assert_eq(JSON.stringify(nbc.get_item_inventory_view()), mid_inv, "pending 不得半投影")
	assert_true(nbc.ingest_networked_event(consumed_ne), "CONSUMED 同 hash 入队")
	assert_eq(JSON.stringify(nbc.get_item_inventory_view()), mid_inv, "双 pending 仍不得半投影")
	assert_true(nbc.ingest_networked_event(snap_ne), "匹配 SNAP 原子提交")
	assert_false(nbc.resync_required())
	var inv_view: Dictionary = nbc.get_item_inventory_view()
	assert_false(inv_view.is_empty(), "须有 item_inventory 投影")
	for it in inv_view.get("items", []):
		assert_ne(str(it.get("item_instance_id", "")), target_iid, "已消费实例不得残留投影")
	var core: Dictionary = nbc.get_core_table_view()
	assert_false(core.is_empty())


## P1-1：异 hash 事件在匹配 SNAP 前不得污染 get_item_inventory_view。
func test_nbc_item_pending_no_half_inventory_until_snapshot() -> void:
	var server := LocalLoopbackServer.new(_cfg_tt_all_human(13), 0)
	assert_true(server.start())
	var base_snap: NetworkedEvent = null
	for ne in server.event_journal(0):
		if ne is NetworkedEvent and (ne as NetworkedEvent).kind == "ROOM_SNAPSHOT":
			base_snap = ne as NetworkedEvent
	assert_not_null(base_snap)
	var nbc2 := NetworkedBattleController.new(str(server.get("_room_id")), 0)
	nbc2.configure_snapshot_registry_for_mode(str(GameSessionConfig.MODE_TRASH_TALK))
	assert_true(nbc2.ingest_networked_event(base_snap))
	var before: Dictionary = nbc2.get_item_inventory_view()
	var before_json := JSON.stringify(before)
	# 合法 ITEM_GRANTED payload + 异 hash（不跟 SNAP）
	var grant_pl := {
		"window_id": "hand_0_window_0",
		"rule_version": "trash_talk_rules_v1",
		"assignment_version": "assign_v1",
		"matched_rule_ids": [],
		"item_id": "iron_shield_v1",
		"item_instance_id": "ii_fake_pending_s0_iron_shield_v1",
		"seat": 0,
		"hand_seq": 0,
		"score": 1,
		"affinity_match": false,
		"armed_for_window_id": null,
	}
	var fake_vh := "a".repeat(64)
	var grant_ev: NetworkedEvent = NetworkedEvent.make(
		"ITEM_GRANTED", int(base_snap.server_seq) + 1,
		str(server.get("_room_id")), grant_pl, fake_vh
	)
	assert_not_null(grant_ev, "ITEM_GRANTED envelope 须合法")
	assert_true(nbc2.ingest_networked_event(grant_ev), "异 hash 应进 pending")
	assert_eq(JSON.stringify(nbc2.get_item_inventory_view()), before_json,
		"pending 期间库存投影不得半更新")
	# 合法 SNAP envelope 但 view_hash 与 pending 不匹配 → resync；库存仍旧
	var bad_snap_pl: Dictionary = base_snap.payload.duplicate(true)
	bad_snap_pl["snapshot_server_seq"] = int(base_snap.server_seq) + 2
	bad_snap_pl["next_server_seq"] = int(base_snap.server_seq) + 3
	var real_vh: String = ProtocolViewCodec.compute_view_hash(bad_snap_pl)
	assert_eq(real_vh.length(), 64)
	# 故意用与 payload 一致的 hash，但与 pending 的 fake_vh 不同
	assert_ne(real_vh, fake_vh)
	var bad_snap: NetworkedEvent = NetworkedEvent.make(
		"ROOM_SNAPSHOT", int(base_snap.server_seq) + 2,
		str(server.get("_room_id")), bad_snap_pl, real_vh
	)
	assert_not_null(bad_snap, "mismatch SNAP envelope 须合法")
	assert_false(nbc2.ingest_networked_event(bad_snap), "pending 不匹配须拒绝")
	assert_true(nbc2.resync_required())
	assert_eq(JSON.stringify(nbc2.get_item_inventory_view()), before_json)


## P2-4.4：同 item_id 双实例经真实 ITEM_USE，各自只消费指定实例。
func test_dual_instance_item_use_independent() -> void:
	var server := LocalLoopbackServer.new(_cfg_tt_all_human(19), 0)
	assert_true(server.start())
	var inv: ItemInventoryModule = server.mode_modules.item_inventory
	var g1: Dictionary = inv.grant_for_seat({
		"seat": 0, "item_id": "wall_collapse_v1",
		"window_id": "hand_0_window_0", "hand_seq": 0, "score": 0,
		"rule_version": "rv", "assignment_version": "av",
		"matched_rule_ids": [], "affinity_match": false,
		"match_namespace": str(server.get("_room_id")),
	})
	var g2: Dictionary = inv.grant_for_seat({
		"seat": 0, "item_id": "wall_collapse_v1",
		"window_id": "hand_0_window_1", "hand_seq": 0, "score": 0,
		"rule_version": "rv", "assignment_version": "av",
		"matched_rule_ids": [], "affinity_match": false,
		"match_namespace": str(server.get("_room_id")),
	})
	assert_true(bool(g1.get("ok", false)))
	assert_true(bool(g2.get("ok", false)))
	var iid1 := str(g1["payload"]["item_instance_id"])
	var iid2 := str(g2["payload"]["item_instance_id"])
	assert_ne(iid1, iid2)
	var bc: BattleController = server.get("_bc") as BattleController
	for s in range(4):
		bc.decision_context_for_seat(s)
	var ctx: DecisionContext = bc.decision_context_for_seat(0)
	var cr1: CommandResult = server.submit_action(Action.item_use(
		0, iid1, str(server.get("_room_id")),
		_cmd(77001), str(ctx.decision_id), int(ctx.hand_seq), 77001
	))
	assert_eq(cr1.status, "ACCEPTED", cr1.error_code)
	assert_null(inv.find_instance(iid1))
	assert_not_null(inv.find_instance(iid2))
	for s2 in range(4):
		bc.decision_context_for_seat(s2)
	ctx = bc.decision_context_for_seat(0)
	var cr2: CommandResult = server.submit_action(Action.item_use(
		0, iid2, str(server.get("_room_id")),
		_cmd(77002), str(ctx.decision_id), int(ctx.hand_seq), 77002
	))
	assert_eq(cr2.status, "ACCEPTED", cr2.error_code)
	assert_null(inv.find_instance(iid2))


## P2-4.7：席快照不泄露他席库存。
func test_seat_snapshot_hides_other_seats_items() -> void:
	var inv := ItemInventoryModule.new()
	inv.set_match_namespace("iso")
	inv.grant_for_seat({
		"seat": 0, "item_id": "iron_shield_v1", "window_id": "w0",
		"hand_seq": 0, "score": 1, "rule_version": "rv",
		"assignment_version": "av", "matched_rule_ids": [], "affinity_match": false,
	})
	inv.grant_for_seat({
		"seat": 1, "item_id": "wall_peek_v1", "window_id": "w0",
		"hand_seq": 0, "score": 2, "rule_version": "rv",
		"assignment_version": "av", "matched_rule_ids": [], "affinity_match": false,
	})
	var dto0: Dictionary = inv.to_seat_snapshot_dto(0)
	var items0: Array = dto0["payload"]["items"]
	assert_eq(items0.size(), 1)
	assert_eq(int(items0[0]["seat"]), 0)
	assert_eq(str(items0[0]["item_id"]), "iron_shield_v1")
	var blob := JSON.stringify(dto0)
	assert_false(blob.contains("wall_peek_v1"))
	assert_false(blob.contains("ii_iso_w0_s1"))
