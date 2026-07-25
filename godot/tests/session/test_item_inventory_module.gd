extends GutTest

# E5-05 / #253：库存/授予/武装纯逻辑 Red→Green。


func test_grant_full_seat_order_and_unique_instance_ids() -> void:
	var inv := ItemInventoryModule.new()
	inv.set_match_namespace("sess_t1")
	var settled := {
		"outcome": "FULL_GRANT",
		"grant_count": 4,
		"window_id": "hand_0_window_0",
		"hand_seq": 0,
		"rule_version": "trash_talk_rules_v1",
		"assignment_version": "assign_v1",
		"assignment": {
			"0": "iron_shield_v1",
			"1": "wall_peek_v1",
			"2": "double_payout_v1",
			"3": "dora_charm_v1",
		},
	}
	var chars := ["lin_yeche", "qiu_jue", "bai_touli", "hua_ling"]
	var gr: Dictionary = ItemAuthority.grant_full_from_settled(
		inv, settled, [], chars, "hand_0_window_1", false, "sess_t1"
	)
	assert_true(bool(gr.get("ok", false)), "grant 须成功: %s" % str(gr))
	assert_eq(inv.instance_count(), 4)
	var seats: Array = []
	for g in gr["grants"]:
		var pl: Dictionary = g["payload"]
		seats.append(int(pl["seat"]))
		assert_eq(
			str(pl["item_instance_id"]),
			ItemInstance.make_instance_id(
				"sess_t1", "hand_0_window_0", int(pl["seat"]), str(pl["item_id"])
			)
		)
	assert_eq(seats, [0, 1, 2, 3])


func test_display_only_and_cancel_zero_grants() -> void:
	var inv := ItemInventoryModule.new()
	var display := {
		"outcome": "DISPLAY_ONLY",
		"grant_count": 0,
		"window_id": "hand_0_window_0",
		"hand_seq": 0,
		"assignment": {},
	}
	var gr: Dictionary = ItemAuthority.grant_full_from_settled(
		inv, display, [], ["lin_yeche", "qiu_jue", "bai_touli", "hua_ling"], "hand_0_window_1"
	)
	assert_false(bool(gr.get("ok", false)))
	assert_eq(inv.instance_count(), 0)
	var cancelled := {
		"outcome": "CANCELLED_BY_WIN",
		"grant_count": 0,
		"window_id": "hand_0_window_0",
		"hand_seq": 0,
		"assignment": {},
	}
	var gr2: Dictionary = ItemAuthority.grant_full_from_settled(
		inv, cancelled, [], ["lin_yeche", "qiu_jue", "bai_touli", "hua_ling"], "hand_0_window_1"
	)
	assert_false(bool(gr2.get("ok", false)))
	assert_eq(inv.instance_count(), 0)


## P2-3：seat0/1 成功后 seat2 失败 → 撤销先前 grant（非 seat0 首步失败）。
func test_grant_full_mid_seat_failure_rolls_back_all() -> void:
	var inv := ItemInventoryModule.new()
	inv.set_match_namespace("sess_rb")
	assert_eq(inv.instance_count(), 0)
	var settled := {
		"outcome": "FULL_GRANT",
		"grant_count": 4,
		"window_id": "hand_0_window_0",
		"hand_seq": 0,
		"rule_version": "rv",
		"assignment_version": "av",
		"assignment": {
			"0": "iron_shield_v1",
			"1": "wall_peek_v1",
			# seat2 非 grantable：循环已写入 seat0/1 后在 seat2 失败
			"2": "seat_swap_v1",
			"3": "dora_charm_v1",
		},
	}
	var gr: Dictionary = ItemAuthority.grant_full_from_settled(
		inv, settled, [], ["lin_yeche", "qiu_jue", "bai_touli", "hua_ling"],
		"hand_0_window_1", false, "sess_rb"
	)
	assert_false(bool(gr.get("ok", false)), "seat2 失败须整体失败: %s" % str(gr))
	assert_eq(str(gr.get("reason", "")), "NOT_GRANTABLE")
	# 不得残留 seat0/1 已成功写入
	assert_eq(inv.instance_count(), 0)
	assert_eq(inv.instances_for_seat(0).size(), 0)
	assert_eq(inv.instances_for_seat(1).size(), 0)
	assert_eq(inv.instances_for_seat(2).size(), 0)
	assert_eq(inv.instances_for_seat(3).size(), 0)
	assert_null(inv.pending_window_id(0))
	assert_null(inv.pending_window_id(1))


