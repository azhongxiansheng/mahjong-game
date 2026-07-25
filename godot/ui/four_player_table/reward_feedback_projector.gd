extends RefCounted

# E5-06 / #254：奖励反馈 display-only 投影 store。
# 无全局 class_name。只接受 schema-valid NetworkedEvent 或 #253 快照 DTO。
# 库存新增只认 ITEM_GRANTED；移除只认 ITEM_CONSUMED / MATCH_SETTLED；
# 效果只认 ITEM_APPLIED；SETTLED 绝不改库存。
# 不调用权威 RewardWindowModule / ItemInventoryModule 写入路径。

const MSG_FULL_GRANT := "分配完成，等待到账事件"
const MSG_DISPLAY_ONLY := "仅本场统计，未发放"
const MSG_CANCELLED_BY_WIN := "和牌优先，本窗作废"
const MSG_ITEM_GRANTED := "到账"
const MSG_ITEM_APPLIED := "发动"

const TARGET_DISCARDS := 24

# ---- display state ----
var _prize_pool: Array = []
var _discard_count: int = 0
var _window_id: String = ""
var _phase: String = ""
var _window_exit = null
var _assignment: Dictionary = {}
var _matrix_summary: Dictionary = {}
var _has_assignment: bool = false
var _show_scores: bool = false
var _local_seat: int = 0
# item_instance_id → row dict
var _instances: Dictionary = {}
var _last_feedback: Dictionary = {}
var _utterances_by_seat: Dictionary = {}
var _character_ids: Array = []
# journal 去重：key = epoch|server_seq
var _seen_feedback_seqs: Dictionary = {}
var _source_epoch: String = ""


func set_local_seat(seat: int) -> void:
	if seat >= 0 and seat <= 3:
		_local_seat = seat


## 接受 NetworkedEvent 实例，或完整六键 wire Dictionary（经 from_dict 验证）。
func project(event: Variant) -> Dictionary:
	var ne: NetworkedEvent = _coerce_networked_event(event)
	if ne == null:
		return _reject("SCHEMA_REJECTED")
	return ingest(ne)


## 摄入并更新 store；返回投影结果。
func ingest(event: Variant) -> Dictionary:
	var ne: NetworkedEvent = _coerce_networked_event(event)
	if ne == null:
		return _reject("SCHEMA_REJECTED")
	var kind := String(ne.kind)
	var payload: Dictionary = ne.payload
	match kind:
		"REWARD_WINDOW_OPENED":
			return _project_opened(payload)
		"REWARD_WINDOW_CLOSING":
			return _project_closing(payload)
		"REWARD_WINDOW_SETTLED":
			return _project_settled(payload)
		"REWARD_WINDOW_CANCELLED":
			return _project_cancelled(payload)
		"ITEM_GRANTED":
			return _project_item_granted(payload)
		"ITEM_APPLIED":
			return _project_item_applied(payload)
		"ITEM_CONSUMED":
			return _project_item_consumed(payload)
		"MATCH_SETTLED":
			return _project_match_settled(payload)
		"ROOM_SNAPSHOT":
			return _project_room_snapshot(payload)
	return _reject("UNSUPPORTED_KIND")


func apply_reward_window_view(view: Dictionary) -> void:
	if view.is_empty():
		return
	var payload: Dictionary = view
	if view.has("payload") and typeof(view.get("payload")) == TYPE_DICTIONARY \
			and String(view.get("module_key", "")) == "reward_window":
		payload = view["payload"] as Dictionary
	if payload.has("prize_pool") and typeof(payload["prize_pool"]) == TYPE_ARRAY:
		_prize_pool = (payload["prize_pool"] as Array).duplicate()
	if payload.has("discard_count"):
		_discard_count = int(payload["discard_count"])
	if payload.has("window_id"):
		_window_id = str(payload["window_id"])
	if payload.has("phase"):
		_phase = str(payload["phase"])
	if payload.has("window_exit"):
		_window_exit = payload["window_exit"]
	if payload.has("assignment") and typeof(payload["assignment"]) == TYPE_DICTIONARY:
		var asg: Dictionary = payload["assignment"]
		if not asg.is_empty():
			_assignment = asg.duplicate(true)
			_has_assignment = true
		elif str(payload.get("window_exit", "")) == "CANCELLED_BY_WIN" \
				or _phase == "CANCELLED":
			_assignment = {}
			_has_assignment = false
	if payload.has("utterances_by_seat"):
		_utterances_by_seat = (payload["utterances_by_seat"] as Dictionary).duplicate(true) \
			if typeof(payload["utterances_by_seat"]) == TYPE_DICTIONARY else {}
	if payload.has("character_ids") and typeof(payload["character_ids"]) == TYPE_ARRAY:
		_character_ids = (payload["character_ids"] as Array).duplicate()
	# 仅快照/视图恢复时：若无瞬时到账/发动，用 window_exit 恢复结算文案
	var prev_kind := String(_last_feedback.get("feedback_kind", ""))
	if prev_kind != "ITEM_GRANTED" and prev_kind != "ITEM_APPLIED":
		var sm := _settlement_message_from_state()
		if not sm.is_empty():
			_last_feedback = {
				"ok": true,
				"message": sm,
				"feedback_kind": _settlement_feedback_kind_from_state(),
			}


