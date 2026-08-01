class_name RewardItemPayloadCodec extends RefCounted

# ARCH-03 #393：奖励/道具/能力 payload codec —— REWARD_WINDOW_* / ITEM_* /
# CHARACTER_ABILITY_* / SKILL_TRIGGERED。校验语义与拆分前 NetworkedEvent 完全一致。

const SKILL_TRIGGERED_REQUIRED_KEYS := [
	"actor_seat", "beneficiary_seat", "skill_id", "skill_name",
	"source_event", "source_kind", "hand_seq",
]

const SKILL_TRIGGERED_OPTIONAL_KEYS := [
	"han_delta", "extra_dora_delta", "extra_red_dora_delta",
	"item_instance_id", "causation_command_id",
]

const SKILL_TRIGGERED_FORBIDDEN_KEYS := [
	"tiles", "wall_top", "private_hand", "waits", "hand", "wall",
]

const SKILL_TRIGGERED_SOURCE_KINDS := ["character", "relic", "item"]

const SETTLED_OUTCOMES := ["FULL_GRANT", "DISPLAY_ONLY"]

const CANCEL_REASON := "CANCELLED_BY_WIN"


static func validate_reward_opened(p: Dictionary) -> Variant:
	var keys := [
		"window_id", "hand_seq", "window_index", "prize_pool",
		"rule_version", "phase", "window_exit",
	]
	if not EventPayloadCodecUtil._has_exact_keys(p, keys):
		return null
	if not EventPayloadCodecUtil._is_nonempty_string(p["window_id"]):
		return null
	var hand_seq: Variant = EventPayloadCodecUtil._require_hand_seq(p["hand_seq"])
	if hand_seq == null:
		return null
	var window_index: Variant = EventPayloadCodecUtil._require_nonneg_safe_int(p["window_index"])
	if window_index == null:
		return null
	var pool: Variant = _validate_prize_pool(p["prize_pool"])
	if pool == null:
		return null
	if not EventPayloadCodecUtil._is_nonempty_string(p["rule_version"]):
		return null
	if typeof(p["phase"]) != TYPE_STRING or str(p["phase"]) != "OPEN":
		return null
	if p["window_exit"] != null:
		return null
	return {
		"window_id": p["window_id"],
		"hand_seq": int(hand_seq),
		"window_index": int(window_index),
		"prize_pool": pool,
		"rule_version": p["rule_version"],
		"phase": "OPEN",
		"window_exit": null,
	}


static func validate_reward_closing(p: Dictionary, envelope_server_seq: int) -> Variant:
	var keys := [
		"window_id", "hand_seq", "closing_boundary_server_seq",
		"grace_deadline_at", "phase", "window_exit",
	]
	if not EventPayloadCodecUtil._has_exact_keys(p, keys):
		return null
	if not EventPayloadCodecUtil._is_nonempty_string(p["window_id"]):
		return null
	var hand_seq: Variant = EventPayloadCodecUtil._require_hand_seq(p["hand_seq"])
	if hand_seq == null:
		return null
	var boundary: Variant = EventPayloadCodecUtil._require_positive_safe_int(p["closing_boundary_server_seq"])
	if boundary == null:
		return null
	# closing_boundary 必须 ≤ envelope.server_seq
	if int(boundary) > envelope_server_seq:
		return null
	if not EventPayloadCodecUtil._is_nonempty_string(p["grace_deadline_at"]):
		return null
	if typeof(p["phase"]) != TYPE_STRING or str(p["phase"]) != "CLOSING":
		return null
	if p["window_exit"] != null:
		return null
	return {
		"window_id": p["window_id"],
		"hand_seq": int(hand_seq),
		"closing_boundary_server_seq": int(boundary),
		"grace_deadline_at": p["grace_deadline_at"],
		"phase": "CLOSING",
		"window_exit": null,
	}


