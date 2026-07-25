class_name ItemInventoryModule extends RefCounted

# E5-05 / #253：同场无容量上限的 ItemInstance 集合 + 每席武装状态。
# 纯逻辑；不推进 RewardWindow phase/window_exit。
# LocalLoopback 与未来 Worker 共用。

const MODULE_KEY := "item_inventory"
const SCHEMA_VERSION := 1

const ERR_INVARIANT := "INVARIANT_PENDING_NONEMPTY"
const ERR_NOT_FOUND := "ITEM_NOT_FOUND"
const ERR_NOT_OWNER := "ITEM_NOT_OWNER"
const ERR_ALREADY_CONSUMED := "ITEM_ALREADY_CONSUMED"

## 全场实例列表（跨席）；移除仅 CONSUMED 或 MATCH_SETTLED 清场。
var _instances: Array = [] # ItemInstance
## seat -> {active_window_id: String|null, pending_window_id: String|null}
var _arm_by_seat: Array = []
## item_instance_id -> true（快速查重）
var _id_index: Dictionary = {}
## 已登记到 SkillRegistry 的实例（relic 获赠 / consumable armed）
## value: { "skill": SkillResource, "seat": int }
var _registered_skills: Dictionary = {}
## 公开 match/session 命名空间（写实例 ID；不含 seed）
var match_namespace: String = ""


func _init() -> void:
	_instances = []
	_arm_by_seat = []
	_id_index = {}
	_registered_skills = {}
	match_namespace = ""
	for _s in range(4):
		_arm_by_seat.append({
			"active_window_id": null,
			"pending_window_id": null,
		})


func set_match_namespace(ns: String) -> void:
	match_namespace = String(ns).strip_edges()


func instance_count() -> int:
	return _instances.size()


func all_instances() -> Array:
	var out: Array = []
	for inst in _instances:
		if inst is ItemInstance:
			out.append(inst)
	return out


func instances_for_seat(seat: int) -> Array:
	var out: Array = []
	if seat < 0 or seat > 3:
		return out
	for inst in _instances:
		if not (inst is ItemInstance):
			continue
		var ii: ItemInstance = inst as ItemInstance
		if int(ii.seat) != seat:
			continue
		# held + armed 均在库存投影中
		if ii.status == ItemInstance.STATUS_HELD or ii.status == ItemInstance.STATUS_ARMED:
			out.append(ii)
	return out


func find_instance(item_instance_id: String) -> ItemInstance:
	var key := String(item_instance_id).strip_edges()
	if key.is_empty() or not _id_index.has(key):
		return null
	for inst in _instances:
		if inst is ItemInstance and inst.item_instance_id == key:
			return inst as ItemInstance
	return null


func active_window_id(seat: int):
	if seat < 0 or seat > 3:
		return null
	return _arm_by_seat[seat]["active_window_id"]


func pending_window_id(seat: int):
	if seat < 0 or seat > 3:
		return null
	return _arm_by_seat[seat]["pending_window_id"]


func is_armed(seat: int) -> bool:
	var a = active_window_id(seat)
	return a != null and String(a) != ""


## 确定性 next window_id（同 hand 下一窗）。流局跨局由调用方传入。
static func next_window_id_same_hand(hand_seq: int, window_index: int) -> String:
	return "hand_%d_window_%d" % [hand_seq, window_index + 1]


static func next_window_id_next_hand(hand_seq: int) -> String:
	return "hand_%d_window_0" % [hand_seq + 1]