func test_dual_same_item_id_two_instances() -> void:
	var inv := ItemInventoryModule.new()
	inv.set_match_namespace("sess_dual")
	var g1: Dictionary = inv.grant_for_seat({
		"seat": 0,
		"item_id": "iron_shield_v1",
		"window_id": "hand_0_window_0",
		"hand_seq": 0,
		"score": 10,
		"rule_version": "rv",
		"assignment_version": "assign_v1",
		"matched_rule_ids": [],
		"affinity_match": false,
	})
	assert_true(bool(g1.get("ok", false)))
	var g2: Dictionary = inv.grant_for_seat({
		"seat": 0,
		"item_id": "iron_shield_v1",
		"window_id": "hand_0_window_1",
		"hand_seq": 0,
		"score": 20,
		"rule_version": "rv",
		"assignment_version": "assign_v1",
		"matched_rule_ids": [],
		"affinity_match": false,
	})
	assert_true(bool(g2.get("ok", false)))
	assert_eq(inv.instance_count(), 2)
	var a: String = str(g1["payload"]["item_instance_id"])
	var b: String = str(g2["payload"]["item_instance_id"])
	assert_ne(a, b)
	assert_eq(inv.instances_for_seat(0).size(), 2)
	# 精确消耗一个
	var c: Dictionary = inv.consume_instance(a, 0)
	assert_true(bool(c.get("ok", false)))
	assert_eq(inv.instance_count(), 1)
	assert_not_null(inv.find_instance(b))
	assert_null(inv.find_instance(a))


func test_affinity_match_registers_pending_only() -> void:
	var inv := ItemInventoryModule.new()
	inv.set_match_namespace("sess_aff")
	var ok: Dictionary = inv.grant_for_seat({
		"seat": 0,
		"item_id": "wall_peek_v1",
		"window_id": "hand_0_window_0",
		"hand_seq": 0,
		"score": 100,
		"rule_version": "rv",
		"assignment_version": "assign_v1",
		"matched_rule_ids": ["r1"],
		"affinity_match": true,
		"next_window_id": "hand_0_window_1",
	})
	assert_true(bool(ok.get("ok", false)))
	assert_eq(str(inv.pending_window_id(0)), "hand_0_window_1")
	assert_null(inv.active_window_id(0))
	var bad: Dictionary = inv.grant_for_seat({
		"seat": 0,
		"item_id": "iron_shield_v1",
		"window_id": "hand_0_window_0b",
		"hand_seq": 0,
		"score": 1,
		"rule_version": "rv",
		"assignment_version": "assign_v1",
		"matched_rule_ids": [],
		"affinity_match": true,
		"next_window_id": "hand_0_window_2",
	})
	assert_false(bool(bad.get("ok", false)))
	assert_eq(str(bad.get("reason", "")), ItemInventoryModule.ERR_INVARIANT)