static func validate_reward_settled(p: Dictionary, envelope_server_seq: int) -> Variant:
	var keys := [
		"window_id", "outcome", "settle_reason", "rule_version",
		"assignment_version", "prize_pool", "matrix_summary", "assignment",
		"closing_boundary_server_seq", "context_boundary_server_seq",
		"grace_deadline_at", "grant_count", "hand_seq", "transcript_summary",
	]
	if not EventPayloadCodecUtil._has_exact_keys(p, keys):
		return null
	if not EventPayloadCodecUtil._is_nonempty_string(p["window_id"]):
		return null
	if typeof(p["outcome"]) != TYPE_STRING:
		return null
	var outcome: String = p["outcome"]
	if outcome not in SETTLED_OUTCOMES:
		return null
	if not EventPayloadCodecUtil._is_nonempty_string(p["settle_reason"]):
		return null
	if not EventPayloadCodecUtil._is_nonempty_string(p["rule_version"]):
		return null
	if not EventPayloadCodecUtil._is_nonempty_string(p["assignment_version"]):
		return null
	var pool: Variant = _validate_prize_pool(p["prize_pool"])
	if pool == null:
		return null
	var matrix_summary: Variant = EventPayloadCodecUtil._validate_opaque_json_dict(p["matrix_summary"])
	if matrix_summary == null:
		return null
	var assignment: Variant = EventPayloadCodecUtil._validate_opaque_json_dict(p["assignment"])
	if assignment == null:
		return null
	var closing_boundary: Variant = EventPayloadCodecUtil._require_positive_safe_int(p["closing_boundary_server_seq"])
	if closing_boundary == null:
		return null
	var context_boundary: Variant = EventPayloadCodecUtil._require_positive_safe_int(p["context_boundary_server_seq"])
	if context_boundary == null:
		return null
	# context 是 CLAIM 完成或无 CLAIM 同事务结果判定序号，不得早于 closing
	if int(context_boundary) < int(closing_boundary):
		return null
	# closing / context 均须 ≤ envelope.server_seq
	if int(closing_boundary) > envelope_server_seq:
		return null
	if int(context_boundary) > envelope_server_seq:
		return null
	if not EventPayloadCodecUtil._is_nonempty_string(p["grace_deadline_at"]):
		return null
	if typeof(p["grant_count"]) != TYPE_INT:
		return null
	var grant_count: int = p["grant_count"]
	if outcome == "FULL_GRANT" and grant_count != 4:
		return null
	if outcome == "DISPLAY_ONLY" and grant_count != 0:
		return null
	var hand_seq: Variant = EventPayloadCodecUtil._require_hand_seq(p["hand_seq"])
	if hand_seq == null:
		return null
	var transcript_summary: Variant = EventPayloadCodecUtil._validate_opaque_json_dict(p["transcript_summary"])
	if transcript_summary == null:
		return null
	return {
		"window_id": p["window_id"],
		"outcome": outcome,
		"settle_reason": p["settle_reason"],
		"rule_version": p["rule_version"],
		"assignment_version": p["assignment_version"],
		"prize_pool": pool,
		"matrix_summary": matrix_summary,
		"assignment": assignment,
		"closing_boundary_server_seq": int(closing_boundary),
		"context_boundary_server_seq": int(context_boundary),
		"grace_deadline_at": p["grace_deadline_at"],
		"grant_count": grant_count,
		"hand_seq": int(hand_seq),
		"transcript_summary": transcript_summary,
	}


static func validate_reward_cancelled(p: Dictionary, envelope_server_seq: int) -> Variant:
	var keys := [
		"window_id", "cancel_reason", "closing_boundary_server_seq",
		"grace_aborted", "scored", "grant_count", "hand_seq",
	]
	if not EventPayloadCodecUtil._has_exact_keys(p, keys):
		return null
	if not EventPayloadCodecUtil._is_nonempty_string(p["window_id"]):
		return null
	if typeof(p["cancel_reason"]) != TYPE_STRING:
		return null
	if str(p["cancel_reason"]) != CANCEL_REASON:
		return null
	var boundary: Variant = p["closing_boundary_server_seq"]
	if boundary != null:
		boundary = EventPayloadCodecUtil._require_positive_safe_int(boundary)
		if boundary == null:
			return null
		# 非 null closing_boundary 必须 ≤ envelope.server_seq
		if int(boundary) > envelope_server_seq:
			return null
	if typeof(p["grace_aborted"]) != TYPE_BOOL:
		return null
	if typeof(p["scored"]) != TYPE_BOOL:
		return null
	if p["scored"] != false:
		return null
	if typeof(p["grant_count"]) != TYPE_INT:
		return null
	if int(p["grant_count"]) != 0:
		return null
	var hand_seq: Variant = EventPayloadCodecUtil._require_hand_seq(p["hand_seq"])
	if hand_seq == null:
		return null
	return {
		"window_id": p["window_id"],
		"cancel_reason": CANCEL_REASON,
		"closing_boundary_server_seq": boundary,
		"grace_aborted": p["grace_aborted"],
		"scored": false,
		"grant_count": 0,
		"hand_seq": int(hand_seq),
	}