## FULL_GRANT 单席授予。成功返回 grant payload；失败 {ok:false, reason}。
## 不发布事件；调用方负责事务与 NetworkedEvent。
func grant_for_seat(input: Dictionary) -> Dictionary:
	var seat: int = int(input.get("seat", -1))
	if seat < 0 or seat > 3:
		return _err("INVALID_SEAT")
	var item_id := String(input.get("item_id", "")).strip_edges()
	if item_id.is_empty():
		return _err("INVALID_ITEM_ID")
	var window_id := String(input.get("window_id", "")).strip_edges()
	if window_id.is_empty():
		return _err("INVALID_WINDOW_ID")
	var hand_seq: int = int(input.get("hand_seq", -1))
	if hand_seq < 0:
		return _err("INVALID_HAND_SEQ")
	var score: int = int(input.get("score", 0))
	if score < 0:
		return _err("INVALID_SCORE")
	var rule_version := String(input.get("rule_version", "")).strip_edges()
	var assignment_version := String(input.get("assignment_version", "")).strip_edges()
	var matched: Array = []
	if typeof(input.get("matched_rule_ids", null)) == TYPE_ARRAY:
		for r in input["matched_rule_ids"]:
			matched.append(String(r))
	matched.sort()

	var affinity_match: bool = bool(input.get("affinity_match", false))
	var next_wid = input.get("next_window_id", null)
	var armed_for = null
	if affinity_match:
		if next_wid == null or String(next_wid).strip_edges().is_empty():
			return _err("MISSING_NEXT_WINDOW")
		armed_for = String(next_wid).strip_edges()
		# 不变量：pending 必须为空才能登记
		var cur_pending = _arm_by_seat[seat]["pending_window_id"]
		if cur_pending != null and String(cur_pending) != "":
			return _err(ERR_INVARIANT)

	var match_ns := String(input.get("match_namespace", match_namespace)).strip_edges()
	if match_ns.is_empty():
		match_ns = match_namespace
	if match_ns.is_empty():
		return _err("MISSING_MATCH_NAMESPACE")
	var instance_id := ItemInstance.make_instance_id(match_ns, window_id, seat, item_id)
	if _id_index.has(instance_id):
		return _err("DUPLICATE_INSTANCE")

	var inst := ItemInstance.new(
		instance_id, item_id, seat, window_id, hand_seq, score,
		affinity_match, armed_for
	)
	_instances.append(inst)
	_id_index[instance_id] = true
	if affinity_match and armed_for != null:
		_arm_by_seat[seat]["pending_window_id"] = armed_for

	return {
		"ok": true,
		"payload": {
			"window_id": window_id,
			"rule_version": rule_version,
			"assignment_version": assignment_version,
			"matched_rule_ids": matched.duplicate(),
			"item_id": item_id,
			"item_instance_id": instance_id,
			"seat": seat,
			"hand_seq": hand_seq,
			"score": score,
			"affinity_match": affinity_match,
			"armed_for_window_id": armed_for,
		},
		"instance": inst,
	}


## 标记延迟武装（实例仍在库存，skill 已注册）。
## command_id 必须 canonical UUID v4；禁止空/非法后在 finalize 伪造。
func mark_armed(item_instance_id: String, seat: int, command_id: String) -> Dictionary:
	var inst: ItemInstance = find_instance(item_instance_id)
	if inst == null:
		return _err(ERR_NOT_FOUND)
	if inst.seat != seat:
		return _err(ERR_NOT_OWNER)
	if inst.status != ItemInstance.STATUS_HELD:
		return _err(ERR_ALREADY_CONSUMED)
	if not ProtocolUuid.is_canonical_v4(command_id):
		return _err("INVALID_COMMAND_ID")
	inst.status = ItemInstance.STATUS_ARMED
	inst.arm_command_id = command_id
	return {"ok": true, "instance": inst}


## 效果真实结算后精确消耗（held 或 armed）。不自动 unregister。
func consume_instance(item_instance_id: String, seat: int) -> Dictionary:
	var inst: ItemInstance = find_instance(item_instance_id)
	if inst == null:
		return _err(ERR_NOT_FOUND)
	if inst.seat != seat:
		return _err(ERR_NOT_OWNER)
	if inst.status == ItemInstance.STATUS_CONSUMED:
		return _err(ERR_ALREADY_CONSUMED)
	if inst.status != ItemInstance.STATUS_HELD and inst.status != ItemInstance.STATUS_ARMED:
		return _err(ERR_ALREADY_CONSUMED)
	var item_id := inst.item_id
	var cmd := inst.arm_command_id
	inst.status = ItemInstance.STATUS_CONSUMED
	_instances.erase(inst)
	_id_index.erase(item_instance_id)
	return {
		"ok": true,
		"item_id": item_id,
		"item_instance_id": item_instance_id,
		"seat": seat,
		"arm_command_id": cmd,
	}


