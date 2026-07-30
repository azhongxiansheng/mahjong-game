extends GutTest

# Issue #379 Green Round 3/4 — 快速 P1/P2 回归（禁止本文件再跑 24 弃）
# P1-1/P1-3：跨局 start 首摸 armed delayed → SKILL 早于 ITEM_APPLIED/CONSUMED
# P2-1：fail_next_hand_start_snapshot 回滚后 cursor/journal 零变化；重试不重放
# P2-2：事务 ARS restore 后继续真实 action 不重投已有技能
# barrier/OPEN/ARM/GAME_BEGIN 恰好一次 + 续 action 不重投 → 见 grant_chain 单次 24 弃

const CHARS := [&"hua_ling", &"lin_yeche", &"qiu_jue", &"bai_touli"]
const PARTS_H := [&"HUMAN", &"HUMAN", &"HUMAN", &"HUMAN"]


func _cmd(n: int) -> String:
	return "550e8400-e29b-41d4-a716-%012d" % n


func _cfg(seed: int, sid: String) -> GameSessionConfig:
	return GameSessionConfig.create_validated(
		GameSessionConfig.ROOM_PUBLIC_CASUAL,
		GameSessionConfig.ROUND_EAST,
		GameSessionConfig.MODE_TRASH_TALK,
		PARTS_H, CHARS, seed, sid, "rv-253")


func _kinds(srv: LocalLoopbackServer, seat: int = 0) -> Array:
	var out: Array = []
	for ne in srv.event_journal(seat):
		if ne is NetworkedEvent:
			out.append((ne as NetworkedEvent).kind)
	return out


func _count_kind(kinds: Array, kind: String) -> int:
	var n := 0
	for k in kinds:
		if String(k) == kind:
			n += 1
	return n


func _count_skill_iid(srv: LocalLoopbackServer, iid: String, seat: int = 0) -> int:
	var n := 0
	for ne in srv.event_journal(seat):
		if not (ne is NetworkedEvent):
			continue
		var e: NetworkedEvent = ne as NetworkedEvent
		if e.kind != "SKILL_TRIGGERED":
			continue
		if str(e.payload.get("item_instance_id", "")) == iid:
			n += 1
	return n


func _idx_of_kind_for_iid(
	srv: LocalLoopbackServer, kind: String, iid: String, seat: int = 0
) -> int:
	var i := 0
	for ne in srv.event_journal(seat):
		if ne is NetworkedEvent:
			var e: NetworkedEvent = ne as NetworkedEvent
			if e.kind == kind and str(e.payload.get("item_instance_id", "")) == iid:
				return i
			i += 1
	return -1


func _submit_item_use(
	srv: LocalLoopbackServer, seat: int, iid: String, n: int
) -> CommandResult:
	var bc: BattleController = srv.get("_bc") as BattleController
	for s in range(4):
		bc.decision_context_for_seat(s)
	var ctx: DecisionContext = bc.decision_context_for_seat(seat)
	assert_not_null(ctx, "ITEM_USE 须有 DecisionContext seat=%d" % seat)
	return srv.submit_action(Action.item_use(
		seat, iid, str(srv.get("_room_id")), _cmd(n),
		str(ctx.decision_id), int(ctx.hand_seq), n
	))