static func validate_item_granted(p: Dictionary) -> Variant:
	var keys := [
		"window_id", "rule_version", "assignment_version", "matched_rule_ids",
		"item_id", "item_instance_id", "seat", "hand_seq", "score",
		"affinity_match", "armed_for_window_id",
	]
	if not EventPayloadCodecUtil._has_exact_keys(p, keys):
		return null
	if not EventPayloadCodecUtil._is_nonempty_string(p["window_id"]):
		return null
	if not EventPayloadCodecUtil._is_nonempty_string(p["rule_version"]):
		return null
	if not EventPayloadCodecUtil._is_nonempty_string(p["assignment_version"]):
		return null
	if typeof(p["matched_rule_ids"]) != TYPE_ARRAY:
		return null
	var matched: Array = []
	for item in p["matched_rule_ids"]:
		if not EventPayloadCodecUtil._is_nonempty_string(item):
			return null
		matched.append(item)
	if not EventPayloadCodecUtil._is_nonempty_string(p["item_id"]):
		return null
	if not EventPayloadCodecUtil._is_nonempty_string(p["item_instance_id"]):
		return null
	if typeof(p["seat"]) != TYPE_INT:
		return null
	var seat_id: int = p["seat"]
	if seat_id < 0 or seat_id > 3:
		return null
	var hand_seq: Variant = EventPayloadCodecUtil._require_hand_seq(p["hand_seq"])
	if hand_seq == null:
		return null
	var score: Variant = EventPayloadCodecUtil._require_nonneg_safe_int(p["score"])
	if score == null:
		return null
	if typeof(p["affinity_match"]) != TYPE_BOOL:
		return null
	var armed = p["armed_for_window_id"]
	if armed != null and not EventPayloadCodecUtil._is_nonempty_string(armed):
		return null
	return {
		"window_id": p["window_id"],
		"rule_version": p["rule_version"],
		"assignment_version": p["assignment_version"],
		"matched_rule_ids": matched.duplicate(),
		"item_id": p["item_id"],
		"item_instance_id": p["item_instance_id"],
		"seat": seat_id,
		"hand_seq": int(hand_seq),
		"score": int(score),
		"affinity_match": p["affinity_match"],
		"armed_for_window_id": armed,
	}


static func validate_item_consumed(p: Dictionary) -> Variant:
	if not EventPayloadCodecUtil._has_exact_keys(p, ["seat", "item_id", "item_instance_id", "command_id"]):
		return null
	if typeof(p["seat"]) != TYPE_INT:
		return null
	var seat_id: int = p["seat"]
	if seat_id < 0 or seat_id > 3:
		return null
	if not EventPayloadCodecUtil._is_nonempty_string(p["item_id"]):
		return null
	if not EventPayloadCodecUtil._is_nonempty_string(p["item_instance_id"]):
		return null
	if typeof(p["command_id"]) != TYPE_STRING:
		return null
	var cmd: String = p["command_id"]
	if not ProtocolUuid.is_canonical_v4(cmd):
		return null
	return {
		"seat": seat_id,
		"item_id": p["item_id"],
		"item_instance_id": p["item_instance_id"],
		"command_id": cmd,
	}


static func validate_item_applied(p: Dictionary) -> Variant:
	if not EventPayloadCodecUtil._has_exact_keys(p, ["seat", "item_id", "item_instance_id", "effect_id", "command_id"]):
		return null
	if typeof(p["seat"]) != TYPE_INT:
		return null
	var seat_id: int = p["seat"]
	if seat_id < 0 or seat_id > 3:
		return null
	if not EventPayloadCodecUtil._is_nonempty_string(p["item_id"]):
		return null
	if not EventPayloadCodecUtil._is_nonempty_string(p["item_instance_id"]):
		return null
	if not EventPayloadCodecUtil._is_nonempty_string(p["effect_id"]):
		return null
	if typeof(p["command_id"]) != TYPE_STRING:
		return null
	var cmd: String = p["command_id"]
	if not ProtocolUuid.is_canonical_v4(cmd):
		return null
	return {
		"seat": seat_id,
		"item_id": p["item_id"],
		"item_instance_id": p["item_instance_id"],
		"effect_id": p["effect_id"],
		"command_id": cmd,
	}


static func validate_ability_armed(p: Dictionary) -> Variant:
	if not EventPayloadCodecUtil._has_exact_keys(p, ["seat", "window_id", "character_id", "ability_id", "active_window_id"]):
		return null
	if typeof(p["seat"]) != TYPE_INT:
		return null
	var seat_id: int = p["seat"]
	if seat_id < 0 or seat_id > 3:
		return null
	if not EventPayloadCodecUtil._is_nonempty_string(p["window_id"]):
		return null
	if not EventPayloadCodecUtil._is_nonempty_string(p["character_id"]):
		return null
	if not EventPayloadCodecUtil._is_nonempty_string(p["ability_id"]):
		return null
	if not EventPayloadCodecUtil._is_nonempty_string(p["active_window_id"]):
		return null
	return {
		"seat": seat_id,
		"window_id": p["window_id"],
		"character_id": p["character_id"],
		"ability_id": p["ability_id"],
		"active_window_id": p["active_window_id"],
	}


