extends GutTest

# #253 道具权威生命周期：DISPLAY_ONLY 终场序、跨局 start finalize、MATCH 清场、回滚。
# 承接原 round5–8 中生产路径验收（轮次命名文件已删除）。

const CHARS := [&"lin_yeche", &"qiu_jue", &"bai_touli", &"hua_ling"]
const PARTS_ALL_H := [&"HUMAN", &"HUMAN", &"HUMAN", &"HUMAN"]
const PARTS_MIX := [&"HUMAN", &"AI", &"AI", &"AI"]
const ViewerRevealResolverScript := preload("res://battle/viewer_reveal_resolver.gd")


func _cfg_tt(p_seed: int, sid: String, all_human: bool = true) -> GameSessionConfig:
	var parts: Array = PARTS_ALL_H if all_human else PARTS_MIX
	return GameSessionConfig.create_validated(
		GameSessionConfig.ROOM_PUBLIC_CASUAL if all_human else GameSessionConfig.ROOM_PRACTICE,
		GameSessionConfig.ROUND_EAST,
		GameSessionConfig.MODE_TRASH_TALK,
		parts, CHARS, p_seed, sid, "rv-253"
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


func _business_kinds(server: LocalLoopbackServer, seat: int = 0) -> Array:
	var out: Array = []
	for ne in server.event_journal(seat):
		if ne is NetworkedEvent and (ne as NetworkedEvent).kind != "ROOM_SNAPSHOT":
			out.append((ne as NetworkedEvent).kind)
	return out


func _drive_until_discard_count(server: LocalLoopbackServer, target: int, cmd_base: int = 1000) -> void:
	var rw: RewardWindowModule = server.mode_modules.reward_window
	var n: int = cmd_base
	var guard := 0
	while rw.discard_count < target:
		guard += 1
		assert_lt(guard, 160, "驱动超时 discard=%d" % rw.discard_count)
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


func _submit_item_use(server: LocalLoopbackServer, seat: int, iid: String, n: int) -> CommandResult:
	var bc: BattleController = server.get("_bc") as BattleController
	for s in range(4):
		bc.decision_context_for_seat(s)
	var ctx: DecisionContext = bc.decision_context_for_seat(seat)
	assert_not_null(ctx)
	return server.submit_action(Action.item_use(
		seat, iid, str(server.get("_room_id")), _cmd(n),
		str(ctx.decision_id), int(ctx.hand_seq), n
	))


func _submit_any(server: LocalLoopbackServer, parts: Array, seat: int, act: Action) -> void:
	var is_human := seat >= 0 and seat < parts.size() and str(parts[seat]) == "HUMAN"
	if is_human and not bool(server.is_seat_ai_controlled(seat)):
		assert_eq(server.submit_action(act).status, "ACCEPTED")
	else:
		assert_true(server.process_internal_action(act).accepted)


## P1-1：终场 DISPLAY_ONLY 剥离 SNAP 后 HAND_SETTLED 在 MATCH_SETTLED 之前，MATCH 后紧随清场 SNAP。
func test_display_only_hand_settled_before_match_settled_order() -> void:
	var server := LocalLoopbackServer.new(_cfg_tt(9, "life-display-order"), 0)
	assert_true(server.start())
	var inv: ItemInventoryModule = server.mode_modules.item_inventory
	assert_true(bool(inv.grant_for_seat({
		"seat": 0, "item_id": "iron_shield_v1", "window_id": "hand_0_window_0",
		"hand_seq": 0, "score": 1, "rule_version": "rv", "assignment_version": "av",
		"matched_rule_ids": [], "affinity_match": false,
		"match_namespace": str(server.get("_room_id")),
	}).get("ok", false)))
	server.set_reward_match_ended(true)
	var rw: RewardWindowModule = server.mode_modules.reward_window
	var bc: BattleController = server.get("_bc") as BattleController
	assert_true(bool(rw.ingest_utterance({
		"seat": 1, "utterance_id": "life_disp", "text": "终", "language": "zh",
		"ptt_end_server_seq": maxi(server.current_server_seq(), 1), "terminal": false,
	}).get("accepted", false)))
	var w: Wall = bc.state.wall
	w.set_draw_index(w.authority_tiles().size() - w.dead_wall_size())
	bc.state.phase = BattlePhase.Kind.DRAW
	bc.set("_settled", false)
	bc.set("_active_window", null)
	assert_true(bc.engine.draw_for_current() == null)
	if not bool(bc.get("_settled")):
		bc._emit(&"EXHAUSTIVE_DRAW", -1, null, {})
		bc.set("_settled", true)
	assert_true(bool(server.call("_emit_settled_if_needed")))
	assert_true(server.advance_reward_time(int(rw._grace_deadline_ms)))
	if _count(_kinds(server), "MATCH_SETTLED") == 0:
		assert_true(server.advance_reward_time(int(rw._grace_deadline_ms) + 100))
	var kinds: Array = _kinds(server)
	assert_eq(_count(kinds, "ITEM_GRANTED"), 0)
	assert_eq(_count(kinds, "REWARD_WINDOW_SETTLED"), 1)
	assert_eq(_count(kinds, "HAND_SETTLED"), 1)
	assert_eq(_count(kinds, "MATCH_SETTLED"), 1)
	var biz: Array = _business_kinds(server)
	var hand_i := biz.find("HAND_SETTLED")
	var match_i := biz.find("MATCH_SETTLED")
	assert_gte(hand_i, 0)
	assert_gte(match_i, 0)
	assert_lt(hand_i, match_i, "E5：HAND_SETTLED 必须在 MATCH_SETTLED 之前")
	# 全 journal：MATCH 后紧随 ROOM_SNAPSHOT
	var journal: Array = server.event_journal(0)
	var match_ne: NetworkedEvent = null
	var snap_after: NetworkedEvent = null
	for i in range(journal.size()):
		var ne: NetworkedEvent = journal[i] as NetworkedEvent
		if ne == null:
			continue
		if ne.kind == "MATCH_SETTLED":
			match_ne = ne
			if i + 1 < journal.size():
				var nxt: NetworkedEvent = journal[i + 1] as NetworkedEvent
				if nxt != null and nxt.kind == "ROOM_SNAPSHOT":
					snap_after = nxt
	assert_not_null(match_ne)
	assert_not_null(snap_after, "MATCH_SETTLED 后须紧随清场 SNAP")
	assert_eq(match_ne.view_hash, snap_after.view_hash)
	assert_eq(int(snap_after.server_seq), int(match_ne.server_seq) + 1)
	assert_eq(inv.instance_count(), 0)


## P2-2：跨局共享 inv 下，第二局 start 庄家首摸命中 armed delayed 时立即 finalize。
func test_cross_hand_start_finalizes_armed_delayed_on_first_draw() -> void:
	var cfg := _cfg_tt(11, "life-start-finalize", true)
	var mods: ModeModuleBundle = ModeModuleBundle.from_config(cfg)
	mods.item_inventory.set_match_namespace(str(cfg.session_id))
	# 第一局：授予并 USE 武装 dora_flip 到 seat0（第二局 dealer=0 首摸必触发 TILE_DRAWN）
	var pbc1 := PlayableBattleController.new(cfg.seed, 0, false, TileId.E, 0)
	pbc1.bind_mode_modules(mods)
	var auth1 := LocalLoopbackServer.new(cfg, 0, pbc1, mods)
	assert_true(auth1.start())
	var inv: ItemInventoryModule = mods.item_inventory
	var gr: Dictionary = inv.grant_for_seat({
		"seat": 0, "item_id": "dora_flip_v1", "window_id": "w0",
		"hand_seq": 0, "score": 1, "rule_version": "rv", "assignment_version": "av",
		"matched_rule_ids": [], "affinity_match": false,
		"match_namespace": str(cfg.session_id),
	})
	assert_true(bool(gr.get("ok", false)), str(gr))
	var delayed_iid := str(gr["payload"]["item_instance_id"])
	var use_cr: CommandResult = _submit_item_use(auth1, 0, delayed_iid, 1001)
	assert_eq(use_cr.status, "ACCEPTED", use_cr.error_code)
	assert_eq(inv.find_instance(delayed_iid).status, ItemInstance.STATUS_ARMED)
	# 第二局：新 PBC + 新权威，共享 inv；dealer=0 首摸触发 armed
	var pbc2 := PlayableBattleController.new(cfg.seed + 1, 0, false, TileId.E, 1)
	pbc2.bind_mode_modules(mods)
	var auth2 := LocalLoopbackServer.new(cfg, 0, pbc2, mods)
	assert_true(auth2.start(), "第二局 start 须成功")
	assert_null(inv.find_instance(delayed_iid), "start 返回后库存不得再有该实例")
	var applied_n := 0
	var consumed_n := 0
	for ne in auth2.event_journal(0):
		if not (ne is NetworkedEvent):
			continue
		var e: NetworkedEvent = ne as NetworkedEvent
		if str(e.payload.get("item_instance_id", "")) != delayed_iid:
			continue
		if e.kind == "ITEM_APPLIED":
			applied_n += 1
			assert_eq(str(e.payload.get("command_id", "")), _cmd(1001))
		if e.kind == "ITEM_CONSUMED":
			consumed_n += 1
			assert_eq(str(e.payload.get("command_id", "")), _cmd(1001))
	assert_eq(applied_n, 1, "start 首摸触发须恰好 1×APPLIED（不得再靠后续动作）")
	assert_eq(consumed_n, 1, "start 首摸触发须恰好 1×CONSUMED")
	var nbc := NetworkedBattleController.new(str(cfg.session_id), 0)
	nbc.configure_snapshot_registry_for_mode(str(GameSessionConfig.MODE_TRASH_TALK))
	for ne2 in auth2.event_journal(0):
		if ne2 is NetworkedEvent:
			assert_true(nbc.ingest_networked_event(ne2 as NetworkedEvent),
				(ne2 as NetworkedEvent).kind)
			assert_false(nbc.resync_required())


## P1：MATCH 后 SNAP hash 对齐 + 库存空（全 HUMAN 终场）。
func test_match_settled_emits_matching_snapshot_and_clears() -> void:
	var server := LocalLoopbackServer.new(_cfg_tt(9, "life-match-snap"), 0)
	assert_true(server.start())
	var inv: ItemInventoryModule = server.mode_modules.item_inventory
	assert_true(bool(inv.grant_for_seat({
		"seat": 0, "item_id": "iron_shield_v1", "window_id": "w0",
		"hand_seq": 0, "score": 1, "rule_version": "rv", "assignment_version": "av",
		"matched_rule_ids": [], "affinity_match": false,
		"match_namespace": "life-match-snap",
	}).get("ok", false)))
	server.set_reward_match_ended(true)
	var rw: RewardWindowModule = server.mode_modules.reward_window
	var bc: BattleController = server.get("_bc") as BattleController
	assert_true(bool(rw.ingest_utterance({
		"seat": 1, "utterance_id": "life_me", "text": "终", "language": "zh",
		"ptt_end_server_seq": maxi(server.current_server_seq(), 1), "terminal": false,
	}).get("accepted", false)))
	var w: Wall = bc.state.wall
	w.set_draw_index(w.authority_tiles().size() - w.dead_wall_size())
	bc.state.phase = BattlePhase.Kind.DRAW
	bc.set("_settled", false)
	bc.set("_active_window", null)
	assert_true(bc.engine.draw_for_current() == null)
	if not bool(bc.get("_settled")):
		bc._emit(&"EXHAUSTIVE_DRAW", -1, null, {})
		bc.set("_settled", true)
	assert_true(bool(server.call("_emit_settled_if_needed")))
	assert_true(server.advance_reward_time(int(rw._grace_deadline_ms)))
	if _count(_kinds(server), "MATCH_SETTLED") == 0:
		assert_true(server.advance_reward_time(int(rw._grace_deadline_ms) + 100))
	assert_gte(_count(_kinds(server), "MATCH_SETTLED"), 1)
	assert_eq(inv.instance_count(), 0)


## P1：start 中 snapshot 失败 → inv 精确回到调用前（共享 modules + armed delayed）。
func test_start_snapshot_fail_rolls_back_inventory_and_registry() -> void:
	var cfg := _cfg_tt(3, "life-start-rb", true)
	var mods: ModeModuleBundle = ModeModuleBundle.from_config(cfg)
	mods.item_inventory.set_match_namespace(str(cfg.session_id))
	var pbc1 := PlayableBattleController.new(cfg.seed, 0, false, TileId.E, 0)
	pbc1.bind_mode_modules(mods)
	var auth1 := LocalLoopbackServer.new(cfg, 0, pbc1, mods)
	assert_true(auth1.start())
	var inv: ItemInventoryModule = mods.item_inventory
	var gr: Dictionary = inv.grant_for_seat({
		"seat": 0, "item_id": "dora_flip_v1", "window_id": "w0",
		"hand_seq": 0, "score": 1, "rule_version": "rv", "assignment_version": "av",
		"matched_rule_ids": [], "affinity_match": false,
		"match_namespace": str(cfg.session_id),
	})
	assert_true(bool(gr.get("ok", false)))
	var delayed_iid := str(gr["payload"]["item_instance_id"])
	assert_eq(_submit_item_use(auth1, 0, delayed_iid, 501).status, "ACCEPTED")
	var pre_fp := JSON.stringify(inv.capture_state())
	# 第二局 start：fail 首 SNAP
	var pbc2 := PlayableBattleController.new(cfg.seed + 1, 0, false, TileId.E, 1)
	pbc2.bind_mode_modules(mods)
	var auth2 := LocalLoopbackServer.new(cfg, 0, pbc2, mods)
	auth2.fail_next_snapshot_for_test()
	assert_false(auth2.start())
	assert_eq(JSON.stringify(inv.capture_state()), pre_fp, "失败后库存须等于 start 前")
	assert_eq(inv.find_instance(delayed_iid).status, ItemInstance.STATUS_ARMED)


## 裸 BC ITEM_USE fail-closed（无 mode modules 时 NOT_ENABLED）。
func test_bare_bc_item_use_rejected_no_side_effect() -> void:
	var inv := ItemInventoryModule.new()
	inv.set_match_namespace("bare")
	var g: Dictionary = inv.grant_for_seat({
		"seat": 0, "item_id": "wall_peek_v1", "window_id": "w0",
		"hand_seq": 0, "score": 0, "rule_version": "rv", "assignment_version": "av",
		"matched_rule_ids": [], "affinity_match": false,
	})
	var iid := str(g["payload"]["item_instance_id"])
	var pre := inv.instance_count()
	var bc := BattleController.new(1, 0, false, TileId.E, 0)
	var act := Action.item_use(
		0, iid, "local", _cmd(42), _cmd(43), int(bc.state.hand_seq), 1
	)
	var res: ActionResolution = bc.apply_action(act, ActionSource.HUMAN)
	assert_false(res.accepted)
	assert_true(
		res.error_code == ActionResolution.RULE_REJECTED \
		or res.error_code == ActionResolution.NOT_ENABLED \
		or str(res.error_code) in ["RULE_REJECTED", "NOT_ENABLED"],
		"裸 BC 须拒绝 ITEM_USE code=%s" % str(res.error_code)
	)
	assert_eq(inv.instance_count(), pre)
	assert_eq(inv.find_instance(iid).status, ItemInstance.STATUS_HELD)


## arm 中途失败零部分 mutation。
func test_arm_seats_mid_failure_rolls_back_seat0() -> void:
	var bc := BattleController.new(2, 0, false, TileId.E, 0)
	var inv := ItemInventoryModule.new()
	inv.set_match_namespace("arm_rb")
	for s in range(2):
		assert_true(bool(inv.grant_for_seat({
			"seat": s, "item_id": "iron_shield_v1", "window_id": "w0",
			"hand_seq": 0, "score": 0, "rule_version": "rv", "assignment_version": "av",
			"matched_rule_ids": [], "affinity_match": true, "next_window_id": "w1",
		}).get("ok", false)))
	var ch0: Character = CharacterPool.find(&"an_cheng")
	var sk0: SkillResource = BossAbilityFactory.build(ch0.ability_id)
	var slots: Array = [
		CharacterAbilitySlot.new(0, &"an_cheng", ch0.ability_id, sk0, false),
		CharacterAbilitySlot.new(1, &"an_cheng", ch0.ability_id, null, false), # 缺 skill
		null, null,
	]
	var pre_reg := bc.registry.get_all_entries().size()
	var arm: Dictionary = ItemAuthority.arm_seats_on_open(bc, inv, slots, "w1")
	assert_false(bool(arm.get("ok", false)))
	assert_eq(bc.registry.get_all_entries().size(), pre_reg)
	assert_false(bool(slots[0].armed))
	assert_false(bool(slots[0].registry_registered))


func test_bai_touli_arm_equivalent_game_begin_emits_one_real_skill_event() -> void:
	var bc := BattleController.new(341, 0, false, TileId.E, 0)
	var inv := ItemInventoryModule.new()
	inv.set_match_namespace("bai-arm")
	assert_true(bool(inv.grant_for_seat({
		"seat": 0, "item_id": "iron_shield_v1", "window_id": "w0",
		"hand_seq": 0, "score": 0, "rule_version": "rv", "assignment_version": "av",
		"matched_rule_ids": [], "affinity_match": true, "next_window_id": "w1",
	}).get("ok", false)))
	var ch := CharacterPool.find(&"bai_touli")
	var skill := BossAbilityFactory.build(ch.ability_id)
	var slot := CharacterAbilitySlot.new(0, ch.id, ch.ability_id, skill, false)
	var slots: Array = [slot, null, null, null]
	var before_events := bc.events.size()
	var arm := ItemAuthority.arm_seats_on_open(bc, inv, slots, "w1")
	assert_true(bool(arm.get("ok", false)))
	assert_eq(bc.events.size(), before_events + 1,
		"等价 GAME_BEGIN 必须把真实 SKILL_TRIGGERED 写入 BC 事件链")
	var event := bc.events[-1] as BattleEvent
	assert_eq(event.type, &"SKILL_TRIGGERED")
	assert_eq(event.actor_seat, 0)
	assert_eq(event.extra.get("skill_id"), &"char_washizu_passive_v1")
	assert_eq(event.extra.get("source_event"), &"GAME_BEGIN")
	assert_false(event.extra.has("tiles"), "公开触发事件不得携带私有牌身份")
	var grouped: Dictionary = ViewerRevealResolverScript.tiles_by_holder(bc.state, 0)
	assert_eq(grouped.keys().size(), 3)
	for holder in [1, 2, 3]:
		assert_eq((grouped.get(holder, []) as Array).size(), 2)
	assert_true(ViewerRevealResolverScript.tiles_by_holder(bc.state, 1).is_empty(),
		"被观察座位不得获得白透璃的私有信息")
	var reveal_count := bc.state.revealed_tiles.size()
	assert_true(bool(ItemAuthority.arm_seats_on_open(bc, inv, slots, "w1").get("ok", false)))
	assert_eq(bc.events.size(), before_events + 1, "同一窗口重复 arm 不得再次激活")
	assert_eq(bc.state.revealed_tiles.size(), reveal_count)
	assert_true(bool(ItemAuthority.disarm_all_active(bc, inv, slots, "w1").get("ok", false)))
	assert_eq(bc.state.revealed_tiles.size(), reveal_count,
		"解除武装不抹除玩家已获得的信息")


func test_an_cheng_arm_once_clears_authoritative_furiten_and_reveals_private_next_draw() -> void:
	var bc := BattleController.new(344, 0, false, TileId.E, 0)
	var inv := ItemInventoryModule.new()
	inv.set_match_namespace("an-cheng-arm")
	assert_true(bool(inv.grant_for_seat({
		"seat": 0, "item_id": "iron_shield_v1", "window_id": "w0",
		"hand_seq": 0, "score": 0, "rule_version": "rv", "assignment_version": "av",
		"matched_rule_ids": [], "affinity_match": true, "next_window_id": "w1",
	}).get("ok", false)))
	var ch := CharacterPool.find(&"an_cheng")
	var skill := BossAbilityFactory.build(ch.ability_id)
	var slot := CharacterAbilitySlot.new(0, ch.id, ch.ability_id, skill, false)
	var slots: Array = [slot, null, null, null]
	bc.state.furiten_flags[0] = true
	bc.state.seats[0].furiten.permanent = true
	bc.state.seats[0].furiten.temporary = true
	bc.state.seats[0].furiten.waits = [TileId.W9]
	var expected: Tile = bc.state.wall.peek_next_draw()
	var before_events := bc.events.size()
	var arm := ItemAuthority.arm_seats_on_open(bc, inv, slots, "w1")
	assert_true(bool(arm.get("ok", false)))
	assert_false(bc.state.furiten_flags[0], "兼容状态须同步清除")
	assert_false(bc.state.seats[0].furiten.is_furiten(), "真实荣和判定读取的 Seat.furiten 须清除")
	assert_eq(bc.state.seats[0].furiten.waits, [TileId.W9], "净化不改写当前听张")
	assert_eq(bc.events.size(), before_events + 1)
	var event := bc.events[-1] as BattleEvent
	assert_eq(event.type, &"SKILL_TRIGGERED")
	assert_eq(event.extra.get("skill_id"), &"char_awai_passive_v1")
	assert_eq(event.extra.get("source_event"), &"GAME_BEGIN")
	var predicted: TileSkillAnchor = ViewerRevealResolverScript.next_draw_for_viewer(
		bc.state, 0)
	assert_not_null(predicted)
	assert_eq(predicted.tile.instance_id, expected.instance_id)
	assert_null(ViewerRevealResolverScript.next_draw_for_viewer(bc.state, 1),
		"下一摸只能授权给安澄青本人")
	assert_true(bool(ItemAuthority.arm_seats_on_open(bc, inv, slots, "w1").get("ok", false)))
	assert_eq(bc.events.size(), before_events + 1, "同窗重复 arm 不得再次发动")