## P1-1 + P1-3：跨局 start 首摸 armed dora_flip → 精确 1×SKILL，且早于 APPLIED/CONSUMED
func test_r3_cross_hand_start_skill_before_item_finalize() -> void:
	var cfg := _cfg(11, "379r3-cross-start")
	var mods := ModeModuleBundle.from_config(cfg)
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
	assert_true(bool(gr.get("ok", false)), str(gr))
	var delayed_iid := str(gr["payload"]["item_instance_id"])
	assert_eq(_submit_item_use(auth1, 0, delayed_iid, 1001).status, "ACCEPTED")
	assert_eq(inv.find_instance(delayed_iid).status, ItemInstance.STATUS_ARMED)

	var pbc2 := PlayableBattleController.new(cfg.seed + 1, 0, false, TileId.E, 1)
	pbc2.bind_mode_modules(mods)
	var auth2 := LocalLoopbackServer.new(cfg, 0, pbc2, mods)
	assert_true(auth2.start(), "第二局 start 须成功")
	assert_null(inv.find_instance(delayed_iid))

	var skill_i := _idx_of_kind_for_iid(auth2, "SKILL_TRIGGERED", delayed_iid)
	var app_i := _idx_of_kind_for_iid(auth2, "ITEM_APPLIED", delayed_iid)
	var cons_i := _idx_of_kind_for_iid(auth2, "ITEM_CONSUMED", delayed_iid)
	assert_gte(skill_i, 0,
		"P1：跨局首摸须投影 SKILL_TRIGGERED iid=%s kinds=%s" % [
			delayed_iid, str(_kinds(auth2))])
	assert_gte(app_i, 0, "须有 ITEM_APPLIED")
	assert_gte(cons_i, 0, "须有 ITEM_CONSUMED")
	assert_lt(skill_i, app_i, "P1-3：SKILL 须早于 ITEM_APPLIED")
	assert_lt(skill_i, cons_i, "P1-3：SKILL 须早于 ITEM_CONSUMED")
	assert_lt(app_i, cons_i, "既有契约：APPLIED 早于 CONSUMED")
	assert_eq(_count_skill_iid(auth2, delayed_iid), 1, "精确 1× 同 iid SKILL")
	# 四席均可见公开技能归因
	for s in range(4):
		assert_eq(_count_skill_iid(auth2, delayed_iid, s), 1, "seat%d 1×SKILL" % s)


## P2-1：start_next_hand 首 SNAP 失败 → journal/cursor 回到调用前；重试成功只新增正确事件
func test_r3_fail_next_hand_snapshot_restores_cursor() -> void:
	var cfg := _cfg(17, "379r3-fail-nh")
	var mods := ModeModuleBundle.from_config(cfg)
	mods.item_inventory.set_match_namespace(str(cfg.session_id))
	var pbc1 := PlayableBattleController.new(17, 0, false, TileId.E, 0)
	pbc1.bind_mode_modules(mods)
	var auth1 := LocalLoopbackServer.new(cfg, 0, pbc1, mods)
	assert_true(auth1.start())
	# 造 HAND_SETTLED 以便 start_next_hand
	var bc1: BattleController = auth1.get("_bc") as BattleController
	# 七对 TSUMO fixture
	_force_tsumo_ready(bc1, 0)
	var ctx1: DecisionContext = bc1.decision_context_for_seat(0)
	assert_not_null(ctx1)
	assert_true(ctx1.has_kind("TSUMO"))
	var room := str(auth1.get("_room_id"))
	assert_eq(auth1.submit_action(Action.tsumo(
		0, room, _cmd(7001), str(ctx1.decision_id), int(ctx1.hand_seq),
		int(auth1.current_server_seq()) + 1
	)).status, "ACCEPTED")
	# 若 deferred HAND，推进时钟
	var guard := 0
	while not bool(auth1.get("_hand_settled_emitted")) and guard < 20:
		guard += 1
		var rw: RewardWindowModule = auth1.mode_modules.reward_window
		if rw != null:
			auth1.advance_reward_time(int(rw.get("_grace_deadline_ms")) + 50 * guard)
		else:
			break
	assert_true(bool(auth1.get("_hand_settled_emitted")), "须已 HAND_SETTLED")

	var j_before: Array = auth1.event_journal(0)
	var skill_before := _count_kind(_kinds(auth1), "SKILL_TRIGGERED")
	var cursor_before: int = int(auth1.get("_skill_bc_proj_upto"))
	var seq_before: int = auth1.current_server_seq()

	# 在 HAND 已 settle 后，用共享 inv 预置 armed delayed（无需 decision 窗 ITEM_USE）
	var inv: ItemInventoryModule = mods.item_inventory
	var gr: Dictionary = inv.grant_for_seat({
		"seat": 0, "item_id": "dora_flip_v1", "window_id": "w_nh",
		"hand_seq": int(bc1.state.hand_seq), "score": 1,
		"rule_version": "rv", "assignment_version": "av",
		"matched_rule_ids": [], "affinity_match": false,
		"match_namespace": str(cfg.session_id),
	})
	assert_true(bool(gr.get("ok", false)))
	var flip_iid := str(gr["payload"]["item_instance_id"])
	# HAND 后无 TURN decision：直接走 ItemAuthority.use_item 武装（生产等价 arm 语义）
	var use_r: Dictionary = ItemAuthority.use_item(
		bc1, inv, 0, flip_iid, _cmd(7101)
	)
	assert_true(bool(use_r.get("accepted", false)), str(use_r))
	assert_eq(inv.find_instance(flip_iid).status, ItemInstance.STATUS_ARMED)
	# 武装后冻结失败前基线（journal 未因私有 arm 改变）
	j_before = auth1.event_journal(0)
	skill_before = _count_kind(_kinds(auth1), "SKILL_TRIGGERED")
	cursor_before = int(auth1.get("_skill_bc_proj_upto"))
	seq_before = auth1.current_server_seq()
	var old_bc: BattleController = auth1.get("_bc") as BattleController

	auth1.fail_next_hand_start_snapshot_for_test()
	var pbc2 := PlayableBattleController.new(18, 0, false, TileId.E, 1)
	pbc2.bind_mode_modules(mods)
	assert_false(auth1.start_next_hand(pbc2), "首 SNAP fail 须 false")
	assert_gte(auth1.fail_next_hand_start_snapshot_hit_count, 1)
	# 旧 BC / journal / cursor / seq 零变化
	assert_eq(auth1.get("_bc"), old_bc, "失败须换回旧 BC")
	assert_eq(auth1.current_server_seq(), seq_before)
	assert_eq(int(auth1.get("_skill_bc_proj_upto")), cursor_before,
		"P2：cursor 须恢复，禁止卡在新局 0 导致旧事件重投")
	assert_eq(_count_kind(_kinds(auth1), "SKILL_TRIGGERED"), skill_before)
	assert_eq(auth1.event_journal(0).size(), j_before.size())
	assert_eq(inv.find_instance(flip_iid).status, ItemInstance.STATUS_ARMED)

	# 重试成功：仅新增一次 flip SKILL
	var pbc3 := PlayableBattleController.new(19, 0, false, TileId.E, 2)
	pbc3.bind_mode_modules(mods)
	assert_true(auth1.start_next_hand(pbc3), "重试 start_next_hand 须成功")
	assert_eq(_count_skill_iid(auth1, flip_iid), 1, "重试成功后 flip SKILL 恰好 1")
	assert_null(inv.find_instance(flip_iid))


