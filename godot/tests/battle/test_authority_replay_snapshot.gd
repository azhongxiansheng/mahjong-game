extends GutTest
# E2-02 Red：AuthorityReplaySnapshot 穷尽字段。真实 BC/State；缺文件/load 失败明确 Red。
# 禁源码字符串门禁、禁 restore_controller has_method、禁恒真断言。
# 公开 journal/replay 仅 action_journal / load_replay_journal / replay_status；无旧 API fallback。
# journal 非空仅经 apply_action 产生；禁 set 私有 _action_journal / set_replay_actions。

const AP := "res://battle/authority_replay_snapshot.gd"
const BP := "res://battle/battle_controller.gd"
const HOOK_A := "res://skills/hooks/xray_1w_hook.gd"
const HOOK_B := "res://skills/hooks/seal_chun_hook.gd"
const ROOM := "ars-red-room"
const FORBIDDEN_ROOM_KEYS := ["modules", "seat_view", "snapshot_server_seq"]
# 0..18：wall/dora/hand/meld/riichi/furiten/scores/points/revealed/kuikae/momentum/
# window_intent/replay_cursor/skill_consumed/skill_anchor/reg_order/next_order/
# sched_chain/event_depth/window_subject
const MUT_N := 19

func _cmd(n: int) -> String:
	return "550e8400-e29b-41d4-a716-%012d" % n

func _hex64(h: String) -> bool:
	return h.length() == 64 and h == h.to_lower() and h.is_valid_hex_number()

func _ars_ready() -> GDScript:
	assert_true(ResourceLoader.exists(AP), "ARS_RED: 缺 authority_replay_snapshot.gd")
	if not ResourceLoader.exists(AP):
		return null
	var scr: GDScript = load(AP) as GDScript
	if scr == null:
		assert_true(false, "ARS_RED: ARS load 失败（并行 parse 未收敛）")
		return null
	return scr

func _bc_ready() -> GDScript:
	assert_true(ResourceLoader.exists(BP), "ARS_RED: 缺 BattleController")
	if not ResourceLoader.exists(BP):
		return null
	var scr: GDScript = load(BP) as GDScript
	if scr == null or not scr.can_instantiate():
		assert_true(false, "ARS_RED: BC load/实例化失败（并行 parse 未收敛）")
		return null
	return scr

func _make_bc(scr: GDScript, rng_seed: int = 7, hand_seq: int = 3) -> Object:
	var bc: Object = scr.new(rng_seed, 0, false, TileId.E, hand_seq)
	assert_not_null(bc)
	if bc == null or bc.get("state") == null:
		assert_true(false, "ARS_RED: BC 构造失败")
		return null
	return bc

func _skill(id: StringName, hook_path: String, consumed: bool) -> SkillResource:
	var s := SkillResource.new()
	s.id = id
	s.display_name = str(id)
	s.description = "ars-red"
	s.hook_script = load(hook_path) as GDScript
	s.consumed = consumed
	return s

func _ns_lo(hs: int) -> int:
	return hs * 136

func _ns_hi(hs: int) -> int:
	return hs * 136 + 135

func _iid_in_hand_seq_ns(iid: int, hs: int) -> bool:
	return iid >= _ns_lo(hs) and iid <= _ns_hi(hs)

## 活动区占用：hand/river/meld/revealed/skill-tile-anchor（wall 本体不算活动区）。
func _collect_active_iids(st: BattleState, reg: SkillRegistry = null) -> Dictionary:
	var occ: Dictionary = {}
	for si in range(4):
		var seat: Seat = st.seats[si]
		for t in seat.hand.tiles():
			if t is Tile:
				occ[int((t as Tile).instance_id)] = true
		for t in seat.river.tiles():
			if t is Tile:
				occ[int((t as Tile).instance_id)] = true
		for m in seat.melds.all():
			if m is Meld:
				for mt in (m as Meld).tiles:
					if mt is Tile:
						occ[int((mt as Tile).instance_id)] = true
	for item in st.revealed_tiles:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var raw = (item as Dictionary).get("tile", null)
		if raw is TileSkillAnchor and (raw as TileSkillAnchor).tile != null:
			occ[int((raw as TileSkillAnchor).tile.instance_id)] = true
		elif raw is Tile:
			occ[int((raw as Tile).instance_id)] = true
	if reg != null:
		for e in reg.get_all_entries():
			var anchor = e["anchor"]
			if anchor is TileSkillAnchor and (anchor as TileSkillAnchor).tile != null:
				occ[int((anchor as TileSkillAnchor).tile.instance_id)] = true
	return occ

func _tile_in_any_hand(st: BattleState, iid: int) -> int:
	for si in range(4):
		if st.seats[si].hand.find_by_instance_id(iid) != null:
			return si
	return -1

## 按 tile id + 未占用 iid 从 state.wall.authority_tiles() 选取真实实体；不得 new Tile 造 iid。
## 优先未在任何手牌中的墙牌；若只能从手取，按 instance_id 从原手移除。
## 选中后写入 occupied；失败返 null。
## tid < 0 时按 wall 顺序取任意未占用真实实体（mutation 回退）。
func _pick_wall_tile(st: BattleState, tid: int, occupied: Dictionary) -> Tile:
	var hs: int = int(st.hand_seq)
	var undrawn: Array = []
	var in_hand: Array = []
	for t in st.wall.authority_tiles():
		if t == null or not (t is Tile):
			continue
		var tile: Tile = t as Tile
		if tid >= 0 and int(tile.id) != tid:
			continue
		var iid: int = int(tile.instance_id)
		if not _iid_in_hand_seq_ns(iid, hs):
			continue
		if occupied.has(iid):
			continue
		if _tile_in_any_hand(st, iid) >= 0:
			in_hand.append(tile)
		else:
			undrawn.append(tile)
	var pick: Tile = null
	if not undrawn.is_empty():
		pick = undrawn[0] as Tile
	elif not in_hand.is_empty():
		pick = in_hand[0] as Tile
		var seat_i: int = _tile_in_any_hand(st, int(pick.instance_id))
		assert_gte(seat_i, 0, "in_hand 候选须仍在某手")
		if seat_i >= 0:
			var taken: Tile = st.seats[seat_i].hand.take_by_instance_id(pick.instance_id)
			assert_not_null(taken, "从手取牌须按 instance_id 成功")
			assert_eq(int(taken.instance_id), int(pick.instance_id))
	if pick == null:
		return null
	occupied[int(pick.instance_id)] = true
	return pick

func _pick_wall_tile_prefer(st: BattleState, preferred_tids: Array, occupied: Dictionary) -> Tile:
	for raw in preferred_tids:
		var t: Tile = _pick_wall_tile(st, int(raw), occupied)
		if t != null:
			return t
	return _pick_wall_tile(st, -1, occupied)

func _tiles_dicts(tiles: Array) -> Array:
	var out: Array = []
	for t in tiles:
		out.append((t as Tile).to_dict())
	return out

func _meld_dict(m: Meld) -> Dictionary:
	return {
		"kind": int(m.kind), "from": int(m.from_seat), "meld_id": int(m.meld_id),
		"called": int(m.called_tile_instance_id), "added": int(m.added_tile_instance_id),
		"tiles": _tiles_dicts(m.tiles),
	}

func _skill_entry_dict(e: Dictionary) -> Dictionary:
	var sk: SkillResource = e["skill"]
	var anchor = e["anchor"]
	var anchor_kind := "int"
	var anchor_val: Variant = 0
	if typeof(anchor) == TYPE_INT:
		anchor_val = int(anchor)
	elif anchor is TileSkillAnchor and (anchor as TileSkillAnchor).tile != null:
		anchor_kind = "tile"
		anchor_val = int((anchor as TileSkillAnchor).tile.instance_id)
	else:
		anchor_kind = "other"
		anchor_val = str(anchor)
	return {
		"id": str(sk.id),
		"hook_path": sk.hook_script.resource_path if sk.hook_script else "",
		"consumed": bool(sk.consumed),
		"anchor_kind": anchor_kind, "anchor": anchor_val,
		"reg_order": int(e["reg_order"]),
	}

func _actions_dicts(raw: Array) -> Array:
	var out: Array = []
	for a in raw:
		if a is Action:
			out.append((a as Action).to_dict())
	return out

func _events_dicts(raw: Array) -> Array:
	var out: Array = []
	for ev in raw:
		if ev is BattleEvent:
			out.append((ev as BattleEvent).to_dict())
	return out

func _revealed_norm(items: Array) -> Array:
	var out: Array = []
	for item in items:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = item
		var tile_d := {}
		var t = d.get("tile", null)
		if t is TileSkillAnchor:
			tile_d = (t as TileSkillAnchor).to_dict()
		elif t is Tile:
			tile_d = (t as Tile).to_dict()
		elif typeof(t) == TYPE_DICTIONARY:
			tile_d = (t as Dictionary).duplicate(true)
		var vis: Array = []
		if d.get("visible_to") is Array:
			vis = (d["visible_to"] as Array).duplicate()
		out.append({"tile": tile_d, "visible_to": vis})
	return out

func _window_dict(win: DecisionWindow) -> Dictionary:
	var intents: Array = []
	for a in win.intents():
		intents.append((a as Action).to_dict())
	var ctxs: Array = []
	for s in win.seats():
		var c: DecisionContext = win.context_for_seat(int(s))
		if c:
			ctxs.append(c.to_dict())
	var responded: Array = []
	for s in win.seats():
		if win.has_responded(int(s)):
			responded.append(int(s))
	responded.sort()
	return {
		"kind": win.kind, "decision_id": win.decision_id, "hand_seq": win.hand_seq,
		"subject_seat": win.subject_seat,
		"subject_tile_instance_id": int(win.subject_tile_instance_id),
		"discarder_seat": int(win.discarder_seat),
		"responded": responded, "contexts": ctxs, "intents": intents,
	}

## 当前 BC 字段名：_active_window（无 decision_window fallback）。
func _get_window(bc: Object) -> DecisionWindow:
	var win = bc.get("_active_window")
	return win as DecisionWindow if win is DecisionWindow else null

## 仅公开 API；缺 method 精确 Red，禁 _action_journal 私有 fallback。
func _action_journal_raw(bc: Object) -> Array:
	assert_true(bc.has_method("action_journal"), "ARS_RED: 缺公开 action_journal()")
	if not bc.has_method("action_journal"):
		return []
	var raw: Variant = bc.call("action_journal")
	if raw is Array:
		return raw as Array
	return []

func _last_discarded_dict(bc: Object) -> Dictionary:
	var t = bc.get("_last_discarded_tile")
	if t is Tile:
		return (t as Tile).to_dict()
	return {}

func _discard_offer_iids(ctx: DecisionContext) -> Array:
	var out: Array = []
	if ctx == null:
		return out
	for offer in ctx.allowed_actions:
		if typeof(offer) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = offer
		if str(d.get("kind", "")) != "DISCARD":
			continue
		for opt in d.get("payload_options", []):
			if opt is Dictionary and (opt as Dictionary).has("tile_instance_id"):
				out.append(int((opt as Dictionary)["tile_instance_id"]))
	return out

func _apply(bc: Object, action: Action, source: StringName = ActionSource.HUMAN) -> ActionResolution:
	assert_true(bc.has_method("apply_action"), "ARS_RED: 缺公开 apply_action()")
	if not bc.has_method("apply_action"):
		return null
	var raw: Variant = bc.call("apply_action", action, source)
	assert_true(raw is ActionResolution, "apply_action 须返 ActionResolution")
	if not (raw is ActionResolution):
		return null
	return raw as ActionResolution

## 完整实体 fixture：wall/dora/seat/meld/state/window/journal/skills → deterministic dict。
func _fixture_dict(bc: Object) -> Dictionary:
	var st: BattleState = bc.get("state") as BattleState
	var wall: Wall = st.wall
	var seats_f: Array = []
	for si in range(4):
		var seat: Seat = st.seats[si]
		var melds_f: Array = []
		for m in seat.melds.all():
			melds_f.append(_meld_dict(m as Meld))
		seats_f.append({
			"hand": _tiles_dicts(seat.hand.tiles()),
			"river": _tiles_dicts(seat.river.tiles()),
			"melds": melds_f,
			"next_meld_id": int(seat.melds.next_local_index()),
			"last_draw": int(seat.last_drawn_instance_id),
			"rinshan": bool(seat.last_draw_is_rinshan),
			"points": int(seat.points),
			"riichi": {
				"declared": bool(seat.riichi.declared),
				"declared_turn": int(seat.riichi.declared_turn),
				"ippatsu": bool(seat.riichi.ippatsu_window),
				"stick": bool(seat.riichi.riichi_stick_paid),
				"double": bool(seat.riichi.double_riichi),
				"discard_index": int(seat.river.riichi_discard_index()),
			},
			"furiten": {
				"permanent": bool(seat.furiten.permanent),
				"temporary": bool(seat.furiten.temporary),
				"waits": seat.furiten.waits.duplicate(),
			},
		})
	var reg: SkillRegistry = bc.get("registry") as SkillRegistry
	var skills: Array = []
	for e in reg.get_all_entries():
		skills.append(_skill_entry_dict(e))
	var win_f := {}
	var win := _get_window(bc)
	if win != null:
		win_f = _window_dict(win)
	var event_journal: Array = []
	if bc.get("events") is Array:
		event_journal = _events_dicts(bc.get("events"))
	var sched: SkillScheduler = bc.get("scheduler") as SkillScheduler
	assert_true(bc.has_method("replay_status"), "ARS_RED: 缺公开 replay_status()")
	var replay_status := ""
	if bc.has_method("replay_status"):
		replay_status = str(bc.call("replay_status"))
	# 实际字段：_expected_replay_idx（非 _replay_action_idx）
	var replay_idx := int(bc.get("_expected_replay_idx")) if bc.get("_expected_replay_idx") != null else -1
	# decision counter：_window_seq
	var window_seq := int(bc.get("_window_seq")) if bc.get("_window_seq") != null else -1
	return {
		"hand_seq": int(st.hand_seq), "phase": int(st.phase),
		"current_seat": int(st.current_seat), "scores": st.scores.duplicate(),
		"turn_count": int(st.turn_count), "first_round_active": bool(st.first_round_active),
		"furiten_flags": st.furiten_flags.duplicate(),
		"ron_cancelled": st.ron_cancelled.duplicate(),
		"haitei_forced_seat": int(st.haitei_forced_seat),
		"extra_dora_count": st.extra_dora_count.duplicate(),
		"extra_red_dora_count": st.extra_red_dora_count.duplicate(),
		"event_chain_depth": int(st.event_chain_depth),
		"revealed": _revealed_norm(st.revealed_tiles),
		"kuikae": st.kuikae_restricted.duplicate(true),
		"momentum_total": float(st.momentum.total_momentum),
		"momentum_scores": st.momentum.scores.duplicate(true),
		"wall": {
			"tiles": _tiles_dicts(wall.authority_tiles()),
			"draw_index": wall.draw_index(),
			"dead_size": wall.dead_wall_size(),
			"rinshan_taken": wall.rinshan_taken(),
			"live": int(wall.live_wall_size()),
		},
		"dora": _tiles_dicts(st.dora_indicators.visible_tiles()),
		"ura": _tiles_dicts(st.dora_indicators.uradora_tiles()),
		"seats": seats_f, "skills": skills,
		"reg_next_order": int(reg.get("_next_order")),
		"sched_next_chain": int(sched.get("_next_chain_id")),
		"window": win_f,
		"action_journal": _actions_dicts(_action_journal_raw(bc)),
		"event_journal": event_journal,
		"settled": bool(bc.get("_settled")) if bc.get("_settled") != null else false,
		"last_event": str(bc.get("_last_event_type")) if bc.get("_last_event_type") != null else "",
		"last_discarder": int(bc.get("_last_discarder_seat")) if bc.get("_last_discarder_seat") != null else -1,
		"last_discarded": _last_discarded_dict(bc),
		"window_seq": window_seq,
		"replay_status": replay_status, "replay_idx": replay_idx,
	}

func _assert_fixture_eq(a: Dictionary, b: Dictionary, tag: String) -> void:
	assert_eq(JSON.stringify(a), JSON.stringify(b), "fixture 字段等值: %s" % tag)

