class_name TrashTalkAiLineSelector extends RefCounted

# E5-01 / #249：AI 席垃圾话纯函数选择器。
# 不发事件、不接 RewardWindow、不在线生成、不合成语音、不维护「已发过」状态。


## 成功返回 Dictionary；失败/静默返回 null。
## 输出字段（rule_version 固定契约）：
##   line_id, text, language, character_id, rule_version,
##   window_id, seat, discard_server_seq, utterance_id
## utterance_id 仅由 rule_version + window_id + seat 决定（不含 line_id）。
static func select_ai_line(input: Dictionary) -> Variant:
	if typeof(input) != TYPE_DICTIONARY or input.is_empty():
		return null

	var hfd: Variant = input.get("has_first_discard", null)
	if typeof(hfd) != TYPE_BOOL:
		return null
	if hfd == false:
		return null

	var rule_version_v: Variant = input.get("rule_version", null)
	if typeof(rule_version_v) != TYPE_STRING and typeof(rule_version_v) != TYPE_STRING_NAME:
		return null
	var rule_version := String(rule_version_v)
	if rule_version != TrashTalkRuleCatalog.rule_version():
		return null

	if not _is_int(input.get("seed", null)):
		return null
	if not _is_int(input.get("hand_seq", null)):
		return null
	var match_seed: int = input["seed"]
	var hand_seq: int = input["hand_seq"]

	var window_v: Variant = input.get("window_id", null)
	if typeof(window_v) != TYPE_STRING and typeof(window_v) != TYPE_STRING_NAME:
		return null
	var window_id := String(window_v)
	if window_id.strip_edges().is_empty():
		return null

	if not _is_int(input.get("seat", null)):
		return null
	var seat: int = input["seat"]
	if seat < 0 or seat > 3:
		return null

	if not _is_int(input.get("discard_server_seq", null)):
		return null
	var discard_server_seq: int = input["discard_server_seq"]
	if discard_server_seq <= 0:
		return null

	var char_v: Variant = input.get("character_id", null)
	if typeof(char_v) != TYPE_STRING and typeof(char_v) != TYPE_STRING_NAME:
		return null
	var character_id := StringName(String(char_v))
	if String(character_id).is_empty() or CharacterPool.find(character_id) == null:
		return null

	var lang_v: Variant = input.get("language", null)
	if typeof(lang_v) != TYPE_STRING and typeof(lang_v) != TYPE_STRING_NAME:
		return null
	var language := String(lang_v)
	if not _lang_allowed(language):
		return null

	var tags_norm: Variant = _normalize_public_context_tags(input.get("public_context_tags", null))
	if tags_norm == null:
		return null
	var tags_sorted: Array = tags_norm

	var candidates: Array = TrashTalkRuleCatalog.ai_lines_for_public_context(
		character_id, language, tags_sorted
	)
	if candidates.is_empty():
		return null

	var state: int = _mix_state(
		match_seed, hand_seq, window_id, seat, discard_server_seq, rule_version,
		String(character_id), language, tags_sorted
	)
	var index: int = state % candidates.size()
	var line: Dictionary = candidates[index]
	var line_id := String(line.get("line_id", ""))
	if line_id.is_empty():
		return null
	return {
		"line_id": line_id,
		"text": String(line.get("text", "")),
		"language": language,
		"character_id": String(character_id),
		"rule_version": rule_version,
		"window_id": window_id,
		"seat": seat,
		"discard_server_seq": discard_server_seq,
		"utterance_id": _utterance_id(rule_version, window_id, seat),
	}


## rule_version 固定命名：ai|{rule_version}|{window_id}|{seat}
## 不含 line_id：同窗同席幂等身份与选中文案解耦。
static func _utterance_id(rule_version: String, window_id: String, seat: int) -> String:
	return "ai|%s|%s|%d" % [rule_version, window_id, seat]


static func _is_int(v: Variant) -> bool:
	return typeof(v) == TYPE_INT


static func _lang_allowed(language: String) -> bool:
	for lang in TrashTalkRuleCatalog.LANGUAGES:
		if String(lang) == language:
			return true
	return false


## 合法：缺失键视为 []；必须是 Array；元素仅 String/StringName；仅允许 PUBLIC_CONTEXT_TAGS；
## 返回字典序去重数组。非法返回 null。
static func _normalize_public_context_tags(raw: Variant) -> Variant:
	var tags: Array = []
	if raw == null:
		pass
	elif typeof(raw) != TYPE_ARRAY:
		return null
	else:
		for item in raw:
			if typeof(item) != TYPE_STRING and typeof(item) != TYPE_STRING_NAME:
				return null
			var s := String(item)
			if s.is_empty():
				return null
			if not _ctx_allowed(s):
				return null
			tags.append(s)
	tags.sort()
	var uniq: Array = []
	var prev := ""
	for t in tags:
		if String(t) != prev:
			uniq.append(String(t))
			prev = String(t)
	return uniq


static func _ctx_allowed(tag: String) -> bool:
	for t in TrashTalkRuleCatalog.PUBLIC_CONTEXT_TAGS:
		if String(t) == tag:
			return true
	return false


static func _mix_state(
	match_seed: int,
	hand_seq: int,
	window_id: String,
	seat: int,
	discard_server_seq: int,
	rule_version: String,
	character_id: String,
	language: String,
	tags_sorted: Array
) -> int:
	var state: int = match_seed & 0xffffffff
	state = _lcrng_next(state ^ (hand_seq & 0xffffffff))
	state = _lcrng_next(state ^ _stable_hash(window_id))
	state = _lcrng_next(state ^ (seat & 0xffffffff))
	state = _lcrng_next(state ^ (discard_server_seq & 0xffffffff))
	state = _lcrng_next(state ^ _stable_hash(rule_version))
	state = _lcrng_next(state ^ _stable_hash(character_id))
	state = _lcrng_next(state ^ _stable_hash(language))
	var packed: PackedStringArray = PackedStringArray()
	for t in tags_sorted:
		packed.append(String(t))
	var tag_key := ",".join(packed)
	state = _lcrng_next(state ^ _stable_hash(tag_key))
	return state & 0xffffffff


static func _lcrng_next(state: int) -> int:
	var s: int = state & 0xffffffff
	return int((s * 1664525 + 1013904223) & 0xffffffff)


static func _stable_hash(text: String) -> int:
	var h: int = 2166136261
	for i in range(text.length()):
		h = int((h ^ text.unicode_at(i)) * 16777619) & 0xffffffff
	return h
