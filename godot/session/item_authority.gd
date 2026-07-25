class_name ItemAuthority extends RefCounted

# E5-05 / #253：权威道具发放 / 使用 / 武装 纯逻辑。
# LocalLoopback 与未来 Worker 共用；不推进 RewardWindow phase。

const GAME_BEGIN_ABILITIES := {
	&"char_washizu_passive_v1": true,
	&"char_awai_passive_v1": true,
	&"char_toki_passive_v1": true,
}


## FULL_GRANT：seat 0→3 授予；成功返回 {ok, grants:[{payload}], effects 侧需注册 relic}。
## matrix 为 try_settle 返回的完整矩阵（可空 → score=0）。
static func grant_full_from_settled(
	inv: ItemInventoryModule,
	settled_payload: Dictionary,
	matrix: Array,
	character_ids: Array,
	next_window_id: String,
	hand_ends_match_continues: bool = false,
	match_namespace: String = ""
) -> Dictionary:
	if inv == null:
		return {"ok": false, "reason": "NO_INVENTORY"}
	if String(settled_payload.get("outcome", "")) != "FULL_GRANT":
		return {"ok": false, "reason": "NOT_FULL_GRANT"}
	if int(settled_payload.get("grant_count", 0)) != 4:
		return {"ok": false, "reason": "BAD_GRANT_COUNT"}
	var assignment: Dictionary = settled_payload.get("assignment", {})
	if typeof(assignment) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "NO_ASSIGNMENT"}
	var window_id := String(settled_payload.get("window_id", ""))
	var hand_seq: int = int(settled_payload.get("hand_seq", 0))
	var rule_version := String(settled_payload.get("rule_version", ""))
	var assignment_version := String(settled_payload.get("assignment_version", ""))

	# 解析当前 window_index
	var window_index := 0
	var parts: PackedStringArray = window_id.split("_")
	# hand_X_window_Y
	if parts.size() >= 4:
		window_index = int(parts[3])

	var next_wid := next_window_id
	if next_wid.is_empty():
		if hand_ends_match_continues:
			next_wid = ItemInventoryModule.next_window_id_next_hand(hand_seq)
		else:
			next_wid = ItemInventoryModule.next_window_id_same_hand(hand_seq, window_index)

	var grants: Array = []
	var snap: Dictionary = inv.capture_state()
	for seat in range(4):
		var item_id := String(assignment.get(str(seat), "")).strip_edges()
		if item_id.is_empty():
			inv.restore_state(snap)
			return {"ok": false, "reason": "MISSING_ASSIGNMENT_SEAT"}
		if not ItemInventoryModule.is_grantable(item_id):
			inv.restore_state(snap)
			return {"ok": false, "reason": "NOT_GRANTABLE"}
		var cid: StringName = &""
		if seat < character_ids.size():
			cid = StringName(String(character_ids[seat]))
		var affinity: bool = ItemInventoryModule.compute_affinity_match(cid, item_id)
		var cell: Dictionary = ItemInventoryModule.score_and_rules_from_matrix(
			matrix, seat, item_id
		)
		var next_for_grant = null
		if affinity:
			next_for_grant = next_wid
		var ns_for_grant: String = String(inv.match_namespace)
		if not match_namespace.is_empty():
			ns_for_grant = match_namespace
		var g: Dictionary = inv.grant_for_seat({
			"seat": seat,
			"item_id": item_id,
			"window_id": window_id,
			"hand_seq": hand_seq,
			"score": int(cell.get("score", 0)),
			"rule_version": rule_version,
			"assignment_version": assignment_version,
			"matched_rule_ids": cell.get("matched_rule_ids", []),
			"affinity_match": affinity,
			"next_window_id": next_for_grant,
			"match_namespace": ns_for_grant,
		})
		if not bool(g.get("ok", false)):
			inv.restore_state(snap)
			return {"ok": false, "reason": String(g.get("reason", "GRANT_FAIL"))}
		grants.append(g)
	return {"ok": true, "grants": grants, "next_window_id": next_wid}


