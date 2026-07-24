class_name TrashTalkContextScorer extends RefCounted

# E5-03 / #251：4 席 × 4 道具确定性整数评分矩阵。
# 纯函数；练习场本地权威与未来公共 Worker 共用。
# 不选择出口、不分配、不发奖；不调用 LLM / 浮点 / Momentum.skill_effect_multiplier()。
# 禁止客户端自报 public_context_tags_active；标签只从权威公开事件/初始态派生。

const WINDOW_EXIT_FULL_GRANT := "FULL_GRANT"
const WINDOW_EXIT_DISPLAY_ONLY := "DISPLAY_ONLY"
const WINDOW_EXIT_CANCELLED := "CANCELLED_BY_WIN"

const ALLOWED_EXITS: Array[String] = [
	WINDOW_EXIT_FULL_GRANT,
	WINDOW_EXIT_DISPLAY_ONLY,
	WINDOW_EXIT_CANCELLED,
]

const ALLOWED_LANGS: Array[String] = ["zh", "en", "ja"]


## 主入口。CANCELLED_BY_WIN 或非法输入 → {ok:false, reason:...} 且无矩阵行。
## FULL_GRANT / DISPLAY_ONLY 对相同评分字段生成字节级相同矩阵。
static func score_matrix(input: Dictionary) -> Dictionary:
	if typeof(input) != TYPE_DICTIONARY or input.is_empty():
		return _reject("INVALID_INPUT")

	var exit_v: Variant = input.get("window_exit", null)
	if typeof(exit_v) != TYPE_STRING and typeof(exit_v) != TYPE_STRING_NAME:
		return _reject("INVALID_WINDOW_EXIT")
	var window_exit := String(exit_v)
	if not ALLOWED_EXITS.has(window_exit):
		return _reject("INVALID_WINDOW_EXIT")
	if window_exit == WINDOW_EXIT_CANCELLED:
		return _reject(WINDOW_EXIT_CANCELLED)

	var rv_v: Variant = input.get("rule_version", null)
	if typeof(rv_v) != TYPE_STRING and typeof(rv_v) != TYPE_STRING_NAME:
		return _reject("INVALID_RULE_VERSION")
	var rule_version := String(rv_v)
	if rule_version != TrashTalkRuleCatalog.rule_version():
		return _reject("RULE_VERSION_MISMATCH")

	var window_v: Variant = input.get("window_id", null)
	if typeof(window_v) != TYPE_STRING and typeof(window_v) != TYPE_STRING_NAME:
		return _reject("INVALID_WINDOW_ID")
	var window_id := String(window_v).strip_edges()
	if window_id.is_empty():
		return _reject("INVALID_WINDOW_ID")

	if not _is_int(input.get("closing_boundary_server_seq", null)):
		return _reject("INVALID_CLOSING_BOUNDARY")
	if not _is_int(input.get("context_boundary_server_seq", null)):
		return _reject("INVALID_CONTEXT_BOUNDARY")
	var closing: int = int(input["closing_boundary_server_seq"])
	var context: int = int(input["context_boundary_server_seq"])
	if closing < 0 or context < 0 or context < closing:
		return _reject("INVALID_BOUNDARIES")

	if not _is_int(input.get("hand_seq", null)):
		return _reject("INVALID_HAND_SEQ")
	var hand_seq: int = int(input["hand_seq"])
	if hand_seq < 0:
		return _reject("INVALID_HAND_SEQ")

	var room_v: Variant = input.get("room_id", null)
	if typeof(room_v) != TYPE_STRING and typeof(room_v) != TYPE_STRING_NAME:
		return _reject("INVALID_ROOM_ID")
	var room_id := String(room_v).strip_edges()
	if room_id.is_empty():
		return _reject("INVALID_ROOM_ID")

	var character_ids := _normalize_character_ids(input.get("character_ids", null))
	if character_ids.is_empty():
		return _reject("INVALID_CHARACTER_IDS")

	var pool := _normalize_pool_item_ids(input.get("pool_item_ids", null))
	if pool.is_empty():
		return _reject("INVALID_POOL")

	var language_raw: Variant = input.get("language", null)
	var language := ""
	if language_raw != null:
		language = _require_lang(language_raw)
		if language == "":
			return _reject("INVALID_LANGUAGE")

	# 禁止客户端自报标签：忽略/不读取 public_context_tags_active
	# public_initial 必须严格白名单且 hand_seq 与窗口一致
	var seat_tag_result: Dictionary = _resolve_seat_tags(
		input, room_id, hand_seq, closing, context
	)
	if not bool(seat_tag_result.get("ok", false)):
		return _reject(String(seat_tag_result.get("reason", "INVALID_PUBLIC_INITIAL")))
	var seat_tag_map: Dictionary = seat_tag_result["seat_tags"]
	var global_tags: Array = _collect_global_tags(seat_tag_map)

	var utt_result: Dictionary = _normalize_utterances_by_seat(
		input.get("utterances_by_seat", null),
		closing,
		language
	)
	if not bool(utt_result.get("ok", false)):
		return _reject(String(utt_result.get("reason", "INVALID_UTTERANCES")))
	var utterances_by_seat: Dictionary = utt_result["utterances"]

	var matrix: Array = []
	var matched_by_seat: Dictionary = {"0": [], "1": [], "2": [], "3": []}

	for seat in range(4):
		var character_id := String(character_ids[seat])
		var utts: Array = utterances_by_seat.get(str(seat), [])
		var has_activity := _seat_has_text_activity(utts)

		var features: Dictionary = {}
		if utts.is_empty():
			features = _empty_features()
		else:
			var seat_lang := language
			if seat_lang == "":
				# 每条 utterance 已解析 language
				seat_lang = String(utts[0].get("language", ""))
			if not ALLOWED_LANGS.has(seat_lang):
				return _reject("INVALID_LANGUAGE")
			features = TextAnalyzer.accumulate_window({
				"rule_version": rule_version,
				"window_id": window_id,
				"seat": seat,
				"character_id": character_id,
				"language": seat_lang,
				"utterances": utts,
			})
			if features.is_empty():
				# 有 utterance 却被 Analyzer 拒绝 → 整窗拒绝（非法语言/冲突等）
				return _reject("TEXT_ANALYZE_REJECTED")

		var seat_tags: Array = seat_tag_map.get(str(seat), [])
		var seat_base := _score_seat_base_components(
			features, character_id, has_activity, seat_tags
		)

		# 席位级规则（persona/expression/public_context）固定；item 规则不得跨 cell 污染
		var seat_base_matched: Dictionary = {}
		for rid in seat_base["matched_rule_ids"]:
			seat_base_matched[String(rid)] = true
		var seat_union: Dictionary = seat_base_matched.duplicate()

		for item_id in pool:
			var item_part: Dictionary = _score_item_tag(
				String(item_id),
				features,
				character_id,
				has_activity,
				seat_tags
			)
			var persona: int = int(seat_base["persona"])
			var expression: int = int(seat_base["expression"])
			var public_context: int = int(seat_base["public_context"])
			var item_tag: int = int(item_part["item_tag"])
			var cell_matched: Dictionary = seat_base_matched.duplicate()
			for rid2 in item_part["matched_rule_ids"]:
				var rs := String(rid2)
				cell_matched[rs] = true
				seat_union[rs] = true
			var matched_ids: Array = cell_matched.keys()
			matched_ids.sort()
			var total: int = persona + item_tag + public_context + expression
			if total > 4000:
				total = 4000
			matrix.append({
				"seat": seat,
				"item_id": String(item_id),
				"persona": persona,
				"item_tag": item_tag,
				"public_context": public_context,
				"expression": expression,
				"total_score": total,
				"matched_rule_ids": matched_ids,
			})

		var seat_ids: Array = seat_union.keys()
		seat_ids.sort()
		matched_by_seat[str(seat)] = seat_ids

	return {
		"ok": true,
		"rule_version": rule_version,
		"window_id": window_id,
		"hand_seq": hand_seq,
		"room_id": room_id,
		"window_exit": window_exit,
		"closing_boundary_server_seq": closing,
		"context_boundary_server_seq": context,
		"pool_item_ids": pool,
		"public_context_tags_active": global_tags,
		"matrix": matrix,
		"matched_rule_ids_by_seat": matched_by_seat,
	}


