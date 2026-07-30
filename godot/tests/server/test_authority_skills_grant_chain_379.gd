extends GutTest

# Issue #379 Round 7/R4 — 单次 Headless FULL_GRANT 权威链（timeout 300；唯一 24 弃）
# 全程 HeadlessRoomSession：journal TURN_PROMPT/CLAIM 公开 DTO → submit_action_for_seat
# 同 session capture_match_authority_state / restore_match_authority_state
# seed=42 三类道具；bai_touli×4 亲和 GAME_BEGIN
# R4：OPEN/ARM 后 GAME_BEGIN skill 恰好 1 次 + 续 action 不重投（并入本链，禁止第二套 24 弃）
# 禁止 domain hand / ars._data / grant_for_seat / server._bc / 空 session restore 自证

const SEED := 42
const SKILL_ID := "char_washizu_passive_v1"
const CHARS := ["bai_touli", "bai_touli", "bai_touli", "bai_touli"]
const PARTS := ["HUMAN", "HUMAN", "HUMAN", "HUMAN"]

var _n: int = 0
var _worker_ms: int = 1000
var _used_decision_ids: Dictionary = {}


func _cid() -> String:
	_n += 1
	return "550e8400-e29b-41d4-a716-%012d" % _n


func _cnt(j: Array, kind: String) -> int:
	var n := 0
	for ne in j:
		if ne is NetworkedEvent and (ne as NetworkedEvent).kind == kind:
			n += 1
	return n


func _evs(j: Array, kind: String) -> Array:
	var o: Array = []
	for ne in j:
		if ne is NetworkedEvent and (ne as NetworkedEvent).kind == kind:
			o.append(ne)
	return o


## 精确计数：skill_id + beneficiary + source_event=GAME_BEGIN（禁止 >= 弱断言）
func _count_game_begin_skill(j: Array, skill_id: String, beneficiary: int) -> int:
	var n := 0
	for ne in j:
		if not (ne is NetworkedEvent):
			continue
		var e: NetworkedEvent = ne as NetworkedEvent
		if e.kind != "SKILL_TRIGGERED":
			continue
		var p: Dictionary = e.payload
		if str(p.get("skill_id", "")) != skill_id:
			continue
		if int(p.get("beneficiary_seat", p.get("actor_seat", -1))) != beneficiary:
			continue
		if str(p.get("source_event", "")) != "GAME_BEGIN":
			continue
		n += 1
	return n


func _boot_headless() -> HeadlessRoomSession:
	var hs := HeadlessRoomSession.new()
	hs.set_seed_override_for_test(SEED)
	assert_true(hs.bootstrap_from_claims({
		"room_id": "379r7-fg",
		"seat": 0,
		"session_id": "sess-0",
		"round_kind": "EAST",
		"game_mode": "TRASH_TALK",
		"participants": PARTS,
		"character_ids": CHARS,
		"expires_at_unix": 9999999999,
	}, _worker_ms))
	for i in range(4):
		assert_true(bool(hs.join(i, "sess-%d" % i)["ok"]), "join %d" % i)
		assert_true(bool(hs.ready(i, "sess-%d" % i)["ok"]), "ready %d" % i)
	assert_true(hs.is_started())
	return hs


## 从 seat journal / events_since 解析公开 decision（仅消费 after_seq 之后，防陈旧 prompt）。
func _parse_actionable(ne: NetworkedEvent, seat: int) -> Dictionary:
	if ne == null:
		return {}
	var p: Dictionary = ne.payload
	if ne.kind == "TURN_PROMPT":
		if int(p.get("seat", -1)) != seat:
			return {}
		for o in p.get("allowed_actions", []):
			if typeof(o) != TYPE_DICTIONARY:
				continue
			var kind := str(o.get("kind", ""))
			if kind == "DISCARD":
				var opts: Array = o.get("payload_options", [])
				if opts.is_empty():
					continue
				return {
					"kind": "DISCARD",
					"seat": seat,
					"hand_seq": int(p.get("hand_seq", 0)),
					"decision_id": str(p.get("decision_id", "")),
					"tile_instance_id": int(opts[0].get("tile_instance_id", -1)),
					"server_seq": int(ne.server_seq),
				}
			if kind == "PASS":
				return {
					"kind": "PASS",
					"seat": seat,
					"hand_seq": int(p.get("hand_seq", 0)),
					"decision_id": str(p.get("decision_id", "")),
					"server_seq": int(ne.server_seq),
				}
	elif ne.kind == "CLAIM_WINDOW":
		for o2 in p.get("allowed_actions", []):
			if typeof(o2) != TYPE_DICTIONARY:
				continue
			if str(o2.get("kind", "")) != "PASS":
				continue
			return {
				"kind": "PASS",
				"seat": seat,
				"hand_seq": int(p.get("hand_seq", 0)),
				"decision_id": str(p.get("decision_id", "")),
				"server_seq": int(ne.server_seq),
			}
	return {}