## 获赠后：常驻 relic 注册到 SkillRegistry（逐实例）。
static func register_relic_for_grant(
	bc: BattleController, inv: ItemInventoryModule, grant_payload: Dictionary
) -> bool:
	if bc == null or inv == null:
		return false
	var item_id := String(grant_payload.get("item_id", ""))
	var iid := String(grant_payload.get("item_instance_id", ""))
	var seat: int = int(grant_payload.get("seat", -1))
	if not ItemInventoryModule.is_relic_item(item_id):
		return true
	var sk: SkillResource = RelicFactory.build_for_instance(StringName(item_id), iid)
	if sk == null:
		return false
	bc.registry.register(sk, seat)
	inv.remember_registered_skill(iid, sk, seat)
	return true


## #253 Round 7：新一局权威启动时，以库存实例为源把跨局 held relic / armed 延迟件
## 重建到新 BC.registry。fail-closed：失败时回滚本函数造成的全部 registry 写入。
## active 窗口武装不跨已结束窗；pending 保留供 OPEN→ARM。
static func prepare_new_hand(
	bc: BattleController, inv: ItemInventoryModule, slots: Array
) -> Dictionary:
	if bc == null or inv == null:
		return {"ok": true}
	var inv_snap: Dictionary = inv.capture_state()
	var reg_snap: Dictionary = inv.duplicate_registered_skills()
	var slots_snap: Array = []
	for slot_v0 in slots:
		if slot_v0 is CharacterAbilitySlot:
			var s0: CharacterAbilitySlot = slot_v0 as CharacterAbilitySlot
			slots_snap.append({
				"armed": s0.armed,
				"active_window_id": s0.active_window_id,
				"registry_registered": s0.registry_registered,
			})
		else:
			slots_snap.append({})
	var registered: Array = []  # {skill, seat}
	# 1) 清角色 slot active；unregister 旧 BC 上可能无效的 skill 引用
	for seat in range(4):
		if seat >= slots.size() or not (slots[seat] is CharacterAbilitySlot):
			continue
		var slot: CharacterAbilitySlot = slots[seat] as CharacterAbilitySlot
		if slot.registry_registered and slot.skill != null and bc.registry != null:
			bc.registry.unregister(slot.skill, seat)
		slot.registry_registered = false
		slot.clear_active_keep_pending()
	# 2) 清库存 active（保留 pending 与实例）
	for seat2 in range(4):
		inv.disarm_active(seat2)
	# 3) 清空旧 registry 索引，按实例重建
	inv.clear_registered_skills_index()
	for inst_v in inv.all_instances():
		if not (inst_v is ItemInstance):
			continue
		var inst: ItemInstance = inst_v as ItemInstance
		if inst.status == ItemInstance.STATUS_CONSUMED:
			continue
		var item_id := inst.item_id
		var iid := inst.item_instance_id
		var seat3: int = inst.seat
		if ItemInventoryModule.is_relic_item(item_id):
			if inst.status != ItemInstance.STATUS_HELD:
				_fail_prepare(bc, registered, slots, slots_snap, inv, inv_snap, reg_snap)
				return {"ok": false, "reason": "RELIC_BAD_STATUS"}
			var rsk: SkillResource = RelicFactory.build_for_instance(StringName(item_id), iid)
			if rsk == null:
				_fail_prepare(bc, registered, slots, slots_snap, inv, inv_snap, reg_snap)
				return {"ok": false, "reason": "RELIC_BUILD_FAIL"}
			bc.registry.register(rsk, seat3)
			registered.append({"skill": rsk, "seat": seat3})
			inv.remember_registered_skill(iid, rsk, seat3)
		elif inst.status == ItemInstance.STATUS_ARMED:
			# armed 必须可重建到 registry；未知/失败 fail-closed 全回滚
			if not ItemInventoryModule.is_battle_consumable(item_id):
				_fail_prepare(bc, registered, slots, slots_snap, inv, inv_snap, reg_snap)
				return {"ok": false, "reason": "ARMED_UNKNOWN_ITEM"}
			var csk: SkillResource = ConsumableFactory.build_for_instance(
				StringName(item_id), iid
			)
			if csk == null:
				_fail_prepare(bc, registered, slots, slots_snap, inv, inv_snap, reg_snap)
				return {"ok": false, "reason": "ARMED_BUILD_FAIL"}
			bc.registry.register(csk, seat3)
			registered.append({"skill": csk, "seat": seat3})
			inv.remember_registered_skill(iid, csk, seat3)
		# held 延迟件未 USE：不注册
	return {"ok": true}