## OPEN 后：消费匹配 pending → active。返回是否武装。
func try_arm_on_open(seat: int, window_id: String) -> Dictionary:
	if seat < 0 or seat > 3:
		return _err("INVALID_SEAT")
	var wid := String(window_id).strip_edges()
	if wid.is_empty():
		return _err("INVALID_WINDOW_ID")
	var pending = _arm_by_seat[seat]["pending_window_id"]
	if pending == null or String(pending) != wid:
		return {"ok": true, "armed": false}
	_arm_by_seat[seat]["pending_window_id"] = null
	_arm_by_seat[seat]["active_window_id"] = wid
	return {"ok": true, "armed": true, "active_window_id": wid}


## SETTLED/CANCELLED 后：只清 active，保留 pending。
func disarm_active(seat: int) -> Dictionary:
	if seat < 0 or seat > 3:
		return _err("INVALID_SEAT")
	var active = _arm_by_seat[seat]["active_window_id"]
	_arm_by_seat[seat]["active_window_id"] = null
	return {
		"ok": true,
		"was_armed": active != null and String(active) != "",
		"cleared_active_window_id": active,
	}


## MATCH_SETTLED：清空库存与全部武装。
func clear_match() -> void:
	_instances.clear()
	_id_index.clear()
	_registered_skills.clear()
	for seat in range(4):
		_arm_by_seat[seat] = {
			"active_window_id": null,
			"pending_window_id": null,
		}


func remember_registered_skill(
	item_instance_id: String, skill: SkillResource, seat: int
) -> void:
	if skill != null and not item_instance_id.is_empty():
		_registered_skills[item_instance_id] = {
			"skill": skill,
			"seat": seat,
			"item_instance_id": item_instance_id,
		}


func registered_skill(item_instance_id: String) -> SkillResource:
	var e = _registered_skills.get(item_instance_id, null)
	if typeof(e) == TYPE_DICTIONARY:
		return (e as Dictionary).get("skill", null) as SkillResource
	if e is SkillResource:
		return e as SkillResource
	return null


func registered_skill_entry(item_instance_id: String) -> Dictionary:
	var e = _registered_skills.get(item_instance_id, null)
	if typeof(e) == TYPE_DICTIONARY:
		return (e as Dictionary).duplicate(true)
	return {}


func forget_registered_skill(item_instance_id: String) -> void:
	_registered_skills.erase(item_instance_id)


func clear_registered_skills_index() -> void:
	_registered_skills.clear()


## 同进程事务冻结：保留 skill 对象引用（ARS 序列化路径不走此表）。
func duplicate_registered_skills() -> Dictionary:
	return _registered_skills.duplicate(true)


func restore_registered_skills(snap: Dictionary) -> void:
	_registered_skills.clear()
	if snap.is_empty():
		return
	for k in snap.keys():
		var e = snap[k]
		if typeof(e) != TYPE_DICTIONARY:
			continue
		_registered_skills[str(k)] = (e as Dictionary).duplicate(true)


## 扫描已 consumed 的延迟 skill，返回待结算条目（不修改库存）。
func list_triggered_armed() -> Array:
	var out: Array = []
	for inst in _instances:
		if not (inst is ItemInstance):
			continue
		var ii: ItemInstance = inst as ItemInstance
		if ii.status != ItemInstance.STATUS_ARMED:
			continue
		var sk: SkillResource = registered_skill(ii.item_instance_id)
		if sk != null and sk.consumed:
			out.append({
				"item_instance_id": ii.item_instance_id,
				"item_id": ii.item_id,
				"seat": ii.seat,
				"command_id": ii.arm_command_id,
				"skill": sk,
			})
	return out