## 接受 payload 字典，或 `to_seat_snapshot_dto` envelope（module_key+payload）。
## 非法结构 fail-closed：不改写既有库存。
func apply_item_inventory_view(view: Dictionary) -> void:
	if view.is_empty():
		return
	var payload: Dictionary = _unwrap_inventory_payload(view)
	if payload.is_empty():
		return
	if not payload.has("items") or typeof(payload.get("items", null)) != TYPE_ARRAY:
		return
	var seat := int(payload.get("seat", _local_seat))
	if seat != _local_seat:
		return
	_instances.clear()
	for raw in payload["items"]:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = _normalize_instance_row(raw as Dictionary)
		var iid := String(row.get("item_instance_id", ""))
		if iid.is_empty():
			continue
		_instances[iid] = row


static func _unwrap_inventory_payload(view: Dictionary) -> Dictionary:
	# envelope: {module_key, schema_version, payload:{seat,items,...}}
	if view.has("payload") and typeof(view.get("payload")) == TYPE_DICTIONARY:
		var key := String(view.get("module_key", ""))
		if not key.is_empty() and key != "item_inventory":
			return {}
		return (view["payload"] as Dictionary).duplicate(true)
	# bare payload
	if view.has("items"):
		return view.duplicate(true)
	return {}


func restore_from_snapshot_modules(modules: Array) -> bool:
	var ok := false
	for m in modules:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var md: Dictionary = m
		var key := String(md.get("module_key", ""))
		var pay: Variant = md.get("payload", {})
		if typeof(pay) != TYPE_DICTIONARY:
			continue
		if key == "item_inventory":
			apply_item_inventory_view(pay as Dictionary)
			ok = true
		elif key == "reward_window":
			apply_reward_window_view(pay as Dictionary)
			ok = true
	return ok


func prize_pool() -> Array:
	return _prize_pool.duplicate()


func discard_progress() -> int:
	return _discard_count


func pool_title_text() -> String:
	var n: int = clampi(_discard_count, 0, TARGET_DISCARDS)
	return "垃圾话奖池 · %d/%d" % [n, TARGET_DISCARDS]


func inventory_count_for_seat(seat: int) -> int:
	if seat != _local_seat:
		return 0
	return _instances.size()


func local_inventory_instances() -> Array:
	var out: Array = []
	var keys: Array = _instances.keys()
	keys.sort()
	for k in keys:
		out.append((_instances[k] as Dictionary).duplicate(true))
	return out


func has_instance(item_instance_id: String) -> bool:
	return _instances.has(item_instance_id)


func use_target_instance_id(item_instance_id: String) -> String:
	var iid := item_instance_id.strip_edges()
	if iid.is_empty() or not _instances.has(iid):
		return ""
	var row: Dictionary = _instances[iid]
	# 与 ItemAuthority.use_item / drawer.can_request_use 对齐
	var DrawerScr = load("res://ui/four_player_table/item_inventory_drawer.gd")
	if DrawerScr != null and DrawerScr.can_request_use(row):
		return iid
	return ""


func last_feedback() -> Dictionary:
	return _last_feedback.duplicate(true)


func last_feedback_message() -> String:
	return String(_last_feedback.get("message", ""))


func has_assignment_display() -> bool:
	return _has_assignment and not _assignment.is_empty()


func assignment_display() -> Dictionary:
	return _assignment.duplicate(true)