static func _fail_prepare(
	bc: BattleController,
	registered: Array,
	slots: Array,
	slots_snap: Array,
	inv: ItemInventoryModule,
	inv_snap: Dictionary,
	reg_snap: Dictionary
) -> void:
	_rollback_prep_regs(bc, registered)
	_restore_slots_snap(slots, slots_snap)
	if inv != null:
		inv.restore_state(inv_snap)
		inv.restore_registered_skills(reg_snap)


static func _restore_slots_snap(slots: Array, slots_snap: Array) -> void:
	for i in range(mini(slots.size(), slots_snap.size())):
		if not (slots[i] is CharacterAbilitySlot):
			continue
		if typeof(slots_snap[i]) != TYPE_DICTIONARY:
			continue
		var slot: CharacterAbilitySlot = slots[i] as CharacterAbilitySlot
		var d: Dictionary = slots_snap[i]
		slot.armed = bool(d.get("armed", false))
		slot.active_window_id = d.get("active_window_id", null)
		slot.registry_registered = bool(d.get("registry_registered", false))


static func _rollback_prep_regs(bc: BattleController, registered: Array) -> void:
	if bc == null or bc.registry == null:
		return
	for e in registered:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var sk: SkillResource = e.get("skill", null) as SkillResource
		var seat: int = int(e.get("seat", -1))
		if sk != null:
			bc.registry.unregister(sk, seat)


## ITEM_USE：校验所有权/可用性。
## 即时效果：真实结算后 ITEM_APPLIED + ITEM_CONSUMED。
## 延迟效果：仅武装（status=armed + registry），零 APPLIED/CONSUMED；触发后由 finalize_triggered 发事件。
static func use_item(
	bc: BattleController,
	inv: ItemInventoryModule,
	seat: int,
	item_instance_id: String,
	command_id: String
) -> Dictionary:
	if inv == null:
		return _reject("NOT_ENABLED")
	if bc == null or bc.state == null:
		return _reject("INVALID_ACTION")
	if seat < 0 or seat > 3:
		return _reject("WRONG_SEAT")
	if not ProtocolUuid.is_canonical_v4(command_id):
		return _reject("INVALID_ACTION")
	var inst: ItemInstance = inv.find_instance(item_instance_id)
	if inst == null:
		return _reject("ENTITY_NOT_FOUND")
	if inst.seat != seat:
		return _reject("WRONG_SEAT")
	if inst.status != ItemInstance.STATUS_HELD:
		return _reject("RULE_REJECTED")
	var item_id := inst.item_id
	if ItemInventoryModule.is_relic_item(item_id):
		return _reject("RULE_REJECTED")
	if not ItemInventoryModule.is_battle_consumable(item_id):
		return _reject("RULE_REJECTED")

	var events: Array = []
	var cid := StringName(item_id)

	# P1-5：seat_swap / tsubame 无稳定权威语义，拒绝发明效果
	if cid == &"seat_swap_v1" or cid == &"tsubame_v1":
		return _reject("RULE_REJECTED")

	if ConsumableFactory.is_immediate_on_use(cid):
		if not _apply_immediate_consumable(bc, seat, cid):
			return _reject("RULE_REJECTED")
		var cons: Dictionary = inv.consume_instance(item_instance_id, seat)
		if not bool(cons.get("ok", false)):
			return _reject("RULE_REJECTED")
		# 即时：同时 unregister 若曾登记
		var sk0: SkillResource = inv.registered_skill(item_instance_id)
		if sk0 != null and bc.registry != null:
			bc.registry.unregister(sk0, seat)
		inv.forget_registered_skill(item_instance_id)
		events.append({
			"kind": "ITEM_APPLIED",
			"payload": {
				"seat": seat,
				"item_id": item_id,
				"item_instance_id": item_instance_id,
				"effect_id": item_id,
				"command_id": command_id,
			},
		})
		events.append({
			"kind": "ITEM_CONSUMED",
			"payload": {
				"seat": seat,
				"item_id": item_id,
				"item_instance_id": item_instance_id,
				"command_id": command_id,
			},
		})
		return {"ok": true, "accepted": true, "events": events}

	# 延迟：武装，保留实例与 registry 索引，不发 APPLIED/CONSUMED
	var sk: SkillResource = ConsumableFactory.build_for_instance(cid, item_instance_id)
	if sk == null:
		return _reject("RULE_REJECTED")
	bc.registry.register(sk, seat)
	inv.remember_registered_skill(item_instance_id, sk, seat)
	var arm: Dictionary = inv.mark_armed(item_instance_id, seat, command_id)
	if not bool(arm.get("ok", false)):
		bc.registry.unregister(sk, seat)
		inv.forget_registered_skill(item_instance_id)
		return _reject("RULE_REJECTED")
	return {"ok": true, "accepted": true, "events": []}