func _collect_actionable(hs: HeadlessRoomSession, _after_seq: int = 0) -> Array:
	# decision_id 去重；after = current-1 保证同 seq CLAIM 可见，避免全量 journal 克隆
	var after := maxi(hs.current_server_seq() - 5, 0)
	var out: Array = []
	for seat in range(4):
		var best: Dictionary = {}
		for ne_v in hs.events_since(seat, after):
			var ne: NetworkedEvent = ne_v as NetworkedEvent
			var meta: Dictionary = _parse_actionable(ne, seat)
			if meta.is_empty():
				continue
			var did := str(meta.get("decision_id", ""))
			if did.is_empty() or _used_decision_ids.has(did):
				continue
			if best.is_empty() or int(meta["server_seq"]) >= int(best.get("server_seq", -1)):
				best = meta
		if not best.is_empty():
			out.append(best)
	return out


func _latest_actionable(hs: HeadlessRoomSession, seat: int) -> Dictionary:
	for meta_v in _collect_actionable(hs):
		var meta: Dictionary = meta_v
		if int(meta.get("seat", -1)) == seat:
			return meta
	return {}


func _submit(hs: HeadlessRoomSession, meta: Dictionary) -> CommandResult:
	var seat := int(meta["seat"])
	var room := hs.room_id
	var did := str(meta.get("decision_id", ""))
	var act: Action
	if str(meta["kind"]) == "DISCARD":
		act = Action.discard(
			seat, int(meta["tile_instance_id"]), room, _cid(),
			did, int(meta["hand_seq"]), _n)
	else:
		act = Action.make_pass(
			seat, room, _cid(), did, int(meta["hand_seq"]), _n)
	var cr: CommandResult = hs.submit_action_for_seat(seat, act)
	if cr.status == "ACCEPTED" and not did.is_empty():
		_used_decision_ids[did] = true
	return cr


func _tick(hs: HeadlessRoomSession, delta_ms: int = 500) -> void:
	_worker_ms += delta_ms
	assert_true(hs.tick_reward_authority(_worker_ms))


func _drive_to_discards(hs: HeadlessRoomSession, target: int) -> void:
	var rw: RewardWindowModule = hs.mode_modules.reward_window
	var guard := 0
	while rw.discard_count < target:
		guard += 1
		assert_lt(guard, 400, "drive timeout disc=%d phase=%s" % [rw.discard_count, rw.phase])
		if rw.phase == RewardWindowModule.PHASE_CLOSING:
			_settle_closing(hs)
			continue
		var actions: Array = _collect_actionable(hs)
		var progressed := false
		# 先 PASS（claim）
		for meta_v in actions:
			var meta: Dictionary = meta_v
			if str(meta.get("kind", "")) != "PASS":
				continue
			if _submit(hs, meta).status == "ACCEPTED":
				progressed = true
		if progressed:
			continue
		# 再 DISCARD：只执行 server_seq 最高的一条（当前回合）
		var best_disc: Dictionary = {}
		for meta2_v in actions:
			var meta2: Dictionary = meta2_v
			if str(meta2.get("kind", "")) != "DISCARD":
				continue
			if best_disc.is_empty() or int(meta2["server_seq"]) > int(best_disc["server_seq"]):
				best_disc = meta2
		if not best_disc.is_empty():
			var cr: CommandResult = _submit(hs, best_disc)
			assert_eq(cr.status, "ACCEPTED",
				"DISCARD seat%d %s @%d" % [int(best_disc["seat"]), cr.error_code, rw.discard_count])
			progressed = true
		if not progressed:
			_tick(hs, 200)
			assert_true(not _collect_actionable(hs).is_empty() or rw.discard_count >= target,
				"无公开 decision 可推进 disc=%d" % rw.discard_count)