func should_show_assignment_for_seat(_seat: int, is_silent: bool) -> bool:
	if not _has_assignment:
		return false
	var exit_s := String(_window_exit) if _window_exit != null else ""
	if exit_s == "CANCELLED_BY_WIN":
		return false
	if String(_last_feedback.get("feedback_kind", "")) == "CANCELLED_BY_WIN":
		return false
	# 静默席仅在 FULL_GRANT / DISPLAY_ONLY 展示
	if is_silent:
		return exit_s == "FULL_GRANT" or exit_s == "DISPLAY_ONLY" \
			or String(_last_feedback.get("feedback_kind", "")).begins_with("SETTLED_")
	return true


func prize_pool_display_rows() -> Array:
	var out: Array = []
	for id_v in _prize_pool:
		var item_id := String(id_v)
		out.append(_item_public_meta(item_id))
	return out


static func _coerce_networked_event(event: Variant) -> NetworkedEvent:
	if event is NetworkedEvent:
		return event as NetworkedEvent
	if typeof(event) == TYPE_DICTIONARY:
		return NetworkedEvent.from_dict(event)
	return null


func _project_opened(payload: Dictionary) -> Dictionary:
	_phase = String(payload.get("phase", "OPEN"))
	_window_id = String(payload.get("window_id", ""))
	_window_exit = null
	_has_assignment = false
	_assignment = {}
	_matrix_summary = {}
	_show_scores = false
	if typeof(payload.get("prize_pool", null)) == TYPE_ARRAY:
		_prize_pool = (payload["prize_pool"] as Array).duplicate()
	_discard_count = int(payload.get("discard_count", 0))
	var res := {
		"ok": true,
		"message": pool_title_text(),
		"feedback_kind": "OPENED",
		"prize_pool": prize_pool(),
		"inventory_changed": false,
	}
	_last_feedback = res.duplicate(true)
	return res


func _project_closing(payload: Dictionary) -> Dictionary:
	_phase = String(payload.get("phase", "CLOSING"))
	if payload.has("discard_count"):
		_discard_count = int(payload["discard_count"])
	var res := {
		"ok": true,
		"message": "窗口结算中…",
		"feedback_kind": "CLOSING",
		"inventory_changed": false,
	}
	_last_feedback = res.duplicate(true)
	return res


func _project_settled(payload: Dictionary) -> Dictionary:
	var outcome := String(payload.get("outcome", "")).strip_edges()
	match outcome:
		"FULL_GRANT":
			_window_exit = "FULL_GRANT"
			_phase = "SETTLED"
			_apply_settled_display(payload, true)
			var res_full := {
				"ok": true,
				"message": MSG_FULL_GRANT,
				"feedback_kind": "SETTLED_FULL_GRANT",
				"assignment": _assignment.duplicate(true),
				"matrix_summary": _matrix_summary.duplicate(true),
				"show_scores": true,
				"show_arrival": false,
				"inventory_changed": false,
			}
			_last_feedback = res_full.duplicate(true)
			return res_full
		"DISPLAY_ONLY":
			_window_exit = "DISPLAY_ONLY"
			_phase = "SETTLED"
			_apply_settled_display(payload, true)
			var res_disp := {
				"ok": true,
				"message": MSG_DISPLAY_ONLY,
				"feedback_kind": "SETTLED_DISPLAY_ONLY",
				"assignment": _assignment.duplicate(true),
				"matrix_summary": _matrix_summary.duplicate(true),
				"show_scores": true,
				"show_arrival": false,
				"inventory_changed": false,
			}
			_last_feedback = res_disp.duplicate(true)
			return res_disp
	return _reject("INVALID_OUTCOME")


func _apply_settled_display(payload: Dictionary, show_scores: bool) -> void:
	_show_scores = show_scores
	if typeof(payload.get("assignment", null)) == TYPE_DICTIONARY:
		_assignment = (payload["assignment"] as Dictionary).duplicate(true)
		_has_assignment = not _assignment.is_empty()
	if typeof(payload.get("matrix_summary", null)) == TYPE_DICTIONARY:
		_matrix_summary = (payload["matrix_summary"] as Dictionary).duplicate(true)
	if typeof(payload.get("prize_pool", null)) == TYPE_ARRAY:
		_prize_pool = (payload["prize_pool"] as Array).duplicate()
	# 明确：不碰 _instances