func test_open_arm_then_disarm_keeps_next_pending() -> void:
	var inv := ItemInventoryModule.new()
	inv.set_match_namespace("sess_arm")
	assert_true(bool(inv.grant_for_seat({
		"seat": 1,
		"item_id": "wall_peek_v1",
		"window_id": "hand_0_window_0",
		"hand_seq": 0,
		"score": 0,
		"rule_version": "rv",
		"assignment_version": "av",
		"matched_rule_ids": [],
		"affinity_match": true,
		"next_window_id": "hand_0_window_1",
	}).get("ok", false)))
	var arm: Dictionary = inv.try_arm_on_open(1, "hand_0_window_1")
	assert_true(bool(arm.get("armed", false)))
	assert_eq(str(inv.active_window_id(1)), "hand_0_window_1")
	assert_null(inv.pending_window_id(1))
	assert_true(bool(inv.grant_for_seat({
		"seat": 1,
		"item_id": "dora_charm_v1",
		"window_id": "hand_0_window_1",
		"hand_seq": 0,
		"score": 0,
		"rule_version": "rv",
		"assignment_version": "av",
		"matched_rule_ids": [],
		"affinity_match": true,
		"next_window_id": "hand_0_window_2",
	}).get("ok", false)))
	assert_eq(str(inv.pending_window_id(1)), "hand_0_window_2")
	var dis: Dictionary = inv.disarm_active(1)
	assert_true(bool(dis.get("was_armed", false)))
	assert_null(inv.active_window_id(1))
	assert_eq(str(inv.pending_window_id(1)), "hand_0_window_2", "DISARM 不得清 next pending")


func test_match_clear_wipes_inventory_and_arm() -> void:
	var inv := ItemInventoryModule.new()
	inv.set_match_namespace("sess_clr")
	inv.grant_for_seat({
		"seat": 0, "item_id": "iron_shield_v1", "window_id": "w0",
		"hand_seq": 0, "score": 0, "rule_version": "rv",
		"assignment_version": "av", "matched_rule_ids": [],
		"affinity_match": true, "next_window_id": "w1",
	})
	inv.try_arm_on_open(0, "w1")
	inv.clear_match()
	assert_eq(inv.instance_count(), 0)
	assert_null(inv.active_window_id(0))
	assert_null(inv.pending_window_id(0))


func test_seat_snapshot_isolation_and_round_trip() -> void:
	var inv := ItemInventoryModule.new()
	inv.set_match_namespace("sess_snap")
	inv.grant_for_seat({
		"seat": 0, "item_id": "iron_shield_v1", "window_id": "w0",
		"hand_seq": 0, "score": 5, "rule_version": "rv",
		"assignment_version": "av", "matched_rule_ids": [], "affinity_match": false,
	})
	inv.grant_for_seat({
		"seat": 1, "item_id": "wall_peek_v1", "window_id": "w0",
		"hand_seq": 0, "score": 7, "rule_version": "rv",
		"assignment_version": "av", "matched_rule_ids": [],
		"affinity_match": true, "next_window_id": "w1",
	})
	var dto0: Dictionary = inv.to_seat_snapshot_dto(0)
	var pl0: Dictionary = dto0["payload"]
	assert_eq(int(pl0["seat"]), 0)
	assert_eq((pl0["items"] as Array).size(), 1)
	assert_eq(str((pl0["items"] as Array)[0]["item_id"]), "iron_shield_v1")
	# 席 0 不得见席 1
	for it in pl0["items"]:
		assert_eq(int(it["seat"]), 0)

	var inv2 := ItemInventoryModule.new()
	assert_true(inv2.restore_seat_snapshot_payload(pl0, 0))
	assert_eq(inv2.instance_count(), 1)
	assert_eq(inv2.instances_for_seat(0).size(), 1)


func test_gold_instance_id_fixture_byte_stable() -> void:
	var fx: Dictionary = ItemInventoryGoldFixtures.gold_instance_id_formula()
	for seat in range(4):
		var item_id: String = String(ItemInventoryGoldFixtures.GOLD_ASSIGNMENT[str(seat)])
		var got := ItemInstance.make_instance_id(
			ItemInventoryGoldFixtures.MATCH_NS,
			ItemInventoryGoldFixtures.WINDOW_ID, seat, item_id
		)
		assert_eq(got, str(fx["expected_instance_ids"][str(seat)]))
		assert_eq(got, str(ItemInventoryGoldFixtures.GOLD_INSTANCE_IDS[str(seat)]))
	# expected 必须为硬编码字面量（与 GOLD_INSTANCE_IDS 字节一致）
	assert_eq(
		JSON.stringify(fx["expected_instance_ids"]),
		JSON.stringify(ItemInventoryGoldFixtures.GOLD_INSTANCE_IDS)
	)


