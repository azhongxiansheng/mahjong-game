extends GutTest

# Issue #379 Green Round 2 — 四个 P2 回归
# P2-1：action 热路径不得调用 event_journal（无全 journal 深拷贝）
# P2-2：同 skill_id 双 relic 实例各自正确 item_instance_id
# P2-3：actor_seat ≠ beneficiary_seat（holder 技能 soul_drain）
# P2-4：SKILL_TRIGGERED 早于 HAND_SETTLED 因果序


func _cfg_tt(seed: int, sid: String) -> GameSessionConfig:
	return GameSessionConfig.create_validated(
		GameSessionConfig.ROOM_PUBLIC_CASUAL,
		GameSessionConfig.ROUND_EAST,
		GameSessionConfig.MODE_TRASH_TALK,
		[&"HUMAN", &"HUMAN", &"HUMAN", &"HUMAN"],
		[&"hua_ling", &"lin_yeche", &"qiu_jue", &"bai_touli"],
		seed, sid, "rv-253")


func _boot_tt(seed: int) -> Dictionary:
	var cfg := _cfg_tt(seed, "379r2-%d" % seed)
	var mods := ModeModuleBundle.from_config(cfg)
	var bc := BattleController.new(seed, 0, false, TileId.E, 0)
	bc.bind_mode_modules(mods)
	var srv := LocalLoopbackServer.new(cfg, 0, bc, mods)
	assert_true(srv.start())
	var room := ""
	for ne in srv.event_journal(0):
		if ne is NetworkedEvent and not (ne as NetworkedEvent).room_id.is_empty():
			room = (ne as NetworkedEvent).room_id
			break
	return {"server": srv, "bc": bc, "room": room, "cfg": cfg}


func _journal_kinds(srv: LocalLoopbackServer) -> Array:
	var kinds: Array = []
	for ne in srv.event_journal(0):
		if ne is NetworkedEvent:
			kinds.append((ne as NetworkedEvent).kind)
	return kinds


## P2-1：accepted action 不得再调用 event_journal（诊断计数不增）
func test_p2_action_path_does_not_call_event_journal() -> void:
	var rt := _boot_tt(11)
	var srv: LocalLoopbackServer = rt.server
	var bc: BattleController = rt.bc
	var room: String = rt.room
	var _j: Array = srv.event_journal(0)
	var calls0: int = srv.event_journal_call_count
	for s in range(4):
		bc.decision_context_for_seat(s)
	var tctx: DecisionContext = null
	var seat := -1
	for s2 in range(4):
		var c: DecisionContext = bc.decision_context_for_seat(s2)
		if c != null and c.has_kind("DISCARD"):
			tctx = c
			seat = s2
			break
	assert_not_null(tctx, "须有 DISCARD 窗")
	var iid := -1
	for o in tctx.allowed_actions:
		if typeof(o) == TYPE_DICTIONARY and str(o.get("kind", "")) == "DISCARD":
			var opts: Array = o.get("payload_options", [])
			if not opts.is_empty():
				iid = int(opts[0]["tile_instance_id"])
				break
	assert_gt(iid, -1)
	var cr: CommandResult = srv.submit_action(Action.discard(
		seat, iid, room,
		"550e8400-e29b-41d4-a716-000000000201",
		str(tctx.decision_id), int(tctx.hand_seq), 1))
	assert_eq(cr.status, "ACCEPTED", cr.error_code)
	assert_eq(srv.event_journal_call_count, calls0,
		"P2-1：accepted action 热路径禁止调用 event_journal() 全量克隆")