func _project_cancelled(payload: Dictionary) -> Dictionary:
	var reason := String(payload.get("cancel_reason", "")).strip_edges()
	if reason != "CANCELLED_BY_WIN":
		return _reject("INVALID_CANCEL_REASON")
	_window_exit = "CANCELLED_BY_WIN"
	_phase = "CANCELLED"
	_has_assignment = false
	_assignment = {}
	_matrix_summary = {}
	_show_scores = false
	var res := {
		"ok": true,
		"message": MSG_CANCELLED_BY_WIN,
		"feedback_kind": "CANCELLED_BY_WIN",
		"show_scores": false,
		"show_arrival": false,
		"inventory_changed": false,
	}
	_last_feedback = res.duplicate(true)
	return res


func _project_item_granted(payload: Dictionary) -> Dictionary:
	var seat := int(payload.get("seat", -1))
	var iid := String(payload.get("item_instance_id", "")).strip_edges()
	var item_id := String(payload.get("item_id", "")).strip_edges()
	if iid.is_empty() or item_id.is_empty() or seat < 0 or seat > 3:
		return _reject("INVALID_GRANT")
	if seat == _local_seat:
		var row := {
			"item_instance_id": iid,
			"item_id": item_id,
			"status": "held",
			"affinity_match": bool(payload.get("affinity_match", false)),
			"armed_for_window_id": payload.get("armed_for_window_id", null),
			"seat": seat,
		}
		row.merge(_item_public_meta(item_id))
		_instances[iid] = row
	var res := {
		"ok": true,
		"message": MSG_ITEM_GRANTED,
		"feedback_kind": "ITEM_GRANTED",
		"show_arrival": true,
		"item_instance_id": iid,
		"item_id": item_id,
		"seat": seat,
		"inventory_changed": seat == _local_seat,
	}
	_last_feedback = res.duplicate(true)
	return res


func _project_item_applied(payload: Dictionary) -> Dictionary:
	var iid := String(payload.get("item_instance_id", "")).strip_edges()
	var item_id := String(payload.get("item_id", "")).strip_edges()
	var meta: Dictionary = _item_public_meta(item_id)
	var name := String(meta.get("display_name", item_id))
	var res := {
		"ok": true,
		"message": "%s · %s" % [MSG_ITEM_APPLIED, name],
		"feedback_kind": "ITEM_APPLIED",
		"item_instance_id": iid,
		"item_id": item_id,
		"inventory_changed": false,
	}
	_last_feedback = res.duplicate(true)
	return res


func _project_item_consumed(payload: Dictionary) -> Dictionary:
	var iid := String(payload.get("item_instance_id", "")).strip_edges()
	var seat := int(payload.get("seat", _local_seat))
	var changed := false
	if seat == _local_seat and _instances.has(iid):
		_instances.erase(iid)
		changed = true
	# 只移除实例；不得覆盖 ITEM_APPLIED「发动」反馈
	var prev_kind := String(_last_feedback.get("feedback_kind", ""))
	var msg := String(_last_feedback.get("message", ""))
	if prev_kind != "ITEM_APPLIED" and prev_kind != "ITEM_GRANTED":
		# 无待保留的到账/发动时保持静默，不把 banner 改成「已消耗」
		msg = msg
	return {
		"ok": true,
		"message": msg,
		"feedback_kind": "ITEM_CONSUMED",
		"item_instance_id": iid,
		"inventory_changed": changed,
		"banner_preserved": prev_kind == "ITEM_APPLIED" or prev_kind == "ITEM_GRANTED",
	}


func _project_match_settled(_payload: Dictionary) -> Dictionary:
	_instances.clear()
	_has_assignment = false
	_assignment = {}
	_matrix_summary = {}
	_prize_pool = []
	_discard_count = 0
	_window_exit = null
	var res := {
		"ok": true,
		"message": "对局结束 · 库存已清空",
		"feedback_kind": "MATCH_SETTLED",
		"inventory_changed": true,
	}
	_last_feedback = res.duplicate(true)
	return res


func _project_room_snapshot(payload: Dictionary) -> Dictionary:
	var mods: Variant = payload.get("modules", [])
	if typeof(mods) != TYPE_ARRAY:
		return _reject("INVALID_SNAPSHOT")
	# 保留瞬时到账/发动文案（真实序列：ITEM_* → ROOM_SNAPSHOT）
	var prev: Dictionary = _last_feedback.duplicate(true)
	var prev_kind := String(prev.get("feedback_kind", ""))
	var ok := restore_from_snapshot_modules(mods as Array)
	if not ok:
		return _reject("INVALID_SNAPSHOT")
	if prev_kind == "ITEM_GRANTED" or prev_kind == "ITEM_APPLIED":
		_last_feedback = prev
		return {
			"ok": true,
			"message": String(prev.get("message", "")),
			"feedback_kind": "ROOM_SNAPSHOT",
			"inventory_changed": true,
			"preserved_feedback": true,
			"preserved_kind": prev_kind,
		}
	# 无瞬时反馈：从公开 window_exit 恢复持久 settlement 文案（重连/仅快照）
	var settle_msg := _settlement_message_from_state()
	var res := {
		"ok": true,
		"message": settle_msg,
		"feedback_kind": "ROOM_SNAPSHOT",
		"inventory_changed": true,
	}
	if not settle_msg.is_empty():
		_last_feedback = {
			"ok": true,
			"message": settle_msg,
			"feedback_kind": _settlement_feedback_kind_from_state(),
		}
	return res


