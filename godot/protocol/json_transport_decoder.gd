extends RefCounted

# E2 JSON transport decoder：JSON 数字 → 冻结 schema 已知 int 路径安全转换，再交 DTO。
# 无 class_name；静态 API only。
# 不得用字符串转数字；E5 opaque 摘要同样只允许 JSON-safe 整数域。

static func decode_action(json_text: String) -> Action:
	var root: Variant = _parse_root_dict(json_text)
	if root == null:
		return null
	var d: Dictionary = (root as Dictionary).duplicate(true)
	if not _convert_action_ints(d):
		return null
	return Action.from_dict(d)


static func decode_event(json_text: String) -> NetworkedEvent:
	var root: Variant = _parse_root_dict(json_text)
	if root == null:
		return null
	var d: Dictionary = (root as Dictionary).duplicate(true)
	if not _convert_event_ints(d):
		return null
	return NetworkedEvent.from_dict(d)


static func decode_command_result(json_text: String) -> CommandResult:
	var root: Variant = _parse_root_dict(json_text)
	if root == null:
		return null
	var d: Dictionary = (root as Dictionary).duplicate(true)
	if not _convert_command_result_ints(d):
		return null
	return CommandResult.from_dict(d)


# JSON.parse_string 对坏输入会打印引擎 ERROR；公网坏帧用 JSON.parse 静默失败。
static func _parse_root_dict(json_text: String) -> Variant:
	var json := JSON.new()
	if json.parse(json_text) != OK:
		return null
	var root: Variant = json.data
	if typeof(root) != TYPE_DICTIONARY:
		return null
	return root


# ---- 安全 int 转换 ----

static func _safe_to_int(value: Variant) -> Variant:
	var t := typeof(value)
	if t == TYPE_INT:
		var n: int = value
		if n < -ProtocolConstants.MAX_SAFE_INT or n > ProtocolConstants.MAX_SAFE_INT:
			return null
		return n
	if t == TYPE_FLOAT:
		var f: float = value
		if not is_finite(f):
			return null
		if f != floor(f):
			return null
		if abs(f) > ProtocolConstants.MAX_SAFE_INT:
			return null
		return int(f)
	return null


static func _set_int_field(d: Dictionary, key: String) -> bool:
	if not d.has(key):
		return true
	var converted: Variant = _safe_to_int(d[key])
	if converted == null:
		return false
	d[key] = converted
	return true


static func _set_nullable_int_field(d: Dictionary, key: String) -> bool:
	if not d.has(key):
		return true
	if d[key] == null:
		return true
	return _set_int_field(d, key)


static func _convert_int_array_field(d: Dictionary, key: String) -> bool:
	if not d.has(key):
		return true
	if typeof(d[key]) != TYPE_ARRAY:
		return true
	var arr: Array = d[key]
	for i in range(arr.size()):
		var converted: Variant = _safe_to_int(arr[i])
		if converted == null:
			return false
		arr[i] = converted
	return true


static func _convert_json_safe_value(value: Variant) -> Array:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_STRING:
			return [true, value]
		TYPE_INT, TYPE_FLOAT:
			var converted: Variant = _safe_to_int(value)
			return [converted != null, converted]
		TYPE_ARRAY:
			var arr: Array = value
			for i in range(arr.size()):
				var item_result: Array = _convert_json_safe_value(arr[i])
				if not bool(item_result[0]):
					return [false, null]
				arr[i] = item_result[1]
			return [true, arr]
		TYPE_DICTIONARY:
			var dict_value: Dictionary = value
			for key_variant in dict_value.keys():
				if typeof(key_variant) != TYPE_STRING:
					return [false, null]
				var child_result: Array = _convert_json_safe_value(dict_value[key_variant])
				if not bool(child_result[0]):
					return [false, null]
				dict_value[key_variant] = child_result[1]
			return [true, dict_value]
		_:
			return [false, null]


static func _convert_opaque_dict_field(d: Dictionary, key: String) -> bool:
	if not d.has(key):
		return true
	if typeof(d[key]) != TYPE_DICTIONARY:
		return true
	var result: Array = _convert_json_safe_value(d[key])
	if not bool(result[0]):
		return false
	d[key] = result[1]
	return true


# ---- Action 已知 int 路径 ----

static func _convert_action_ints(d: Dictionary) -> bool:
	if not _set_int_field(d, "protocol_version"):
		return false
	if not _set_int_field(d, "seat"):
		return false
	if not _set_int_field(d, "hand_seq"):
		return false
	if not _set_int_field(d, "client_seq"):
		return false
	if not d.has("payload") or typeof(d["payload"]) != TYPE_DICTIONARY:
		return true
	var kind_str := ""
	if d.has("kind") and typeof(d["kind"]) == TYPE_STRING:
		kind_str = d["kind"]
	return _convert_action_payload_ints(d["payload"], kind_str)