static func _score_seat_base_components(
	features: Dictionary,
	character_id: String,
	has_activity: bool,
	seat_tags: Array
) -> Dictionary:
	var matched_text: Dictionary = {}
	for rid in features.get("matched_rule_ids", []):
		matched_text[String(rid)] = true

	var persona := 0
	var expression := 0
	var public_context := 0
	var contrib: Dictionary = {}

	for rule in TrashTalkRuleCatalog.persona_rules():
		if typeof(rule) != TYPE_DICTIONARY:
			continue
		var rid := String(rule.get("rule_id", ""))
		if rid.is_empty() or not matched_text.has(rid):
			continue
		if String(rule.get("component", "")) != "persona":
			continue
		persona = mini(1000, persona + _clamped_points(rule))
		contrib[rid] = true

	for rule2 in TrashTalkRuleCatalog.expression_rules():
		if typeof(rule2) != TYPE_DICTIONARY:
			continue
		var rid2 := String(rule2.get("rule_id", ""))
		if rid2.is_empty() or not matched_text.has(rid2):
			continue
		if String(rule2.get("component", "")) != "expression":
			continue
		expression = mini(1000, expression + _clamped_points(rule2))
		contrib[rid2] = true

	if has_activity:
		var active: Dictionary = {}
		for t in seat_tags:
			active[String(t)] = true
		for rule3 in TrashTalkRuleCatalog.public_context_rules():
			if typeof(rule3) != TYPE_DICTIONARY:
				continue
			var rid3 := String(rule3.get("rule_id", ""))
			if rid3.is_empty() or contrib.has(rid3):
				continue
			var match: Dictionary = rule3.get("match", {})
			if String(match.get("kind", "")) != "PUBLIC_CONTEXT":
				continue
			var tag := String(match.get("context_tag", ""))
			if tag.is_empty() or not active.has(tag):
				continue
			public_context = mini(1000, public_context + _clamped_points(rule3))
			contrib[rid3] = true

	var matched_ids: Array = contrib.keys()
	matched_ids.sort()
	return {
		"persona": persona,
		"expression": expression,
		"public_context": public_context,
		"matched_rule_ids": matched_ids,
		"character_id": character_id,
	}