## P2-2：AuthorityReplaySnapshot 事务回滚后 cursor 与 journal 一致，续 action 不重投
func test_r3_ars_rollback_cursor_then_continue_action() -> void:
	var cfg := _cfg(8, "379r3-ars")
	var mods := ModeModuleBundle.from_config(cfg)
	mods.item_inventory.set_match_namespace(str(cfg.session_id))
	var bc := BattleController.new(8, 0, false, TileId.E, 0)
	bc.bind_mode_modules(mods)
	var srv := LocalLoopbackServer.new(cfg, 0, bc, mods)
	assert_true(srv.start())
	# 真实 dora_flip arm + 强制首摸触发路径外的另一席 DISCARD 不触发；
	# 用 fail_next_action_publish 在接受后发布失败 → 整事务回滚
	var inv: ItemInventoryModule = mods.item_inventory
	var gr: Dictionary = inv.grant_for_seat({
		"seat": 0, "item_id": "dora_flip_v1", "window_id": "w_ars",
		"hand_seq": 0, "score": 1, "rule_version": "rv", "assignment_version": "av",
		"matched_rule_ids": [], "affinity_match": false,
		"match_namespace": str(cfg.session_id),
	})
	assert_true(bool(gr.get("ok", false)))
	var flip_iid := str(gr["payload"]["item_instance_id"])
	assert_eq(_submit_item_use(srv, 0, flip_iid, 8001).status, "ACCEPTED")
	var skill0 := _count_kind(_kinds(srv), "SKILL_TRIGGERED")
	var cursor0: int = int(srv.get("_skill_bc_proj_upto"))
	var j0 := srv.event_journal(0).size()
	# 失败 seam：下一动作业务发布失败
	srv.fail_next_action_publish_for_test()
	var tctx: DecisionContext = null
	var seat := -1
	for s in range(4):
		var c: DecisionContext = bc.decision_context_for_seat(s)
		if c != null and c.has_kind("DISCARD"):
			tctx = c
			seat = s
			break
	assert_not_null(tctx)
	var tile_iid := -1
	for o in tctx.allowed_actions:
		if typeof(o) == TYPE_DICTIONARY and str(o.get("kind", "")) == "DISCARD":
			tile_iid = int((o.get("payload_options", []) as Array)[0]["tile_instance_id"])
			break
	var cr: CommandResult = srv.submit_action(Action.discard(
		seat, tile_iid, str(srv.get("_room_id")), _cmd(8101),
		str(tctx.decision_id), int(tctx.hand_seq), 1))
	assert_eq(cr.status, "REJECTED", "publish fail 须 REJECTED")
	assert_eq(int(srv.get("_skill_bc_proj_upto")), cursor0,
		"P2：publish 失败回滚后 cursor 须回到事务前")
	assert_eq(srv.event_journal(0).size(), j0)
	assert_eq(_count_kind(_kinds(srv), "SKILL_TRIGGERED"), skill0)
	# 续真实 DISCARD 成功
	for s2 in range(4):
		bc.decision_context_for_seat(s2)
	tctx = null
	for s3 in range(4):
		var c2: DecisionContext = bc.decision_context_for_seat(s3)
		if c2 != null and c2.has_kind("DISCARD"):
			tctx = c2
			seat = s3
			break
	assert_not_null(tctx)
	for o2 in tctx.allowed_actions:
		if typeof(o2) == TYPE_DICTIONARY and str(o2.get("kind", "")) == "DISCARD":
			tile_iid = int((o2.get("payload_options", []) as Array)[0]["tile_instance_id"])
			break
	assert_eq(srv.submit_action(Action.discard(
		seat, tile_iid, str(srv.get("_room_id")), _cmd(8102),
		str(tctx.decision_id), int(tctx.hand_seq), 2
	)).status, "ACCEPTED")
	# 不得因 cursor 错位重投 start 阶段已有技能
	assert_eq(_count_kind(_kinds(srv), "SKILL_TRIGGERED"), skill0,
		"续 action 不得重投历史 SKILL（本 fixture 无新技能）")