static func _convert_action_payload_ints(payload: Dictionary, kind_str: String) -> bool:
	match kind_str:
		"DISCARD", "RIICHI":
			return _set_int_field(payload, "tile_instance_id")
		"CHI", "PON":
			return _convert_int_array_field(payload, "companion_tile_instance_ids")
		"KAN":
			var kan_kind := ""
			if payload.has("kan_kind") and typeof(payload["kan_kind"]) == TYPE_STRING:
				kan_kind = payload["kan_kind"]
			match kan_kind:
				"MINKAN":
					return _convert_int_array_field(payload, "companion_tile_instance_ids")
				"ANKAN":
					return _convert_int_array_field(payload, "tile_instance_ids")
				"ADDED_KAN":
					if not _set_int_field(payload, "meld_id"):
						return false
					return _set_int_field(payload, "added_tile_instance_id")
				_:
					return true
		_:
			return true


# ---- CommandResult 已知 int 路径 ----

static func _convert_command_result_ints(d: Dictionary) -> bool:
	if not _set_int_field(d, "protocol_version"):
		return false
	return _set_int_field(d, "server_seq")


# ---- Event 已知 int 路径 ----

static func _convert_event_ints(d: Dictionary) -> bool:
	if not _set_int_field(d, "protocol_version"):
		return false
	if not _set_int_field(d, "server_seq"):
		return false
	if not d.has("payload") or typeof(d["payload"]) != TYPE_DICTIONARY:
		return true
	var kind_str := ""
	if d.has("kind") and typeof(d["kind"]) == TYPE_STRING:
		kind_str = d["kind"]
	return _convert_event_payload_ints(d["payload"], kind_str)


static func _convert_event_payload_ints(payload: Dictionary, kind_str: String) -> bool:
	match kind_str:
		"ACTION_APPLIED":
			if not _set_int_field(payload, "hand_seq"):
				return false
			if not _set_int_field(payload, "seat"):
				return false
			if not payload.has("resolved_payload") or typeof(payload["resolved_payload"]) != TYPE_DICTIONARY:
				return true
			var action_kind := ""
			if payload.has("action_kind") and typeof(payload["action_kind"]) == TYPE_STRING:
				action_kind = payload["action_kind"]
			return _convert_resolved_payload_ints(payload["resolved_payload"], action_kind)
		"TURN_PROMPT":
			return _convert_turn_prompt_ints(payload)
		"CLAIM_WINDOW":
			return _convert_claim_window_ints(payload)
		"REWARD_WINDOW_OPENED":
			if not _set_int_field(payload, "hand_seq"):
				return false
			return _set_int_field(payload, "window_index")
		"REWARD_WINDOW_CLOSING":
			if not _set_int_field(payload, "hand_seq"):
				return false
			return _set_int_field(payload, "closing_boundary_server_seq")
		"REWARD_WINDOW_SETTLED":
			if not _set_int_field(payload, "closing_boundary_server_seq"):
				return false
			if not _set_int_field(payload, "context_boundary_server_seq"):
				return false
			if not _set_int_field(payload, "grant_count"):
				return false
			if not _set_int_field(payload, "hand_seq"):
				return false
			for opaque_key in ["matrix_summary", "assignment", "transcript_summary"]:
				if not _convert_opaque_dict_field(payload, opaque_key):
					return false
			return true
		"REWARD_WINDOW_CANCELLED":
			if not _set_nullable_int_field(payload, "closing_boundary_server_seq"):
				return false
			if not _set_int_field(payload, "grant_count"):
				return false
			return _set_int_field(payload, "hand_seq")
		"ITEM_GRANTED":
			if not _set_int_field(payload, "seat"):
				return false
			if not _set_int_field(payload, "hand_seq"):
				return false
			return _set_int_field(payload, "score")
		"ITEM_CONSUMED", "ITEM_APPLIED", "CHARACTER_ABILITY_ARMED", "CHARACTER_ABILITY_DISARMED":
			return _set_int_field(payload, "seat")
		"ROOM_SNAPSHOT":
			return _convert_room_snapshot_ints(payload)
		"PLAYER_JOINED":
			return _set_int_field(payload, "seat")
		"HAND_SETTLED":
			if not _set_int_field(payload, "hand_seq"):
				return false
			if not _convert_int_array_field(payload, "winner_seats"):
				return false
			if not _set_int_field(payload, "loser_seat"):
				return false
			if not _convert_int_array_field(payload, "score_deltas"):
				return false
			return _convert_int_array_field(payload, "scores")
		"MATCH_SETTLED":
			if not _convert_int_array_field(payload, "final_scores"):
				return false
			return _convert_int_array_field(payload, "seat_order")
		_:
			return true