## 领域丰化 + 公开 apply_action 产 journal + 真实 CLAIM 窗 + 独立 load_replay_journal。
func _enrich(bc: Object) -> Dictionary:
	var st: BattleState = bc.get("state") as BattleState
	var engine: TurnEngine = bc.get("engine") as TurnEngine
	var hs: int = int(st.hand_seq)
	if st.phase == BattlePhase.Kind.DRAW:
		engine.draw_for_current()
	assert_eq(st.phase, BattlePhase.Kind.DISCARD)
	var wall: Wall = st.wall
	assert_true(wall.set_rinshan_taken(1))
	var dora1: Tile = wall.peek_dora_indicator(1)
	var ura1: Tile = wall.peek_uradora_indicator(1)
	if dora1 != null and ura1 != null:
		assert_true(st.dora_indicators.reveal_pair(dora1, ura1))
	st.scores = [24000, 26000, 23000, 27000] as Array[int]
	st.turn_count = 5
	st.first_round_active = false
	st.furiten_flags = [true, false, true, false] as Array[bool]
	st.ron_cancelled = [false, true, false, false] as Array[bool]
	st.haitei_forced_seat = 2
	st.extra_dora_count = [1, 0, 2, 0] as Array[int]
	st.extra_red_dora_count = [0, 1, 0, 0] as Array[int]
	st.event_chain_depth = 0
	var disc_seat: int = int(st.current_seat)
	# 活动区占用：先登记河；手牌仅在被取走时按 iid 移除，避免同 iid 双持。
	var occupied: Dictionary = {}
	for si in range(4):
		var seat: Seat = st.seats[si]
		seat.points = 25000 + si * 100 + 17
		# 他席可先入河；当前席保留 14 张以便 DISCARD apply_action
		if si != disc_seat and seat.hand.size() > 2:
			var t: Tile = seat.hand.tiles()[0]
			seat.hand.take_by_instance_id(t.instance_id)
			seat.river.append_discard(t)
			occupied[int(t.instance_id)] = true
		if si == disc_seat:
			seat.last_draw_is_rinshan = true
		# 当前席勿预立直，以免封锁 DISCARD offer 路径
		if si != disc_seat:
			seat.riichi.declared = true
			seat.riichi.declared_turn = 2 + si
			seat.riichi.ippatsu_window = (si % 2 == 0)
			seat.riichi.riichi_stick_paid = true
			seat.riichi.double_riichi = (si == 1)
			assert_true(seat.river.restore(seat.river.tiles(), 0))
		seat.furiten.permanent = (si == 0)
		seat.furiten.temporary = (si == 2)
		seat.furiten.waits = [TileId.W1 + si, TileId.T5]
	# 四席合法 CHI：tiles 序 W1/W2/W3、called=W3、from 他席；实体仅来自 wall 本局 namespace
	for si in range(4):
		var seat: Seat = st.seats[si]
		var t1: Tile = _pick_wall_tile(st, TileId.W1, occupied)
		var t2: Tile = _pick_wall_tile(st, TileId.W2, occupied)
		var t3: Tile = _pick_wall_tile(st, TileId.W3, occupied)
		assert_not_null(t1, "CHI 须从 wall 选到真实 W1")
		assert_not_null(t2, "CHI 须从 wall 选到真实 W2")
		assert_not_null(t3, "CHI 须从 wall 选到真实 W3")
		if t1 == null or t2 == null or t3 == null:
			return {}
		assert_eq(int(t1.id), TileId.W1)
		assert_eq(int(t2.id), TileId.W2)
		assert_eq(int(t3.id), TileId.W3)
		var mt: Array[Tile] = [t1, t2, t3]
		seat.melds.add_existing(Meld.make_chi(mt, (si + 1) % 4, si, t3))
		assert_true(seat.melds.restore(seat.melds.all(), si + 5))
	var rev_src: Tile = _pick_wall_tile(st, TileId.S3, occupied)
	assert_not_null(rev_src, "revealed 须本局 wall 真实 S3 iid")
	if rev_src == null:
		return {}
	var rev_tile := TileSkillAnchor.make(rev_src, 1, null)
	st.revealed_tiles = [{"tile": rev_tile, "visible_to": [0, 2]}]
	st.kuikae_restricted = [[TileId.W2], [], [TileId.T1], []]
	st.momentum.scores[Momentum.Attribute.DOMINATION] = 0.7
	st.momentum.scores[Momentum.Attribute.CALM] = 0.4
	st.momentum._recalculate_total()
	var reg: SkillRegistry = bc.get("registry") as SkillRegistry
	var sk_a := _skill(&"ars_probe_a", HOOK_A, false)
	var sk_b := _skill(&"ars_probe_b", HOOK_B, true)
	var anchor_src: Tile = _pick_wall_tile(st, TileId.W5, occupied)
	assert_not_null(anchor_src, "skill anchor 须本局 wall 真实 W5 iid")
	if anchor_src == null:
		return {}
	reg.register(sk_a, TileSkillAnchor.make(anchor_src, 0, sk_a))
	reg.register(sk_b, 2)
	var sched: SkillScheduler = bc.get("scheduler") as SkillScheduler
	sched.emit_event(BattleEvent.make(&"ARS_ENRICH_PROBE", 0, null, {"probe": 1}))
	assert_eq(st.event_chain_depth, 0)
	assert_gt(int(sched.get("_next_chain_id")), 1)
	var ev_list = bc.get("events")
	if ev_list is Array and (ev_list as Array).is_empty():
		(ev_list as Array).append(BattleEvent.make(&"ARS_JOURNAL_SEED", 1, null, {"n": 1}))

	# ── 1) 公开 apply_action 产 accepted journal（DISCARD）；禁 set 私有 _action_journal ──
	assert_true(bc.has_method("action_journal"), "ARS_RED: 缺公开 action_journal()")
	if not bc.has_method("action_journal"):
		return {}
	assert_true(bc.has_method("decision_context_for_seat"),
		"ARS_RED: 缺公开 decision_context_for_seat()")
	if not bc.has_method("decision_context_for_seat"):
		return {}
	var turn_ctx_raw: Variant = bc.call("decision_context_for_seat", disc_seat)
	assert_true(turn_ctx_raw is DecisionContext, "TURN DecisionContext 须可得")
	if not (turn_ctx_raw is DecisionContext):
		return {}
	var turn_ctx: DecisionContext = turn_ctx_raw as DecisionContext
	var disc_iids: Array = _discard_offer_iids(turn_ctx)
	assert_gt(disc_iids.size(), 0, "TURN 须 offer DISCARD")
	if disc_iids.is_empty():
		return {}
	var disc_iid: int = int(disc_iids[0])
	var disc_act: Action = Action.discard(
		disc_seat, disc_iid, ROOM, _cmd(1), turn_ctx.decision_id, hs, 1)
	assert_not_null(disc_act, "Action.discard 须成功")
	if disc_act == null:
		return {}
	var disc_res: ActionResolution = _apply(bc, disc_act, ActionSource.HUMAN)
	assert_not_null(disc_res, "apply_action DISCARD 须返 Resolution")
	if disc_res == null:
		return {}
	assert_true(disc_res.accepted, "合法 DISCARD 须 accepted 进 journal")
	if not disc_res.accepted:
		return {}
	assert_false(_action_journal_raw(bc).is_empty(), "apply_action 后 action_journal 须非空")
	if _action_journal_raw(bc).is_empty():
		return {}

	# 真实弃牌后：phase=CLAIM、_last_discarded_tile 完整实体、河含 subject iid
	assert_eq(st.phase, BattlePhase.Kind.CLAIM, "discard 后 phase=CLAIM")
	var last_tile = bc.get("_last_discarded_tile")
	assert_true(last_tile is Tile, "ARS_RED: 须有真实 _last_discarded_tile Tile")
	if not (last_tile is Tile):
		return {}
	var subj_iid: int = int((last_tile as Tile).instance_id)
	assert_eq(subj_iid, disc_iid, "last_discarded.instance_id 对齐 DISCARD payload")
	var river: Array = st.seats[disc_seat].river.tiles()
	assert_gt(river.size(), 0, "discarder 河须有牌")
	if river.is_empty():
		return {}
	var river_has := false
	for rt in river:
		if rt is Tile and int((rt as Tile).instance_id) == subj_iid:
			river_has = true
			break
	assert_true(river_has, "subject iid 须来自 discarder 河")

	# ── 2) 真实 CLAIM 窗：subject==discarder；context 他席 + PASS [{}]；公开 PASS 工厂 ──
	var claim_seat: int = (disc_seat + 1) % 4
	assert_ne(claim_seat, disc_seat)
	var claim_ctx_raw: Variant = bc.call("decision_context_for_seat", claim_seat)
	assert_true(claim_ctx_raw is DecisionContext, "CLAIM DecisionContext 须可得")
	if not (claim_ctx_raw is DecisionContext):
		return {}
	var claim_ctx: DecisionContext = claim_ctx_raw as DecisionContext
	assert_eq(claim_ctx.window_kind, DecisionContext.KIND_CLAIM)
	assert_eq(int(claim_ctx.seat), claim_seat)
	assert_ne(int(claim_ctx.seat), disc_seat)
	assert_eq(int(claim_ctx.discarder_seat), disc_seat)
	assert_eq(int(claim_ctx.claimed_tile_instance_id), subj_iid)
	assert_true(claim_ctx.has_kind("PASS"), "CLAIM offer 须含 PASS")
	assert_true(claim_ctx.allows("PASS", {}), "PASS payload {} 须合法")

	var win := _get_window(bc)
	assert_not_null(win, "ARS_RED: 缺 _active_window DecisionWindow")
	if win == null:
		return {}
	assert_eq(win.kind, DecisionWindow.KIND_CLAIM)
	assert_eq(int(win.subject_seat), disc_seat, "CLAIM subject==discarder")
	assert_eq(int(win.discarder_seat), disc_seat)
	assert_eq(int(win.subject_tile_instance_id), subj_iid, "subject tile 来自 discarder 河")

	# PASS 经 apply_action 进 journal（窗 intent 亦经公开入口登记；非私有数组）
	var pass_act: Action = Action.make_pass(
		claim_seat, ROOM, _cmd(2), claim_ctx.decision_id, hs, 2)
	assert_not_null(pass_act, "Action.make_pass 须成功")
	if pass_act == null:
		return {}
	var j_before: int = _action_journal_raw(bc).size()
	var pass_res: ActionResolution = _apply(bc, pass_act, ActionSource.HUMAN)
	assert_not_null(pass_res)
	if pass_res == null:
		return {}
	assert_true(pass_res.accepted, "合法 CLAIM PASS 须 accepted 进 journal")
	if not pass_res.accepted:
		return {}
	assert_gt(_action_journal_raw(bc).size(), j_before, "PASS 须追加 journal")
	win = _get_window(bc)
	# 多席 CLAIM 未齐 → 窗仍在；至少 claim_seat 已 respond
	assert_not_null(win, "部分 PASS 后 CLAIM 窗应仍存活")
	if win == null:
		return {}
	assert_true(win.has_responded(claim_seat), "PASS 后 claim_seat 已 respond")
	assert_gt(win.intents().size(), 0, "window intents 非空")
	assert_eq(str((win.intents()[0] as Action).kind), "PASS")

	# ── 3) 独立 replay queue：仅 load_replay_journal（与 journal 分离；禁私有 set）──
	assert_true(bc.has_method("load_replay_journal"), "ARS_RED: 缺公开 load_replay_journal()")
	if not bc.has_method("load_replay_journal"):
		return {}
	# 深拷贝当前 journal 装入期望队列（公开 API；装载不污染 accepted journal）
	var replay_src: Array = []
	for a in _action_journal_raw(bc):
		if a is Action:
			var cloned: Action = Action.from_dict((a as Action).to_dict())
			assert_not_null(cloned)
			if cloned != null:
				replay_src.append(cloned)
	assert_gt(replay_src.size(), 0, "replay 源须非空 Action[]")
	var j_size_before_load: int = _action_journal_raw(bc).size()
	assert_true(bool(bc.call("load_replay_journal", replay_src)),
		"load_replay_journal 须接受 Action 数组")
	assert_eq(_action_journal_raw(bc).size(), j_size_before_load,
		"load_replay_journal 不得改 accepted journal")
	assert_true(bc.has_method("replay_status"), "ARS_RED: 缺公开 replay_status()")
	if not bc.has_method("replay_status"):
		return {}
	assert_eq(str(bc.call("replay_status")), "LOADED", "load 后 replay_status=LOADED")

	bc.set("_settled", false)
	# 捕获真实 _window_seq / _expected_replay_idx / last_discarded（不虚构字段）
	var fix := _fixture_dict(bc)
	assert_ne(fix["scores"][0], fix["seats"][0]["points"], "scores≠Seat.points")
	assert_eq(int(fix["turn_count"]), 5)
	assert_false(bool(fix["first_round_active"]))
	assert_eq(int(fix["haitei_forced_seat"]), 2)
	assert_eq((fix["skills"] as Array).size(), 2)
	assert_gt((fix["seats"][disc_seat]["river"] as Array).size(), 0)
	assert_gt((fix["seats"][0]["melds"] as Array).size(), 0)
	assert_eq(int((fix["seats"][0]["melds"] as Array)[0]["kind"]), int(Meld.Kind.CHI))
	assert_false((fix["window"] as Dictionary).is_empty(), "window 须真实建立")
	var win_d: Dictionary = fix["window"] as Dictionary
	assert_eq(str(win_d.get("kind", "")), DecisionWindow.KIND_CLAIM, "window 须为 CLAIM")
	assert_eq(int(win_d.get("subject_seat", -2)), int(win_d.get("discarder_seat", -3)),
		"CLAIM subject==discarder")
	assert_eq(int(win_d.get("subject_tile_instance_id", -1)), subj_iid,
		"subject tile 来自 discarder 河")
	assert_gt((win_d.get("intents", []) as Array).size(), 0)
	assert_eq(str((win_d.get("intents", []) as Array)[0].get("kind", "")), "PASS")
	assert_gt((fix["action_journal"] as Array).size(), 0, "action journal 须非空")
	# journal 仅经 apply_action：至少 DISCARD + PASS
	var j_kinds: Array = []
	for ja in fix["action_journal"] as Array:
		j_kinds.append(str((ja as Dictionary).get("kind", "")))
	assert_true(j_kinds.has("DISCARD"), "journal 须含 apply_action DISCARD")
	assert_true(j_kinds.has("PASS"), "journal 须含 apply_action PASS")
	# 完整 Tile dict（真实 _last_discarded_tile）
	assert_false((fix["last_discarded"] as Dictionary).is_empty(),
		"last_discarded 完整 Tile dict 须入 fixture")
	assert_eq(int((fix["last_discarded"] as Dictionary).get("instance_id", -1)), subj_iid)
	assert_true((fix["last_discarded"] as Dictionary).has("id"),
		"last_discarded Tile dict 须含 id")
	assert_eq(int(fix["replay_idx"]), 0, "load 后 _expected_replay_idx=0")
	assert_gte(int(fix["window_seq"]), 1, "真实 _window_seq 入 fixture")
	assert_eq(str(fix["replay_status"]), "LOADED")
	assert_gt(int(fix["sched_next_chain"]), 1)
	assert_gt(int(fix["wall"]["rinshan_taken"]), 0)
	assert_eq((fix["wall"]["tiles"] as Array).size(), 136)
	assert_gt((fix["dora"] as Array).size(), 0)
	assert_eq((fix["revealed"] as Array).size(), 1)
	assert_eq(typeof((fix["revealed"] as Array)[0]["tile"]), TYPE_DICTIONARY,
		"revealed.tile 须规范化 dict，禁 RefCounted")
	_assert_rich_fixture_identity(fix, hs, disc_seat)
	return fix

## 基线身份契约：本局 namespace + 活动区全局唯一 + 四席 CHI W1/W2/W3 与 called∈tiles。
func _assert_rich_fixture_identity(fix: Dictionary, hs: int, disc_seat: int) -> void:
	var lo: int = _ns_lo(hs)
	var hi: int = _ns_hi(hs)
	var all_tile_iids: Array = []
	# wall / dora / ura
	for t in fix["wall"]["tiles"] as Array:
		assert_true(typeof(t) == TYPE_DICTIONARY)
		var iid: int = int((t as Dictionary).get("instance_id", -1))
		assert_true(iid >= lo and iid <= hi, "wall tile iid 须在本局 namespace [%d,%d] 得 %d" % [lo, hi, iid])
		var serial: int = iid - lo
		assert_true(serial >= 0 and serial <= 135, "canonical serial 0..135 得 %d" % serial)
		all_tile_iids.append(iid)
	assert_eq(all_tile_iids.size(), 136)
	for t in fix["dora"] as Array:
		var iid2: int = int((t as Dictionary).get("instance_id", -1))
		assert_true(iid2 >= lo and iid2 <= hi, "dora iid 本局 namespace")
	for t in fix["ura"] as Array:
		var iid3: int = int((t as Dictionary).get("instance_id", -1))
		assert_true(iid3 >= lo and iid3 <= hi, "ura iid 本局 namespace")
	# hand / river / meld 活动区全局唯一
	var active: Dictionary = {}
	for si in range(4):
		var seat_f: Dictionary = (fix["seats"] as Array)[si]
		for t in seat_f["hand"] as Array:
			var hiid: int = int((t as Dictionary).get("instance_id", -1))
			assert_true(hiid >= lo and hiid <= hi, "hand iid 本局 namespace seat=%d" % si)
			assert_false(active.has(hiid), "活动区唯一：hand 重复 iid=%d" % hiid)
			active[hiid] = "hand:%d" % si
		for t in seat_f["river"] as Array:
			var riid: int = int((t as Dictionary).get("instance_id", -1))
			assert_true(riid >= lo and riid <= hi, "river iid 本局 namespace seat=%d" % si)
			assert_false(active.has(riid), "活动区唯一：river 重复 iid=%d" % riid)
			active[riid] = "river:%d" % si
		for md in seat_f["melds"] as Array:
			var md_d: Dictionary = md
			assert_eq(int(md_d.get("kind", -1)), int(Meld.Kind.CHI), "基线副露须为 CHI")
			var tiles_arr: Array = md_d.get("tiles", []) as Array
			assert_eq(tiles_arr.size(), 3, "CHI 须 3 张")
			assert_eq(int((tiles_arr[0] as Dictionary).get("id", -1)), TileId.W1, "CHI tiles[0]=W1")
			assert_eq(int((tiles_arr[1] as Dictionary).get("id", -1)), TileId.W2, "CHI tiles[1]=W2")
			assert_eq(int((tiles_arr[2] as Dictionary).get("id", -1)), TileId.W3, "CHI tiles[2]=W3")
			var called: int = int(md_d.get("called", -1))
			var called_in_tiles := false
			for td in tiles_arr:
				var miid: int = int((td as Dictionary).get("instance_id", -1))
				assert_true(miid >= lo and miid <= hi, "meld tile iid 本局 namespace")
				assert_false(active.has(miid), "活动区唯一：meld 与 hand/river/它 meld 重复 iid=%d" % miid)
				active[miid] = "meld:%d" % si
				if miid == called:
					called_in_tiles = true
			assert_true(called_in_tiles, "CHI called iid 须属于 tiles")
			assert_eq(called, int((tiles_arr[2] as Dictionary).get("instance_id", -2)),
				"CHI called=W3（tiles[2]）")
	# revealed / skill tile-anchor：本局 namespace且不与 hand/river/meld 重复
	for item in fix["revealed"] as Array:
		var tile_d: Dictionary = (item as Dictionary).get("tile", {}) as Dictionary
		var revid: int = -1
		if tile_d.has("instance_id"):
			revid = int(tile_d["instance_id"])
		elif tile_d.has("tile_instance_id"):
			revid = int(tile_d["tile_instance_id"])
		assert_true(revid >= lo and revid <= hi, "revealed iid 本局 namespace")
		assert_false(active.has(revid), "活动区唯一：revealed 与 hand/river/meld 重复 iid=%d" % revid)
		active[revid] = "revealed"
	for sk in fix["skills"] as Array:
		var sk_d: Dictionary = sk
		if str(sk_d.get("anchor_kind", "")) != "tile":
			continue
		var aid: int = int(sk_d.get("anchor", -1))
		assert_true(aid >= lo and aid <= hi, "skill anchor iid 本局 namespace")
		assert_false(active.has(aid), "活动区唯一：skill anchor 与活动区重复 iid=%d" % aid)
		active[aid] = "skill_anchor"
	# last_discarded 亦须本局 namespace（与 discarder 河同源）
	var last_d: Dictionary = fix["last_discarded"] as Dictionary
	if not last_d.is_empty():
		var lid: int = int(last_d.get("instance_id", -1))
		assert_true(lid >= lo and lid <= hi, "last_discarded iid 本局 namespace")
		assert_true(active.has(lid), "last_discarded 应关联 discarder 河实体")
	assert_gt((fix["seats"][disc_seat]["river"] as Array).size(), 0)

func _capture(ars: GDScript, bc: Object) -> Variant:
	var snap: Variant = ars.call("capture", bc)
	assert_not_null(snap, "ARS_RED: capture 返 null")
	return snap

func _sha(snap: Variant) -> String:
	var h: String = str(snap.call("sha256"))
	assert_true(_hex64(h), "sha256 须 64 lowercase hex")
	return h