## 扫描 delayed skill.consumed，精确结算 ITEM_APPLIED + ITEM_CONSUMED 并 unregister。
static func finalize_triggered(bc: BattleController, inv: ItemInventoryModule) -> Dictionary:
	if inv == null:
		return {"ok": true, "events": []}
	var events: Array = []
	for row in inv.list_triggered_armed():
		var iid := String(row.get("item_instance_id", ""))
		var seat: int = int(row.get("seat", -1))
		var item_id := String(row.get("item_id", ""))
		var cmd := String(row.get("command_id", ""))
		# 禁止伪造 command_id：非法关联 fail-closed，不消费、不发事件
		if cmd.is_empty() or not ProtocolUuid.is_canonical_v4(cmd):
			return {"ok": false, "reason": "INVALID_ARM_COMMAND_ID"}
		var sk: SkillResource = row.get("skill", null) as SkillResource
		var cons: Dictionary = inv.consume_instance(iid, seat)
		if not bool(cons.get("ok", false)):
			return {"ok": false, "reason": String(cons.get("reason", "CONSUME_FAIL"))}
		if sk != null and bc != null and bc.registry != null:
			bc.registry.unregister(sk, seat)
		inv.forget_registered_skill(iid)
		events.append({
			"kind": "ITEM_APPLIED",
			"payload": {
				"seat": seat,
				"item_id": item_id,
				"item_instance_id": iid,
				"effect_id": item_id,
				"command_id": cmd,
			},
		})
		events.append({
			"kind": "ITEM_CONSUMED",
			"payload": {
				"seat": seat,
				"item_id": item_id,
				"item_instance_id": iid,
				"command_id": cmd,
			},
		})
	return {"ok": true, "events": events}


static func _apply_immediate_consumable(
	bc: BattleController, seat: int, consumable_id: StringName
) -> bool:
	var sk: SkillResource = ConsumableFactory.build(consumable_id)
	if sk == null:
		return false
	var ev := BattleEvent.make(&"GAME_BEGIN", seat, null, {})
	var ctx := SkillCtx.new(bc.state, ev)
	ctx.beneficiary_seat = seat
	ctx.current_skill = sk
	match consumable_id:
		&"wall_peek_v1":
			ctx.reveal_wall_top_to(seat, 5)
		&"wall_collapse_v1":
			# CardPool：开局减少牌墙 10 张 → 权威 wall.draw 推进 live wall
			if bc.state.wall == null:
				return false
			var n: int = mini(10, bc.state.wall.live_wall_size())
			for _i in range(n):
				if bc.state.wall.draw() == null:
					break
		&"seat_swap_v1", &"tsubame_v1":
			return false
		_:
			if sk.hook_script != null:
				var hook = sk.hook_script.new()
				if hook is SkillHook:
					hook.on_event(sk, ev, ctx)
			else:
				return false
	return true