static func _convert_resolved_payload_ints(rp: Dictionary, action_kind: String) -> bool:
	match action_kind:
		"DISCARD", "RIICHI":
			if rp.has("tile") and typeof(rp["tile"]) == TYPE_DICTIONARY:
				if not _convert_tile_view_ints(rp["tile"]):
					return false
			return true
		"CHI", "PON", "KAN":
			if rp.has("meld") and typeof(rp["meld"]) == TYPE_DICTIONARY:
				return _convert_meld_view_ints(rp["meld"])
			return true
		"RON":
			if rp.has("winning_tile") and typeof(rp["winning_tile"]) == TYPE_DICTIONARY:
				if not _convert_tile_view_ints(rp["winning_tile"]):
					return false
			return _set_int_field(rp, "from_seat")
		"TSUMO":
			if rp.has("winning_tile") and typeof(rp["winning_tile"]) == TYPE_DICTIONARY:
				return _convert_tile_view_ints(rp["winning_tile"])
			return true
		_:
			return true


static func _convert_turn_prompt_ints(payload: Dictionary) -> bool:
	if not _set_int_field(payload, "hand_seq"):
		return false
	if not _set_int_field(payload, "seat"):
		return false
	if not _set_int_field(payload, "last_drawn_tile_instance_id"):
		return false
	if payload.has("hand") and typeof(payload["hand"]) == TYPE_ARRAY:
		for item in payload["hand"]:
			if typeof(item) != TYPE_DICTIONARY:
				continue
			if not _convert_tile_view_ints(item):
				return false
	return _convert_allowed_actions_ints(payload.get("allowed_actions", null))


static func _convert_claim_window_ints(payload: Dictionary) -> bool:
	if not _set_int_field(payload, "hand_seq"):
		return false
	if not _set_int_field(payload, "discarded_by_seat"):
		return false
	if payload.has("discarded_tile") and typeof(payload["discarded_tile"]) == TYPE_DICTIONARY:
		if not _convert_tile_view_ints(payload["discarded_tile"]):
			return false
	return _convert_allowed_actions_ints(payload.get("allowed_actions", null))


static func _convert_allowed_actions_ints(raw: Variant) -> bool:
	if typeof(raw) != TYPE_ARRAY:
		return true
	for offer in raw:
		if typeof(offer) != TYPE_DICTIONARY:
			continue
		var od: Dictionary = offer
		var offer_kind := ""
		if od.has("kind") and typeof(od["kind"]) == TYPE_STRING:
			offer_kind = od["kind"]
		if not od.has("payload_options") or typeof(od["payload_options"]) != TYPE_ARRAY:
			continue
		for opt in od["payload_options"]:
			if typeof(opt) != TYPE_DICTIONARY:
				continue
			if not _convert_action_payload_ints(opt, offer_kind):
				return false
	return true


static func _convert_tile_view_ints(tv: Dictionary) -> bool:
	if not _set_int_field(tv, "instance_id"):
		return false
	if not _set_int_field(tv, "tile_id"):
		return false
	return _set_int_field(tv, "owner_seat")


static func _convert_meld_view_ints(mv: Dictionary) -> bool:
	if not _set_int_field(mv, "meld_id"):
		return false
	if not _set_int_field(mv, "from_seat"):
		return false
	if not _set_int_field(mv, "called_tile_instance_id"):
		return false
	if not _set_int_field(mv, "added_tile_instance_id"):
		return false
	if mv.has("tiles") and typeof(mv["tiles"]) == TYPE_ARRAY:
		for item in mv["tiles"]:
			if typeof(item) != TYPE_DICTIONARY:
				continue
			if not _convert_tile_view_ints(item):
				return false
	return true


# ---- ROOM_SNAPSHOT 模块化 + 严格 recipient DTO ----

static func _convert_room_snapshot_ints(payload: Dictionary) -> bool:
	if not _set_int_field(payload, "snapshot_server_seq"):
		return false
	if not _set_int_field(payload, "next_server_seq"):
		return false
	if not _set_int_field(payload, "seat_view"):
		return false
	if not payload.has("modules") or typeof(payload["modules"]) != TYPE_ARRAY:
		return true
	for item in payload["modules"]:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var md: Dictionary = item
		if not _set_int_field(md, "schema_version"):
			return false
		var mkey := ""
		if md.has("module_key") and typeof(md["module_key"]) == TYPE_STRING:
			mkey = md["module_key"]
		if not md.has("payload"):
			continue
		if mkey == "core_table":
			var sver: Variant = md.get("schema_version")
			if typeof(sver) == TYPE_INT and int(sver) == 1:
				if typeof(md["payload"]) == TYPE_DICTIONARY:
					if not _convert_core_table_ints(md["payload"]):
						return false
		elif mkey == "viewer_next_draw" \
				and typeof(md.get("schema_version")) == TYPE_INT \
				and int(md["schema_version"]) == 1:
			if typeof(md["payload"]) == TYPE_DICTIONARY \
					and not _convert_viewer_next_draw_ints(md["payload"]):
				return false
		else:
			var pl: Variant = md["payload"]
			if typeof(pl) == TYPE_FLOAT:
				var converted: Variant = _safe_to_int(pl)
				if converted == null:
					return false
				md["payload"] = converted
			elif not _convert_unknown_module_payload_ints(pl):
				return false
	return true