func capture_state() -> Dictionary:
	var insts: Array = []
	for inst in _instances:
		if inst is ItemInstance:
			insts.append((inst as ItemInstance).to_dict())
	var arms: Array = []
	for seat in range(4):
		arms.append({
			"active_window_id": _arm_by_seat[seat]["active_window_id"],
			"pending_window_id": _arm_by_seat[seat]["pending_window_id"],
		})
	# registered_skills 由 ARS/registry rebind 恢复，不入 capture
	return {
		"instances": insts,
		"arm_by_seat": arms,
		"match_namespace": match_namespace,
	}


func restore_state(snap: Dictionary) -> bool:
	if typeof(snap.get("instances", null)) != TYPE_ARRAY:
		return false
	if typeof(snap.get("arm_by_seat", null)) != TYPE_ARRAY:
		return false
	var arms: Array = snap["arm_by_seat"]
	if arms.size() != 4:
		return false
	var new_insts: Array = []
	var new_idx: Dictionary = {}
	for raw in snap["instances"]:
		var inst: ItemInstance = ItemInstance.from_dict(raw)
		if inst == null:
			return false
		if inst.status != ItemInstance.STATUS_HELD and inst.status != ItemInstance.STATUS_ARMED:
			return false
		if new_idx.has(inst.item_instance_id):
			return false
		new_insts.append(inst)
		new_idx[inst.item_instance_id] = true
	var new_arms: Array = []
	for seat in range(4):
		if typeof(arms[seat]) != TYPE_DICTIONARY:
			return false
		var a: Dictionary = arms[seat]
		var act = a.get("active_window_id", null)
		var pen = a.get("pending_window_id", null)
		if act != null and String(act).strip_edges().is_empty():
			return false
		if pen != null and String(pen).strip_edges().is_empty():
			return false
		new_arms.append({
			"active_window_id": act if act == null else String(act),
			"pending_window_id": pen if pen == null else String(pen),
		})
	_instances = new_insts
	_id_index = new_idx
	_arm_by_seat = new_arms
	# registered_skills 由调用方用 ARS registry + rebind_registered_from_registry 重建
	_registered_skills.clear()
	if snap.has("match_namespace"):
		match_namespace = String(snap.get("match_namespace", ""))
	return true


## 从 BC.registry 按 params.item_instance_id 重绑库存索引（ARS 恢复后）。
func rebind_registered_from_registry(registry: SkillRegistry) -> void:
	_registered_skills.clear()
	if registry == null:
		return
	for e in registry.get_all_entries():
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var sk: SkillResource = e.get("skill", null) as SkillResource
		if sk == null or not sk.params.has("item_instance_id"):
			continue
		var iid := String(sk.params["item_instance_id"])
		if not _id_index.has(iid):
			continue
		var seat: int = int(e.get("anchor", -1))
		_registered_skills[iid] = {
			"skill": sk,
			"seat": seat,
			"item_instance_id": iid,
		}


## 按席快照 DTO（仅该席实例 + 该席 active/pending）。
func to_seat_snapshot_dto(seat: int) -> Dictionary:
	if seat < 0 or seat > 3:
		return {}
	var items: Array = []
	for inst in instances_for_seat(seat):
		var d: Dictionary = (inst as ItemInstance).to_dict()
		# 快照不暴露他席；本席完整。status 仅 held|armed（延迟武装身份，防恢复后重复 USE）
		var st := String(d.get("status", ItemInstance.STATUS_HELD))
		if st != ItemInstance.STATUS_HELD and st != ItemInstance.STATUS_ARMED:
			st = ItemInstance.STATUS_HELD
		items.append({
			"item_instance_id": d["item_instance_id"],
			"item_id": d["item_id"],
			"seat": d["seat"],
			"window_id": d["window_id"],
			"hand_seq": d["hand_seq"],
			"score": d["score"],
			"affinity_match": d["affinity_match"],
			"armed_for_window_id": d["armed_for_window_id"],
			"status": st,
		})
	return {
		"module_key": MODULE_KEY,
		"schema_version": SCHEMA_VERSION,
		"payload": {
			"seat": seat,
			"items": items,
			"active_window_id": _arm_by_seat[seat]["active_window_id"],
			"pending_window_id": _arm_by_seat[seat]["pending_window_id"],
		},
	}