func _draw_live(bc: BattleController, tid: int, used: Dictionary) -> Tile:
	var w: Wall = bc.state.wall
	var end_i: int = w.authority_tiles().size() - w.dead_wall_size()
	var live_idx := -1
	for i in range(w.draw_index(), end_i):
		var t: Tile = w.authority_tiles()[i]
		if t == null or int(t.id) != tid:
			continue
		if used.has(int(t.instance_id)):
			continue
		live_idx = i
		break
	assert_true(live_idx >= 0, "live 无 id=%d" % tid)
	if live_idx != w.draw_index():
		assert_true(w.move_live_index_to_top(live_idx))
	var drawn: Tile = w.draw()
	if drawn != null:
		used[int(drawn.instance_id)] = true
	return drawn


func _force_tsumo_ready(bc: BattleController, seat: int) -> void:
	var used: Dictionary = {}
	var draw_floor: int = int(bc.state.wall.draw_index())
	for s in range(4):
		var st: Seat = bc.state.seats[s]
		st.hand = Hand.new()
		st.melds.restore([], 0)
		st.last_drawn_instance_id = Tile.INVALID_INSTANCE_ID
		st.furiten = FuritenState.new()
		bc.state.seats[s].river.restore([])
	bc.state.wall.set_draw_index(0)
	var ids := [
		TileId.W1, TileId.W1, TileId.W2, TileId.W2, TileId.W3, TileId.W3,
		TileId.W5, TileId.W5, TileId.W6, TileId.W6, TileId.W7, TileId.W7,
		TileId.W9,
	]
	var h := Hand.new()
	for tid in ids:
		var t: Tile = _draw_live(bc, int(tid), used)
		assert_not_null(t)
		assert_true(h.add(t))
	bc.state.seats[seat].hand = h
	bc.state.first_round_active = false
	var win_t: Tile = _draw_live(bc, TileId.W9, used)
	assert_not_null(win_t)
	assert_true(bc.state.seats[seat].hand.add(win_t))
	bc.state.seats[seat].last_drawn_instance_id = win_t.instance_id
	bc.state.current_seat = seat
	bc.state.phase = BattlePhase.Kind.DISCARD
	bc.set("_settled", false)
	bc.set("_active_window", null)
	bc.state.wall.set_draw_index(maxi(draw_floor, int(bc.state.wall.draw_index())))