static func _score_item_tag(
	item_id: String,
	features: Dictionary,
	character_id: String,
	has_activity: bool,
	seat_tags: Array
) -> Dictionary:
	var def: Dictionary = TrashTalkRuleCatalog.item_def(StringName(item_id))
	if def.is_empty():
		return {"item_tag": 0, "matched_rule_ids": []}

	var matched_text: Dictionary = {}
	for rid in features.get("matched_rule_ids", []):
		matched_text[String(rid)] = true

	var primary := ""
	var secondary := ""
	var c: Character = CharacterPool.find(StringName(character_id))
	if c != null:
		primary = String(Character.normalize_affinity(c.affinity_primary))
		secondary = String(Character.normalize_affinity(c.affinity_secondary))
	else:
		var persona: Dictionary = TrashTalkRuleCatalog.character_persona(StringName(character_id))
		primary = String(persona.get("affinity_primary", "")).to_upper()
		secondary = String(persona.get("affinity_secondary", "")).to_upper()

	var active_ctx: Dictionary = {}
	for t in seat_tags:
		active_ctx[String(t)] = true
	var item_ctx_hit := false
	for ct in def.get("public_context_tags", []):
		if active_ctx.has(String(ct)):
			item_ctx_hit = true
			break

	var item_tag := 0
	var contrib: Dictionary = {}
	for rule in def.get("rules", []):
		if typeof(rule) != TYPE_DICTIONARY:
			continue
		if String(rule.get("component", "")) != "item_tag":
			continue
		var rid := String(rule.get("rule_id", ""))
		if rid.is_empty() or contrib.has(rid):
			continue
		var match: Dictionary = rule.get("match", {})
		var tag := String(match.get("tag", "")).to_upper()
		var hit := false
		if matched_text.has(rid):
			hit = true
		elif has_activity:
			if tag != "" and (tag == primary or tag == secondary):
				hit = true
			elif item_ctx_hit:
				hit = true
		if not hit:
			continue
		item_tag = mini(1000, item_tag + _clamped_points(rule))
		contrib[rid] = true

	var matched_ids: Array = contrib.keys()
	matched_ids.sort()
	return {"item_tag": item_tag, "matched_rule_ids": matched_ids}