## 19 类独立 mutation；skill/registry/window intent 分项，禁虚构 DecisionWindow._next_order。
func _apply_mutation(bc: Object, kind: int) -> void:
	var st: BattleState = bc.get("state") as BattleState
	match kind:
		0: # wall tile/order
			assert_true(st.wall.set_draw_index(st.wall.draw_index() + 1))
		1: # dora/ura
			var pair_index: int = st.dora_indicators.visible_count()
			var d: Tile = st.wall.peek_dora_indicator(pair_index)
			var u: Tile = st.wall.peek_uradora_indicator(pair_index)
			assert_true(st.dora_indicators.reveal_pair(d, u))
		2: # hand order
			var htiles = st.seats[0].hand.tiles()
			assert_gte(htiles.size(), 2)
			var a = htiles[0]
			htiles[0] = htiles[1]
			htiles[1] = a
			assert_true(st.seats[0].hand.restore_tiles(htiles))
		3: # meld content：保持顺子合法，只改变来源席
			var original: Meld = st.seats[0].melds.all()[0]
			var changed := Meld.new(original.kind, original.tiles, 2,
				original.meld_id, original.called_tile)
			assert_true(st.seats[0].melds.restore([changed],
				st.seats[0].melds.next_local_index()))
		4: # riichi（挑已 declared 席）
			var riichi_seat: int = 1 if st.seats[1].riichi.declared else (disc_alt_seat(st))
			st.seats[riichi_seat].riichi.declared_turn += 3
		5: # furiten
			st.seats[2].furiten.waits.append(TileId.S9)
		6: # scores
			st.scores[0] = int(st.scores[0]) + 111
		7: # points
			st.seats[0].points += 9
		8: # revealed：追加 wall 本局未占用真实 Tile
			var reg_v: SkillRegistry = bc.get("registry") as SkillRegistry
			var occ_v: Dictionary = _collect_active_iids(st, reg_v)
			var repl_v: Tile = _pick_wall_tile_prefer(st, [TileId.T9, TileId.T8, TileId.T1], occ_v)
			assert_not_null(repl_v, "mutation[8] 须 wall 未占用真实 Tile")
			if repl_v != null:
				st.revealed_tiles.append({
					"tile": TileSkillAnchor.make(repl_v, 0, null),
					"visible_to": [3]})
		9: # kuikae
			st.kuikae_restricted[0] = [TileId.W3, TileId.W4]
		10: # momentum
			st.momentum.scores[Momentum.Attribute.PASSION] = 0.9
			st.momentum._recalculate_total()
		11: # DecisionWindow intent 内容（无 _next_order 字段；改真实 intents 存储）
			var w := _get_window(bc)
			assert_not_null(w, "mutation[11] 须有 DecisionWindow")
			if w != null:
				var intents_map = w.get("_intents_by_seat")
				assert_true(intents_map is Dictionary and not (intents_map as Dictionary).is_empty(),
					"mutation[11] 须有已登记 intent")
				if intents_map is Dictionary and not (intents_map as Dictionary).is_empty():
					var seat_key = (intents_map as Dictionary).keys()[0]
					var old_act: Action = (intents_map as Dictionary)[seat_key] as Action
					assert_not_null(old_act)
					if old_act != null:
						# 同 kind/payload 合法 PASS，改 command_id 以变 fixture intents 内容
						var mut_act: Action = Action.make_pass(
							old_act.seat, ROOM, _cmd(900 + int(seat_key)),
							old_act.decision_id, old_act.hand_seq, old_act.client_seq + 50)
						assert_not_null(mut_act)
						if mut_act != null:
							(intents_map as Dictionary)[seat_key] = mut_act
		12: # replay cursor：实际字段 _expected_replay_idx
			assert_true(bc.get("_expected_replay_idx") != null,
				"mutation[12] 缺 _expected_replay_idx")
			if bc.get("_expected_replay_idx") != null:
				bc.set("_expected_replay_idx", int(bc.get("_expected_replay_idx")) + 1)
		13: # SkillResource.consumed 独立项
			var reg_c: SkillRegistry = bc.get("registry") as SkillRegistry
			var entries_c: Array = reg_c.get_all_entries()
			assert_gte(entries_c.size(), 1)
			var sk_c: SkillResource = entries_c[0]["skill"]
			sk_c.consumed = not bool(sk_c.consumed)
		14: # skill anchor 独立项：仅 wall 本局未占用真实 Tile
			var reg_a: SkillRegistry = bc.get("registry") as SkillRegistry
			var entries_a: Array = reg_a.get_all_entries()
			assert_gte(entries_a.size(), 1)
			var e0: Dictionary = entries_a[0]
			var sk0: SkillResource = e0["skill"]
			var old_anchor = e0["anchor"]
			if old_anchor is TileSkillAnchor:
				var occ_a: Dictionary = _collect_active_iids(st, reg_a)
				# 旧 anchor 即将被替换，释放其占用以便可选其它牌
				if (old_anchor as TileSkillAnchor).tile != null:
					occ_a.erase(int((old_anchor as TileSkillAnchor).tile.instance_id))
				var repl_a: Tile = _pick_wall_tile_prefer(st, [TileId.W9, TileId.W8, TileId.W4], occ_a)
				assert_not_null(repl_a, "mutation[14] 须 wall 未占用真实 Tile")
				if repl_a != null:
					e0["anchor"] = TileSkillAnchor.make(repl_a, 0, sk0)
			elif typeof(old_anchor) == TYPE_INT:
				e0["anchor"] = (int(old_anchor) + 1) % 4
			else:
				e0["anchor"] = 3
		15: # skill entry reg_order 独立项
			var reg_r: SkillRegistry = bc.get("registry") as SkillRegistry
			var entries_r: Array = reg_r.get_all_entries()
			assert_gte(entries_r.size(), 1)
			entries_r[0]["reg_order"] = int(entries_r[0]["reg_order"]) + 10
		16: # SkillRegistry._next_order 独立项（非 DecisionWindow 字段）
			var reg_n: SkillRegistry = bc.get("registry") as SkillRegistry
			reg_n.set("_next_order", int(reg_n.get("_next_order")) + 1)
		17: # Scheduler next_chain
			bc.get("scheduler").set("_next_chain_id",
				int(bc.get("scheduler").get("_next_chain_id")) + 5)
		18: # event_chain_depth
			st.event_chain_depth = 2
		_:
			assert_true(false, "未知 mutation kind=%d（禁 honba/虚构 fallback）" % kind)

func disc_alt_seat(st: BattleState) -> int:
	for si in range(4):
		if st.seats[si].riichi.declared:
			return si
	return 0

func test_ars_api_freeze_and_missing_file_red() -> void:
	var ars := _ars_ready()
	if ars == null:
		return
	var bc_scr := _bc_ready()
	if bc_scr == null:
		return
	var bc := _make_bc(bc_scr)
	if bc == null:
		return
	var snap: Variant = _capture(ars, bc)
	if snap == null:
		return
	assert_true(snap.has_method("to_dict") and snap.has_method("sha256")
		and snap.has_method("restore_into"))
	var d: Dictionary = snap.call("to_dict")
	for k in FORBIDDEN_ROOM_KEYS:
		assert_false(d.has(k), "ARS 禁公开 ROOM 键 %s" % k)
	assert_true(_hex64(_sha(snap)))

func test_rich_fixture_mutation_changes_sha_and_restore_fields() -> void:
	# 先验证 fixture 契约（公开 API），再因 ARS 缺失 Red
	var bc_scr := _bc_ready()
	if bc_scr == null:
		return
	var bc_probe := _make_bc(bc_scr, 11, 4)
	if bc_probe == null:
		return
	var want0 := _enrich(bc_probe)
	if want0.is_empty():
		return
	# fixture 已契约正确；ARS 缺失则精确 Red
	var ars := _ars_ready()
	if ars == null:
		return
	var snap0: Variant = _capture(ars, bc_probe)
	if snap0 == null:
		return
	var sha0 := _sha(snap0)
	assert_eq(_sha(_capture(ars, bc_probe)), sha0, "双 capture 稳定")
	for i in range(MUT_N):
		var bc_m := _make_bc(bc_scr, 11, 4)
		if bc_m == null:
			return
		if _enrich(bc_m).is_empty():
			return
		var s_before := _sha(_capture(ars, bc_m))
		_apply_mutation(bc_m, i)
		assert_ne(_sha(_capture(ars, bc_m)), s_before, "mutation[%d] 须改变 sha" % i)
	var bc_src := _make_bc(bc_scr, 13, 5)
	if bc_src == null:
		return
	var want := _enrich(bc_src)
	if want.is_empty():
		return
	var snap: Variant = _capture(ars, bc_src)
	if snap == null:
		return
	var sha := _sha(snap)
	var bc_dst := _make_bc(bc_scr, 99, 0)
	assert_true(bool(snap.call("restore_into", bc_dst)), "restore_into 须 true")
	_assert_fixture_eq(want, _fixture_dict(bc_dst), "restore 全字段")
	assert_eq(JSON.stringify(want["skills"]), JSON.stringify(_fixture_dict(bc_dst)["skills"]))
	assert_eq(int(want["reg_next_order"]), int(_fixture_dict(bc_dst)["reg_next_order"]))
	assert_eq(JSON.stringify(want["last_discarded"]),
		JSON.stringify(_fixture_dict(bc_dst)["last_discarded"]),
		"restore 后 _last_discarded_tile 完整 Tile dict 等值")
	assert_eq(int(want["replay_idx"]), int(_fixture_dict(bc_dst)["replay_idx"]),
		"restore 后 _expected_replay_idx 等值")
	assert_eq(int(want["window_seq"]), int(_fixture_dict(bc_dst)["window_seq"]),
		"restore 后 _window_seq 等值")
	assert_eq(_sha(_capture(ars, bc_dst)), sha)
	var d: Dictionary = snap.call("to_dict")
	assert_false(d.is_empty())
	for k in FORBIDDEN_ROOM_KEYS:
		assert_false(d.has(k), "ARS 非 ROOM")
	assert_false(d.has("next_server_seq") or d.has("view_hash"))
	var ok: Variant = snap.call("restore_into", _make_bc(bc_scr, 3, 1))
	assert_eq(typeof(ok), TYPE_BOOL, "restore_into -> bool")
	assert_true(bool(ok))
	assert_false(bool(snap.call("restore_into", null)))

## capture→restore 须完整恢复 SkillResource 非默认字段与 TileSkillAnchor owner/holder，
## 且同一 owner/holder trigger 事件下 spy 触发与 beneficiary 语义不变。
func test_ars_skill_full_fields_and_tile_anchor_owner_holder_roundtrip() -> void:
	const SpyHook := preload("res://tests/_fixtures/spy_hook.gd")
	const SK_ID := &"ars_full_fields_probe"
	const OWNER_EVT := &"ARS_SNAP_OWNER_TRIG"
	const HOLDER_EVT := &"ARS_SNAP_HOLDER_TRIG"
	const OWNER_SEAT := 2
	const HOLDER_SEAT := 1
	const WANT_RARITY := 3
	const WANT_ATTACHED := TileId.W5
	const WANT_PARAMS := {"probe_key": 42, "tag": "ars-full"}

	SpyHook.reset()
	var ars := _ars_ready()
	if ars == null:
		return
	var bc_scr := _bc_ready()
	if bc_scr == null:
		return
	var bc_src := _make_bc(bc_scr, 21, 6)
	if bc_src == null:
		return
	var st: BattleState = bc_src.get("state") as BattleState
	var reg: SkillRegistry = bc_src.get("registry") as SkillRegistry
	var sched: SkillScheduler = bc_src.get("scheduler") as SkillScheduler
	assert_not_null(st)
	assert_not_null(reg)
	assert_not_null(sched)
	if st == null or reg == null or sched == null:
		return

	var occupied: Dictionary = _collect_active_iids(st, reg)
	var wall_tile: Tile = _pick_wall_tile(st, WANT_ATTACHED, occupied)
	assert_not_null(wall_tile, "须从本局 wall 选到真实 W5 Tile 作 anchor")
	if wall_tile == null:
		return
	assert_eq(int(wall_tile.id), WANT_ATTACHED)
	var anchor_iid: int = int(wall_tile.instance_id)
	assert_true(_iid_in_hand_seq_ns(anchor_iid, int(st.hand_seq)),
		"anchor iid 须在本局 hand_seq namespace")

	var sk := SkillResource.new()
	sk.id = SK_ID
	sk.display_name = "ARS Full Fields"
	sk.description = "roundtrip non-default skill fields"
	sk.hook_script = load("res://tests/_fixtures/spy_hook.gd") as GDScript
	sk.consumed = false
	sk.is_ability = false
	sk.rarity = WANT_RARITY
	sk.attached_tile = WANT_ATTACHED
	var ot: Array[StringName] = [OWNER_EVT]
	var ht: Array[StringName] = [HOLDER_EVT]
	sk.owner_triggers = ot
	sk.holder_triggers = ht
	sk.params = WANT_PARAMS.duplicate(true)
	assert_ne(sk.rarity, 0, "fixture rarity 须非默认")
	assert_ne(sk.attached_tile, -1, "fixture attached_tile 须非默认")
	assert_false(sk.owner_triggers.is_empty())
	assert_false(sk.holder_triggers.is_empty())
	assert_false(sk.params.is_empty())

	var ti := TileSkillAnchor.make(wall_tile, OWNER_SEAT, sk)
	ti.holder_seat = HOLDER_SEAT
	assert_eq(ti.owner_seat, OWNER_SEAT)
	assert_eq(ti.holder_seat, HOLDER_SEAT)
	assert_ne(ti.owner_seat, 0, "owner_seat 须非 restore 硬编码默认 0")
	assert_ne(ti.holder_seat, -1, "holder_seat 须非默认 -1")
	reg.register(sk, ti)

	# 恢复前：owner / holder 各触发一次，记录 spy trace 与 beneficiary
	SpyHook.reset()
	var ctx_owner_pre: SkillCtx = sched.emit_event(BattleEvent.make(OWNER_EVT, OWNER_SEAT))
	assert_eq(SpyHook.trace.size(), 1, "恢复前 owner trigger 须 fire 一次")
	assert_eq(SpyHook.trace[0]["skill_id"], SK_ID)
	assert_eq(SpyHook.trace[0]["event_type"], OWNER_EVT)
	assert_eq(ctx_owner_pre.beneficiary_seat, OWNER_SEAT,
		"恢复前 owner beneficiary=anchor.owner_seat")
	var owner_trace_pre: Array = SpyHook.trace.duplicate(true)

	SpyHook.reset()
	var ctx_holder_pre: SkillCtx = sched.emit_event(BattleEvent.make(HOLDER_EVT, HOLDER_SEAT))
	assert_eq(SpyHook.trace.size(), 1, "恢复前 holder trigger 须 fire 一次")
	assert_eq(SpyHook.trace[0]["skill_id"], SK_ID)
	assert_eq(SpyHook.trace[0]["event_type"], HOLDER_EVT)
	assert_eq(ctx_holder_pre.beneficiary_seat, HOLDER_SEAT,
		"恢复前 holder beneficiary=anchor.holder_seat")
	var holder_trace_pre: Array = SpyHook.trace.duplicate(true)

	var snap: Variant = _capture(ars, bc_src)
	if snap == null:
		return
	assert_true(snap.has_method("restore_into"), "公开 restore_into API")

	var bc_dst := _make_bc(bc_scr, 99, 0)
	if bc_dst == null:
		return
	assert_true(bool(snap.call("restore_into", bc_dst)), "restore_into 须 true")

	var reg_dst: SkillRegistry = bc_dst.get("registry") as SkillRegistry
	var sched_dst: SkillScheduler = bc_dst.get("scheduler") as SkillScheduler
	assert_not_null(reg_dst)
	assert_not_null(sched_dst)
	if reg_dst == null or sched_dst == null:
		return

	var restored_entry: Dictionary = {}
	for e in reg_dst.get_all_entries():
		var es: SkillResource = e["skill"] as SkillResource
		if es != null and es.id == SK_ID:
			restored_entry = e
			break
	assert_false(restored_entry.is_empty(), "restore 后 registry 须含 %s" % SK_ID)
	if restored_entry.is_empty():
		return
	var sk_r: SkillResource = restored_entry["skill"] as SkillResource
	var anchor_r = restored_entry["anchor"]
	assert_not_null(sk_r)
	assert_true(anchor_r is TileSkillAnchor, "restore 后 anchor 须为 TileSkillAnchor")
	if sk_r == null or not (anchor_r is TileSkillAnchor):
		return
	var ti_r: TileSkillAnchor = anchor_r as TileSkillAnchor
	assert_not_null(ti_r.tile, "restore 后 anchor.tile 须非 null")
	if ti_r.tile == null:
		return
	assert_eq(int(ti_r.tile.instance_id), anchor_iid, "anchor 底层 tile iid 须对齐")

	# 逐字段：当前 ARS 漏 rarity/attached_tile/triggers/params 与 owner/holder seats
	assert_eq(int(sk_r.rarity), WANT_RARITY, "restore 后 rarity 须保留")
	assert_eq(int(sk_r.attached_tile), WANT_ATTACHED, "restore 后 attached_tile 须保留")
	assert_true(sk_r.owner_triggers.has(OWNER_EVT),
		"restore 后 owner_triggers 须含 %s（实际 size=%d）" % [OWNER_EVT, sk_r.owner_triggers.size()])
	assert_true(sk_r.holder_triggers.has(HOLDER_EVT),
		"restore 后 holder_triggers 须含 %s（实际 size=%d）" % [HOLDER_EVT, sk_r.holder_triggers.size()])
	assert_eq(JSON.stringify(sk_r.params), JSON.stringify(WANT_PARAMS),
		"restore 后 params 须保留")
	assert_eq(int(ti_r.owner_seat), OWNER_SEAT, "restore 后 TileSkillAnchor.owner_seat")
	assert_eq(int(ti_r.holder_seat), HOLDER_SEAT, "restore 后 TileSkillAnchor.holder_seat")

	# 同一事件：spy trace 与 beneficiary 与恢复前一致（真 scheduler，禁 mock）
	SpyHook.reset()
	var ctx_owner_post: SkillCtx = sched_dst.emit_event(BattleEvent.make(OWNER_EVT, OWNER_SEAT))
	assert_eq(JSON.stringify(SpyHook.trace), JSON.stringify(owner_trace_pre),
		"restore 后 owner trigger spy trace 须与恢复前一致")
	assert_eq(ctx_owner_post.beneficiary_seat, OWNER_SEAT,
		"restore 后 owner beneficiary 语义不变")

	SpyHook.reset()
	var ctx_holder_post: SkillCtx = sched_dst.emit_event(BattleEvent.make(HOLDER_EVT, HOLDER_SEAT))
	assert_eq(JSON.stringify(SpyHook.trace), JSON.stringify(holder_trace_pre),
		"restore 后 holder trigger spy trace 须与恢复前一致")
	assert_eq(ctx_holder_post.beneficiary_seat, HOLDER_SEAT,
		"restore 后 holder beneficiary 语义不变")

