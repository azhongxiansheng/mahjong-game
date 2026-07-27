extends GutTest

# #253 道具权威回放 / 黄金流 / STANDARD 隔离 / provider。
# 承接原 round5–8 中 schema/NBC/黄金 fixture 验收。

const CHARS := [&"lin_yeche", &"qiu_jue", &"bai_touli", &"hua_ling"]
const PARTS_ALL_H := [&"HUMAN", &"HUMAN", &"HUMAN", &"HUMAN"]
const PARTS_MIX := [&"HUMAN", &"AI", &"AI", &"AI"]


func _cfg_tt(p_seed: int, sid: String) -> GameSessionConfig:
	return GameSessionConfig.create_validated(
		GameSessionConfig.ROOM_PUBLIC_CASUAL, GameSessionConfig.ROUND_EAST,
		GameSessionConfig.MODE_TRASH_TALK, PARTS_ALL_H, CHARS, p_seed, sid, "rv-253"
	)


func _cfg_practice(p_seed: int, sid: String) -> GameSessionConfig:
	return GameSessionConfig.create_validated(
		GameSessionConfig.ROOM_PRACTICE, GameSessionConfig.ROUND_EAST,
		GameSessionConfig.MODE_TRASH_TALK, PARTS_MIX, CHARS, p_seed, sid, "rv-253"
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


func _drive_until_discard_count(server: LocalLoopbackServer, target: int, cmd_base: int = 1000) -> void:
	var rw: RewardWindowModule = server.mode_modules.reward_window
	var n: int = cmd_base
	var guard := 0
	while rw.discard_count < target:
		guard += 1
		assert_lt(guard, 160)
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
				if not dw.has_responded(int(seat_i)):
					target_seat = int(seat_i)
					break
			var ctx: DecisionContext = dw.context_for_seat(target_seat)
			assert_eq(server.submit_action(Action.make_pass(
				target_seat, str(server.get("_room_id")), _cmd(n),
				str(ctx.decision_id), int(ctx.hand_seq), n
			)).status, "ACCEPTED")
			n += 1
			continue
		if dw.kind == DecisionWindow.KIND_TURN:
			var actor: int = int(dw.subject_seat)
			var tctx: DecisionContext = dw.context_for_seat(actor)
			var iid := -1
			for o in tctx.allowed_actions:
				if typeof(o) == TYPE_DICTIONARY and str(o.get("kind", "")) == "DISCARD":
					iid = int((o.get("payload_options", []) as Array)[0]["tile_instance_id"])
					break
			assert_gt(iid, -1)
			assert_eq(server.submit_action(Action.discard(
				actor, iid, str(server.get("_room_id")), _cmd(n),
				str(tctx.decision_id), int(tctx.hand_seq), n
			)).status, "ACCEPTED")
			n += 1


func _settle_closing_full_grant(server: LocalLoopbackServer, cmd_base: int = 9000) -> void:
	var rw: RewardWindowModule = server.mode_modules.reward_window
	var n := cmd_base
	var guard := 0
	while rw.phase == RewardWindowModule.PHASE_CLOSING and guard < 50:
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
				for seat_i in dw.seats():
					if dw.has_responded(int(seat_i)):
						continue
					var ctx: DecisionContext = dw.context_for_seat(int(seat_i))
					assert_eq(server.submit_action(Action.make_pass(
						int(seat_i), str(server.get("_room_id")), _cmd(n),
						str(ctx.decision_id), int(ctx.hand_seq), n
					)).status, "ACCEPTED")
					n += 1
					break
				continue
		if not rw.barrier_released(server._reward_now_ms()):
			assert_true(server.advance_reward_time(int(rw._grace_deadline_ms)))
			continue
		assert_true(server.advance_reward_time(server._reward_now_ms() + 1))


func _inject_seat0_score_utterance(server: LocalLoopbackServer, utt_id: String) -> void:
	var rw: RewardWindowModule = server.mode_modules.reward_window
	assert_eq(rw.phase, RewardWindowModule.PHASE_OPEN, "须在 OPEN 注入 utterance")
	var ptt: int = maxi(1, int(server.current_server_seq()))
	# 仅 wall_peek 标签（勿夹 double_payout 的「倍率券/碾压」等更高分 pattern）
	var ing: Dictionary = rw.ingest_utterance({
		"seat": 0,
		"utterance_id": utt_id,
		"text": "千里眼透视牌墙",
		"language": "zh",
		"ptt_end_server_seq": ptt,
		"terminal": true,
	})
	assert_true(bool(ing.get("accepted", false)), "utterance 注入须 accepted: %s" % str(ing))


func _seat0_held_battle(inv: ItemInventoryModule) -> ItemInstance:
	for inst_v in inv.instances_for_seat(0):
		if not (inst_v is ItemInstance):
			continue
		var ii: ItemInstance = inst_v as ItemInstance
		if ii.status == ItemInstance.STATUS_HELD \
				and ItemInventoryModule.is_battle_consumable(ii.item_id):
			return ii
	return null


func _canon_journal(server: LocalLoopbackServer, seat: int = 0) -> String:
	var arr: Array = []
	for ne in server.event_journal(seat):
		if ne is NetworkedEvent:
			arr.append((ne as NetworkedEvent).to_dict())
	return JSON.stringify(arr)


## 推进至 seat0 有 decision（HUMAN+3AI 路径）；失败返回 null。
func _ensure_decision_seat0(server: LocalLoopbackServer, cmd_base: int = 11000) -> DecisionContext:
	var n: int = cmd_base
	var guard := 0
	while guard < 40:
		guard += 1
		var bc: BattleController = server.get("_bc") as BattleController
		if bool(bc.get("_settled")):
			return null
		for s in range(4):
			bc.decision_context_for_seat(s)
		var ctx0: DecisionContext = bc.decision_context_for_seat(0)
		if ctx0 != null:
			return ctx0
		var win = bc.get("_active_window")
		if not (win is DecisionWindow):
			return null
		var dw: DecisionWindow = win as DecisionWindow
		if dw.kind == DecisionWindow.KIND_CLAIM or dw.kind == DecisionWindow.KIND_ROB_KAN:
			var ts := -1
			for seat_i in dw.seats():
				if not dw.has_responded(int(seat_i)):
					ts = int(seat_i)
					break
			if ts < 0:
				return null
			var cpass: DecisionContext = dw.context_for_seat(ts)
			assert_eq(server.submit_action(Action.make_pass(
				ts, str(server.get("_room_id")), _cmd(n),
				str(cpass.decision_id), int(cpass.hand_seq), n
			)).status, "ACCEPTED")
			n += 1
			continue
		if dw.kind == DecisionWindow.KIND_TURN:
			var actor: int = int(dw.subject_seat)
			if actor != 0:
				return null
			var tctx: DecisionContext = dw.context_for_seat(actor)
			var tile_iid := -1
			for o in tctx.allowed_actions:
				if typeof(o) == TYPE_DICTIONARY and str(o.get("kind", "")) == "DISCARD":
					tile_iid = int((o.get("payload_options", []) as Array)[0]["tile_instance_id"])
					break
			assert_gt(tile_iid, -1)
			assert_eq(server.submit_action(Action.discard(
				actor, tile_iid, str(server.get("_room_id")), _cmd(n),
				str(tctx.decision_id), int(tctx.hand_seq), n
			)).status, "ACCEPTED")
			n += 1
			continue
		return null
	return null


## P2-1：黄金流合法生产序 + FULL_GRANT payload + E5 偏序 + NBC 零 resync。
func test_gold_stream_is_valid_production_order_and_nbc() -> void:
	var events: Array = ItemInventoryGoldFixtures.gold_public_networked_events()
	assert_gt(events.size(), 0)
	var snap_hashes: Dictionary = {}
	var business: Array = []
	var prev_seq := 0
	var grant_n := 0
	var grant_items: Dictionary = {}
	var settled_outcome := ""
	var settled_grant_count := -1
	var settled_assignment: Dictionary = {}
	for raw0 in events:
		var d0: Dictionary = raw0
		var seq0: int = int(d0.get("server_seq", -1))
		assert_eq(seq0, prev_seq + 1)
		prev_seq = seq0
		var ne0: NetworkedEvent = NetworkedEvent.from_dict(d0)
		assert_not_null(ne0, "kind=%s" % d0.get("kind"))
		if str(d0.get("kind", "")) == "ROOM_SNAPSHOT":
			var exp0: String = ProtocolViewCodec.compute_view_hash(ne0.payload)
			assert_eq(str(d0["view_hash"]), exp0)
			snap_hashes[exp0] = true
			# grant 后 SNAP：reward 不得仍伪装 OPEN
			var mods: Array = ne0.payload.get("modules", []) as Array
			var inv_n := 0
			for m in mods:
				if typeof(m) != TYPE_DICTIONARY:
					continue
				var md: Dictionary = m
				if str(md.get("module_key", "")) == "item_inventory":
					inv_n = ((md.get("payload", {}) as Dictionary).get("items", []) as Array).size()
				if str(md.get("module_key", "")) == "reward_window" and inv_n > 0:
					var rwp: Dictionary = md.get("payload", {}) as Dictionary
					assert_eq(str(rwp.get("phase", "")), "SETTLED",
						"持有库存的 SNAP 须为 SETTLED 投影")
					assert_eq(str(rwp.get("window_exit", "")), "FULL_GRANT")
					assert_eq(int(rwp.get("grant_count", -1)), 4)
		else:
			business.append(str(d0["kind"]))
	for raw in events:
		var d: Dictionary = raw
		assert_true(snap_hashes.has(str(d["view_hash"])), "hash 对齐 SNAP kind=%s" % d.get("kind"))
		match str(d.get("kind", "")):
			"REWARD_WINDOW_SETTLED":
				settled_outcome = str(d["payload"].get("outcome", ""))
				settled_grant_count = int(d["payload"].get("grant_count", -1))
				settled_assignment = (d["payload"].get("assignment", {}) as Dictionary).duplicate(true)
			"ITEM_GRANTED":
				grant_n += 1
				grant_items[str(d["payload"].get("seat", -1))] = str(d["payload"].get("item_id", ""))
				assert_eq(
					str(d["payload"].get("item_instance_id", "")),
					str(ItemInventoryGoldFixtures.GOLD_INSTANCE_IDS[str(d["payload"].get("seat", -1))])
				)
			"HAND_SETTLED":
				pass
			"MATCH_SETTLED":
				pass
	assert_eq(settled_outcome, "FULL_GRANT")
	assert_eq(settled_grant_count, 4)
	assert_eq(grant_n, 4)
	assert_eq(JSON.stringify(settled_assignment), JSON.stringify(ItemInventoryGoldFixtures.GOLD_ASSIGNMENT))
	assert_eq(JSON.stringify(grant_items), JSON.stringify(ItemInventoryGoldFixtures.GOLD_ASSIGNMENT))
	# E5：SETTLED 后 4 grant；HAND 在 MATCH 前
	assert_true(business.has("REWARD_WINDOW_SETTLED"))
	assert_true(business.has("HAND_SETTLED"))
	assert_true(business.has("MATCH_SETTLED"))
	assert_lt(business.find("HAND_SETTLED"), business.find("MATCH_SETTLED"))
	assert_lt(business.find("REWARD_WINDOW_SETTLED"), business.find("ITEM_GRANTED"))
	# 等价严格 E5 偏序：SETTLED 后连续 4×ITEM_GRANTED（seat 0..3），HAND 后 MATCH
	var settled_i: int = business.find("REWARD_WINDOW_SETTLED")
	assert_gte(settled_i, 0)
	for gi in range(4):
		assert_eq(str(business[settled_i + 1 + gi]), "ITEM_GRANTED",
			"SETTLED 后第 %d 个业务 kind 须为 ITEM_GRANTED" % (gi + 1))
	# E5EventOrder meta 约束：FULL_GRANT 须恰好 4 grant（脚本无 class_name，preload）
	var E5 = load("res://protocol/e5_event_order.gd")
	var full24: Array = [
		"ACTION_APPLIED", "REWARD_WINDOW_CLOSING", "CLAIM_WINDOW", "ACTION_APPLIED",
		"REWARD_WINDOW_SETTLED",
		"ITEM_GRANTED", "ITEM_GRANTED", "ITEM_GRANTED", "ITEM_GRANTED",
	]
	assert_true(E5.is_legal_sequence(full24, {
		"settled_outcome": "FULL_GRANT",
		"grant_seats": [0, 1, 2, 3],
	}), "E5 FULL_GRANT 路径+meta 契约仍有效（对照黄金 4 grant）")
	# NBC 全流
	var nbc := NetworkedBattleController.new(ItemInventoryGoldFixtures.ROOM_ID, 0)
	nbc.configure_snapshot_registry_for_mode(str(GameSessionConfig.MODE_TRASH_TALK))
	for raw2 in events:
		var ne2: NetworkedEvent = NetworkedEvent.from_dict(raw2)
		assert_true(nbc.ingest_networked_event(ne2), "ingest %s" % ne2.kind)
		assert_false(nbc.resync_required())
	assert_eq((nbc.get_item_inventory_view().get("items", []) as Array).size(), 0)


## P1-2：STANDARD NBC 不得被 ITEM 事件污染出 item_inventory。
func test_standard_nbc_ignores_item_events_no_inventory_module() -> void:
	var cfg := GameSessionConfig.create_validated(
		GameSessionConfig.ROOM_PRACTICE, GameSessionConfig.ROUND_EAST,
		GameSessionConfig.MODE_STANDARD, PARTS_MIX, CHARS, 3, "std-nbc-iso", "rv"
	)
	var server := LocalLoopbackServer.new(cfg, 0)
	assert_true(server.start())
	var snap0: NetworkedEvent = null
	for ne in server.event_journal(0):
		if ne is NetworkedEvent and (ne as NetworkedEvent).kind == "ROOM_SNAPSHOT":
			snap0 = ne as NetworkedEvent
			break
	assert_not_null(snap0)
	var nbc := NetworkedBattleController.new(str(cfg.session_id), 0)
	nbc.configure_snapshot_registry_for_mode(str(GameSessionConfig.MODE_STANDARD))
	assert_true(nbc.ingest_networked_event(snap0))
	var applied0: Dictionary = nbc.get("_applied_modules") as Dictionary
	assert_false(applied0.has("item_inventory"), "初始 STANDARD SNAP 无 item_inventory")
	# schema 合法、同 committed hash 的 ITEM_GRANTED / ARMED
	var vh := snap0.view_hash
	var seq := int(snap0.server_seq)
	var grant := NetworkedEvent.from_dict({
		"kind": "ITEM_GRANTED",
		"protocol_version": 1,
		"room_id": str(cfg.session_id),
		"server_seq": seq + 1,
		"view_hash": vh,
		"payload": {
			"window_id": "w0",
			"rule_version": "rv",
			"assignment_version": "av",
			"matched_rule_ids": [],
			"item_id": "wall_peek_v1",
			"item_instance_id": "ii_std_pollute_s0",
			"seat": 0,
			"hand_seq": 0,
			"score": 0,
			"affinity_match": false,
			"armed_for_window_id": null,
		},
	})
	assert_not_null(grant, "ITEM_GRANTED schema 须合法")
	nbc.ingest_networked_event(grant)
	# 再喂一条 schema 合法 ITEM_APPLIED（同 hash）
	var applied_ev := NetworkedEvent.from_dict({
		"kind": "ITEM_APPLIED",
		"protocol_version": 1,
		"room_id": str(cfg.session_id),
		"server_seq": seq + 2,
		"view_hash": vh,
		"payload": {
			"seat": 0,
			"item_id": "wall_peek_v1",
			"item_instance_id": "ii_std_pollute_s0",
			"effect_id": "wall_peek_v1",
			"command_id": "550e8400-e29b-41d4-a716-0000000000aa",
		},
	})
	assert_not_null(applied_ev)
	nbc.ingest_networked_event(applied_ev)
	var applied1: Dictionary = nbc.get("_applied_modules") as Dictionary
	assert_false(applied1.has("item_inventory"),
		"STANDARD 收到 ITEM_* 后仍不得出现 item_inventory")
	var inv_view: Dictionary = nbc.get_item_inventory_view()
	assert_true(
		inv_view.is_empty() \
		or not inv_view.has("items") \
		or (inv_view.get("items", []) as Array).is_empty(),
		"STANDARD 库存投影须保持空"
	)


## provider schema + stage/commit。
func test_item_inventory_provider_schema_and_stage_commit() -> void:
	var prov := ItemInventorySnapshotProvider.new()
	assert_eq(prov.module_key(), "item_inventory")
	var inv := ItemInventoryModule.new()
	inv.set_match_namespace("prov")
	inv.grant_for_seat({
		"seat": 0, "item_id": "iron_shield_v1", "window_id": "w0",
		"hand_seq": 0, "score": 1, "rule_version": "rv", "assignment_version": "av",
		"matched_rule_ids": [], "affinity_match": false,
	})
	var dto: Dictionary = inv.to_seat_snapshot_dto(0)
	var payload: Dictionary = dto["payload"]
	assert_true(prov.can_restore(payload, 0))
	var bad_seat: Dictionary = payload.duplicate(true)
	bad_seat["seat"] = 1
	assert_false(prov.can_restore(bad_seat, 0))
	var staged: Variant = prov.stage_restore(payload, 0)
	assert_not_null(staged)
	var nbc := NetworkedBattleController.new("r", 0)
	nbc.configure_snapshot_registry_for_mode(str(GameSessionConfig.MODE_TRASH_TALK))
	assert_true(prov.commit_restore(staged, 0, nbc))
	assert_eq((nbc.get_item_inventory_view().get("items", []) as Array).size(), 1)


## Practice 真实 FULL_GRANT + seat0 battle USE。
func test_practice_full_grant_and_item_use() -> void:
	var cfg := _cfg_practice(13, "replay-practice-use")
	var driver: GameDriver = PracticeSessionLauncher.new().launch(cfg)
	var pbc: PlayableBattleController = driver.start_hand() as PlayableBattleController
	assert_not_null(pbc)
	var auth: LocalLoopbackServer = pbc.get_meta("local_authority") as LocalLoopbackServer
	assert_not_null(auth)
	_inject_seat0_score_utterance(auth, "replay_s0")
	_drive_until_discard_count(auth, 24, 100)
	_settle_closing_full_grant(auth, 9000)
	assert_eq(_count(_kinds(auth), "ITEM_GRANTED"), 4)
	var inv: ItemInventoryModule = driver.mode_modules.item_inventory
	var held: ItemInstance = _seat0_held_battle(inv)
	assert_not_null(held, "seat0 须有 battle consumable")
	var bc: BattleController = auth.get("_bc") as BattleController
	for s in range(4):
		bc.decision_context_for_seat(s)
	var ctx: DecisionContext = bc.decision_context_for_seat(0)
	assert_not_null(ctx)
	var cr: CommandResult = auth.submit_action(Action.item_use(
		0, held.item_instance_id, str(auth.get("_room_id")), _cmd(50),
		str(ctx.decision_id), int(ctx.hand_seq), 50
	))
	assert_eq(cr.status, "ACCEPTED", cr.error_code)
	# imm 或 delayed 均可；库存状态须变化
	var after: ItemInstance = inv.find_instance(held.item_instance_id)
	assert_true(after == null or after.status == ItemInstance.STATUS_ARMED)


## 12 角色被动 triggers 钉死。
func test_twelve_character_passives_exact_triggers() -> void:
	var expected := {
		&"char_akagi_passive_v1": [&"TILE_DRAWN"],
		&"char_kaiji_passive_v1": [&"WIN_DECLARED_PRE"],
		&"char_washizu_passive_v1": [&"GAME_BEGIN"],
		&"char_saki_passive_v1": [&"WIN_DECLARED_PRE"],
		&"char_teru_passive_v1": [
			&"WIN_DECLARED_PRE", &"EXHAUSTIVE_DRAW", &"ABORTIVE_DRAW"],
		&"char_awai_passive_v1": [&"GAME_BEGIN"],
		&"char_koromo_passive_v1": [&"HAITEI", &"HOUTEI", &"TILE_DRAWN"],
		&"char_nodoka_passive_v1": [&"WIN_DECLARED_PRE", &"HAND_FORMED"],
		&"char_toki_passive_v1": [&"GAME_BEGIN"],
		&"char_kuro_passive_v1": [&"WIN_DECLARED_PRE"],
		&"char_momoko_passive_v1": [
			&"RIICHI_DECLARED", &"WIN_DECLARED_PRE", &"EXHAUSTIVE_DRAW", &"ABORTIVE_DRAW"],
		&"char_tetsuya_passive_v1": [&"WIN_DECLARED_PRE"],
	}
	assert_eq(expected.size(), 12)
	for aid in expected.keys():
		var sk: SkillResource = BossAbilityFactory.build(aid)
		assert_not_null(sk)
		var got: Array = []
		for t in sk.owner_triggers:
			got.append(t)
		assert_eq(JSON.stringify(got), JSON.stringify(expected[aid]))


## P2-3：道具 arm/disarm 不得吞并业务 params/consumed；先示可维护明确命名的私有运行态。
func test_twelve_character_skill_business_params_stable_across_item_arm_disarm() -> void:
	const ABILITIES := [
		&"char_akagi_passive_v1", &"char_kaiji_passive_v1", &"char_washizu_passive_v1",
		&"char_saki_passive_v1", &"char_teru_passive_v1", &"char_awai_passive_v1",
		&"char_koromo_passive_v1", &"char_nodoka_passive_v1", &"char_toki_passive_v1",
		&"char_kuro_passive_v1", &"char_momoko_passive_v1", &"char_tetsuya_passive_v1",
	]
	# ability → 角色 id（CharacterPool 中 ability_id 对应）
	const CHAR_BY_ABILITY := {
		&"char_akagi_passive_v1": &"lin_yeche",
		&"char_kaiji_passive_v1": &"qiu_jue",
		&"char_washizu_passive_v1": &"bai_touli",
		&"char_saki_passive_v1": &"hua_ling",
		&"char_teru_passive_v1": &"lian_yao",
		&"char_awai_passive_v1": &"an_cheng",
		&"char_koromo_passive_v1": &"yuan_xi",
		&"char_nodoka_passive_v1": &"ji_shu",
		&"char_toki_passive_v1": &"xian_shi",
		&"char_kuro_passive_v1": &"bao_luo",
		&"char_momoko_passive_v1": &"ying_li",
		&"char_tetsuya_passive_v1": &"ju_jin",
	}
	assert_eq(ABILITIES.size(), 12)
	for aid in ABILITIES:
		var cid: StringName = CHAR_BY_ABILITY[aid]
		var ch: Character = CharacterPool.find(cid)
		assert_not_null(ch, "角色 %s 须存在" % String(cid))
		assert_eq(ch.ability_id, aid)
		var sk: SkillResource = BossAbilityFactory.build(aid)
		assert_not_null(sk)
		# 预置非空 params + 未 consumed，确认 arm 不吞并
		sk.params = {"probe": 1, "ability": String(aid)}
		sk.consumed = false
		var consumed_before: bool = sk.consumed
		var bc := BattleController.new(7, 0, false, TileId.E, 0)
		var inv := ItemInventoryModule.new()
		inv.set_match_namespace("char-arm-%s" % String(aid))
		assert_true(bool(inv.grant_for_seat({
			"seat": 0, "item_id": "iron_shield_v1", "window_id": "w0",
			"hand_seq": 0, "score": 0, "rule_version": "rv", "assignment_version": "av",
			"matched_rule_ids": [], "affinity_match": true, "next_window_id": "w1",
		}).get("ok", false)))
		var slot := CharacterAbilitySlot.new(0, cid, aid, sk, false)
		var slots: Array = [slot, null, null, null]
		var arm: Dictionary = ItemAuthority.arm_seats_on_open(bc, inv, slots, "w1")
		assert_true(bool(arm.get("ok", false)), "arm %s: %s" % [String(aid), str(arm)])
		assert_eq(int(sk.params.get("probe", -1)), 1,
			"arm 后业务 params 不得被吞并 ability=%s" % String(aid))
		assert_eq(str(sk.params.get("ability", "")), String(aid))
		if aid == &"char_toki_passive_v1":
			assert_true(bool(sk.params.get("seat_draw_forecast_active", false)))
			assert_eq(int(sk.params.get("seat_draw_forecast_hand_seq", -1)), 0)
			assert_eq(int(sk.params.get("seat_draw_forecast_viewer", -1)), 0)
			assert_eq(sk.params.get("seat_draw_forecast_pending", []), [0, 1, 2, 3])
		else:
			assert_eq(sk.params.keys().size(), 2,
				"非先示角色不得新增私有运行态 ability=%s" % String(aid))
		assert_eq(sk.consumed, consumed_before,
			"arm 后 consumed 不得被统一改写 ability=%s" % String(aid))
		var dis: Dictionary = ItemAuthority.disarm_all_active(bc, inv, slots, "w1")
		assert_true(bool(dis.get("ok", false)), "disarm %s" % String(aid))
		assert_eq(int(sk.params.get("probe", -1)), 1,
			"disarm 后业务 params 仍须稳定 ability=%s" % String(aid))
		assert_eq(str(sk.params.get("ability", "")), String(aid))
		assert_eq(sk.consumed, consumed_before,
			"disarm 后 consumed 仍须稳定 ability=%s" % String(aid))
		assert_false(slot.armed)
		assert_eq(slot.registry_registered, aid == &"char_toki_passive_v1",
			"仅仍有待消费预测的先示可在 disarm 后保留注册")


## P2-1：HeadlessRoomSession 与 Practice 同 seed 真实 FULL_GRANT + 无条件 ITEM_USE 字节一致。
func test_worker_headless_room_vs_practice_full_grant_item_use() -> void:
	# seed=2 + HUMAN+3AI + seat0 评分 utterance → seat0 即时 battle 道具可 USE
	var seed_v := 2
	var sid := "r12-worker-practice"
	# --- Worker / HeadlessRoomSession ---
	var session := HeadlessRoomSession.new()
	session.set_seed_override_for_test(seed_v)
	assert_true(session.bootstrap_from_claims({
		"room_id": sid,
		"seat": 0,
		"session_id": sid,
		"round_kind": "EAST",
		"game_mode": "TRASH_TALK",
		"participants": ["HUMAN", "AI", "AI", "AI"],
		"expires_at_unix": 2_000_000_000,
	}))
	var wcfg: GameSessionConfig = session.config
	assert_not_null(wcfg)
	assert_true(bool(session.join(0, "sess-0", 1, 1)["ok"]))
	assert_true(bool(session.ready(0, "sess-0")["ok"]))
	assert_true(session.is_started())
	var w_server: LocalLoopbackServer = session.server
	assert_not_null(w_server)
	_inject_seat0_score_utterance(w_server, "r12_force_s0")
	_drive_until_discard_count(w_server, 24, 2000)
	_settle_closing_full_grant(w_server, 9000)
	assert_eq(_count(_kinds(w_server), "ITEM_GRANTED"), 4)
	# 四席唯一 instance
	var grant_iids: Dictionary = {}
	for ne_g in w_server.event_journal(0):
		if ne_g is NetworkedEvent and (ne_g as NetworkedEvent).kind == "ITEM_GRANTED":
			var gp: Dictionary = (ne_g as NetworkedEvent).payload
			var giid := str(gp.get("item_instance_id", ""))
			assert_false(grant_iids.has(giid), "ITEM_GRANTED instance 须全局唯一")
			grant_iids[giid] = int(gp.get("seat", -1))
	assert_eq(grant_iids.size(), 4)
	var w_inv: ItemInventoryModule = w_server.mode_modules.item_inventory
	var w_inst: ItemInstance = _seat0_held_battle(w_inv)
	assert_not_null(w_inst, "FULL_GRANT 后 seat0 须有 battle consumable（不得跳过）")
	var use_iid := w_inst.item_instance_id
	var use_item_id := w_inst.item_id
	_force_complete_item_use_path(session, w_server, null, 0, use_iid, use_item_id, 12000)
	assert_eq(_count(_kinds(w_server), "ITEM_APPLIED"), 1, "须精确 1×ITEM_APPLIED")
	assert_eq(_count(_kinds(w_server), "ITEM_CONSUMED"), 1, "须精确 1×ITEM_CONSUMED")
	assert_null(w_inv.find_instance(use_iid), "结算后须从库存移除")
	var w_canon := _canon_journal(w_server, 0)

	# --- Practice：同 seed/chars/rule/session + 同 utterance ---
	var chars_sn: Array = []
	for c in wcfg.character_ids:
		chars_sn.append(StringName(str(c)))
	var pcfg := GameSessionConfig.create_validated(
		GameSessionConfig.ROOM_PRACTICE, GameSessionConfig.ROUND_EAST,
		GameSessionConfig.MODE_TRASH_TALK, PARTS_MIX,
		chars_sn, seed_v, sid, str(wcfg.rule_version)
	)
	assert_not_null(pcfg)
	var driver: GameDriver = PracticeSessionLauncher.new().launch(pcfg)
	assert_not_null(driver)
	var pbc: PlayableBattleController = driver.start_hand() as PlayableBattleController
	assert_not_null(pbc)
	var p_auth: LocalLoopbackServer = pbc.get_meta("local_authority") as LocalLoopbackServer
	assert_not_null(p_auth)
	_inject_seat0_score_utterance(p_auth, "r12_force_s0")
	_drive_until_discard_count(p_auth, 24, 2000)
	_settle_closing_full_grant(p_auth, 9000)
	assert_eq(_count(_kinds(p_auth), "ITEM_GRANTED"), 4)
	var p_inv: ItemInventoryModule = p_auth.mode_modules.item_inventory
	var p_inst: ItemInstance = _seat0_held_battle(p_inv)
	assert_not_null(p_inst, "Practice FULL_GRANT 后 seat0 须有 battle consumable")
	assert_eq(p_inst.item_instance_id, use_iid, "两侧须同一 FULL_GRANT 实例")
	assert_eq(p_inst.item_id, use_item_id)
	_force_complete_item_use_path(null, p_auth, pbc, 0, use_iid, use_item_id, 12000)
	assert_eq(_count(_kinds(p_auth), "ITEM_APPLIED"), 1)
	assert_eq(_count(_kinds(p_auth), "ITEM_CONSUMED"), 1)
	assert_null(p_inv.find_instance(use_iid))
	var p_canon := _canon_journal(p_auth, 0)
	assert_eq(p_canon, w_canon, "完整公开 journal 字节须一致")

	# 双侧 NBC 回放：库存 / 武装窗口 / 终态一致
	var nbc_views: Array = []
	for srv in [w_server, p_auth]:
		var nbc := NetworkedBattleController.new(str(srv.get("_room_id")), 0)
		nbc.configure_snapshot_registry_for_mode(str(GameSessionConfig.MODE_TRASH_TALK))
		for ne in srv.event_journal(0):
			if ne is NetworkedEvent:
				assert_true(nbc.ingest_networked_event(ne as NetworkedEvent),
					(ne as NetworkedEvent).kind)
				assert_false(nbc.resync_required())
		var inv_v: Dictionary = nbc.get_item_inventory_view()
		for it in inv_v.get("items", []) as Array:
			if typeof(it) == TYPE_DICTIONARY:
				assert_ne(str((it as Dictionary).get("item_instance_id", "")), use_iid)
		nbc_views.append({
			"items": JSON.stringify(inv_v.get("items", [])),
			"active": inv_v.get("active_window_id", null),
			"pending": inv_v.get("pending_window_id", null),
			"core_phase": str(nbc.get_core_table_view().get("phase", "")),
		})
	assert_eq(JSON.stringify(nbc_views[0]), JSON.stringify(nbc_views[1]),
		"Worker/Practice NBC 终态库存与武装/core 须一致")


## 真实 ITEM_USE；若 delayed 则经 BC 生产事件触发 + Loopback finalize 得到 APPLIED/CONSUMED。
func _force_complete_item_use_path(
	session: HeadlessRoomSession,
	server: LocalLoopbackServer,
	pbc: PlayableBattleController,
	seat: int,
	use_iid: String,
	use_item_id: String,
	cmd_n: int
) -> void:
	var ctx: DecisionContext = _ensure_decision_seat0(server, cmd_n - 1000)
	assert_not_null(ctx, "seat%d 须有 decision 才能 ITEM_USE" % seat)
	var act := Action.item_use(
		seat, use_iid, str(server.get("_room_id")), _cmd(cmd_n),
		str(ctx.decision_id), int(ctx.hand_seq), cmd_n
	)
	if session != null:
		var cr: CommandResult = session.submit_action_for_seat(seat, act)
		assert_eq(cr.status, "ACCEPTED", "Worker ITEM_USE: %s item=%s" % [cr.error_code, use_item_id])
	else:
		assert_not_null(pbc)
		var res: ActionResolution = pbc.apply_action(act, ActionSource.HUMAN)
		assert_true(res.accepted, "Practice ITEM_USE 须成功 item=%s" % use_item_id)
	# 即时件：submit/apply 内已 finalize
	if ConsumableFactory.is_immediate_on_use(StringName(use_item_id)):
		return
	# 延迟件：经生产 BC 事件触发 skill.consumed，再权威 finalize 发 APPLIED/CONSUMED
	var inv: ItemInventoryModule = server.mode_modules.item_inventory
	var sk: SkillResource = inv.registered_skill(use_iid)
	assert_not_null(sk, "delayed USE 后须已注册 skill")
	var bc: BattleController = server.get("_bc") as BattleController
	assert_not_null(bc)
	var fired := false
	for t in sk.owner_triggers:
		bc._emit(t, seat, null, {})
		if sk.consumed:
			fired = true
			break
	assert_true(fired, "生产事件须触发 delayed skill.consumed item=%s" % use_item_id)
	assert_true(bool(server.call("_finalize_item_triggers")),
		"finalize_triggered 须发布 APPLIED/CONSUMED")