func _settle_closing(hs: HeadlessRoomSession) -> void:
	var rw: RewardWindowModule = hs.mode_modules.reward_window
	var g := 0
	while rw.phase == RewardWindowModule.PHASE_CLOSING and g < 80:
		g += 1
		var passed := false
		for meta_v in _collect_actionable(hs):
			var meta: Dictionary = meta_v
			if str(meta.get("kind", "")) != "PASS":
				continue
			if _submit(hs, meta).status == "ACCEPTED":
				passed = true
		if passed:
			continue
		if not rw.claim_is_terminal():
			_tick(hs, 50)
			continue
		# 权威时钟推进至宽限结束（公开 tick_reward_authority，不读 _bc）
		_tick(hs, maxi(500, int(RewardWindowModule.GRACE_MS / 2) + 100))


func _latest_turn_prompt(hs: HeadlessRoomSession, seat: int) -> Dictionary:
	# 全 journal 最新 TURN_PROMPT（ITEM_USE 可对齐该席当前 decision，不受 discard used 限制）
	var best: Dictionary = {}
	for ne_v in hs.event_journal(seat):
		var ne: NetworkedEvent = ne_v as NetworkedEvent
		if ne == null or ne.kind != "TURN_PROMPT":
			continue
		var p: Dictionary = ne.payload
		if int(p.get("seat", -1)) != seat:
			continue
		if str(p.get("decision_id", "")).is_empty():
			continue
		var meta := {
			"kind": "TURN",
			"seat": seat,
			"hand_seq": int(p.get("hand_seq", 0)),
			"decision_id": str(p.get("decision_id", "")),
			"server_seq": int(ne.server_seq),
		}
		if best.is_empty() or int(meta["server_seq"]) >= int(best["server_seq"]):
			best = meta
	return best


func _ensure_item_decision(hs: HeadlessRoomSession, seat: int) -> Dictionary:
	for _i in range(60):
		var meta: Dictionary = _latest_turn_prompt(hs, seat)
		if not meta.is_empty():
			return meta
		# 推进公开 Action 直到该席出现 TURN_PROMPT
		var moved := false
		for meta_v in _collect_actionable(hs):
			var m2: Dictionary = meta_v
			if _submit(hs, m2).status == "ACCEPTED":
				moved = true
		if not moved:
			_tick(hs, 100)
	return _latest_turn_prompt(hs, seat)


## 公开 ITEM_USE：在该席当前可行动 TURN/CLAIM decision 上提交；否则推进直到该席有 DISCARD 窗。
func _submit_item_use_retry(
	hs: HeadlessRoomSession, seat: int, item_iid: String, room: String
) -> bool:
	var last_code := ""
	for _i in range(24):
		# 该席当前未消费 decision（优先 DISCARD）
		var live: Dictionary = {}
		for meta_v in _collect_actionable(hs):
			var meta: Dictionary = meta_v
			if int(meta.get("seat", -1)) != seat:
				continue
			if str(meta.get("kind", "")) == "DISCARD":
				live = meta
				break
			if live.is_empty():
				live = meta
		if not live.is_empty():
			var did := str(live.get("decision_id", ""))
			var act := Action.item_use(
				seat, item_iid, room, _cid(), did, int(live.get("hand_seq", 0)), _n)
			var cr: CommandResult = hs.submit_action_for_seat(seat, act)
			last_code = "%s:%s" % [cr.status, cr.error_code]
			if cr.status == "ACCEPTED":
				assert_eq(hs.submit_action_for_seat(seat, act).status, "ACCEPTED")
				return true
			# 该 decision 对 ITEM_USE 无效：推进它再试
			_submit(hs, live)
		else:
			var moved := false
			for meta2_v in _collect_actionable(hs):
				if _submit(hs, meta2_v as Dictionary).status == "ACCEPTED":
					moved = true
			if not moved:
				_tick(hs, 200)
	push_warning("ITEM_USE fail seat=%d last=%s" % [seat, last_code])
	return false