## #232 ARS AI 连续性：SimpleAi RNG seed/state 捕获，restore 后下一步弃牌 instance_id 一致。
## 目标 BC 故意用不同 seed + HeuristicAi 构造，证明 restore 恢复 exact SimpleAi kind。
func test_ars_simple_ai_rng_continuity_roundtrip() -> void:
	var ars := _ars_ready()
	if ars == null:
		return
	var bc_scr := _bc_ready()
	if bc_scr == null:
		return
	# 源：SimpleAi（_make_bc 默认 use_heuristic_ai=false）
	var bc_src := _make_bc(bc_scr, 17, 3)
	if bc_src == null:
		return
	var ai_src = bc_src.get("ai")
	assert_not_null(ai_src, "源 BC 须有 ai")
	assert_true(ai_src is SimpleAi, "源 ai 须为 SimpleAi")
	assert_false(ai_src is HeuristicAi, "源 ai 须非 HeuristicAi")
	if ai_src == null or not (ai_src is SimpleAi) or (ai_src is HeuristicAi):
		return
	var simple_src: SimpleAi = ai_src as SimpleAi
	var st_src: BattleState = bc_src.get("state") as BattleState
	assert_not_null(st_src)
	if st_src == null:
		return
	var seat_src: Seat = st_src.seats[0] as Seat
	assert_gt(seat_src.hand.size(), 0, "源 seat.hand 须非空")
	if seat_src.hand.size() == 0:
		return

	# 先对真实 hand 调用一次 decide_discard 推进 RNG
	var pre: Tile = simple_src.decide_discard(seat_src)
	assert_not_null(pre, "推进 RNG 的 decide_discard 须返真实 Tile")
	if pre == null:
		return

	var snap: Variant = _capture(ars, bc_src)
	if snap == null:
		return
	var cap_seed: int = int(simple_src._rng.seed)
	var cap_state: int = int(simple_src._rng.state)

	# 快照后源侧再弃一步，作为 restore 后下一步期望 instance_id
	var next_src: Tile = simple_src.decide_discard(seat_src)
	assert_not_null(next_src, "快照后源 decide_discard 须返真实 Tile")
	if next_src == null:
		return
	var want_iid: int = int(next_src.instance_id)

	# 冻结 capture contract：须有明确 ai 字段（禁源码字符串门禁）
	var d: Dictionary = snap.call("to_dict")
	assert_true(d.has("ai"), "ARS capture contract 须有明确 ai 字段")

	# 目标：不同 seed + use_heuristic_ai=true，初始为 HeuristicAi
	var bc_dst: Object = bc_scr.new(991, 0, true, TileId.E, 0)
	assert_not_null(bc_dst)
	if bc_dst == null or bc_dst.get("state") == null:
		assert_true(false, "目标 BC 构造失败")
		return
	var ai_dst_before = bc_dst.get("ai")
	assert_true(ai_dst_before is HeuristicAi, "目标初始须为 HeuristicAi（对照）")
	assert_true(bool(snap.call("restore_into", bc_dst)), "restore_into 须 true")

	var ai_dst = bc_dst.get("ai")
	assert_not_null(ai_dst)
	assert_true(ai_dst is SimpleAi, "restore 后 ai 须为 SimpleAi")
	assert_false(ai_dst is HeuristicAi, "restore 后 ai 须非 HeuristicAi（exact kind）")
	if ai_dst == null or not (ai_dst is SimpleAi) or (ai_dst is HeuristicAi):
		return
	var simple_dst: SimpleAi = ai_dst as SimpleAi
	assert_eq(int(simple_dst._rng.seed), cap_seed, "restore 后 SimpleAi._rng.seed")
	assert_eq(int(simple_dst._rng.state), cap_state, "restore 后 SimpleAi._rng.state")

	var st_dst: BattleState = bc_dst.get("state") as BattleState
	assert_not_null(st_dst)
	if st_dst == null:
		return
	var seat_dst: Seat = st_dst.seats[0] as Seat
	assert_gt(seat_dst.hand.size(), 0, "restore 后 seat.hand 须非空")
	var next_dst: Tile = simple_dst.decide_discard(seat_dst)
	assert_not_null(next_dst, "restore 后 decide_discard 须返真实 Tile")
	if next_dst == null:
		return
	assert_eq(int(next_dst.instance_id), want_iid,
		"restore 后下一步弃牌 instance_id 须等于源快照后下一步")

## #232 ARS AI 连续性：HeuristicAi 全配置（shanten/strategic/defense/RNG）捕获恢复。
## 目标 BC 故意用不同 seed + SimpleAi 构造，证明 restore 恢复 exact HeuristicAi kind。
func test_ars_heuristic_ai_full_config_roundtrip() -> void:
	var ars := _ars_ready()
	if ars == null:
		return
	var bc_scr := _bc_ready()
	if bc_scr == null:
		return
	const SRC_SEED := 31
	const SRC_HS := 4
	const HAND_INDEX := 5
	const TOTAL_HANDS := 8
	var scores: Array = [41000, 29000, 19000, 11000]
	var riichi_seats: Array = [1, 3]
	var discards_flat: Array = [TileId.W1, TileId.T9]

	var bc_src: Object = bc_scr.new(SRC_SEED, 0, true, TileId.E, SRC_HS)
	assert_not_null(bc_src)
	if bc_src == null or bc_src.get("state") == null:
		assert_true(false, "HeuristicAi 源 BC 构造失败")
		return
	var ai_src = bc_src.get("ai")
	assert_true(ai_src is HeuristicAi, "源 ai 须为 HeuristicAi")
	if not (ai_src is HeuristicAi):
		return
	var h_src: HeuristicAi = ai_src as HeuristicAi

	h_src.use_shanten_aware_discard = true
	h_src.set_strategic_context(scores, HAND_INDEX, TOTAL_HANDS)
	h_src.set_defense_context(riichi_seats, discards_flat)
	# 推进继承 RNG（真 RandomNumberGenerator，禁伪造）
	h_src._rng.randi()

	var snap: Variant = _capture(ars, bc_src)
	if snap == null:
		return
	var cap_seed: int = int(h_src._rng.seed)
	var cap_state: int = int(h_src._rng.state)

	var d: Dictionary = snap.call("to_dict")
	assert_true(d.has("ai"), "ARS capture contract 须有明确 ai 字段")

	# 目标：不同 seed + SimpleAi
	var bc_dst: Object = bc_scr.new(777, 0, false, TileId.E, 0)
	assert_not_null(bc_dst)
	if bc_dst == null or bc_dst.get("state") == null:
		assert_true(false, "目标 BC 构造失败")
		return
	var ai_before = bc_dst.get("ai")
	assert_true(ai_before is SimpleAi, "目标初始须为 SimpleAi")
	assert_false(ai_before is HeuristicAi, "目标初始须非 HeuristicAi")
	assert_true(bool(snap.call("restore_into", bc_dst)), "restore_into 须 true")

	var ai_dst = bc_dst.get("ai")
	assert_true(ai_dst is HeuristicAi, "restore 后须为 HeuristicAi exact kind")
	if not (ai_dst is HeuristicAi):
		return
	var h_dst: HeuristicAi = ai_dst as HeuristicAi
	assert_true(bool(h_dst.use_shanten_aware_discard), "use_shanten_aware_discard")
	assert_eq(JSON.stringify(h_dst._cumulative_scores), JSON.stringify(scores),
		"_cumulative_scores")
	assert_eq(int(h_dst._hand_index), HAND_INDEX, "_hand_index")
	assert_eq(int(h_dst._total_hands), TOTAL_HANDS, "_total_hands")
	assert_eq(JSON.stringify(h_dst._opponent_riichi_seats), JSON.stringify(riichi_seats),
		"_opponent_riichi_seats")
	assert_eq(JSON.stringify(h_dst._opponent_discards_flat), JSON.stringify(discards_flat),
		"_opponent_discards_flat")
	assert_eq(int(h_dst._rng.seed), cap_seed, "HeuristicAi._rng.seed")
	assert_eq(int(h_dst._rng.state), cap_state, "HeuristicAi._rng.state")

# ── #232 ARS strict + atomic：损坏快照必须 reject 且零污染（本轮仅 Red）──
# 构造：真实 BC + _enrich → capture.to_dict → 变异 dict → ars.new()+set("_data")。
# 禁 snapshot_dict/snapshot_hash 旧 API；禁 mock / 源码扫描 / 恒真断言。

func _ars_from_data(ars: GDScript, data: Dictionary) -> Object:
	var snap: Object = ars.new() as Object
	assert_not_null(snap, "ARS_STRICT: ars.new() 须成功")
	if snap == null:
		return null
	# 仅经 _data 注入；不得走 snapshot_dict / snapshot_hash
	snap.set("_data", data.duplicate(true))
	return snap

## 有效源：capture 后 window/contexts/intents 须非空（供 D1/D2 与 window 契约）。
func _valid_enriched_dict(ars: GDScript, bc_scr: GDScript, rng_seed: int, hand_seq: int) -> Dictionary:
	var bc := _make_bc(bc_scr, rng_seed, hand_seq)
	if bc == null:
		return {}
	if _enrich(bc).is_empty():
		return {}
	var snap: Variant = _capture(ars, bc)
	if snap == null:
		return {}
	var d: Dictionary = snap.call("to_dict") as Dictionary
	assert_false(d.is_empty(), "ARS_STRICT: 有效 snap.to_dict 非空")
	assert_true(d.has("window"), "ARS_STRICT: snap 须有 window")
	var win: Dictionary = d.get("window", {}) as Dictionary
	assert_false(win.is_empty(), "ARS_STRICT: 有效源 window 非空")
	var ctxs: Array = win.get("contexts", []) as Array
	var intents: Array = win.get("intents", []) as Array
	assert_gt(ctxs.size(), 0, "ARS_STRICT: 有效源 contexts 非空")
	assert_gt(intents.size(), 0, "ARS_STRICT: 有效源 intents 非空")
	assert_true(d.has("wall") and (d["wall"] as Dictionary).has("tiles"),
		"ARS_STRICT: 有效源 wall.tiles")
	assert_eq(((d["wall"] as Dictionary)["tiles"] as Array).size(), 136,
		"ARS_STRICT: wall.tiles=136")
	assert_gt((d.get("action_journal", []) as Array).size(), 0,
		"ARS_STRICT: 有效源 action_journal 非空")
	return d

## 快照中所有非-wall 结构引用的 tile iid（供 E/F 选未引用 wall tile）。
## 覆盖 seats hand/river/meld/last_draw、dora/ura/revealed、last_discarded、
## window subject/context/intents、journals/events、skill tile anchor。
## 不校验 AI / skill anchor 行为，仅用于避开选样。
func _add_tile_dict_iid(occ: Dictionary, raw: Variant) -> void:
	if typeof(raw) != TYPE_DICTIONARY:
		return
	var td: Dictionary = raw
	if td.has("instance_id"):
		var iid: int = int(td["instance_id"])
		if iid >= 0:
			occ[iid] = true
	elif td.has("tile_instance_id"):
		var iid2: int = int(td["tile_instance_id"])
		if iid2 >= 0:
			occ[iid2] = true

func _add_payload_iids(occ: Dictionary, raw: Variant) -> void:
	if typeof(raw) != TYPE_DICTIONARY:
		return
	var p: Dictionary = raw
	if p.has("tile_instance_id"):
		var a: int = int(p["tile_instance_id"])
		if a >= 0:
			occ[a] = true
	if p.has("added_tile_instance_id"):
		var b: int = int(p["added_tile_instance_id"])
		if b >= 0:
			occ[b] = true
	for key in ["companion_tile_instance_ids", "tile_instance_ids"]:
		if not (p.get(key) is Array):
			continue
		for v in p[key] as Array:
			var cid: int = int(v)
			if cid >= 0:
				occ[cid] = true

func _add_action_dict_iids(occ: Dictionary, raw: Variant) -> void:
	if typeof(raw) != TYPE_DICTIONARY:
		return
	_add_payload_iids(occ, (raw as Dictionary).get("payload", {}))

func _add_allowed_actions_iids(occ: Dictionary, raw: Variant) -> void:
	if not (raw is Array):
		return
	for offer in raw as Array:
		if typeof(offer) != TYPE_DICTIONARY:
			continue
		var od: Dictionary = offer
		_add_payload_iids(occ, od)
		for opt in od.get("payload_options", []) as Array:
			_add_payload_iids(occ, opt)

func _collect_snapshot_non_wall_iids(snap: Dictionary) -> Dictionary:
	var occ: Dictionary = {}
	var seats: Array = snap.get("seats", []) as Array
	for si in range(mini(4, seats.size())):
		if typeof(seats[si]) != TYPE_DICTIONARY:
			continue
		var seat: Dictionary = seats[si]
		for t in seat.get("hand", []) as Array:
			_add_tile_dict_iid(occ, t)
		for t in seat.get("river", []) as Array:
			_add_tile_dict_iid(occ, t)
		for md in seat.get("melds", []) as Array:
			if typeof(md) != TYPE_DICTIONARY:
				continue
			var m: Dictionary = md
			for t in m.get("tiles", []) as Array:
				_add_tile_dict_iid(occ, t)
			var called: int = int(m.get("called", -1))
			if called >= 0:
				occ[called] = true
			var added: int = int(m.get("added", -1))
			if added >= 0:
				occ[added] = true
		var ld: int = int(seat.get("last_draw", -1))
		if ld >= 0:
			occ[ld] = true
	for t in snap.get("dora", []) as Array:
		_add_tile_dict_iid(occ, t)
	for t in snap.get("ura", []) as Array:
		_add_tile_dict_iid(occ, t)
	for item in snap.get("revealed", []) as Array:
		if typeof(item) == TYPE_DICTIONARY:
			_add_tile_dict_iid(occ, (item as Dictionary).get("tile", {}))
	_add_tile_dict_iid(occ, snap.get("last_discarded", {}))
	var win: Dictionary = snap.get("window", {}) as Dictionary
	if not win.is_empty():
		var subj: int = int(win.get("subject_tile_instance_id", -1))
		if subj >= 0:
			occ[subj] = true
		for ctx in win.get("contexts", []) as Array:
			if typeof(ctx) != TYPE_DICTIONARY:
				continue
			var cd: Dictionary = ctx
			var claimed: int = int(cd.get("claimed_tile_instance_id", -1))
			if claimed >= 0:
				occ[claimed] = true
			_add_allowed_actions_iids(occ, cd.get("allowed_actions", []))
		for intent in win.get("intents", []) as Array:
			_add_action_dict_iids(occ, intent)
	for ad in snap.get("action_journal", []) as Array:
		_add_action_dict_iids(occ, ad)
	for ad in snap.get("expected_replay", []) as Array:
		_add_action_dict_iids(occ, ad)
	for ed in snap.get("event_journal", []) as Array:
		if typeof(ed) == TYPE_DICTIONARY:
			_add_tile_dict_iid(occ, (ed as Dictionary).get("tile", {}))
	for sk in snap.get("skills", []) as Array:
		if typeof(sk) != TYPE_DICTIONARY:
			continue
		var skd: Dictionary = sk
		if str(skd.get("anchor_kind", "")) != "tile":
			continue
		var aid: int = int(skd.get("anchor", -1))
		if aid >= 0:
			occ[aid] = true
	return occ

## 选 wall 中未被任何非-wall 结构引用的 tile 下标；失败返 -1。
func _pick_unreferenced_wall_index(snap: Dictionary) -> int:
	var referenced: Dictionary = _collect_snapshot_non_wall_iids(snap)
	var tiles: Array = ((snap.get("wall", {}) as Dictionary).get("tiles", []) as Array)
	for i in range(tiles.size()):
		if typeof(tiles[i]) != TYPE_DICTIONARY:
			continue
		var iid: int = int((tiles[i] as Dictionary).get("instance_id", -1))
		if iid < 0:
			continue
		if not referenced.has(iid):
			return i
	return -1