static func _convert_core_table_ints(core: Dictionary) -> bool:
	if not _set_int_field(core, "recipient_seat"):
		return false
	if not _set_int_field(core, "hand_seq"):
		return false
	if not _set_int_field(core, "dealer_seat"):
		return false
	if not _set_int_field(core, "current_seat"):
		return false
	if not _set_int_field(core, "round_wind"):
		return false
	if not _set_int_field(core, "hand_number"):
		return false
	if not _set_int_field(core, "honba"):
		return false
	if not _set_int_field(core, "riichi_sticks"):
		return false
	if not _set_int_field(core, "live_wall_count"):
		return false
	if core.has("dora_indicators") and typeof(core["dora_indicators"]) == TYPE_ARRAY:
		for item in core["dora_indicators"]:
			if typeof(item) != TYPE_DICTIONARY:
				continue
			if not _convert_tile_view_ints(item):
				return false
	if core.has("seats") and typeof(core["seats"]) == TYPE_ARRAY:
		for item in core["seats"]:
			if typeof(item) != TYPE_DICTIONARY:
				continue
			if not _convert_seat_view_ints(item):
				return false
	return true


static func _convert_viewer_next_draw_ints(payload: Dictionary) -> bool:
	if not _set_int_field(payload, "recipient_seat"):
		return false
	if not _set_int_field(payload, "hand_seq"):
		return false
	if payload.has("tile") and typeof(payload["tile"]) == TYPE_DICTIONARY:
		return _convert_tile_view_ints(payload["tile"])
	return true


static func _convert_seat_view_ints(sv: Dictionary) -> bool:
	if not _set_int_field(sv, "seat"):
		return false
	if not _set_int_field(sv, "seat_wind"):
		return false
	if not _set_int_field(sv, "score"):
		return false
	if not _set_int_field(sv, "concealed_count"):
		return false
	if not _set_int_field(sv, "last_drawn_tile_instance_id"):
		return false
	if not _set_int_field(sv, "riichi_discard_index"):
		return false
	if sv.has("concealed_tiles") and typeof(sv["concealed_tiles"]) == TYPE_ARRAY:
		for item in sv["concealed_tiles"]:
			if typeof(item) != TYPE_DICTIONARY:
				continue
			if not _convert_tile_view_ints(item):
				return false
	if sv.has("river") and typeof(sv["river"]) == TYPE_ARRAY:
		for item in sv["river"]:
			if typeof(item) != TYPE_DICTIONARY:
				continue
			if not _convert_tile_view_ints(item):
				return false
	if sv.has("melds") and typeof(sv["melds"]) == TYPE_ARRAY:
		for item in sv["melds"]:
			if typeof(item) != TYPE_DICTIONARY:
				continue
			if not _convert_meld_view_ints(item):
				return false
	return true


## unknown module：只递归将安全整数 float→int；不解释业务键、不排序数组。
static func _convert_unknown_module_payload_ints(payload: Variant) -> bool:
	var t := typeof(payload)
	if t == TYPE_DICTIONARY:
		var d: Dictionary = payload
		for k in d.keys():
			var val: Variant = d[k]
			var vt := typeof(val)
			if vt == TYPE_FLOAT:
				var converted: Variant = _safe_to_int(val)
				if converted == null:
					return false
				d[k] = converted
			elif vt == TYPE_DICTIONARY or vt == TYPE_ARRAY:
				if not _convert_unknown_module_payload_ints(val):
					return false
		return true
	if t == TYPE_ARRAY:
		var arr: Array = payload
		for i in range(arr.size()):
			var val: Variant = arr[i]
			var vt := typeof(val)
			if vt == TYPE_FLOAT:
				var converted: Variant = _safe_to_int(val)
				if converted == null:
					return false
				arr[i] = converted
			elif vt == TYPE_DICTIONARY or vt == TYPE_ARRAY:
				if not _convert_unknown_module_payload_ints(val):
					return false
		return true
	# int / bool / string / null 等保持原样
	return true