func test_gold_public_event_trace_literal_kinds() -> void:
	# 合法生产流：SETTLED FULL_GRANT + 4 grant + HAND + MATCH
	var events: Array = ItemInventoryGoldFixtures.gold_public_networked_events()
	assert_gt(events.size(), 0)
	var kinds: Dictionary = {}
	for ev in events:
		var k := str(ev["kind"])
		kinds[k] = int(kinds.get(k, 0)) + 1
	assert_eq(int(kinds.get("REWARD_WINDOW_SETTLED", 0)), 1)
	assert_eq(int(kinds.get("ITEM_GRANTED", 0)), 4)
	assert_eq(int(kinds.get("ITEM_APPLIED", 0)), 1)
	assert_eq(int(kinds.get("ITEM_CONSUMED", 0)), 1)
	assert_eq(int(kinds.get("HAND_SETTLED", 0)), 1)
	assert_eq(int(kinds.get("MATCH_SETTLED", 0)), 1)
	assert_gte(int(kinds.get("ROOM_SNAPSHOT", 0)), 2)
	assert_eq(str(events[0]["room_id"]), ItemInventoryGoldFixtures.ROOM_ID)



func test_delayed_use_arms_without_applied_until_trigger() -> void:
	var inv := ItemInventoryModule.new()
	inv.set_match_namespace("sess_delay")
	var g: Dictionary = inv.grant_for_seat({
		"seat": 0, "item_id": "iron_shield_v1", "window_id": "w0",
		"hand_seq": 0, "score": 0, "rule_version": "rv",
		"assignment_version": "av", "matched_rule_ids": [], "affinity_match": false,
	})
	assert_true(bool(g.get("ok", false)))
	var iid := str(g["payload"]["item_instance_id"])
	var bc := BattleController.new(1, 0, false, TileId.E, 0)
	var use: Dictionary = ItemAuthority.use_item(
		bc, inv, 0, iid, "550e8400-e29b-41d4-a716-0000000000d1"
	)
	assert_true(bool(use.get("accepted", false)), str(use))
	assert_eq((use.get("events", []) as Array).size(), 0, "延迟武装不得立即 APPLIED/CONSUMED")
	assert_eq(inv.instance_count(), 1)
	var inst: ItemInstance = inv.find_instance(iid)
	assert_not_null(inst)
	assert_eq(inst.status, ItemInstance.STATUS_ARMED)
	# 模拟 hook 触发
	var sk: SkillResource = inv.registered_skill(iid)
	assert_not_null(sk)
	sk.consumed = true
	var fin: Dictionary = ItemAuthority.finalize_triggered(bc, inv)
	assert_true(bool(fin.get("ok", false)))
	assert_eq((fin.get("events", []) as Array).size(), 2)
	assert_eq(inv.instance_count(), 0)


func test_cross_session_instance_ids_differ() -> void:
	var a := ItemInstance.make_instance_id("room_a", "hand_0_window_0", 0, "iron_shield_v1")
	var b := ItemInstance.make_instance_id("room_b", "hand_0_window_0", 0, "iron_shield_v1")
	assert_ne(a, b)
	assert_true(a.begins_with("ii_room_a_"))
	assert_true(b.begins_with("ii_room_b_"))


func test_scheduler_multi_instance_same_item_id_both_fire() -> void:
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	var sk1: SkillResource = RelicFactory.build_for_instance(
		&"relic_lucky_cat_v1", "ii_a"
	)
	var sk2: SkillResource = RelicFactory.build_for_instance(
		&"relic_lucky_cat_v1", "ii_b"
	)
	assert_not_null(sk1)
	assert_not_null(sk2)
	reg.register(sk1, 0)
	reg.register(sk2, 0)
	sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_eq(st.extra_dora_count[0], 2, "同 item_id 双实例须各触发一次")