## OPEN 后武装：pending→active，注册角色 skill，GAME_BEGIN 能力等价激活。
## fail-closed：mutation 前预检所有将 arm 席；任一步失败恢复 inventory/slots/registry。
static func arm_seats_on_open(
	bc: BattleController,
	inv: ItemInventoryModule,
	slots: Array,
	window_id: String
) -> Dictionary:
	var armed_events: Array = []
	if inv == null:
		return {"ok": true, "events": armed_events}
	var inv_snap: Dictionary = inv.capture_state()
	var slots_snap: Array = []
	for slot_v in slots:
		if slot_v is CharacterAbilitySlot:
			var s0: CharacterAbilitySlot = slot_v as CharacterAbilitySlot
			slots_snap.append({
				"armed": s0.armed,
				"active_window_id": s0.active_window_id,
				"registry_registered": s0.registry_registered,
			})
		else:
			slots_snap.append({})
	# mutation 前预检：凡将 arm 的 seat 必须有 skill
	for seat_pre in range(4):
		var pend0 = inv.pending_window_id(seat_pre)
		if pend0 == null or String(pend0) != window_id:
			continue
		var slot_chk: CharacterAbilitySlot = null
		if seat_pre < slots.size() and slots[seat_pre] is CharacterAbilitySlot:
			slot_chk = slots[seat_pre] as CharacterAbilitySlot
		if slot_chk == null or slot_chk.skill == null:
			return {"ok": false, "reason": "MISSING_SLOT_SKILL"}
	var reg_done: Array = []  # {skill, seat}
	for seat in range(4):
		var r: Dictionary = inv.try_arm_on_open(seat, window_id)
		if not bool(r.get("ok", false)):
			_rollback_arm_partial(bc, inv, slots, inv_snap, slots_snap, reg_done)
			return {"ok": false, "reason": String(r.get("reason", "ARM_FAIL"))}
		if not bool(r.get("armed", false)):
			continue
		var slot: CharacterAbilitySlot = slots[seat] as CharacterAbilitySlot
		slot.set_armed_for_window(window_id)
		if not slot.registry_registered and bc != null and bc.registry != null:
			bc.registry.register(slot.skill, seat)
			slot.registry_registered = true
			reg_done.append({"skill": slot.skill, "seat": seat})
		# GAME_BEGIN-only 等价激活（BattleState 副作用：失败时无法精确回滚 reveal，
		# 故预检已保证不会中途缺 skill；GAME_BEGIN 副作用在预检通过后执行）
		if GAME_BEGIN_ABILITIES.has(slot.ability_id):
			_activate_game_begin_ability(bc, slot, seat)
		armed_events.append({
			"kind": "CHARACTER_ABILITY_ARMED",
			"payload": {
				"seat": seat,
				"window_id": window_id,
				"character_id": String(slot.character_id),
				"ability_id": String(slot.ability_id),
				"active_window_id": window_id,
			},
		})
	return {"ok": true, "events": armed_events}


static func _rollback_arm_partial(
	bc: BattleController,
	inv: ItemInventoryModule,
	slots: Array,
	inv_snap: Dictionary,
	slots_snap: Array,
	reg_done: Array
) -> void:
	if bc != null and bc.registry != null:
		for e in reg_done:
			if typeof(e) != TYPE_DICTIONARY:
				continue
			var sk: SkillResource = e.get("skill", null) as SkillResource
			if sk != null:
				bc.registry.unregister(sk, int(e.get("seat", -1)))
	inv.restore_state(inv_snap)
	for i in range(mini(slots.size(), slots_snap.size())):
		if not (slots[i] is CharacterAbilitySlot):
			continue
		if typeof(slots_snap[i]) != TYPE_DICTIONARY:
			continue
		var slot: CharacterAbilitySlot = slots[i] as CharacterAbilitySlot
		var d: Dictionary = slots_snap[i]
		slot.armed = bool(d.get("armed", false))
		slot.active_window_id = d.get("active_window_id", null)
		slot.registry_registered = bool(d.get("registry_registered", false))