## P2-2：双同 skill_id relic 实例各自精确 item_instance_id
func test_p2_dual_relic_instances_distinct_attribution() -> void:
	var bc := BattleController.new(42, 0, false, TileId.E, 0)
	var def := ItemCatalog.definition(&"relic_lucky_cat_v1")
	assert_not_null(def)
	var sk_a: SkillResource = ItemSkillBuilder.build(def, "ii_relic_a_379")
	var sk_b: SkillResource = ItemSkillBuilder.build(def, "ii_relic_b_379")
	assert_not_null(sk_a)
	assert_not_null(sk_b)
	bc.registry.register(sk_a, 0)
	bc.registry.register(sk_b, 0)
	var before_dora := int(bc.state.extra_dora_count[0])
	bc.call("_emit", &"WIN_DECLARED_PRE", 0, null, {})
	var iids: Array = []
	for ev in bc.events:
		if not (ev is BattleEvent):
			continue
		var be: BattleEvent = ev as BattleEvent
		if be.type != &"SKILL_TRIGGERED":
			continue
		if str(be.extra.get("skill_id", "")) != "relic_lucky_cat_v1":
			continue
		iids.append(str(be.extra.get("item_instance_id", "")))
	assert_eq(iids.size(), 2, "两实例须各产生一次 SKILL_TRIGGERED")
	iids.sort()
	assert_eq(iids, ["ii_relic_a_379", "ii_relic_b_379"],
		"P2-2：不得都归因到 registry 首实例")
	assert_eq(int(bc.state.extra_dora_count[0]), before_dora + 2)


## P2-3：holder 技能 actor ≠ beneficiary（soul_drain：对手胡 → holder 受益）
func test_p2_owner_holder_actor_beneficiary_split() -> void:
	var bc := BattleController.new(8, 0, false, TileId.E, 0)
	var sk := SkillResource.new()
	sk.id = &"soul_drain_hatsu_v1"
	sk.display_name = "吸魂"
	sk.is_ability = false
	var ht: Array[StringName] = [&"WIN_DECLARED"]
	sk.holder_triggers = ht
	sk.hook_script = load("res://skills/hooks/soul_drain_hatsu_hook.gd") as GDScript
	var ti := TileSkillAnchor.make(Tile.new(TileId.HATSU), 2, sk)
	ti.holder_seat = 1  # holder 受益
	bc.registry.register(sk, ti)
	# actor=0 胡牌，holder=1 吸魂
	bc.state.scores = [25000, 25000, 25000, 25000]
	bc.call("_emit", &"WIN_DECLARED", 0, null, {"points_won": 8000})
	var found := false
	for ev in bc.events:
		if not (ev is BattleEvent):
			continue
		var be: BattleEvent = ev as BattleEvent
		if be.type != &"SKILL_TRIGGERED":
			continue
		if str(be.extra.get("skill_id", "")) != "soul_drain_hatsu_v1":
			continue
		found = true
		assert_eq(int(be.extra.get("actor_seat", -1)), 0,
			"P2-3：actor_seat 须为源事件 actor（胡家）")
		assert_eq(int(be.extra.get("beneficiary_seat", -1)), 1,
			"P2-3：beneficiary 须为 holder")
		assert_ne(int(be.extra.get("actor_seat", -1)),
			int(be.extra.get("beneficiary_seat", -1)))
	assert_true(found, "须产生 holder SKILL_TRIGGERED")
	# 未武装
	var bc2 := BattleController.new(9, 0, false, TileId.E, 0)
	bc2.call("_emit", &"WIN_DECLARED", 0, null, {"points_won": 8000})
	var n2 := 0
	for ev2 in bc2.events:
		if ev2 is BattleEvent and (ev2 as BattleEvent).type == &"SKILL_TRIGGERED":
			n2 += 1
	assert_eq(n2, 0, "未注册不得 SKILL_TRIGGERED")


## 从 live 墙抽出指定 tid 的实体牌（与 loopback settle fixture 同构）
func _draw_live_tid(bc: BattleController, tid: int, used: Dictionary) -> Tile:
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
	assert_true(live_idx >= 0, "live 区无 id=%d" % tid)
	if live_idx < 0:
		return null
	if live_idx != w.draw_index():
		assert_true(w.move_live_index_to_top(live_idx))
	var drawn: Tile = w.draw()
	if drawn != null:
		used[int(drawn.instance_id)] = true
	return drawn