## 返回 {ok, reason?, seat_tags?}
static func _resolve_seat_tags(
	input: Dictionary,
	room_id: String,
	hand_seq: int,
	closing: int,
	context: int
) -> Dictionary:
	var derive_input := {
		"room_id": room_id,
		"hand_seq": hand_seq,
		"closing_boundary_server_seq": closing,
		"context_boundary_server_seq": context,
		"public_initial": input.get("public_initial", null),
	}
	if input.get("public_events", null) is Array:
		derive_input["public_events"] = input["public_events"]
	var seat_map: Dictionary = TrashTalkPublicContextAdapter.derive_seat_public_context_tags(
		derive_input
	)
	if not bool(seat_map.get("ok", false)):
		return {
			"ok": false,
			"reason": String(seat_map.get("reason", "INVALID_PUBLIC_INITIAL")),
		}
	var out := {"0": [], "1": [], "2": [], "3": []}
	for i in range(4):
		var arr: Array = seat_map.get(str(i), [])
		var clean: Array = []
		for t in arr:
			clean.append(String(t))
		clean.sort()
		out[str(i)] = clean
	return {"ok": true, "seat_tags": out}


static func _collect_global_tags(seat_tag_map: Dictionary) -> Array:
	var global: Dictionary = {}
	for i in range(4):
		for t in seat_tag_map.get(str(i), []):
			global[String(t)] = true
	var out: Array = global.keys()
	out.sort()
	return out