func test_compute_affinity_match_primary_secondary() -> void:
	# lin_yeche: CUNNING / MYSTIC
	assert_true(ItemInventoryModule.compute_affinity_match(&"lin_yeche", "wall_peek_v1"))
	assert_false(ItemInventoryModule.compute_affinity_match(&"lin_yeche", "iron_shield_v1"))


## P2-5：将 arm 却缺 skill → fail-closed，不得留下 active。
func test_arm_seats_missing_skill_fail_closed() -> void:
	var inv := ItemInventoryModule.new()
	inv.set_match_namespace("arm_fc")
	assert_true(bool(inv.grant_for_seat({
		"seat": 0, "item_id": "wall_peek_v1", "window_id": "w0",
		"hand_seq": 0, "score": 0, "rule_version": "rv",
		"assignment_version": "av", "matched_rule_ids": [],
		"affinity_match": true, "next_window_id": "w1",
	}).get("ok", false)))
	var empty_slots: Array = [null, null, null, null]
	var r: Dictionary = ItemAuthority.arm_seats_on_open(
		null, inv, empty_slots, "w1"
	)
	assert_false(bool(r.get("ok", false)))
	assert_eq(str(r.get("reason", "")), "MISSING_SLOT_SKILL")
	assert_null(inv.active_window_id(0), "失败不得留下 active")
	assert_eq(str(inv.pending_window_id(0)), "w1", "回滚后 pending 保留")


## P2-4.3：12 角色被动 SkillResource 均可 build，params 含 ability 身份且默认未 consumed。
func test_twelve_character_passive_skill_resources() -> void:
	var ids: Array = [
		&"char_akagi_passive_v1", &"char_kaiji_passive_v1", &"char_washizu_passive_v1",
		&"char_saki_passive_v1", &"char_teru_passive_v1", &"char_awai_passive_v1",
		&"char_koromo_passive_v1", &"char_nodoka_passive_v1", &"char_toki_passive_v1",
		&"char_kuro_passive_v1", &"char_momoko_passive_v1", &"char_tetsuya_passive_v1",
	]
	assert_eq(ids.size(), 12)
	for aid in ids:
		var sk: SkillResource = BossAbilityFactory.build(aid)
		assert_not_null(sk, "须能构建 %s" % String(aid))
		assert_eq(sk.id, aid)
		assert_false(sk.consumed, "%s 默认未 consumed" % String(aid))
		assert_true(typeof(sk.params) == TYPE_DICTIONARY)


## P2-5：seat DTO 保留 armed status，restore 后不得当 held 重复 USE。
func test_seat_snapshot_preserves_armed_status() -> void:
	var inv := ItemInventoryModule.new()
	inv.set_match_namespace("st_arm")
	var g: Dictionary = inv.grant_for_seat({
		"seat": 0, "item_id": "iron_shield_v1", "window_id": "w0",
		"hand_seq": 0, "score": 0, "rule_version": "rv",
		"assignment_version": "av", "matched_rule_ids": [], "affinity_match": false,
	})
	assert_true(bool(g.get("ok", false)))
	var iid := str(g["payload"]["item_instance_id"])
	assert_true(bool(inv.mark_armed(iid, 0, "550e8400-e29b-41d4-a716-0000000000a1").get("ok", false)))
	var dto: Dictionary = inv.to_seat_snapshot_dto(0)
	assert_eq(str(dto["payload"]["items"][0]["status"]), "armed")
	var inv2 := ItemInventoryModule.new()
	assert_true(inv2.restore_seat_snapshot_payload(dto["payload"], 0))
	var inst2: ItemInstance = inv2.find_instance(iid)
	assert_not_null(inst2)
	assert_eq(inst2.status, ItemInstance.STATUS_ARMED)