func _settlement_message_from_state() -> String:
	var exit_s := str(_window_exit) if _window_exit != null else ""
	match exit_s:
		"FULL_GRANT":
			return MSG_FULL_GRANT
		"DISPLAY_ONLY":
			return MSG_DISPLAY_ONLY
		"CANCELLED_BY_WIN":
			return MSG_CANCELLED_BY_WIN
	if _phase == "CANCELLED":
		return MSG_CANCELLED_BY_WIN
	if not _prize_pool.is_empty():
		return pool_title_text()
	return ""


func _settlement_feedback_kind_from_state() -> String:
	var exit_s := str(_window_exit) if _window_exit != null else ""
	match exit_s:
		"FULL_GRANT":
			return "SETTLED_FULL_GRANT"
		"DISPLAY_ONLY":
			return "SETTLED_DISPLAY_ONLY"
		"CANCELLED_BY_WIN":
			return "CANCELLED_BY_WIN"
	if _phase == "CANCELLED":
		return "CANCELLED_BY_WIN"
	return "ROOM_SNAPSHOT"


func _normalize_instance_row(raw: Dictionary) -> Dictionary:
	var item_id := String(raw.get("item_id", ""))
	var row := {
		"item_instance_id": String(raw.get("item_instance_id", "")),
		"item_id": item_id,
		"status": String(raw.get("status", "held")),
		"affinity_match": bool(raw.get("affinity_match", false)),
		"armed_for_window_id": raw.get("armed_for_window_id", null),
		"seat": int(raw.get("seat", _local_seat)),
	}
	row.merge(_item_public_meta(item_id))
	return row


static func _item_public_meta(item_id: String) -> Dictionary:
	var display_name := item_id
	var description := ""
	var tags: Array = []
	var tag_labels: Array = []
	# CardPool 公开名称
	for c in CardPool.all_consumables():
		if String(c.id) == item_id:
			display_name = String(c.display_name)
			description = String(c.description)
			break
	if display_name == item_id:
		for r in CardPool.all_relics():
			if String(r.id) == item_id:
				display_name = String(r.display_name)
				description = String(r.description)
				break
	var def: Dictionary = TrashTalkRuleCatalog.item_def(StringName(item_id))
	if not def.is_empty():
		if typeof(def.get("tags", null)) == TYPE_ARRAY:
			for t in def["tags"]:
				var ts := String(t)
				if ts.is_empty():
					continue
				tags.append(ts)
				tag_labels.append(_affinity_label(ts))
	return {
		"display_name": display_name,
		"description": description,
		"effect_summary": description,
		"tags": tags,
		"tag_labels": tag_labels,
	}


static func _affinity_label(key: String) -> String:
	match key:
		"DOMINATION":
			return "统治"
		"CALM":
			return "冷静"
		"CUNNING":
			return "诡诈"
		"PASSION":
			return "热血"
		"MYSTIC":
			return "神秘"
	return key