## 返回 {ok, reason?, utterances}
static func _normalize_utterances_by_seat(
	raw: Variant,
	closing: int,
	window_lang: String
) -> Dictionary:
	var out := {"0": [], "1": [], "2": [], "3": []}
	if raw == null:
		return {"ok": true, "utterances": out}
	if not (raw is Dictionary):
		return {"ok": false, "reason": "INVALID_UTTERANCES"}
	var d: Dictionary = raw
	for seat in range(4):
		var key := str(seat)
		if not d.has(key) and not d.has(seat):
			continue
		var list_v: Variant = d.get(key, d.get(seat, null))
		if list_v == null:
			continue
		if not (list_v is Array):
			return {"ok": false, "reason": "INVALID_UTTERANCES"}
		var by_uid: Dictionary = {}
		for u in list_v:
			if typeof(u) != TYPE_DICTIONARY:
				return {"ok": false, "reason": "INVALID_UTTERANCE"}
			var uid_v: Variant = u.get("utterance_id", null)
			if typeof(uid_v) != TYPE_STRING and typeof(uid_v) != TYPE_STRING_NAME:
				return {"ok": false, "reason": "INVALID_UTTERANCE_ID"}
			var uid := String(uid_v)
			if uid.is_empty():
				return {"ok": false, "reason": "INVALID_UTTERANCE_ID"}
			# 真实窗口文字必须显式绑定 closing boundary
			if not u.has("ptt_end_server_seq") or not _is_int(u.get("ptt_end_server_seq", null)):
				return {"ok": false, "reason": "MISSING_PTT_END_SERVER_SEQ"}
			var ptt: int = int(u["ptt_end_server_seq"])
			if ptt < 0:
				return {"ok": false, "reason": "INVALID_PTT_END_SERVER_SEQ"}
			# 不得用 context 放宽 closing
			if ptt > closing:
				continue
			var text := String(u.get("text", ""))
			var lang := ""
			if u.has("language") and u.get("language", null) != null:
				lang = _require_lang(u.get("language", null))
				if lang == "":
					return {"ok": false, "reason": "INVALID_LANGUAGE"}
			elif window_lang != "":
				lang = window_lang
			else:
				return {"ok": false, "reason": "MISSING_LANGUAGE"}
			if by_uid.has(uid):
				var prev: Dictionary = by_uid[uid]
				if String(prev["text"]) != text or String(prev["language"]) != lang:
					return {"ok": false, "reason": "UTTERANCE_CONFLICT"}
				continue
			by_uid[uid] = {
				"utterance_id": uid,
				"text": text,
				"language": lang,
			}
		var arr: Array = by_uid.values()
		arr.sort_custom(func(a, b): return String(a["utterance_id"]) < String(b["utterance_id"]))
		out[key] = arr
	return {"ok": true, "utterances": out}


static func _seat_has_text_activity(utterances: Array) -> bool:
	for u in utterances:
		if typeof(u) != TYPE_DICTIONARY:
			continue
		var norm := TextAnalyzer.normalize(String(u.get("text", "")))
		if not norm.is_empty():
			return true
	return false


static func _normalize_character_ids(raw: Variant) -> Array:
	if not (raw is Array):
		return []
	var arr: Array = raw
	if arr.size() != 4:
		return []
	var out: Array = []
	for v in arr:
		var s := String(v).strip_edges()
		if s.is_empty():
			return []
		if CharacterPool.find(StringName(s)) == null:
			return []
		out.append(s)
	return out


static func _normalize_pool_item_ids(raw: Variant) -> Array:
	if not (raw is Array):
		return []
	var arr: Array = raw
	if arr.size() != 4:
		return []
	var seen: Dictionary = {}
	var out: Array = []
	for v in arr:
		var id := String(v).strip_edges()
		if id.is_empty():
			return []
		if seen.has(id):
			return [] # 重复奖池：拒绝（不静默去重）
		if TrashTalkRuleCatalog.item_def(StringName(id)).is_empty():
			return []
		seen[id] = true
		out.append(id)
	out.sort()
	return out


static func _clamped_points(rule: Dictionary) -> int:
	var points: int = int(rule.get("points", 0))
	var cap: int = int(rule.get("cap", 1000))
	if points < 0:
		points = 0
	if cap < 0:
		cap = 0
	if cap > 1000:
		cap = 1000
	if points > cap:
		points = cap
	return points


static func _require_lang(v: Variant) -> String:
	if typeof(v) != TYPE_STRING and typeof(v) != TYPE_STRING_NAME:
		return ""
	var s := String(v).strip_edges().to_lower()
	if ALLOWED_LANGS.has(s):
		return s
	return ""


static func _empty_features() -> Dictionary:
	return {
		"matched_rule_ids": [],
		"affinity": _zero_affinity(),
		"specificity": 0,
		"expression_quality": 0,
	}


static func _zero_affinity() -> Dictionary:
	var d: Dictionary = {}
	for k in TrashTalkRuleCatalog.AFFINITY_KEYS:
		d[k] = 0
	return d


static func _is_int(v: Variant) -> bool:
	return typeof(v) == TYPE_INT


static func _reject(reason: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"matrix": [],
		"matched_rule_ids_by_seat": {"0": [], "1": [], "2": [], "3": []},
	}