## 七对听 + 摸 W9 → 真实可 TSUMO
func _force_seat0_tsumo_ready(bc: BattleController) -> void:
	var used: Dictionary = {}
	var draw_floor: int = int(bc.state.wall.draw_index())
	for s in range(4):
		var seat: Seat = bc.state.seats[s]
		seat.hand = Hand.new()
		seat.melds.restore([], 0)
		seat.last_drawn_instance_id = Tile.INVALID_INSTANCE_ID
		seat.furiten = FuritenState.new()
		bc.state.seats[s].river.restore([])
	bc.state.wall.set_draw_index(0)
	var ids := [
		TileId.W1, TileId.W1, TileId.W2, TileId.W2, TileId.W3, TileId.W3,
		TileId.W5, TileId.W5, TileId.W6, TileId.W6, TileId.W7, TileId.W7,
		TileId.W9,
	]
	var h := Hand.new()
	for tid in ids:
		var t: Tile = _draw_live_tid(bc, int(tid), used)
		assert_not_null(t)
		assert_true(h.add(t))
	bc.state.seats[0].hand = h
	bc.state.first_round_active = false
	var win_t: Tile = _draw_live_tid(bc, TileId.W9, used)
	assert_not_null(win_t)
	assert_true(bc.state.seats[0].hand.add(win_t))
	bc.state.seats[0].last_drawn_instance_id = win_t.instance_id
	bc.state.current_seat = 0
	bc.state.phase = BattlePhase.Kind.DISCARD
	bc.set("_settled", false)
	bc.set("_active_window", null)
	bc.state.wall.set_draw_index(maxi(draw_floor, int(bc.state.wall.draw_index())))


## P2-4：SKILL_TRIGGERED 须在 HAND_SETTLED 之前（权威 journal）
func test_p2_skill_triggered_before_hand_settled_in_journal() -> void:
	var cfg := GameSessionConfig.create_validated(
		GameSessionConfig.ROOM_PUBLIC_CASUAL, GameSessionConfig.ROUND_EAST,
		GameSessionConfig.MODE_TRASH_TALK,
		[&"HUMAN", &"HUMAN", &"HUMAN", &"HUMAN"],
		[&"hua_ling", &"lin_yeche", &"qiu_jue", &"bai_touli"],
		42, "379r2-order", "rv-253")
	var mods := ModeModuleBundle.from_config(cfg)
	var bc := BattleController.new(42, 0, false, TileId.E, 0)
	bc.bind_mode_modules(mods)
	var srv := LocalLoopbackServer.new(cfg, 0, bc, mods)
	assert_true(srv.start())
	assert_true(BossAbilityFactory.inject(bc.registry, &"char_saki_passive_v1", 0))
	_force_seat0_tsumo_ready(bc)
	var ctx: DecisionContext = bc.decision_context_for_seat(0)
	assert_not_null(ctx)
	assert_true(ctx.has_kind("TSUMO"), "fixture 须 TSUMO")
	var room := ""
	for ne0 in srv.event_journal(0):
		if ne0 is NetworkedEvent and not (ne0 as NetworkedEvent).room_id.is_empty():
			room = (ne0 as NetworkedEvent).room_id
			break
	var cmd := "550e8400-e29b-41d4-a716-000000000342"
	var cr: CommandResult = srv.submit_action(Action.tsumo(
		0, room, cmd, str(ctx.decision_id), int(ctx.hand_seq),
		int(srv.current_server_seq()) + 1))
	assert_eq(cr.status, "ACCEPTED", cr.error_code)
	var kinds: Array = _journal_kinds(srv)
	var skill_i := kinds.find("SKILL_TRIGGERED")
	var hand_i := kinds.find("HAND_SETTLED")
	assert_gte(skill_i, 0, "journal 须含 SKILL_TRIGGERED（华岭自摸） kinds=%s" % str(kinds))
	assert_gte(hand_i, 0, "journal 须含 HAND_SETTLED kinds=%s" % str(kinds))
	assert_lt(skill_i, hand_i,
		"P2-4：SKILL_TRIGGERED 须早于 HAND_SETTLED（kinds=%s）" % str(kinds))
	var skill_n := 0
	for k in kinds:
		if k == "SKILL_TRIGGERED":
			skill_n += 1
	var cr2: CommandResult = srv.submit_action(Action.tsumo(
		0, room, cmd, str(ctx.decision_id), int(ctx.hand_seq),
		int(srv.current_server_seq()) + 1))
	assert_eq(cr2.status, "ACCEPTED")
	var skill_n2 := 0
	for k2 in _journal_kinds(srv):
		if k2 == "SKILL_TRIGGERED":
			skill_n2 += 1
	assert_eq(skill_n2, skill_n, "同 command 重放不得重复 SKILL_TRIGGERED")