static func validate_ability_disarmed(p: Dictionary) -> Variant:
	if not EventPayloadCodecUtil._has_exact_keys(p, ["seat", "window_id", "character_id", "ability_id", "active_window_id"]):
		return null
	if typeof(p["seat"]) != TYPE_INT:
		return null
	var seat_id: int = p["seat"]
	if seat_id < 0 or seat_id > 3:
		return null
	if not EventPayloadCodecUtil._is_nonempty_string(p["window_id"]):
		return null
	if not EventPayloadCodecUtil._is_nonempty_string(p["character_id"]):
		return null
	if not EventPayloadCodecUtil._is_nonempty_string(p["ability_id"]):
		return null
	var active = p["active_window_id"]
	if active != null and not EventPayloadCodecUtil._is_nonempty_string(active):
		return null
	return {
		"seat": seat_id,
		"window_id": p["window_id"],
		"character_id": p["character_id"],
		"ability_id": p["ability_id"],
		"active_window_id": active,
	}


## #379：技能公开归因。仅允许最小公开字段 + 可选 delta；拒绝私有牌面/墙/听牌字段。


## #379：技能公开归因。仅允许最小公开字段 + 可选 delta；拒绝私有牌面/墙/听牌字段。
static func validate_skill_triggered(p: Dictionary) -> Variant:
	for bad in SKILL_TRIGGERED_FORBIDDEN_KEYS:
		if p.has(bad):
			return null
	for req in SKILL_TRIGGERED_REQUIRED_KEYS:
		if not p.has(req):
			return null
	# 禁止未知键
	for k in p.keys():
		var ks := str(k)
		if ks in SKILL_TRIGGERED_REQUIRED_KEYS:
			continue
		if ks in SKILL_TRIGGERED_OPTIONAL_KEYS:
			continue
		return null
	if typeof(p["actor_seat"]) != TYPE_INT:
		return null
	var actor: int = p["actor_seat"]
	if actor < 0 or actor > 3:
		return null
	if typeof(p["beneficiary_seat"]) != TYPE_INT:
		return null
	var ben: int = p["beneficiary_seat"]
	if ben < 0 or ben > 3:
		return null
	if not EventPayloadCodecUtil._is_nonempty_string(p["skill_id"]):
		return null
	if typeof(p["skill_name"]) != TYPE_STRING:
		return null
	if not EventPayloadCodecUtil._is_nonempty_string(p["source_event"]):
		return null
	if typeof(p["source_kind"]) != TYPE_STRING:
		return null
	var skind: String = p["source_kind"]
	if skind not in SKILL_TRIGGERED_SOURCE_KINDS:
		return null
	var hand_seq: Variant = EventPayloadCodecUtil._require_hand_seq(p["hand_seq"])
	if hand_seq == null:
		return null
	var out := {
		"actor_seat": actor,
		"beneficiary_seat": ben,
		"skill_id": str(p["skill_id"]),
		"skill_name": str(p["skill_name"]),
		"source_event": str(p["source_event"]),
		"source_kind": skind,
		"hand_seq": int(hand_seq),
	}
	if p.has("han_delta"):
		if typeof(p["han_delta"]) != TYPE_INT:
			return null
		out["han_delta"] = int(p["han_delta"])
	if p.has("extra_dora_delta"):
		if typeof(p["extra_dora_delta"]) != TYPE_INT:
			return null
		out["extra_dora_delta"] = int(p["extra_dora_delta"])
	if p.has("extra_red_dora_delta"):
		if typeof(p["extra_red_dora_delta"]) != TYPE_INT:
			return null
		out["extra_red_dora_delta"] = int(p["extra_red_dora_delta"])
	if p.has("item_instance_id"):
		if not EventPayloadCodecUtil._is_nonempty_string(p["item_instance_id"]):
			return null
		out["item_instance_id"] = str(p["item_instance_id"])
	if p.has("causation_command_id"):
		if typeof(p["causation_command_id"]) != TYPE_STRING:
			return null
		var causation: String = p["causation_command_id"]
		if not ProtocolUuid.is_canonical_v4(causation):
			return null
		out["causation_command_id"] = causation
	return out


static func _validate_prize_pool(raw: Variant) -> Variant:
	if typeof(raw) != TYPE_ARRAY:
		return null
	var arr: Array = raw
	if arr.size() != 4:
		return null
	var seen: Dictionary = {}
	var out: Array = []
	for item in arr:
		if not EventPayloadCodecUtil._is_nonempty_string(item):
			return null
		var s: String = item
		if seen.has(s):
			return null
		seen[s] = true
		out.append(s)
	return out


# ---- helpers ----