func _corrupt_ars_case(valid: Dictionary, case_name: String) -> Dictionary:
	var d: Dictionary = valid.duplicate(true)
	match case_name:
		"A_dup_wall_iid":
			var tiles: Array = (d["wall"] as Dictionary)["tiles"] as Array
			assert_gte(tiles.size(), 2, "%s: wall.tiles 须≥2" % case_name)
			var iid0: int = int((tiles[0] as Dictionary).get("instance_id", -1))
			var iid1: int = int((tiles[1] as Dictionary).get("instance_id", -1))
			assert_ne(iid0, -1, "%s: tiles[0].instance_id 须有效" % case_name)
			assert_ne(iid0, iid1,
				"%s: 基线 tiles[0/1] iid 须不同，才能制造重复" % case_name)
			tiles[1] = (tiles[0] as Dictionary).duplicate(true)
			assert_eq(int((tiles[1] as Dictionary)["instance_id"]),
				int((tiles[0] as Dictionary)["instance_id"]),
				"%s: 损坏后 tiles[1].instance_id 须等于 tiles[0]" % case_name)
		"B_bad_action_journal":
			var aj: Array = d.get("action_journal", []) as Array
			assert_gt(aj.size(), 0, "%s: action_journal 须非空" % case_name)
			# {} → Action.from_dict 无法解析（空 dict / 缺 envelope）
			assert_null(Action.from_dict({}),
				"%s: 预检 Action.from_dict({}) 须 null" % case_name)
			aj.append({})
			d["action_journal"] = aj
		"C_bad_event_journal":
			var ej: Array = d.get("event_journal", []) as Array
			assert_null(BattleEvent.from_dict({}),
				"%s: 预检 BattleEvent.from_dict({}) 须 null" % case_name)
			ej.append({})
			d["event_journal"] = ej
		"D1_claimed_iid_oos":
			var win: Dictionary = d.get("window", {}) as Dictionary
			var ctxs: Array = win.get("contexts", []) as Array
			assert_gt(ctxs.size(), 0, "%s: contexts 须非空" % case_name)
			var hs: int = int(d.get("hand_seq", 0))
			var lo: int = _ns_lo(hs)
			var hi: int = _ns_hi(hs)
			# hand_seq 命名空间外且不存在的 iid（非 wall/hand 实体）
			var bad_iid: int = hi + 10007
			assert_false(bad_iid >= lo and bad_iid <= hi,
				"%s: bad_iid 须在 hand_seq 命名空间外" % case_name)
			var ctx: Dictionary = (ctxs[0] as Dictionary).duplicate(true)
			var old_claimed: int = int(ctx.get("claimed_tile_instance_id", -1))
			assert_true(old_claimed >= lo and old_claimed <= hi,
				"%s: 基线 claimed_tile_instance_id 须在本局 namespace" % case_name)
			ctx["claimed_tile_instance_id"] = bad_iid
			ctxs[0] = ctx
			win["contexts"] = ctxs
			d["window"] = win
		"D2_bad_window_intent":
			var win2: Dictionary = d.get("window", {}) as Dictionary
			var intents: Array = win2.get("intents", []) as Array
			assert_gt(intents.size(), 0, "%s: intents 须非空" % case_name)
			# 非法 dict：Action.from_dict 无法解析（非合法 PASS payload 路径）
			assert_null(Action.from_dict({}),
				"%s: 预检非法 intent dict 须无法解析" % case_name)
			intents[0] = {}
			win2["intents"] = intents
			d["window"] = win2
		"E_wall_iid_out_of_namespace":
			# 仅改未被非-wall 引用的 wall tile.instance_id → 本局 namespace 外合法全局 int
			var e_idx: int = _pick_unreferenced_wall_index(d)
			assert_gte(e_idx, 0, "%s: 须能选到未被非-wall 引用的 wall tile" % case_name)
			if e_idx < 0:
				return d
			var e_tiles: Array = (d["wall"] as Dictionary)["tiles"] as Array
			var e_td: Dictionary = (e_tiles[e_idx] as Dictionary).duplicate(true)
			var e_old_iid: int = int(e_td.get("instance_id", -1))
			var e_hs: int = int(d.get("hand_seq", 0))
			var e_lo: int = _ns_lo(e_hs)
			var e_hi: int = _ns_hi(e_hs)
			assert_true(e_old_iid >= e_lo and e_old_iid <= e_hi,
				"%s: 选中 wall tile 基线 iid 须在本局 namespace" % case_name)
			var e_refs: Dictionary = _collect_snapshot_non_wall_iids(d)
			assert_false(e_refs.has(e_old_iid),
				"%s: 选中前 wall iid=%d 不得被任何非-wall 结构引用" % [case_name, e_old_iid])
			var wall_iids: Dictionary = {}
			for wt in e_tiles:
				if typeof(wt) == TYPE_DICTIONARY:
					wall_iids[int((wt as Dictionary).get("instance_id", -1))] = true
			# 合法全局 int、本局 namespace 外、不与其它 wall 重复
			var e_bad: int = e_hi + 1
			while wall_iids.has(e_bad) or (e_bad >= e_lo and e_bad <= e_hi) \
					or not Tile.is_valid_instance_id(e_bad):
				e_bad += 1
				if e_bad > Tile.MAX_SAFE_INSTANCE_ID:
					assert_true(false, "%s: 无法构造合法 out-of-namespace iid" % case_name)
					return d
			assert_false(e_bad >= e_lo and e_bad <= e_hi,
				"%s: bad iid 须在 hand_seq namespace 外" % case_name)
			assert_true(Tile.is_valid_instance_id(e_bad),
				"%s: bad iid 须为合法全局 instance_id" % case_name)
			assert_false(wall_iids.has(e_bad),
				"%s: bad iid 不得与其它 wall 重复" % case_name)
			var e_id_keep: int = int(e_td.get("id", -1))
			var e_red_keep: bool = bool(e_td.get("is_red_dora", false))
			var e_own_keep: int = int(e_td.get("owner_seat", -2))
			e_td["instance_id"] = e_bad
			assert_not_null(Tile.from_dict(e_td),
				"%s: 损坏后 Tile.from_dict 仍须合法（仅 namespace 违规）" % case_name)
			assert_eq(int(e_td["id"]), e_id_keep)
			assert_eq(bool(e_td["is_red_dora"]), e_red_keep)
			assert_eq(int(e_td["owner_seat"]), e_own_keep)
			assert_eq(int(e_td["instance_id"]), e_bad)
			e_tiles[e_idx] = e_td
			# wall 仍 136 且 iid 唯一
			var e_seen: Dictionary = {}
			for wt2 in e_tiles:
				var wi: int = int((wt2 as Dictionary)["instance_id"])
				assert_false(e_seen.has(wi), "%s: wall iid 仍须唯一" % case_name)
				e_seen[wi] = true
			assert_eq(e_tiles.size(), 136)
		"F_wall_canonical_owner_mismatch":
			# 仅改未被非-wall 引用的 wall tile.owner_seat → 唯一违反 serial canonical owner
			var f_idx: int = _pick_unreferenced_wall_index(d)
			assert_gte(f_idx, 0, "%s: 须能选到未被非-wall 引用的 wall tile" % case_name)
			if f_idx < 0:
				return d
			var f_tiles: Array = (d["wall"] as Dictionary)["tiles"] as Array
			var f_td: Dictionary = (f_tiles[f_idx] as Dictionary).duplicate(true)
			var f_iid: int = int(f_td.get("instance_id", -1))
			var f_hs: int = int(d.get("hand_seq", 0))
			var f_lo: int = _ns_lo(f_hs)
			var f_hi: int = _ns_hi(f_hs)
			assert_true(f_iid >= f_lo and f_iid <= f_hi,
				"%s: 选中 wall tile 基线 iid 须在本局 namespace" % case_name)
			var f_refs: Dictionary = _collect_snapshot_non_wall_iids(d)
			assert_false(f_refs.has(f_iid),
				"%s: 选中前 wall iid=%d 不得被任何非-wall 结构引用" % [case_name, f_iid])
			var f_serial: int = f_iid - f_lo
			assert_true(f_serial >= 0 and f_serial <= 135,
				"%s: serial 须 0..135 得 %d" % [case_name, f_serial])
			var f_canon_owner: int = f_serial % 4
			var f_old_owner: int = int(f_td.get("owner_seat", -2))
			assert_eq(f_old_owner, f_canon_owner,
				"%s: 基线 owner 须等于 serial%%4 canonical" % case_name)
			var f_bad_owner: int = (f_old_owner + 1) % 4
			assert_ne(f_bad_owner, f_canon_owner,
				"%s: 损坏 owner 须唯一违反 serial canonical" % case_name)
			var f_id_keep: int = int(f_td.get("id", -1))
			var f_red_keep: bool = bool(f_td.get("is_red_dora", false))
			f_td["owner_seat"] = f_bad_owner
			assert_not_null(Tile.from_dict(f_td),
				"%s: 损坏后 Tile.from_dict 仍须合法（仅 canonical owner 违规）" % case_name)
			assert_eq(int(f_td["instance_id"]), f_iid, "%s: iid 不变" % case_name)
			assert_eq(int(f_td["id"]), f_id_keep, "%s: id 不变" % case_name)
			assert_eq(bool(f_td["is_red_dora"]), f_red_keep, "%s: red 不变" % case_name)
			assert_eq(int(f_td["owner_seat"]), f_bad_owner)
			assert_ne(int(f_td["owner_seat"]), f_canon_owner)
			f_tiles[f_idx] = f_td
			assert_eq(f_tiles.size(), 136)
		"G_duplicate_active_iid":
			# wall 136 唯一完整不变；两活动区完整引用同一合法 wall iid（优先两席 hand[0]）
			var g_seats: Array = d.get("seats", []) as Array
			assert_eq(g_seats.size(), 4, "%s: seats 须 4" % case_name)
			var g_wall_tiles: Array = (d["wall"] as Dictionary)["tiles"] as Array
			var g_wall_iids: Dictionary = {}
			for wt in g_wall_tiles:
				g_wall_iids[int((wt as Dictionary)["instance_id"])] = true
			assert_eq(g_wall_iids.size(), 136, "%s: 基线 wall iid 唯一" % case_name)
			# 收集活动位置：优先 hand[0]，不足时补 river[0]
			var g_locs: Array = []  # {seat, zone, index}
			for si in range(4):
				var hand_arr: Array = (g_seats[si] as Dictionary).get("hand", []) as Array
				if hand_arr.size() > 0:
					g_locs.append({"seat": si, "zone": "hand", "index": 0})
			if g_locs.size() < 2:
				for si2 in range(4):
					var river_arr: Array = (g_seats[si2] as Dictionary).get("river", []) as Array
					if river_arr.size() > 0:
						g_locs.append({"seat": si2, "zone": "river", "index": 0})
					if g_locs.size() >= 2:
						break
			assert_gte(g_locs.size(), 2,
				"%s: 须至少两个活动位置（hand/river）" % case_name)
			if g_locs.size() < 2:
				return d
			var g_loc_a: Dictionary = g_locs[0]
			var g_loc_b: Dictionary = g_locs[1]
			var g_zone_a: String = str(g_loc_a["zone"])
			var g_zone_b: String = str(g_loc_b["zone"])
			var g_sa: int = int(g_loc_a["seat"])
			var g_sb: int = int(g_loc_b["seat"])
			var g_arr_a: Array = (g_seats[g_sa] as Dictionary)[g_zone_a] as Array
			var g_arr_b: Array = (g_seats[g_sb] as Dictionary)[g_zone_b] as Array
			var g_td_a: Dictionary = (g_arr_a[0] as Dictionary).duplicate(true)
			var g_td_b_old: Dictionary = (g_arr_b[0] as Dictionary).duplicate(true)
			var g_iid_a: int = int(g_td_a.get("instance_id", -1))
			var g_iid_b: int = int(g_td_b_old.get("instance_id", -1))
			assert_ne(g_iid_a, g_iid_b,
				"%s: 基线两活动位置 iid 须不同（才能制造 duplicate active）" % case_name)
			assert_true(g_wall_iids.has(g_iid_a),
				"%s: 源活动 tile iid 须为合法 wall 实体" % case_name)
			# 第二个完整 tile dict ← 第一个 duplicate(true)；不单改 iid
			g_arr_b[0] = g_td_a.duplicate(true)
			assert_eq(int((g_arr_b[0] as Dictionary)["instance_id"]), g_iid_a)
			assert_eq(int((g_arr_b[0] as Dictionary)["id"]), int(g_td_a["id"]))
			assert_eq(bool((g_arr_b[0] as Dictionary)["is_red_dora"]),
				bool(g_td_a["is_red_dora"]))
			assert_eq(int((g_arr_b[0] as Dictionary)["owner_seat"]),
				int(g_td_a["owner_seat"]))
			# wall 完整不变且仍唯一
			assert_eq(g_wall_tiles.size(), 136)
			var g_seen: Dictionary = {}
			for wt2 in g_wall_tiles:
				var wi: int = int((wt2 as Dictionary)["instance_id"])
				assert_false(g_seen.has(wi), "%s: wall 仍须唯一" % case_name)
				g_seen[wi] = true
			assert_eq(g_seen.size(), 136)
			assert_eq(int((g_arr_a[0] as Dictionary)["instance_id"]),
				int((g_arr_b[0] as Dictionary)["instance_id"]),
				"%s: 两活动区须完整引用同一 wall iid" % case_name)
		_:
			assert_true(false, "未知 strict case: %s" % case_name)
	return d

## restore 前记录 target hash + 五对象引用；restore 后须 false 且零污染。
func _assert_strict_atomic_reject(
	ars: GDScript, target: Object, corrupted: Object, case_name: String
) -> void:
	assert_not_null(target, "%s: target BC 非 null" % case_name)
	assert_not_null(corrupted, "%s: corrupted ARS 非 null" % case_name)
	if target == null or corrupted == null:
		return
	# 公开 capture.sha256；禁旧 snapshot_hash API
	var before_snap: Variant = _capture(ars, target)
	assert_not_null(before_snap, "%s: restore 前 capture(target) 须成功" % case_name)
	if before_snap == null:
		return
	var before_sha: String = _sha(before_snap)
	var ref_state = target.get("state")
	var ref_engine = target.get("engine")
	var ref_registry = target.get("registry")
	var ref_scheduler = target.get("scheduler")
	var ref_ai = target.get("ai")
	assert_not_null(ref_state, "%s: target.state 非 null" % case_name)
	assert_not_null(ref_engine, "%s: target.engine 非 null" % case_name)
	assert_not_null(ref_registry, "%s: target.registry 非 null" % case_name)
	assert_not_null(ref_scheduler, "%s: target.scheduler 非 null" % case_name)
	assert_not_null(ref_ai, "%s: target.ai 非 null" % case_name)

	var ok_raw: Variant = corrupted.call("restore_into", target)
	assert_eq(typeof(ok_raw), TYPE_BOOL, "%s: restore_into 须返 bool" % case_name)
	assert_false(bool(ok_raw),
		"%s: 损坏快照 restore_into 须 false（严格校验 / 禁止半恢复）" % case_name)

	var after_snap: Variant = _capture(ars, target)
	assert_not_null(after_snap, "%s: restore 后 capture(target) 仍须成功" % case_name)
	if after_snap == null:
		return
	assert_eq(_sha(after_snap), before_sha,
		"%s: restore 失败后 capture(target).sha256 须与 before 完全相同（零污染）" % case_name)
	assert_same(target.get("state"), ref_state,
		"%s: state 对象引用不变" % case_name)
	assert_same(target.get("engine"), ref_engine,
		"%s: engine 对象引用不变" % case_name)
	assert_same(target.get("registry"), ref_registry,
		"%s: registry 对象引用不变" % case_name)
	assert_same(target.get("scheduler"), ref_scheduler,
		"%s: scheduler 对象引用不变" % case_name)
	assert_same(target.get("ai"), ref_ai,
		"%s: ai 对象引用不变" % case_name)

## 八个独立 case：各自全新 seed 源 + 全新 seed 目标，避免交叉污染。
## A–D2：既有 strict；E/F/G：实体完整性（namespace / canonical owner / active-ref 唯一）。
func test_ars_strict_atomic_reject_corrupted_snapshots() -> void:
	var ars := _ars_ready()
	if ars == null:
		return
	var bc_scr := _bc_ready()
	if bc_scr == null:
		return

	# case_name → [src_seed, src_hs, dst_seed, dst_hs]
	# 源 seed 取既有 ARS 测已验证可 _enrich 的组合；目标 seed 每 case 全新且不同。
	var cases: Array = [
		["A_dup_wall_iid", 11, 4, 141, 1],
		["B_bad_action_journal", 13, 5, 142, 2],
		["C_bad_event_journal", 17, 3, 143, 3],
		["D1_claimed_iid_oos", 11, 4, 144, 4],
		["D2_bad_window_intent", 13, 5, 145, 5],
		["E_wall_iid_out_of_namespace", 11, 4, 146, 6],
		["F_wall_canonical_owner_mismatch", 13, 5, 147, 7],
		["G_duplicate_active_iid", 17, 3, 148, 0],
	]
	for row in cases:
		var case_name: String = str(row[0])
		var src_seed: int = int(row[1])
		var src_hs: int = int(row[2])
		var dst_seed: int = int(row[3])
		var dst_hs: int = int(row[4])
		assert_ne(src_seed, dst_seed, "%s: 源/目标 seed 须不同" % case_name)

		var valid: Dictionary = _valid_enriched_dict(ars, bc_scr, src_seed, src_hs)
		if valid.is_empty():
			assert_true(false, "%s: 有效源 fixture 生成失败" % case_name)
			return

		var corrupted_dict: Dictionary = _corrupt_ars_case(valid, case_name)
		var corrupted: Object = _ars_from_data(ars, corrupted_dict)
		if corrupted == null:
			return

		# 每 case 全新 target，杜绝半恢复污染串联
		var target := _make_bc(bc_scr, dst_seed, dst_hs)
		if target == null:
			assert_true(false, "%s: 目标 BC 构造失败" % case_name)
			return
		_assert_strict_atomic_reject(ars, target, corrupted, case_name)

## skill tile-anchor 严格校验 Red：oos / 与活动区重复（含 revealed）/ owner|holder OOB，且原子拒绝。
## 五 case 各自全新 valid + target；仅改目标字段。生产未严格校验时本测应 fail（Red）。
func test_ars_strict_rejects_invalid_skill_tile_anchors_and_is_atomic() -> void:
	var ars := _ars_ready()
	if ars == null:
		return
	var bc_scr := _bc_ready()
	if bc_scr == null:
		return

	# case_name → [src_seed, src_hs, dst_seed, dst_hs]
	var cases: Array = [
		["anchor_missing_oos", 11, 4, 151, 1],
		["anchor_duplicate_active", 13, 5, 152, 2],
		["anchor_duplicate_revealed", 17, 3, 155, 5],
		["anchor_owner_oob", 17, 3, 153, 3],
		["anchor_holder_oob", 11, 4, 154, 4],
	]
	for row in cases:
		var case_name: String = str(row[0])
		var src_seed: int = int(row[1])
		var src_hs: int = int(row[2])
		var dst_seed: int = int(row[3])
		var dst_hs: int = int(row[4])
		assert_ne(src_seed, dst_seed, "%s: 源/目标 seed 须不同" % case_name)

		var valid: Dictionary = _valid_enriched_dict(ars, bc_scr, src_seed, src_hs)
		if valid.is_empty():
			assert_true(false, "%s: 有效源 fixture 生成失败" % case_name)
			return

		var skills: Array = valid.get("skills", []) as Array
		var tile_idx := -1
		for i in range(skills.size()):
			if typeof(skills[i]) != TYPE_DICTIONARY:
				continue
			if str((skills[i] as Dictionary).get("anchor_kind", "")) == "tile":
				tile_idx = i
				break
		assert_gte(tile_idx, 0, "%s: 基线 skills 须含 anchor_kind=tile" % case_name)
		if tile_idx < 0:
			return
		var sk0: Dictionary = (skills[tile_idx] as Dictionary).duplicate(true)
		assert_eq(str(sk0.get("anchor_kind", "")), "tile",
			"%s: 基线首个 tile anchor 的 kind 须为 tile" % case_name)

		var corrupted_dict: Dictionary = valid.duplicate(true)
		var sk_arr: Array = corrupted_dict.get("skills", []) as Array
		var sk_mut: Dictionary = (sk_arr[tile_idx] as Dictionary).duplicate(true)
		match case_name:
			"anchor_missing_oos":
				var hs: int = int(valid.get("hand_seq", 0))
				var hi: int = _ns_hi(hs)
				var bad_iid: int = hi + 10007
				assert_false(_iid_in_hand_seq_ns(bad_iid, hs),
					"%s: bad anchor 须在 hand_seq namespace 外" % case_name)
				sk_mut["anchor"] = bad_iid
			"anchor_duplicate_active":
				var active_iid := -1
				var seats: Array = valid.get("seats", []) as Array
				for si in range(mini(4, seats.size())):
					if typeof(seats[si]) != TYPE_DICTIONARY:
						continue
					var seat: Dictionary = seats[si]
					for zone in ["hand", "river"]:
						var arr: Array = seat.get(zone, []) as Array
						if arr.is_empty():
							continue
						if typeof(arr[0]) != TYPE_DICTIONARY:
							continue
						active_iid = int((arr[0] as Dictionary).get("instance_id", -1))
						if active_iid >= 0:
							break
					if active_iid >= 0:
						break
					for md in seat.get("melds", []) as Array:
						if typeof(md) != TYPE_DICTIONARY:
							continue
						var mtiles: Array = (md as Dictionary).get("tiles", []) as Array
						if mtiles.is_empty() or typeof(mtiles[0]) != TYPE_DICTIONARY:
							continue
						active_iid = int((mtiles[0] as Dictionary).get("instance_id", -1))
						if active_iid >= 0:
							break
					if active_iid >= 0:
						break
				assert_gte(active_iid, 0,
					"%s: 须能从 seats hand/river/meld 取到真实活动 tile iid" % case_name)
				if active_iid < 0:
					return
				var base_anchor: int = int(sk0.get("anchor", -1))
				assert_ne(active_iid, base_anchor,
					"%s: 活动 iid 须不同于基线 skill anchor" % case_name)
				sk_mut["anchor"] = active_iid
			"anchor_duplicate_revealed":
				# 活动区含 revealed：用 valid["revealed"] 第一项真实 tile 的 iid 污染 skill anchor
				var rev_iid := -1
				var revealed: Array = valid.get("revealed", []) as Array
				assert_gt(revealed.size(), 0, "%s: valid 须含至少一项 revealed" % case_name)
				if revealed.is_empty():
					return
				assert_eq(typeof(revealed[0]), TYPE_DICTIONARY,
					"%s: revealed[0] 须为 dict" % case_name)
				if typeof(revealed[0]) != TYPE_DICTIONARY:
					return
				var rev_tile = (revealed[0] as Dictionary).get("tile", null)
				assert_eq(typeof(rev_tile), TYPE_DICTIONARY,
					"%s: revealed[0].tile 须为规范化 dict" % case_name)
				if typeof(rev_tile) != TYPE_DICTIONARY:
					return
				var rev_td: Dictionary = rev_tile as Dictionary
				# TileSkillAnchor 六键 tile_instance_id；Tile 四键 instance_id
				if rev_td.has("tile_instance_id"):
					rev_iid = int(rev_td["tile_instance_id"])
				elif rev_td.has("instance_id"):
					rev_iid = int(rev_td["instance_id"])
				assert_gte(rev_iid, 0,
					"%s: 须能从 revealed 第一项真实 tile 取到 iid" % case_name)
				if rev_iid < 0:
					return
				var base_anchor_rev: int = int(sk0.get("anchor", -1))
				assert_ne(rev_iid, base_anchor_rev,
					"%s: revealed iid 须不同于基线 skill tile anchor" % case_name)
				sk_mut["anchor"] = rev_iid
			"anchor_owner_oob":
				sk_mut["anchor_owner"] = 4
			"anchor_holder_oob":
				sk_mut["anchor_holder"] = -2
			_:
				assert_true(false, "未知 skill-anchor case: %s" % case_name)
				return
		sk_arr[tile_idx] = sk_mut
		corrupted_dict["skills"] = sk_arr

		var corrupted: Object = _ars_from_data(ars, corrupted_dict)
		if corrupted == null:
			return
		var target := _make_bc(bc_scr, dst_seed, dst_hs)
		if target == null:
			assert_true(false, "%s: 目标 BC 构造失败" % case_name)
			return
		_assert_strict_atomic_reject(ars, target, corrupted, case_name)