func restore_seat_snapshot_payload(payload: Dictionary, seat: int) -> bool:
	if seat < 0 or seat > 3:
		return false
	if int(payload.get("seat", -1)) != seat:
		return false
	if typeof(payload.get("items", null)) != TYPE_ARRAY:
		return false
	var act = payload.get("active_window_id", null)
	var pen = payload.get("pending_window_id", null)
	if act != null and (typeof(act) != TYPE_STRING or String(act).is_empty()):
		return false
	if pen != null and (typeof(pen) != TYPE_STRING or String(pen).is_empty()):
		return false

	# 替换该席实例，保留他席
	var kept: Array = []
	var new_idx: Dictionary = {}
	for inst in _instances:
		if inst is ItemInstance and int(inst.seat) != seat:
			kept.append(inst)
			new_idx[inst.item_instance_id] = true
	for raw in payload["items"]:
		if typeof(raw) != TYPE_DICTIONARY:
			return false
		var row: Dictionary = (raw as Dictionary).duplicate(true)
		if not row.has("seat"):
			row["seat"] = seat
		# 保留公开 DTO 的 held|armed；缺省 held（兼容旧快照）
		var st := String(row.get("status", ItemInstance.STATUS_HELD))
		if st != ItemInstance.STATUS_HELD and st != ItemInstance.STATUS_ARMED:
			return false
		row["status"] = st
		var inst2: ItemInstance = ItemInstance.from_dict(row)
		if inst2 == null or inst2.seat != seat:
			return false
		if new_idx.has(inst2.item_instance_id):
			return false
		kept.append(inst2)
		new_idx[inst2.item_instance_id] = true
	_instances = kept
	_id_index = new_idx
	_arm_by_seat[seat] = {
		"active_window_id": act,
		"pending_window_id": pen,
	}
	return true


## 角色 affinity 与道具 tags 是否命中 primary/secondary。
static func compute_affinity_match(character_id: StringName, item_id: String) -> bool:
	var ch: Character = CharacterPool.find(character_id)
	if ch == null:
		return false
	var def: Dictionary = TrashTalkRuleCatalog.item_def(StringName(item_id))
	if def.is_empty():
		return false
	var tags: Array = def.get("tags", [])
	var primary := String(ch.affinity_primary)
	var secondary := String(ch.affinity_secondary)
	for t in tags:
		var ts := String(t)
		if ts == primary or ts == secondary:
			return true
	return false


## 从 SETTLED 矩阵行取 seat+item 的 total_score 与 matched_rule_ids。
static func score_and_rules_from_matrix(
	matrix: Array, seat: int, item_id: String
) -> Dictionary:
	for row in matrix:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var r: Dictionary = row
		if int(r.get("seat", -1)) == seat and String(r.get("item_id", "")) == item_id:
			var matched: Array = []
			if typeof(r.get("matched_rule_ids", null)) == TYPE_ARRAY:
				for mid in r["matched_rule_ids"]:
					matched.append(String(mid))
			matched.sort()
			return {
				"score": int(r.get("total_score", 0)),
				"matched_rule_ids": matched,
			}
	return {"score": 0, "matched_rule_ids": []}


static func is_relic_item(item_id: String) -> bool:
	for r in CardPool.all_relics():
		if String(r.id) == item_id:
			return true
	return false


static func is_battle_consumable(item_id: String) -> bool:
	for c in CardPool.consumables_by_kind(ConsumableItem.Kind.BATTLE):
		if String(c.id) == item_id:
			return true
	return false


static func is_grantable(item_id: String) -> bool:
	return TrashTalkRuleCatalog.is_alpha_grantable(item_id)


func _err(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