## 从公开 RewardWindow view 投影 STT 失败 / final 字幕输入（display-only）。
func project_utterances_for_display(view: Dictionary = {}) -> Array:
	var utts: Dictionary = _utterances_by_seat
	if not view.is_empty() and view.has("utterances_by_seat") \
			and typeof(view["utterances_by_seat"]) == TYPE_DICTIONARY:
		utts = view["utterances_by_seat"] as Dictionary
	var chars: Array = _character_ids
	if not view.is_empty() and view.has("character_ids") \
			and typeof(view["character_ids"]) == TYPE_ARRAY:
		chars = view["character_ids"] as Array
	var out: Array = []
	for seat in range(4):
		var arr: Array = []
		var raw = utts.get(str(seat), utts.get(seat, []))
		if typeof(raw) == TYPE_ARRAY:
			arr = raw as Array
		if arr.is_empty():
			continue
		# 取最后一条 terminal 记录
		var last_term: Dictionary = {}
		for u in arr:
			if typeof(u) != TYPE_DICTIONARY:
				continue
			if bool((u as Dictionary).get("terminal", true)):
				last_term = u as Dictionary
		if last_term.is_empty():
			continue
		var text := String(last_term.get("text", ""))
		var lang := String(last_term.get("language", "zh"))
		var utt_id := String(last_term.get("utterance_id", "utt_%d" % seat))
		var char_id := ""
		if seat < chars.size():
			char_id = String(chars[seat])
		# 冻结 AI identity：ai|{rule_version}|{window_id}|{seat}
		var source := "server_stt"
		if utt_id.begins_with("ai|"):
			source = "ai_text"
		if text.strip_edges().is_empty():
			out.append({
				"seat": seat,
				"utterance_id": utt_id,
				"text": "转写失败或超时 · 未计分",
				"kind": "final",
				"source": source if source == "ai_text" else "server_stt",
				"lang": lang,
				"stt_failed": true,
				"character_id": char_id,
				"is_reward": false,
			})
		else:
			out.append({
				"seat": seat,
				"utterance_id": utt_id,
				"text": text,
				"kind": "final",
				"source": source,
				"lang": lang,
				"stt_failed": false,
				"character_id": char_id,
				"is_reward": false,
			})
	return out


func silent_seats_from_view(view: Dictionary = {}) -> Array:
	var utts: Dictionary = _utterances_by_seat
	if not view.is_empty() and view.has("utterances_by_seat") \
			and typeof(view["utterances_by_seat"]) == TYPE_DICTIONARY:
		utts = view["utterances_by_seat"] as Dictionary
	var silent: Array = []
	for seat in range(4):
		var raw = utts.get(str(seat), utts.get(seat, []))
		var arr: Array = raw as Array if typeof(raw) == TYPE_ARRAY else []
		if arr.is_empty():
			silent.append(seat)
	return silent


## force_reset=true：同 room 新 hand/authority 无条件清空去重（不依赖 epoch 字符串碰巧变化）。
func begin_source(epoch: String, seat: int = -1, force_reset: bool = false) -> void:
	var ep := String(epoch).strip_edges()
	if force_reset or ep != _source_epoch:
		_source_epoch = ep
		_seen_feedback_seqs.clear()
		_instances.clear()
		_prize_pool = []
		_assignment = {}
		_has_assignment = false
		_last_feedback = {}
		_utterances_by_seat = {}
		_window_id = ""
		_phase = ""
		_window_exit = null
		_discard_count = 0
		_matrix_summary = {}
		_character_ids = []
	elif not ep.is_empty():
		_source_epoch = ep
	if seat >= 0 and seat <= 3:
		_local_seat = seat


## 重连/bootstrap：cursor 由调用方推进；此处绑定 epoch 且可 force 清空 seen。
func mark_feedback_up_to(epoch: String, server_seq: int) -> void:
	# 重连同一 source：不 force_reset 库存视图由 snapshot 恢复；seen 在 bootstrap 后只防历史重放
	if not epoch.is_empty():
		_source_epoch = epoch
	if server_seq < 0:
		return
	_seen_feedback_seqs["%s|%d" % [_source_epoch, server_seq]] = true


## journal 事件反馈：同一 epoch+server_seq 只投影一次。
func ingest_journal_event(
	event: Variant, server_seq: int = -1, epoch: String = ""
) -> Dictionary:
	var ne: NetworkedEvent = _coerce_networked_event(event)
	if ne == null:
		return _reject("SCHEMA_REJECTED")
	if not epoch.is_empty() and epoch != _source_epoch:
		begin_source(epoch, _local_seat)
	var seq: int = server_seq if server_seq >= 0 else int(ne.server_seq)
	var key := "%s|%d" % [_source_epoch, seq]
	if _seen_feedback_seqs.has(key):
		return {"ok": true, "idempotent": true, "reason": "DUPLICATE_SEQ"}
	# 库存真相：ROOM_SNAPSHOT 完整恢复；ITEM_* 增量；SETTLED 不改库存
	var res: Dictionary = ingest(ne)
	if bool(res.get("ok", false)):
		_seen_feedback_seqs[key] = true
	return res


func reset_feedback_seq_cursor() -> void:
	_seen_feedback_seqs.clear()


static func _reject(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