# ── #232 ARS AI 非空 snapshot 严格 schema + 原子拒绝（本轮仅 Red）──
# 构造：真实 BC capture → to_dict → 仅污染 ai 字段 → ars.new()+set("_data")。
# 每 case 全新 target；restore_into 须 false 且 SHA + state/engine/registry/scheduler/ai 五引用不变。
# 合法 Simple/Heuristic roundtrip 保持不动；ai={} 保留 target.ai 见独立回归。

## 真实 SimpleAi capture 全量 dict（非空 ai：kind/seed/state）。
func _valid_simple_ai_snap_dict(
	ars: GDScript, bc_scr: GDScript, rng_seed: int, hand_seq: int
) -> Dictionary:
	var bc := _make_bc(bc_scr, rng_seed, hand_seq)
	if bc == null:
		return {}
	var ai = bc.get("ai")
	assert_true(ai is SimpleAi, "ARS_AI_STRICT: 源须 SimpleAi")
	assert_false(ai is HeuristicAi, "ARS_AI_STRICT: 源须非 HeuristicAi")
	if ai == null or not (ai is SimpleAi) or (ai is HeuristicAi):
		return {}
	# 推进 RNG，保证 seed/state 为真实捕获值（非构造默认 0 巧合）
	var st: BattleState = bc.get("state") as BattleState
	if st != null and st.seats[0].hand.size() > 0:
		(ai as SimpleAi).decide_discard(st.seats[0] as Seat)
	var snap: Variant = _capture(ars, bc)
	if snap == null:
		return {}
	var d: Dictionary = snap.call("to_dict") as Dictionary
	assert_true(d.has("ai"), "ARS_AI_STRICT: capture 须有 ai")
	var ai_d: Dictionary = d.get("ai", {}) as Dictionary
	assert_false(ai_d.is_empty(), "ARS_AI_STRICT: SimpleAi ai 非空")
	assert_eq(str(ai_d.get("kind", "")), "SimpleAi", "ARS_AI_STRICT: kind=SimpleAi")
	assert_eq(typeof(ai_d.get("seed")), TYPE_INT, "ARS_AI_STRICT: seed TYPE_INT")
	assert_eq(typeof(ai_d.get("state")), TYPE_INT, "ARS_AI_STRICT: state TYPE_INT")
	return d

## 真实 HeuristicAi 全配置 capture（shanten + strategic/defense context 非空）。
func _valid_heuristic_ai_snap_dict(
	ars: GDScript, bc_scr: GDScript, rng_seed: int, hand_seq: int
) -> Dictionary:
	var bc: Object = bc_scr.new(rng_seed, 0, true, TileId.E, hand_seq)
	assert_not_null(bc, "ARS_AI_STRICT: HeuristicAi 源 BC")
	if bc == null or bc.get("state") == null:
		return {}
	var ai = bc.get("ai")
	assert_true(ai is HeuristicAi, "ARS_AI_STRICT: 源须 HeuristicAi")
	if not (ai is HeuristicAi):
		return {}
	var h: HeuristicAi = ai as HeuristicAi
	var scores: Array = [41000, 29000, 19000, 11000]
	var riichi_seats: Array = [1, 3]
	var discards_flat: Array = [TileId.W1, TileId.T9]
	h.use_shanten_aware_discard = true
	h.set_strategic_context(scores, 5, 8)
	h.set_defense_context(riichi_seats, discards_flat)
	h._rng.randi()
	var snap: Variant = _capture(ars, bc)
	if snap == null:
		return {}
	var d: Dictionary = snap.call("to_dict") as Dictionary
	assert_true(d.has("ai"), "ARS_AI_STRICT: capture 须有 ai")
	var ai_d: Dictionary = d.get("ai", {}) as Dictionary
	assert_false(ai_d.is_empty(), "ARS_AI_STRICT: HeuristicAi ai 非空")
	assert_eq(str(ai_d.get("kind", "")), "HeuristicAi", "ARS_AI_STRICT: kind=HeuristicAi")
	assert_eq(typeof(ai_d.get("seed")), TYPE_INT)
	assert_eq(typeof(ai_d.get("state")), TYPE_INT)
	assert_eq(typeof(ai_d.get("use_shanten_aware_discard")), TYPE_BOOL)
	assert_eq(typeof(ai_d.get("_cumulative_scores")), TYPE_ARRAY)
	assert_eq(typeof(ai_d.get("_hand_index")), TYPE_INT)
	assert_eq(typeof(ai_d.get("_total_hands")), TYPE_INT)
	assert_eq(typeof(ai_d.get("_opponent_riichi_seats")), TYPE_ARRAY)
	assert_eq(typeof(ai_d.get("_opponent_discards_flat")), TYPE_ARRAY)
	assert_eq((ai_d.get("_cumulative_scores") as Array).size(), 4,
		"ARS_AI_STRICT: 基线 _cumulative_scores 恰四席")
	assert_gt((ai_d.get("_opponent_riichi_seats") as Array).size(), 0,
		"ARS_AI_STRICT: 基线 riichi seats 非空（供元素类型/范围污染）")
	assert_gt((ai_d.get("_opponent_discards_flat") as Array).size(), 0,
		"ARS_AI_STRICT: 基线 discards_flat 非空（供元素类型污染）")
	return d

## 仅污染 ai 子 dict（或顶层 erase ai）；valid 其余字段保持真实 capture 原样。
func _corrupt_ai_case(valid: Dictionary, case_name: String) -> Dictionary:
	var d: Dictionary = valid.duplicate(true)
	# 顶层完全缺失 ai（≠ 显式 ai={} 合法保留）
	if case_name == "missing_top_level_ai":
		assert_true(d.has("ai"), "%s: 基线 capture 须有顶层 ai" % case_name)
		assert_false((d.get("ai", {}) as Dictionary).is_empty(),
			"%s: 基线 ai 须非空（再 erase 整键）" % case_name)
		d.erase("ai")
		assert_false(d.has("ai"), "%s: 损坏后顶层 ai 键须完全缺失" % case_name)
		return d

	var ai: Dictionary = (d.get("ai", {}) as Dictionary).duplicate(true)
	assert_false(ai.is_empty(), "%s: 基线 ai 须非空" % case_name)
	match case_name:
		"simple_missing_kind":
			assert_true(ai.has("kind"), "%s: 基线须有 kind" % case_name)
			ai.erase("kind")
			assert_false(ai.has("kind"), "%s: 损坏后 kind 须缺失" % case_name)
			assert_false(ai.is_empty(), "%s: 缺 kind 后 ai 仍须非空（走非空路径）" % case_name)
		"simple_unknown_kind":
			ai["kind"] = "UnknownAiKind"
			assert_ne(str(ai["kind"]), "SimpleAi")
			assert_ne(str(ai["kind"]), "HeuristicAi")
		"simple_seed_not_int":
			assert_eq(typeof(ai.get("seed")), TYPE_INT, "%s: 基线 seed 须 int" % case_name)
			ai["seed"] = "not-an-int"
			assert_eq(typeof(ai["seed"]), TYPE_STRING)
		"simple_state_not_int":
			assert_eq(typeof(ai.get("state")), TYPE_INT, "%s: 基线 state 须 int" % case_name)
			ai["state"] = true
			assert_eq(typeof(ai["state"]), TYPE_BOOL)
		"simple_unknown_extra_key":
			# 合法 SimpleAi 全字段仅额外加一个未知键
			var n_simple: int = ai.size()
			assert_false(ai.has("extra_unknown"), "%s: 基线不得已有 extra_unknown" % case_name)
			ai["extra_unknown"] = 0
			assert_true(ai.has("extra_unknown"))
			assert_eq(ai.size(), n_simple + 1, "%s: 只额外一个未知键" % case_name)
			assert_eq(str(ai.get("kind", "")), "SimpleAi")
			assert_eq(typeof(ai.get("seed")), TYPE_INT)
			assert_eq(typeof(ai.get("state")), TYPE_INT)
		"heuristic_seed_not_int":
			assert_eq(typeof(ai.get("seed")), TYPE_INT)
			ai["seed"] = 1.5
			assert_eq(typeof(ai["seed"]), TYPE_FLOAT)
		"heuristic_state_not_int":
			assert_eq(typeof(ai.get("state")), TYPE_INT)
			ai["state"] = "0"
			assert_eq(typeof(ai["state"]), TYPE_STRING)
		"heuristic_shanten_not_bool":
			assert_eq(typeof(ai.get("use_shanten_aware_discard")), TYPE_BOOL)
			ai["use_shanten_aware_discard"] = 1
			assert_eq(typeof(ai["use_shanten_aware_discard"]), TYPE_INT)
		"heuristic_scores_not_array":
			assert_eq(typeof(ai.get("_cumulative_scores")), TYPE_ARRAY)
			ai["_cumulative_scores"] = 41000
			assert_ne(typeof(ai["_cumulative_scores"]), TYPE_ARRAY)
		"heuristic_hand_index_not_int":
			assert_eq(typeof(ai.get("_hand_index")), TYPE_INT)
			ai["_hand_index"] = "5"
			assert_eq(typeof(ai["_hand_index"]), TYPE_STRING)
		"heuristic_total_hands_not_int":
			assert_eq(typeof(ai.get("_total_hands")), TYPE_INT)
			ai["_total_hands"] = 8.0
			assert_eq(typeof(ai["_total_hands"]), TYPE_FLOAT)
		"heuristic_riichi_not_array":
			assert_eq(typeof(ai.get("_opponent_riichi_seats")), TYPE_ARRAY)
			ai["_opponent_riichi_seats"] = 1
			assert_ne(typeof(ai["_opponent_riichi_seats"]), TYPE_ARRAY)
		"heuristic_discards_not_array":
			assert_eq(typeof(ai.get("_opponent_discards_flat")), TYPE_ARRAY)
			ai["_opponent_discards_flat"] = {"tid": TileId.W1}
			assert_eq(typeof(ai["_opponent_discards_flat"]), TYPE_DICTIONARY)
		"heuristic_scores_elem_not_int":
			# capture 可能带 Array[int]；须拷入 untyped Array 才能写入非 int 元素
			var sc: Array = []
			for v in ai.get("_cumulative_scores") as Array:
				sc.append(v)
			assert_eq(sc.size(), 4, "%s: 基线 scores 恰 4" % case_name)
			assert_eq(typeof(sc[0]), TYPE_INT)
			sc[2] = "19000"
			assert_eq(typeof(sc[2]), TYPE_STRING)
			ai["_cumulative_scores"] = sc
		"heuristic_riichi_elem_not_int":
			var rs: Array = []
			for v2 in ai.get("_opponent_riichi_seats") as Array:
				rs.append(v2)
			assert_gt(rs.size(), 0, "%s: 基线 riichi 非空" % case_name)
			assert_eq(typeof(rs[0]), TYPE_INT)
			rs[0] = "1"
			assert_eq(typeof(rs[0]), TYPE_STRING)
			ai["_opponent_riichi_seats"] = rs
		"heuristic_discards_elem_not_int":
			var df: Array = []
			for v3 in ai.get("_opponent_discards_flat") as Array:
				df.append(v3)
			assert_gt(df.size(), 0, "%s: 基线 discards 非空" % case_name)
			assert_eq(typeof(df[0]), TYPE_INT)
			df[0] = 1.0
			assert_eq(typeof(df[0]), TYPE_FLOAT)
			ai["_opponent_discards_flat"] = df
		"heuristic_scores_len_not_4":
			# 允许空；非空必须恰好四席 → 长度 3 违规
			var sc3: Array = [41000, 29000, 19000]
			assert_eq(sc3.size(), 3)
			assert_ne(sc3.size(), 0)
			assert_ne(sc3.size(), 4)
			for v in sc3:
				assert_eq(typeof(v), TYPE_INT)
			ai["_cumulative_scores"] = sc3
		"heuristic_riichi_seat_oob":
			# 元素须 0..3；4 越界
			var rs_oob: Array = [1, 4]
			assert_eq(typeof(rs_oob[0]), TYPE_INT)
			assert_eq(typeof(rs_oob[1]), TYPE_INT)
			assert_true(int(rs_oob[1]) < 0 or int(rs_oob[1]) > 3,
				"%s: 损坏 seat 须越界 0..3" % case_name)
			ai["_opponent_riichi_seats"] = rs_oob
		"heuristic_hand_index_negative":
			ai["_hand_index"] = -1
			assert_eq(typeof(ai["_hand_index"]), TYPE_INT)
			assert_lt(int(ai["_hand_index"]), 0)
		"heuristic_total_hands_negative":
			ai["_total_hands"] = -2
			assert_eq(typeof(ai["_total_hands"]), TYPE_INT)
			assert_lt(int(ai["_total_hands"]), 0)
		"heuristic_hand_index_ge_total":
			# total_hands>0 时须 hand_index < total_hands；等号违规
			ai["_hand_index"] = 8
			ai["_total_hands"] = 8
			assert_eq(typeof(ai["_hand_index"]), TYPE_INT)
			assert_eq(typeof(ai["_total_hands"]), TYPE_INT)
			assert_gt(int(ai["_total_hands"]), 0)
			assert_false(int(ai["_hand_index"]) < int(ai["_total_hands"]),
				"%s: 损坏后 hand_index 不得 < total_hands" % case_name)
		"heuristic_unknown_extra_key":
			# 合法 HeuristicAi 全字段仅额外加一个未知键
			var n_h: int = ai.size()
			assert_false(ai.has("extra_unknown"), "%s: 基线不得已有 extra_unknown" % case_name)
			ai["extra_unknown"] = true
			assert_true(ai.has("extra_unknown"))
			assert_eq(ai.size(), n_h + 1, "%s: 只额外一个未知键" % case_name)
			assert_eq(str(ai.get("kind", "")), "HeuristicAi")
			assert_eq(typeof(ai.get("seed")), TYPE_INT)
			assert_eq(typeof(ai.get("state")), TYPE_INT)
		"heuristic_discards_tid_not_in_all":
			# 仅含一个 TYPE_INT，但不属于 TileId.ALL（0..33 之外）
			var bad_tid: int = 34
			assert_eq(typeof(bad_tid), TYPE_INT)
			assert_false(TileId.ALL.has(bad_tid),
				"%s: 损坏 tid 不得 ∈ TileId.ALL" % case_name)
			ai["_opponent_discards_flat"] = [bad_tid]
			var df_bad: Array = ai["_opponent_discards_flat"] as Array
			assert_eq(df_bad.size(), 1, "%s: discards 须仅含一个元素" % case_name)
			assert_eq(typeof(df_bad[0]), TYPE_INT)
			assert_false(TileId.ALL.has(int(df_bad[0])))
		"heuristic_riichi_duplicate_seats":
			# 元素类型/范围合法（0..3 int）但 seat 重复
			var rs_dup: Array = [1, 1]
			assert_eq(rs_dup.size(), 2)
			assert_eq(typeof(rs_dup[0]), TYPE_INT)
			assert_eq(typeof(rs_dup[1]), TYPE_INT)
			assert_true(int(rs_dup[0]) >= 0 and int(rs_dup[0]) <= 3)
			assert_true(int(rs_dup[1]) >= 0 and int(rs_dup[1]) <= 3)
			assert_eq(int(rs_dup[0]), int(rs_dup[1]),
				"%s: 损坏后 seat 须重复" % case_name)
			ai["_opponent_riichi_seats"] = rs_dup
		_:
			assert_true(false, "未知 ai strict case: %s" % case_name)
	d["ai"] = ai
	assert_false((d["ai"] as Dictionary).is_empty(),
		"%s: 损坏后 ai 仍非空（非 ai={} 保留语义）" % case_name)
	return d

## 回归：ai={} 视为「保持 target.ai」——restore 成功且 ai 引用不变（非严格拒绝）。
func test_ars_empty_ai_dict_restore_preserves_target_ai_ref() -> void:
	var ars := _ars_ready()
	if ars == null:
		return
	var bc_scr := _bc_ready()
	if bc_scr == null:
		return
	# 源：真实 SimpleAi 全量 capture（ai 非空）
	var valid: Dictionary = _valid_simple_ai_snap_dict(ars, bc_scr, 19, 2)
	if valid.is_empty():
		assert_true(false, "empty-ai 回归: 有效源 fixture 失败")
		return
	assert_false((valid.get("ai", {}) as Dictionary).is_empty(),
		"empty-ai 回归: 基线 capture.ai 须非空")

	var with_empty_ai: Dictionary = valid.duplicate(true)
	with_empty_ai["ai"] = {}
	assert_true((with_empty_ai["ai"] as Dictionary).is_empty())

	var snap: Object = _ars_from_data(ars, with_empty_ai)
	if snap == null:
		return
	# 目标：不同 seed；故意用 HeuristicAi 便于观察「保留」而非被源 SimpleAi 覆盖
	var target: Object = bc_scr.new(991, 0, true, TileId.E, 1)
	assert_not_null(target)
	if target == null or target.get("state") == null:
		assert_true(false, "empty-ai 回归: 目标 BC 构造失败")
		return
	var ai_before = target.get("ai")
	assert_not_null(ai_before, "empty-ai 回归: target.ai 非 null")
	assert_true(ai_before is HeuristicAi, "empty-ai 回归: 目标初始须 HeuristicAi")

	var ok_raw: Variant = snap.call("restore_into", target)
	assert_eq(typeof(ok_raw), TYPE_BOOL, "empty-ai 回归: restore_into 须返 bool")
	assert_true(bool(ok_raw), "empty-ai 回归: ai={} 须 restore 成功")
	assert_same(target.get("ai"), ai_before,
		"empty-ai 回归: restore 后 target.ai 须保持同一引用")