static func _activate_game_begin_ability(
	bc: BattleController, slot: CharacterAbilitySlot, seat: int
) -> void:
	if bc == null or slot == null or slot.skill == null:
		return
	var ev := BattleEvent.make(&"GAME_BEGIN", seat, null, {})
	var ctx := SkillCtx.new(bc.state, ev)
	ctx.beneficiary_seat = seat
	ctx.current_skill = slot.skill
	if slot.skill.hook_script != null:
		var hook = slot.skill.hook_script.new()
		if hook is SkillHook:
			# 不经 scheduler 去重；直接等价激活；不改写 params
			hook.on_event(slot.skill, ev, ctx)


## SETTLED/CANCELLED 后 DISARM：只清 active，unregister 停止后续 hook。
static func disarm_all_active(
	bc: BattleController,
	inv: ItemInventoryModule,
	slots: Array,
	window_id: String
) -> Dictionary:
	var events: Array = []
	if inv == null:
		return {"ok": true, "events": events}
	for seat in range(4):
		var was_active = inv.active_window_id(seat)
		var r: Dictionary = inv.disarm_active(seat)
		if not bool(r.get("ok", false)):
			return {"ok": false, "reason": String(r.get("reason", "DISARM_FAIL"))}
		if not bool(r.get("was_armed", false)):
			continue
		var slot: CharacterAbilitySlot = null
		if seat < slots.size() and slots[seat] is CharacterAbilitySlot:
			slot = slots[seat] as CharacterAbilitySlot
		if slot != null:
			var prev_active = was_active
			if slot.registry_registered and bc != null and bc.registry != null and slot.skill != null:
				bc.registry.unregister(slot.skill, seat)
				slot.registry_registered = false
			slot.clear_active_keep_pending()
			events.append({
				"kind": "CHARACTER_ABILITY_DISARMED",
				"payload": {
					"seat": seat,
					"window_id": window_id,
					"character_id": String(slot.character_id),
					"ability_id": String(slot.ability_id),
					"active_window_id": prev_active,
				},
			})
	return {"ok": true, "events": events}


## 和牌取消：pending 必须为空，DISARM active（库存保留）。
static func on_cancel_by_win(
	bc: BattleController,
	inv: ItemInventoryModule,
	slots: Array,
	window_id: String
) -> Dictionary:
	if inv == null:
		return {"ok": true, "events": []}
	for seat0 in range(4):
		var p = inv.pending_window_id(seat0)
		if p != null and String(p) != "":
			return {"ok": false, "reason": ERR_INVARIANT}
	return disarm_all_active(bc, inv, slots, window_id)


const ERR_INVARIANT := "INVARIANT_PENDING_NONEMPTY"


## MATCH_SETTLED：清库存/武装/registry 道具技能。
static func clear_match(
	bc: BattleController,
	inv: ItemInventoryModule,
	slots: Array
) -> void:
	if inv != null:
		var to_unreg: Array = []
		for iid in inv._registered_skills.keys():
			var e: Dictionary = inv.registered_skill_entry(String(iid))
			if e.is_empty():
				continue
			var sk: SkillResource = e.get("skill", null) as SkillResource
			if sk != null:
				to_unreg.append({
					"skill": sk,
					"seat": int(e.get("seat", 0)),
				})
		for entry in to_unreg:
			if bc != null and bc.registry != null:
				bc.registry.unregister(entry["skill"], int(entry["seat"]))
		inv.clear_match()
	for seat in range(4):
		if seat < slots.size() and slots[seat] is CharacterAbilitySlot:
			var slot: CharacterAbilitySlot = slots[seat] as CharacterAbilitySlot
			if slot.registry_registered and bc != null and bc.registry != null and slot.skill != null:
				bc.registry.unregister(slot.skill, seat)
			slot.registry_registered = false
			slot.clear_all_arm()


static func _reject(code: String) -> Dictionary:
	return {"ok": true, "accepted": false, "error_code": code, "events": []}