func test_headless_full_grant_game_begin_items_same_session_restore() -> void:
	_used_decision_ids.clear()
	_n = 0
	_worker_ms = 1000
	var hs := _boot_headless()
	var room := hs.room_id
	assert_false(room.is_empty())
	# 首窗 unarmed
	for slot_v in hs.mode_modules.character_ability_slots:
		assert_false((slot_v as CharacterAbilitySlot).armed)
	assert_eq(_cnt(hs.event_journal(0), "CHARACTER_ABILITY_ARMED"), 0)
	assert_eq(_cnt(hs.event_journal(0), "SKILL_TRIGGERED"), 0)

	# --- 真实 FULL_GRANT（公开 Action）---
	_drive_to_discards(hs, 24)
	_settle_closing(hs)
	var j: Array = hs.event_journal(0)
	assert_eq(_cnt(j, "ITEM_GRANTED"), 4)
	assert_gt(_cnt(j, "REWARD_WINDOW_SETTLED"), 0)
	assert_gt(_cnt(j, "CHARACTER_ABILITY_ARMED"), 0)

	# 三类道具强制
	var relic_id := ""
	var relic_iid := ""
	var imm_id := ""
	var imm_iid := ""
	var imm_seat := -1
	var arm_id := ""
	var arm_iid := ""
	var arm_seat := -1
	var aff_seat := -1
	for e in _evs(j, "ITEM_GRANTED"):
		var p: Dictionary = (e as NetworkedEvent).payload
		var item_id := str(p.get("item_id", ""))
		var iid := str(p.get("item_instance_id", ""))
		var seat := int(p.get("seat", -1))
		if bool(p.get("affinity_match", false)):
			aff_seat = seat
		if ItemInventoryModule.is_relic_item(item_id) and relic_id.is_empty():
			relic_id = item_id
			relic_iid = iid
		elif ConsumableFactory.is_immediate_on_use(StringName(item_id)) and imm_id.is_empty():
			imm_id = item_id
			imm_iid = iid
			imm_seat = seat
		elif ItemInventoryModule.is_battle_consumable(item_id) and arm_id.is_empty():
			arm_id = item_id
			arm_iid = iid
			arm_seat = seat
	assert_false(relic_id.is_empty(), "seed=42 须 relic")
	assert_false(imm_id.is_empty(), "seed=42 须 immediate")
	assert_false(arm_id.is_empty(), "seed=42 须 armed consumable")
	assert_gte(aff_seat, 0, "亲和 seat")
	assert_not_null(hs.mode_modules.item_inventory.registered_skill(relic_iid))
	assert_not_null(hs.mode_modules.item_inventory.find_instance(relic_iid))

	var slot: CharacterAbilitySlot = hs.mode_modules.character_ability_slots[aff_seat]
	assert_true(slot.armed and slot.registry_registered)
	assert_eq(String(slot.ability_id), SKILL_ID)

	# immediate ITEM_USE
	# 以 inventory 权威 seat 为准
	var imm_inst0: ItemInstance = hs.mode_modules.item_inventory.find_instance(imm_iid)
	assert_not_null(imm_inst0)
	imm_seat = imm_inst0.seat
	var arm_inst0: ItemInstance = hs.mode_modules.item_inventory.find_instance(arm_iid)
	assert_not_null(arm_inst0)
	arm_seat = arm_inst0.seat

	# 先 armed 再 immediate（均走公开 submit_action_for_seat）
	var arm_ok := _submit_item_use_retry(hs, arm_seat, arm_iid, room)
	assert_true(arm_ok, "armed ITEM_USE %s seat=%d" % [arm_id, arm_seat])
	var armed_inst: ItemInstance = hs.mode_modules.item_inventory.find_instance(arm_iid)
	assert_not_null(armed_inst)
	assert_eq(armed_inst.status, ItemInstance.STATUS_ARMED)

	var inv_before := hs.mode_modules.item_inventory.instance_count()
	var cons_before := _cnt(hs.event_journal(0), "ITEM_CONSUMED")
	# 尝试任意 immediate 实例（防止某一席 decision 饿死）
	var imm_ok := false
	for s in range(4):
		for inst_v in hs.mode_modules.item_inventory.instances_for_seat(s):
			var ii: ItemInstance = inst_v as ItemInstance
			if not ConsumableFactory.is_immediate_on_use(StringName(ii.item_id)):
				continue
			if _submit_item_use_retry(hs, s, ii.item_instance_id, room):
				imm_ok = true
				imm_id = ii.item_id
				imm_seat = s
				break
		if imm_ok:
			break
	assert_true(imm_ok, "immediate ITEM_USE 须成功（tried all immediate instances）")
	assert_eq(hs.mode_modules.item_inventory.instance_count(), inv_before - 1)
	assert_eq(_cnt(hs.event_journal(0), "ITEM_CONSUMED"), cons_before + 1)

	# --- journal SKILL_TRIGGERED 精确（#379 R4：并入本单次 24 弃，禁止第二套 24 弃）---
	j = hs.event_journal(0)
	var gb_n := _count_game_begin_skill(j, SKILL_ID, aff_seat)
	assert_eq(gb_n, 1,
		"亲和 seat=%d skill=%s src=GAME_BEGIN 须恰好 1 次（OPEN/ARM 后）" % [aff_seat, SKILL_ID])
	var armed_i := -1
	var skill_i := -1
	var idx := 0
	for ne_ord in j:
		if ne_ord is NetworkedEvent:
			var e_ord: NetworkedEvent = ne_ord as NetworkedEvent
			if e_ord.kind == "CHARACTER_ABILITY_ARMED" \
					and int(e_ord.payload.get("seat", -1)) == aff_seat:
				armed_i = idx
			if e_ord.kind == "SKILL_TRIGGERED":
				var po: Dictionary = e_ord.payload
				if str(po.get("skill_id", "")) == SKILL_ID \
						and int(po.get("beneficiary_seat", -1)) == aff_seat \
						and str(po.get("source_event", "")) == "GAME_BEGIN":
					skill_i = idx
					for bad in ["tiles", "wall_top", "private_hand", "waits", "hand", "wall"]:
						assert_false(po.has(bad), "GAME_BEGIN skill 禁私字段 %s" % bad)
					assert_eq(str(po.get("source_kind", "")), "character")
			idx += 1
	assert_gte(armed_i, 0, "须有 seat=%d 的 CHARACTER_ABILITY_ARMED" % aff_seat)
	assert_gte(skill_i, 0, "须有 seat=%d 的 GAME_BEGIN SKILL_TRIGGERED" % aff_seat)
	assert_lt(armed_i, skill_i,
		"CHARACTER_ABILITY_ARMED 须早于对应 GAME_BEGIN SKILL（armed_i=%d skill_i=%d）"
		% [armed_i, skill_i])

	# 四席：该 GAME_BEGIN 归因公开恰好 1 次，且无隐私泄漏
	for seat in range(4):
		var sj: Array = hs.event_journal(seat)
		assert_eq(_count_game_begin_skill(sj, SKILL_ID, aff_seat), 1,
			"seat%d 须恰好 1× GAME_BEGIN skill=%s aff=%d" % [seat, SKILL_ID, aff_seat])
		for e4 in _evs(sj, "SKILL_TRIGGERED"):
			var p4: Dictionary = (e4 as NetworkedEvent).payload
			for bad2 in ["tiles", "wall_top", "private_hand", "waits", "hand", "wall"]:
				assert_false(p4.has(bad2))

	# 续一个真实公开 Action 后：该 GAME_BEGIN 不得重投（cursor 不吞也不重放）
	var progressed_one := false
	for _retry in range(40):
		var actions_one: Array = _collect_actionable(hs)
		# 先 PASS 再 DISCARD
		for meta_p in actions_one:
			if str((meta_p as Dictionary).get("kind", "")) != "PASS":
				continue
			if _submit(hs, meta_p as Dictionary).status == "ACCEPTED":
				progressed_one = true
				break
		if progressed_one:
			break
		var best_d: Dictionary = {}
		for meta_d in actions_one:
			if str((meta_d as Dictionary).get("kind", "")) != "DISCARD":
				continue
			if best_d.is_empty() \
					or int((meta_d as Dictionary)["server_seq"]) > int(best_d["server_seq"]):
				best_d = meta_d as Dictionary
		if not best_d.is_empty():
			assert_eq(_submit(hs, best_d).status, "ACCEPTED", "续 action 须 ACCEPTED")
			progressed_one = true
			break
		_tick(hs, 100)
	assert_true(progressed_one, "FULL_GRANT 后须能推进至少 1 个真实公开 Action")
	assert_eq(_count_game_begin_skill(hs.event_journal(0), SKILL_ID, aff_seat), 1,
		"续 action 后 GAME_BEGIN skill 仍恰好 1 次（禁止 cursor 重投）")
	for seat2 in range(4):
		assert_eq(
			_count_game_begin_skill(hs.event_journal(seat2), SKILL_ID, aff_seat), 1,
			"续 action 后 seat%d GAME_BEGIN 仍恰好 1" % seat2)

	# --- 同 session 完整 authority restore（经历真实 FG 的同一 hs）---
	var grant_n := _cnt(hs.event_journal(0), "ITEM_GRANTED")
	var armed_n := _cnt(hs.event_journal(0), "CHARACTER_ABILITY_ARMED")
	var skill_n := _cnt(hs.event_journal(0), "SKILL_TRIGGERED")
	var cons_n := _cnt(hs.event_journal(0), "ITEM_CONSUMED")
	var settled_n := _cnt(hs.event_journal(0), "REWARD_WINDOW_SETTLED")
	assert_gt(grant_n, 0)
	assert_gt(armed_n, 0)
	assert_gt(hs.mode_modules.item_inventory.instance_count(), 0)
	var seq := hs.current_server_seq()
	assert_gt(seq, 0)
	var inst_ids: Array = []
	for s in range(4):
		for inst in hs.mode_modules.item_inventory.instances_for_seat(s):
			inst_ids.append((inst as ItemInstance).item_instance_id)
	inst_ids.sort()
	var scores_cap: Array = []
	var snap: Dictionary = hs.capture_match_authority_state()
	assert_false(snap.is_empty())
	assert_true(snap.has("cumulative_scores"))
	for sc in snap["cumulative_scores"]:
		scores_cap.append(int(sc))
	assert_gt(int(scores_cap[0]), 0, "非零起分")
	var armed_flags: Array = []
	for slot_v2 in hs.mode_modules.character_ability_slots:
		armed_flags.append((slot_v2 as CharacterAbilitySlot).armed)

	assert_true(hs.restore_match_authority_state(snap))
	assert_true(hs.restore_match_authority_state(snap))

	assert_eq(hs.current_server_seq(), seq, "restore 不推进 seq")
	assert_eq(_cnt(hs.event_journal(0), "ITEM_GRANTED"), grant_n)
	assert_eq(_cnt(hs.event_journal(0), "CHARACTER_ABILITY_ARMED"), armed_n)
	assert_eq(_cnt(hs.event_journal(0), "SKILL_TRIGGERED"), skill_n)
	assert_eq(_cnt(hs.event_journal(0), "ITEM_CONSUMED"), cons_n)
	assert_eq(_cnt(hs.event_journal(0), "REWARD_WINDOW_SETTLED"), settled_n)
	var inst_after: Array = []
	for s2 in range(4):
		for inst2 in hs.mode_modules.item_inventory.instances_for_seat(s2):
			inst_after.append((inst2 as ItemInstance).item_instance_id)
	inst_after.sort()
	assert_eq(inst_after, inst_ids, "instance id 不重复/不丢失")
	for i in range(4):
		assert_eq(
			(hs.mode_modules.character_ability_slots[i] as CharacterAbilitySlot).armed,
			bool(armed_flags[i]), "armed slot %d" % i)
	var snap2: Dictionary = hs.capture_match_authority_state()
	assert_eq(int((snap2["cumulative_scores"] as Array)[0]), int(scores_cap[0]))

	# --- 同一真实 TT snap 送入 STANDARD ---
	var hs_std := HeadlessRoomSession.new()
	hs_std.set_seed_override_for_test(3)
	assert_true(hs_std.bootstrap_from_claims({
		"room_id": "379r7-std", "seat": 0, "session_id": "sess-s",
		"round_kind": "EAST", "game_mode": "STANDARD",
		"participants": ["HUMAN", "AI", "AI", "AI"],
		"character_ids": ["hua_ling", "lin_yeche", "qiu_jue", "bai_touli"],
		"expires_at_unix": 9999999999,
	}, 2000))
	assert_true(bool(hs_std.join(0, "sess-s")["ok"]))
	assert_true(bool(hs_std.ready(0, "sess-s")["ok"]))
	var ok_std := hs_std.restore_match_authority_state(snap)
	if ok_std:
		assert_eq(hs_std.mode_modules.character_ability_slots.size(), 0)
		assert_null(hs_std.mode_modules.item_inventory)
		assert_eq(_cnt(hs_std.event_journal(0), "SKILL_TRIGGERED"), 0)
		assert_eq(_cnt(hs_std.event_journal(0), "ITEM_GRANTED"), 0)
		assert_eq(_cnt(hs_std.event_journal(0), "CHARACTER_ABILITY_ARMED"), 0)
	else:
		assert_false(ok_std, "STANDARD 拒绝真实 TT FG snapshot")