## SimpleAi / HeuristicAi 非空 ai 严格 schema 损坏：各自全新 valid + target，原子拒绝。
func test_ars_strict_rejects_invalid_ai_snapshots_and_is_atomic() -> void:
	var ars := _ars_ready()
	if ars == null:
		return
	var bc_scr := _bc_ready()
	if bc_scr == null:
		return

	# case_name → [family, src_seed, src_hs, dst_seed, dst_hs]
	# family: "simple" | "heuristic"；源/目标 seed 每 case 独立，避免交叉污染。
	var cases: Array = [
		["simple_missing_kind", "simple", 17, 3, 161, 1],
		["simple_unknown_kind", "simple", 17, 3, 162, 2],
		["simple_seed_not_int", "simple", 17, 3, 163, 3],
		["simple_state_not_int", "simple", 17, 3, 164, 4],
		["heuristic_seed_not_int", "heuristic", 31, 4, 165, 5],
		["heuristic_state_not_int", "heuristic", 31, 4, 166, 6],
		["heuristic_shanten_not_bool", "heuristic", 31, 4, 167, 0],
		["heuristic_scores_not_array", "heuristic", 31, 4, 168, 1],
		["heuristic_hand_index_not_int", "heuristic", 31, 4, 169, 2],
		["heuristic_total_hands_not_int", "heuristic", 31, 4, 170, 3],
		["heuristic_riichi_not_array", "heuristic", 31, 4, 171, 4],
		["heuristic_discards_not_array", "heuristic", 31, 4, 172, 5],
		["heuristic_scores_elem_not_int", "heuristic", 31, 4, 173, 6],
		["heuristic_riichi_elem_not_int", "heuristic", 31, 4, 174, 0],
		["heuristic_discards_elem_not_int", "heuristic", 31, 4, 175, 1],
		["heuristic_scores_len_not_4", "heuristic", 31, 4, 176, 2],
		["heuristic_riichi_seat_oob", "heuristic", 31, 4, 177, 3],
		["heuristic_hand_index_negative", "heuristic", 31, 4, 178, 4],
		["heuristic_total_hands_negative", "heuristic", 31, 4, 179, 5],
		["heuristic_hand_index_ge_total", "heuristic", 31, 4, 180, 6],
		# 本轮 Red：顶层缺 ai / 未知键 / discards∉ALL / riichi 重复
		["missing_top_level_ai", "simple", 17, 3, 181, 1],
		["simple_unknown_extra_key", "simple", 17, 3, 182, 2],
		["heuristic_unknown_extra_key", "heuristic", 31, 4, 183, 3],
		["heuristic_discards_tid_not_in_all", "heuristic", 31, 4, 184, 4],
		["heuristic_riichi_duplicate_seats", "heuristic", 31, 4, 185, 5],
	]
	for row in cases:
		var case_name: String = str(row[0])
		var family: String = str(row[1])
		var src_seed: int = int(row[2])
		var src_hs: int = int(row[3])
		var dst_seed: int = int(row[4])
		var dst_hs: int = int(row[5])
		assert_ne(src_seed, dst_seed, "%s: 源/目标 seed 须不同" % case_name)

		var valid: Dictionary = {}
		if family == "simple":
			valid = _valid_simple_ai_snap_dict(ars, bc_scr, src_seed, src_hs)
		elif family == "heuristic":
			valid = _valid_heuristic_ai_snap_dict(ars, bc_scr, src_seed, src_hs)
		else:
			assert_true(false, "%s: 未知 family %s" % [case_name, family])
			return
		if valid.is_empty():
			assert_true(false, "%s: 有效源 fixture 生成失败" % case_name)
			return

		var corrupted_dict: Dictionary = _corrupt_ai_case(valid, case_name)
		var corrupted: Object = _ars_from_data(ars, corrupted_dict)
		if corrupted == null:
			return

		# 每 case 全新 target，杜绝半恢复污染串联
		var target := _make_bc(bc_scr, dst_seed, dst_hs)
		if target == null:
			assert_true(false, "%s: 目标 BC 构造失败" % case_name)
			return
		_assert_strict_atomic_reject(ars, target, corrupted, case_name)

## #232 ARS AI：合法默认 HeuristicAi 空 context roundtrip。
## 真实 bc_scr.new(..., use_heuristic=true) 默认态：scores/riichi/discards 均空、
## hand_index/total_hands=0、use_shanten_aware_discard=false。
## 锁定「_cumulative_scores 允许空；仅非空才必须四席」。
## 目标故意不同 seed + SimpleAi，restore 须成功并恢复 exact HeuristicAi + 空 context + RNG。
func test_ars_heuristic_ai_default_empty_context_roundtrip() -> void:
	var ars := _ars_ready()
	if ars == null:
		return
	var bc_scr := _bc_ready()
	if bc_scr == null:
		return
	const SRC_SEED := 41
	const SRC_HS := 2
	const DST_SEED := 802
	const DST_HS := 0

	# 源：合法默认 HeuristicAi（不注入 strategic/defense；不改 shanten 开关）
	var bc_src: Object = bc_scr.new(SRC_SEED, 0, true, TileId.E, SRC_HS)
	assert_not_null(bc_src)
	if bc_src == null or bc_src.get("state") == null:
		assert_true(false, "empty-ctx: HeuristicAi 源 BC 构造失败")
		return
	var ai_src = bc_src.get("ai")
	assert_not_null(ai_src, "empty-ctx: 源 ai 非 null")
	assert_true(ai_src is HeuristicAi, "empty-ctx: 源 ai 须为 HeuristicAi")
	if not (ai_src is HeuristicAi):
		return
	var h_src: HeuristicAi = ai_src as HeuristicAi
	assert_true(h_src._cumulative_scores.is_empty(), "empty-ctx: 默认 _cumulative_scores 空")
	assert_true(h_src._opponent_riichi_seats.is_empty(), "empty-ctx: 默认 _opponent_riichi_seats 空")
	assert_true(h_src._opponent_discards_flat.is_empty(), "empty-ctx: 默认 _opponent_discards_flat 空")
	assert_eq(int(h_src._hand_index), 0, "empty-ctx: 默认 _hand_index=0")
	assert_eq(int(h_src._total_hands), 0, "empty-ctx: 默认 _total_hands=0")
	assert_false(bool(h_src.use_shanten_aware_discard),
		"empty-ctx: 默认 use_shanten_aware_discard=false")

	var snap: Variant = _capture(ars, bc_src)
	if snap == null:
		return
	var cap_seed: int = int(h_src._rng.seed)
	var cap_state: int = int(h_src._rng.state)

	var d: Dictionary = snap.call("to_dict") as Dictionary
	assert_true(d.has("ai"), "empty-ctx: capture contract 须有 ai")
	var ai_d: Dictionary = d.get("ai", {}) as Dictionary
	assert_false(ai_d.is_empty(), "empty-ctx: 默认 HeuristicAi capture.ai 须非空")
	assert_eq(str(ai_d.get("kind", "")), "HeuristicAi", "empty-ctx: kind=HeuristicAi")
	assert_eq(typeof(ai_d.get("_cumulative_scores")), TYPE_ARRAY)
	assert_eq(typeof(ai_d.get("_opponent_riichi_seats")), TYPE_ARRAY)
	assert_eq(typeof(ai_d.get("_opponent_discards_flat")), TYPE_ARRAY)
	assert_true((ai_d.get("_cumulative_scores") as Array).is_empty(),
		"empty-ctx: capture _cumulative_scores 须空（允许空，非强制四席）")
	assert_true((ai_d.get("_opponent_riichi_seats") as Array).is_empty(),
		"empty-ctx: capture _opponent_riichi_seats 须空")
	assert_true((ai_d.get("_opponent_discards_flat") as Array).is_empty(),
		"empty-ctx: capture _opponent_discards_flat 须空")
	assert_eq(int(ai_d.get("_hand_index", -1)), 0)
	assert_eq(int(ai_d.get("_total_hands", -1)), 0)
	assert_false(bool(ai_d.get("use_shanten_aware_discard", true)))
	assert_eq(int(ai_d.get("seed", -1)), cap_seed)
	assert_eq(int(ai_d.get("state", -1)), cap_state)

	# 目标：不同 seed + SimpleAi（对照 exact kind 切换）
	var bc_dst: Object = bc_scr.new(DST_SEED, 0, false, TileId.E, DST_HS)
	assert_not_null(bc_dst)
	if bc_dst == null or bc_dst.get("state") == null:
		assert_true(false, "empty-ctx: 目标 BC 构造失败")
		return
	var ai_before = bc_dst.get("ai")
	assert_true(ai_before is SimpleAi, "empty-ctx: 目标初始须 SimpleAi")
	assert_false(ai_before is HeuristicAi, "empty-ctx: 目标初始须非 HeuristicAi")
	assert_true(bool(snap.call("restore_into", bc_dst)),
		"empty-ctx: 空 context HeuristicAi restore_into 须 true")

	var ai_dst = bc_dst.get("ai")
	assert_not_null(ai_dst, "empty-ctx: restore 后 ai 非 null")
	assert_true(ai_dst is HeuristicAi, "empty-ctx: restore 后 exact HeuristicAi")
	if not (ai_dst is HeuristicAi):
		return
	var h_dst: HeuristicAi = ai_dst as HeuristicAi
	assert_true(h_dst._cumulative_scores.is_empty(),
		"empty-ctx: restore 后 _cumulative_scores 仍空")
	assert_true(h_dst._opponent_riichi_seats.is_empty(),
		"empty-ctx: restore 后 _opponent_riichi_seats 仍空")
	assert_true(h_dst._opponent_discards_flat.is_empty(),
		"empty-ctx: restore 后 _opponent_discards_flat 仍空")
	assert_eq(int(h_dst._hand_index), 0, "empty-ctx: restore 后 _hand_index=0")
	assert_eq(int(h_dst._total_hands), 0, "empty-ctx: restore 后 _total_hands=0")
	assert_false(bool(h_dst.use_shanten_aware_discard),
		"empty-ctx: restore 后 use_shanten_aware_discard=false")
	assert_eq(int(h_dst._rng.seed), cap_seed, "empty-ctx: RNG seed 原样")
	assert_eq(int(h_dst._rng.state), cap_state, "empty-ctx: RNG state 原样")


# ── #232 ARS canonical Dictionary 键：int/string wire 规范化 + 冲突严格拒绝 ──
# 方案 A：canonical JSON 允许 Dictionary 整数键与字符串键，按 JSON wire 键名规范化
# （int 0 → wire "0"）；同一 Dictionary 同时含 0 与 "0" → wire 冲突 → sha256 ""，不崩溃。
# 整数 payout 键须稳定 hash / JSON roundtrip / restore；等价数据稳定 SHA。

## 纯 int 键 vs 等价 string wire 键 → 同 SHA；插入顺序无关；嵌套可传播。
func test_ars_canonical_int_keys_wire_normalize_stable_sha() -> void:
	var ars := _ars_ready()
	if ars == null:
		return
	# 整数 payout 键（真实 PayoutCalculator 形态）
	var payout_int: Dictionary = {0: 1000, 1: 2000, 3: 4000}
	var payout_str: Dictionary = {"0": 1000, "1": 2000, "3": 4000}
	# 插入顺序不同、键类型不同 → 仍须 wire 等价
	var payout_int_reordered: Dictionary = {3: 4000, 0: 1000, 1: 2000}

	var snap_int: Object = _ars_from_data(ars, {"payout": payout_int, "tag": "ars-wire"})
	var snap_str: Object = _ars_from_data(ars, {"payout": payout_str, "tag": "ars-wire"})
	var snap_re: Object = _ars_from_data(ars, {"payout": payout_int_reordered, "tag": "ars-wire"})
	if snap_int == null or snap_str == null or snap_re == null:
		return

	var h_int: String = str(snap_int.call("sha256"))
	var h_str: String = str(snap_str.call("sha256"))
	var h_re: String = str(snap_re.call("sha256"))
	assert_true(_hex64(h_int), "int 键 payout 须产生 64 hex SHA（不得崩溃/空串）")
	assert_true(_hex64(h_str), "string wire 键 payout 须 64 hex SHA")
	assert_eq(h_int, h_str, "int 键与 wire 字符串键须稳定同 SHA")
	assert_eq(h_int, h_re, "键插入顺序不得影响 canonical SHA")
	# 同实例再 hash 稳定
	assert_eq(str(snap_int.call("sha256")), h_int, "同 _data 再 sha256 须稳定")

	# 嵌套 Dictionary 中的 int 键同样规范化
	var nested_int: Object = _ars_from_data(ars, {
		"event_journal": [{"extra": {"payout": {2: 8000, 0: 1600}}}],
	})
	var nested_str: Object = _ars_from_data(ars, {
		"event_journal": [{"extra": {"payout": {"0": 1600, "2": 8000}}}],
	})
	if nested_int == null or nested_str == null:
		return
	var hn_i: String = str(nested_int.call("sha256"))
	var hn_s: String = str(nested_str.call("sha256"))
	assert_true(_hex64(hn_i), "嵌套 int 键须 64 hex SHA")
	assert_eq(hn_i, hn_s, "嵌套 int/string wire 键须同 SHA")


## 同一 Dictionary 同时含 int 0 与 string "0" → wire 冲突 → sha256 ""；任意嵌套传播失败。
func test_ars_canonical_wire_key_conflict_0_and_string_0_rejects() -> void:
	var ars := _ars_ready()
	if ars == null:
		return
	# 顶层 payout 冲突
	var conflict: Dictionary = {}
	conflict[0] = 100
	conflict["0"] = 200
	assert_eq(conflict.size(), 2, "Godot Dictionary 须能同时持有 0 与 \"0\"")
	var snap_top: Object = _ars_from_data(ars, {"payout": conflict})
	if snap_top == null:
		return
	var h_top: String = str(snap_top.call("sha256"))
	assert_eq(h_top, "", "顶层 0/\"0\" wire 冲突须 sha256 空串，不得崩溃")
	assert_eq(h_top.length(), 0)
	# 再次调用仍失败、不抛
	assert_eq(str(snap_top.call("sha256")), "", "冲突态再 sha256 仍空串")

	# 嵌套：event_journal[].extra.payout 冲突必须向上传播为失败
	var nested_conflict: Dictionary = {}
	nested_conflict[1] = 50
	nested_conflict["1"] = 99
	var snap_nested: Object = _ars_from_data(ars, {
		"ok_sibling": {"a": 1},
		"event_journal": [
			{"type": "WIN_DECLARED", "extra": {"payout": nested_conflict}},
		],
	})
	if snap_nested == null:
		return
	assert_eq(str(snap_nested.call("sha256")), "",
		"嵌套 Dictionary wire 键冲突须传播为 sha256 空串")

	# 合法旁路：仅 int 或仅 string 不得被冲突逻辑误伤
	var ok_int: Object = _ars_from_data(ars, {"payout": {0: 100}})
	var ok_str: Object = _ars_from_data(ars, {"payout": {"0": 100}})
	if ok_int == null or ok_str == null:
		return
	assert_true(_hex64(str(ok_int.call("sha256"))), "仅 int 0 合法")
	assert_eq(str(ok_int.call("sha256")), str(ok_str.call("sha256")),
		"仅 int 0 与仅 \"0\" 等价合法")


## 真实合法 capture：event_journal 注入结构完整 BattleEvent，payout 同时含 0/"0"。
## 契约：冲突 snapshot.sha256==""；restore_into 在触碰 target/staging 前走同一 _canonical_json，
## 返回 null 则 false；target 前后 capture SHA 相同（零污染）。
func test_ars_real_capture_payout_wire_conflict_rejects_restore() -> void:
	var ars := _ars_ready()
	if ars == null:
		return
	var bc_scr := _bc_ready()
	if bc_scr == null:
		return
	# 真实合法 AuthorityReplaySnapshot capture（_enrich 丰化 + 公开 capture）
	var bc_src := _make_bc(bc_scr, 11, 4)
	if bc_src == null:
		return
	if _enrich(bc_src).is_empty():
		return
	var snap_src: Variant = _capture(ars, bc_src)
	if snap_src == null:
		return
	var h_src: String = _sha(snap_src)
	assert_true(_hex64(h_src), "wire-conflict: 基线 capture 须 64 hex SHA")

	var data: Dictionary = snap_src.call("to_dict") as Dictionary
	assert_false(data.is_empty(), "wire-conflict: to_dict 非空")
	# 结构完整 BattleEvent（真实 make→to_dict），extra.payout 同时含 int 0 与 string "0"
	var conflict_payout: Dictionary = {}
	conflict_payout[0] = 1000
	conflict_payout["0"] = 2000
	assert_eq(conflict_payout.size(), 2, "wire-conflict: Godot Dict 须同时持有 0 与 \"0\"")
	var be: BattleEvent = BattleEvent.make(
		&"WIN_DECLARED", 0, null,
		{"payout": conflict_payout, "han": 3, "fu": 30})
	assert_not_null(be, "wire-conflict: BattleEvent.make 须成功")
	var be_d: Dictionary = be.to_dict()
	assert_false(be_d.is_empty())
	assert_eq(str(be_d.get("type", "")), "WIN_DECLARED")
	assert_true(be_d.has("actor_seat") and be_d.has("tile") and be_d.has("chain_id")
		and be_d.has("extra"), "wire-conflict: 须为完整 BattleEvent to_dict 结构")
	var extra_d: Dictionary = be_d.get("extra", {}) as Dictionary
	var pay_d: Dictionary = extra_d.get("payout", {}) as Dictionary
	assert_eq(pay_d.size(), 2, "wire-conflict: 序列化后 payout 须保留 0 与 \"0\"")
	assert_true(pay_d.has(0) and pay_d.has("0"),
		"wire-conflict: payout 键须同时含 int 0 与 string \"0\"")
	# 注入/替换 event_journal：在真实 journal 上追加完整冲突事件
	var ej: Array = (data.get("event_journal", []) as Array).duplicate()
	ej.append(be_d)
	data["event_journal"] = ej
	# 写入新 ARS（仅 _data；不经 capture）
	var conflict_snap: Object = _ars_from_data(ars, data)
	if conflict_snap == null:
		return
	assert_eq(str(conflict_snap.call("sha256")), "",
		"wire-conflict: 真实 capture 嵌套 payout 0/\"0\" 须 sha256 空串")

	# 目标 BC：先 capture SHA 作零污染基线
	var target := _make_bc(bc_scr, 99, 1)
	if target == null:
		return
	var before_snap: Variant = _capture(ars, target)
	if before_snap == null:
		return
	var before_sha: String = _sha(before_snap)

	var ok_raw: Variant = conflict_snap.call("restore_into", target)
	assert_eq(typeof(ok_raw), TYPE_BOOL, "wire-conflict: restore_into 须返 bool")
	assert_false(bool(ok_raw),
		"wire-conflict: payout 0/\"0\" 冲突 restore_into 须 false（禁止半恢复）")

	var after_snap: Variant = _capture(ars, target)
	if after_snap == null:
		return
	assert_eq(_sha(after_snap), before_sha,
		"wire-conflict: restore 后 target capture SHA 须与 before 相同（零污染）")


## 真实 capture：int payout 键稳定 hash；wire 字符串键 roundtrip 同 SHA；restore 成功。
## 注：Godot JSON.parse 会把 number 变成 float，整包 stringify/parse 会改值类型，
## 故「JSON wire roundtrip」指键名规范化（int 0 → "0"），值保持 int 的等价数据。
func test_ars_int_payout_keys_hash_json_roundtrip_restore() -> void:
	var ars := _ars_ready()
	if ars == null:
		return
	var bc_scr := _bc_ready()
	if bc_scr == null:
		return
	# seed 42 + heuristic：run_to_end 后 event_journal 常含 WIN_DECLARED.extra.payout（int 键）
	var bc_src: Object = bc_scr.new(42, 0, true, TileId.E, 0)
	assert_not_null(bc_src)
	if bc_src == null or bc_src.get("state") == null:
		assert_true(false, "payout-rt: 源 BC 构造失败")
		return
	assert_true(bc_src.has_method("run_to_end"), "payout-rt: 缺 run_to_end")
	bc_src.call("run_to_end")

	var snap: Variant = _capture(ars, bc_src)
	if snap == null:
		return
	var h0: String = str(snap.call("sha256"))
	assert_true(_hex64(h0), "payout-rt: 终态 capture.sha256 须 64 hex（int 键不得崩溃）")
	assert_eq(str(snap.call("sha256")), h0, "payout-rt: 双 sha256 稳定")

	var d: Dictionary = snap.call("to_dict") as Dictionary
	assert_false(d.is_empty())
	var scan: Dictionary = _collect_int_key_stats(d)
	var saw_int_key: bool = bool(scan.get("int_keys", false))
	var saw_payout: bool = bool(scan.get("payout", false))

	# 显式 int payout 注入：hash 稳定 + wire 字符串键等价（值仍 int，模拟 JSON 键名 roundtrip）
	var payout_int: Dictionary = {0: 12000, 1: 4000, 2: 4000, 3: 4000}
	var d_inj: Dictionary = d.duplicate(true)
	var ej: Array = (d_inj.get("event_journal", []) as Array).duplicate()
	ej.append({
		"type": "WIN_DECLARED",
		"actor_seat": 0,
		"tile": {},
		"extra": {"payout": payout_int.duplicate(), "han": 5, "fu": 40},
	})
	d_inj["event_journal"] = ej
	assert_true(
		bool(_collect_int_key_stats(d_inj).get("int_keys", false)),
		"payout-rt: 注入后须存在 int 键"
	)
	var snap_inj: Object = _ars_from_data(ars, d_inj)
	if snap_inj == null:
		return
	var h_inj: String = str(snap_inj.call("sha256"))
	assert_true(_hex64(h_inj), "payout-rt: 注入 int payout 后须 64 hex SHA")

	# JSON wire 键 roundtrip：stringify 仅取 payout 叶子验证键变为 string，
	# 再构造值仍为 int 的 string-key 等价 _data（避免 Godot parse→float 干扰键契约）
	var leaf_json: String = JSON.stringify({"payout": payout_int})
	var leaf_parsed: Variant = JSON.parse_string(leaf_json)
	assert_eq(typeof(leaf_parsed), TYPE_DICTIONARY)
	var leaf_payout: Dictionary = (leaf_parsed as Dictionary).get("payout", {}) as Dictionary
	assert_gt(leaf_payout.size(), 0)
	for k in leaf_payout.keys():
		assert_eq(typeof(k), TYPE_STRING,
			"payout-rt: JSON.stringify 后 wire 键须 string，得 typeof=%d" % typeof(k))
	var payout_wire: Dictionary = {}
	for k in payout_int.keys():
		payout_wire[str(int(k))] = int(payout_int[k])
	var d_wire: Dictionary = d.duplicate(true)
	var ej_wire: Array = (d_wire.get("event_journal", []) as Array).duplicate()
	ej_wire.append({
		"type": "WIN_DECLARED",
		"actor_seat": 0,
		"tile": {},
		"extra": {"payout": payout_wire, "han": 5, "fu": 40},
	})
	d_wire["event_journal"] = ej_wire
	var snap_wire: Object = _ars_from_data(ars, d_wire)
	if snap_wire == null:
		return
	assert_eq(str(snap_wire.call("sha256")), h_inj,
		"payout-rt: int 键与 JSON wire 字符串键（值 int）须同 SHA")

	# restore 真实 capture 路径
	var target: Object = _make_bc(bc_scr, 99, 1)
	if target == null:
		return
	assert_true(bool(snap.call("restore_into", target)),
		"payout-rt: 真实终态 restore_into 须 true")
	var recap: Variant = _capture(ars, target)
	if recap == null:
		return
	assert_eq(str(recap.call("sha256")), h0,
		"payout-rt: restore 后再 capture SHA 须与源一致")

	var only_int: Object = _ars_from_data(ars, {"payout": {1: 2000, 2: 2000, 3: 2000}})
	var only_str: Object = _ars_from_data(ars, {"payout": {"1": 2000, "2": 2000, "3": 2000}})
	if only_int == null or only_str == null:
		return
	assert_eq(str(only_int.call("sha256")), str(only_str.call("sha256")),
		"payout-rt: 纯 int/string payout 等价 SHA")
	if not saw_int_key and not saw_payout:
		gut.p("payout-rt: 源 capture 无 int 键/payout（依赖注入路径）")


## 递归统计：是否出现 TYPE_INT 键；是否出现名为 payout 且含键的 Dictionary。
func _collect_int_key_stats(v: Variant) -> Dictionary:
	var out := {"int_keys": false, "payout": false}
	_collect_int_key_stats_into(v, out)
	return out


func _collect_int_key_stats_into(v: Variant, out: Dictionary) -> void:
	match typeof(v):
		TYPE_ARRAY:
			for item in v as Array:
				_collect_int_key_stats_into(item, out)
		TYPE_DICTIONARY:
			var d: Dictionary = v as Dictionary
			for k in d.keys():
				if typeof(k) == TYPE_INT:
					out["int_keys"] = true
				if str(k) == "payout" and typeof(d[k]) == TYPE_DICTIONARY \
					and not (d[k] as Dictionary).is_empty():
					out["payout"] = true
				_collect_int_key_stats_into(d[k], out)
		_:
			pass


## 回归：现有 TileSkillFactory 用 INVALID_INSTANCE_ID 的虚拟 TileSkillAnchor 作技能锚点。
## 该锚点不属于 136 张实体牌墙，但仍是权威技能状态，capture/restore 必须无损。
func test_ars_restores_tile_skill_factory_virtual_anchor() -> void:
	var source := BattleController.new(73, 0, false, TileId.E, 2)
	assert_true(TileSkillFactory.inject_one(
		source.registry, &"xray_1w_v1", 0),
		"真实 TileSkillFactory fixture 必须注入成功")
	var source_entries: Array = source.registry.get_all_entries()
	assert_eq(source_entries.size(), 1)
	if source_entries.size() != 1:
		return
	var source_anchor: Variant = (source_entries[0] as Dictionary).get("anchor")
	assert_true(source_anchor is TileSkillAnchor)
	if not (source_anchor is TileSkillAnchor):
		return
	assert_eq(int((source_anchor as TileSkillAnchor).tile.instance_id), Tile.INVALID_INSTANCE_ID)

	var snap: AuthorityReplaySnapshot = AuthorityReplaySnapshot.capture(source)
	assert_not_null(snap)
	if snap == null:
		return
	assert_eq(snap.sha256().length(), 64)
	var target := BattleController.new(99, 1, false, TileId.S_WIND, 0)
	assert_true(snap.restore_into(target),
		"虚拟牌锚点不在 wall namespace，但必须按虚拟锚点契约恢复")

	var restored_entries: Array = target.registry.get_all_entries()
	assert_eq(restored_entries.size(), 1)
	if restored_entries.size() != 1:
		return
	var restored: Dictionary = restored_entries[0] as Dictionary
	var restored_skill: SkillResource = restored.get("skill") as SkillResource
	var restored_anchor: TileSkillAnchor = restored.get("anchor") as TileSkillAnchor
	assert_not_null(restored_skill)
	assert_not_null(restored_anchor)
	if restored_skill == null or restored_anchor == null:
		return
	assert_eq(restored_skill.id, &"xray_1w_v1")
	assert_true(restored_anchor.skill == restored_skill,
		"恢复后的虚拟锚点必须引用同一份恢复 SkillResource")
	assert_eq(restored_anchor.tile.id, TileId.W1)
	assert_eq(restored_anchor.tile.instance_id, Tile.INVALID_INSTANCE_ID)
	assert_eq(restored_anchor.owner_seat, 0)
	assert_eq(restored_anchor.holder_seat, -1)
	var recap: AuthorityReplaySnapshot = AuthorityReplaySnapshot.capture(target)
	assert_not_null(recap)
	if recap != null:
		assert_eq(recap.sha256(), snap.sha256(), "恢复后再捕获必须保持确定性哈希")


## 顶层与嵌套恢复字段必须保持 capture 的精确 Variant 类型；禁止 int/bool/str 静默强转。
## 每个 case 都来自真实 enriched capture，只改变一个字段，并验证失败时 target 原子不变。
func test_ars_strict_rejects_scalar_and_nested_type_coercion() -> void:
	var ars := _ars_ready()
	var bc_scr := _bc_ready()
	if ars == null or bc_scr == null:
		return
	var valid: Dictionary = _valid_enriched_dict(ars, bc_scr, 79, 4)
	if valid.is_empty():
		assert_true(false, "ARS_TYPE: 有效 enriched fixture 生成失败")
		return

	var cases: Array = []
	var phase_string: Dictionary = valid.duplicate(true)
	phase_string["phase"] = str(int(valid["phase"]))
	cases.append(["top_phase_string", phase_string])

	var bool_int: Dictionary = valid.duplicate(true)
	bool_int["first_round_active"] = 1 if bool(valid["first_round_active"]) else 0
	cases.append(["top_bool_as_int", bool_int])

	var score_string: Dictionary = valid.duplicate(true)
	var scores: Array = []
	for score in score_string["scores"] as Array:
		scores.append(score)
	scores[0] = str(int(scores[0]))
	score_string["scores"] = scores
	cases.append(["score_string", score_string])

	var seat_points_string: Dictionary = valid.duplicate(true)
	var seats: Array = (seat_points_string["seats"] as Array).duplicate(true)
	var seat0: Dictionary = (seats[0] as Dictionary).duplicate(true)
	seat0["points"] = str(int(seat0["points"]))
	seats[0] = seat0
	seat_points_string["seats"] = seats
	cases.append(["seat_points_string", seat_points_string])

	var riichi_bool_int: Dictionary = valid.duplicate(true)
	var seats2: Array = (riichi_bool_int["seats"] as Array).duplicate(true)
	var seat02: Dictionary = (seats2[0] as Dictionary).duplicate(true)
	var riichi: Dictionary = (seat02["riichi"] as Dictionary).duplicate(true)
	riichi["declared"] = 1 if bool(riichi["declared"]) else 0
	seat02["riichi"] = riichi
	seats2[0] = seat02
	riichi_bool_int["seats"] = seats2
	cases.append(["riichi_bool_as_int", riichi_bool_int])

	var wall_cursor_string: Dictionary = valid.duplicate(true)
	var wall: Dictionary = (wall_cursor_string["wall"] as Dictionary).duplicate(true)
	wall["draw_index"] = str(int(wall["draw_index"]))
	wall_cursor_string["wall"] = wall
	cases.append(["wall_draw_index_string", wall_cursor_string])

	var momentum_string: Dictionary = valid.duplicate(true)
	var momentum: Dictionary = (momentum_string["momentum_scores"] as Dictionary).duplicate(true)
	var momentum_keys: Array = momentum.keys()
	assert_gt(momentum_keys.size(), 0, "ARS_TYPE: enriched fixture 须有 momentum score")
	if momentum_keys.is_empty():
		return
	var momentum_key: Variant = momentum_keys[0]
	momentum[momentum_key] = str(momentum[momentum_key])
	momentum_string["momentum_scores"] = momentum
	cases.append(["momentum_value_string", momentum_string])

	var replay_invalid: Dictionary = valid.duplicate(true)
	var expected: Array = (replay_invalid["expected_replay"] as Array).duplicate(true)
	expected.append({})
	replay_invalid["expected_replay"] = expected
	cases.append(["expected_replay_invalid_action", replay_invalid])

	var event_actor_string: Dictionary = valid.duplicate(true)
	var events: Array = (event_actor_string["event_journal"] as Array).duplicate(true)
	assert_gt(events.size(), 0, "ARS_TYPE: enriched fixture 须有 event journal")
	if events.is_empty():
		return
	var event0: Dictionary = (events[0] as Dictionary).duplicate(true)
	event0["actor_seat"] = str(int(event0["actor_seat"]))
	events[0] = event0
	event_actor_string["event_journal"] = events
	cases.append(["event_actor_string", event_actor_string])

	var dora_identity_mismatch: Dictionary = valid.duplicate(true)
	var dora: Array = (dora_identity_mismatch["dora"] as Array).duplicate(true)
	assert_gt(dora.size(), 0, "ARS_TYPE: fixture 须有 dora indicator")
	if dora.is_empty():
		return
	var dora0: Dictionary = (dora[0] as Dictionary).duplicate(true)
	dora0["owner_seat"] = (int(dora0["owner_seat"]) + 1) % 4
	dora[0] = dora0
	dora_identity_mismatch["dora"] = dora
	cases.append(["dora_identity_mismatch", dora_identity_mismatch])

	for i in range(cases.size()):
		var row: Array = cases[i]
		var case_name: String = str(row[0])
		var corrupted: Object = _ars_from_data(ars, row[1] as Dictionary)
		var target := _make_bc(bc_scr, 300 + i, i % 8)
		_assert_strict_atomic_reject(ars, target, corrupted, case_name)


## 能 restore 但会在 recapture 时被归一化的字段也必须预先拒绝，保证回放哈希闭环。
func test_ars_rejects_restore_recapture_hash_drift() -> void:
	var ars := _ars_ready()
	var bc_scr := _bc_ready()
	if ars == null or bc_scr == null:
		return
	var valid: Dictionary = _valid_enriched_dict(ars, bc_scr, 91, 6)
	if valid.is_empty():
		assert_true(false, "ARS_DRIFT: 有效 enriched fixture 生成失败")
		return

	var cases: Array = []
	var wall_live_mismatch: Dictionary = valid.duplicate(true)
	var wall: Dictionary = (wall_live_mismatch["wall"] as Dictionary).duplicate(true)
	wall["live"] = int(wall["live"]) + 1
	wall_live_mismatch["wall"] = wall
	cases.append(["wall_live_mismatch", wall_live_mismatch])

	var wall_cursor_invalid: Dictionary = valid.duplicate(true)
	var wall2: Dictionary = (wall_cursor_invalid["wall"] as Dictionary).duplicate(true)
	wall2["draw_index"] = 137
	wall_cursor_invalid["wall"] = wall2
	cases.append(["wall_cursor_invalid", wall_cursor_invalid])

	var momentum_total_mismatch: Dictionary = valid.duplicate(true)
	momentum_total_mismatch["momentum_total"] = 0.987654
	cases.append(["momentum_total_mismatch", momentum_total_mismatch])

	var momentum_key_alias: Dictionary = valid.duplicate(true)
	var scores: Dictionary = (momentum_key_alias["momentum_scores"] as Dictionary).duplicate(true)
	var mystic_score: float = scores["4"]
	scores.erase("4")
	scores["00"] = mystic_score
	momentum_key_alias["momentum_scores"] = scores
	cases.append(["momentum_key_alias", momentum_key_alias])

	var responded_mismatch: Dictionary = valid.duplicate(true)
	var window: Dictionary = (responded_mismatch["window"] as Dictionary).duplicate(true)
	window["responded"] = []
	responded_mismatch["window"] = window
	cases.append(["window_responded_mismatch", responded_mismatch])

	var allowed_kinds_mismatch: Dictionary = valid.duplicate(true)
	var window2: Dictionary = (allowed_kinds_mismatch["window"] as Dictionary).duplicate(true)
	var contexts: Array = (window2["contexts"] as Array).duplicate(true)
	assert_gt(contexts.size(), 0, "ARS_DRIFT: enriched fixture 须有 context")
	if contexts.is_empty():
		return
	var context0: Dictionary = (contexts[0] as Dictionary).duplicate(true)
	context0["allowed_kinds"] = ["TSUMO"]
	contexts[0] = context0
	window2["contexts"] = contexts
	allowed_kinds_mismatch["window"] = window2
	cases.append(["context_allowed_kinds_mismatch", allowed_kinds_mismatch])

	var missing_hook: Dictionary = valid.duplicate(true)
	var skills: Array = (missing_hook["skills"] as Array).duplicate(true)
	assert_gt(skills.size(), 0, "ARS_DRIFT: enriched fixture 须有 skill")
	if skills.is_empty():
		return
	var skill0: Dictionary = (skills[0] as Dictionary).duplicate(true)
	skill0["hook_path"] = "res://tests/_fixtures/not_existing_snapshot_hook.gd"
	skills[0] = skill0
	missing_hook["skills"] = skills
	cases.append(["missing_hook_path", missing_hook])

	for i in range(cases.size()):
		var row: Array = cases[i]
		var case_name: String = str(row[0])
		var corrupted: Object = _ars_from_data(ars, row[1] as Dictionary)
		var target := _make_bc(bc_scr, 400 + i, i % 8)
		_assert_strict_atomic_reject(ars, target, corrupted, case_name)


## #253：墙顶 reveal 后真实摸入 hand 时，revealed 可与 hand 共享 iid；capture/can_restore/restore 成功且 hash 稳定。
## 真正活动区重复（hand/river 同 iid）仍 fail-closed。
func test_ars_allows_revealed_overlap_with_drawn_hand_tile() -> void:
	var ars := _ars_ready()
	var bc_scr := _bc_ready()
	if ars == null or bc_scr == null:
		return
	var bc := _make_bc(bc_scr, 2531, 0)
	if bc == null:
		return
	var st: BattleState = bc.get("state") as BattleState
	assert_not_null(st)
	assert_gt(st.wall.live_wall_size(), 0)
	var top: Tile = st.wall.authority_tiles()[st.wall.draw_index()]
	assert_not_null(top)
	var top_iid: int = int(top.instance_id)
	# 墙顶 peek 式 reveal（投影），随后真实 draw 进 hand
	st.revealed_tiles = [{
		"tile": TileSkillAnchor.make(top, 0, null),
		"visible_to": [0, 1, 2, 3],
	}]
	var drawn: Tile = st.wall.draw()
	assert_not_null(drawn)
	assert_eq(int(drawn.instance_id), top_iid)
	var seat_i: int = int(st.current_seat)
	assert_true(st.seats[seat_i].hand.add(drawn))
	var snap1: Variant = _capture(ars, bc)
	assert_not_null(snap1, "revealed∩hand capture 须成功")
	assert_true(bool(snap1.call("can_restore")), "revealed∩hand 须 can_restore")
	var h1: String = _sha(snap1)
	assert_true(_hex64(h1))
	var target := _make_bc(bc_scr, 2532, 1)
	assert_true(bool(snap1.call("restore_into", target)), "revealed∩hand restore_into 须成功")
	var target_state: BattleState = target.get("state") as BattleState
	var restored_reveal: TileSkillAnchor = target_state.revealed_tiles[0]["tile"] as TileSkillAnchor
	assert_same(restored_reveal.tile,
		target_state.seats[seat_i].hand.find_by_instance_id(top_iid),
		"reveal 必须锚定恢复后的同一物理 Tile")
	var snap2: Variant = _capture(ars, target)
	assert_not_null(snap2)
	assert_eq(_sha(snap2), h1, "restore 后 hash 须稳定")
	# 负例：同一 tile 同时出现在 hand 与 river → fail-closed
	var data: Dictionary = (snap1.call("to_dict") as Dictionary).duplicate(true)
	var seats: Array = (data.get("seats", []) as Array).duplicate(true)
	assert_gt(seats.size(), 0)
	var s0: Dictionary = (seats[seat_i] as Dictionary).duplicate(true)
	var hand: Array = (s0.get("hand", []) as Array)
	assert_gt(hand.size(), 0, "须有 hand 牌以构造 river 重复")
	var river: Array = (s0.get("river", []) as Array).duplicate(true)
	river.append((hand[hand.size() - 1] as Dictionary).duplicate(true))
	s0["river"] = river
	seats[seat_i] = s0
	data["seats"] = seats
	var corrupted: Object = _ars_from_data(ars, data)
	assert_not_null(corrupted)
	assert_false(bool(corrupted.call("can_restore")), "hand∩river 真重复须 fail-closed")
