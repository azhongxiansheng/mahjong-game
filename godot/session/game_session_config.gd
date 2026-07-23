class_name GameSessionConfig extends RefCounted

# E2-01（#231）：正式会话配置。
# SessionIntent → Config 的唯一转换在此；大厅 UI 不得直接拼装本类。
# 方案 A：STANDARD / TRASH_TALK 均记录四席 character_ids（身份/外观）；
# STANDARD 后续绝不创建角色能力（本类亦不实例化能力）。

# ---- 命名 enum（稳定整数值；wire 字符串见下方常量与映射）----
enum GameMode {
	STANDARD = 0,
	TRASH_TALK = 1,
}

enum RoomKind {
	PRACTICE = 0,
	PUBLIC_CASUAL = 1,
}

enum RoundKind {
	EAST = 0,
	HANCHAN = 1,
}

enum ParticipantKind {
	HUMAN = 0,
	AI = 1,
}

# ---- 稳定协议枚举（wire 字符串）----
const ROOM_PRACTICE := &"PRACTICE"
const ROOM_PUBLIC_CASUAL := &"PUBLIC_CASUAL"
const ROUND_EAST := &"EAST"
const ROUND_HANCHAN := &"HANCHAN"
const MODE_STANDARD := &"STANDARD"
const MODE_TRASH_TALK := &"TRASH_TALK"
const PARTICIPANT_HUMAN := &"HUMAN"
const PARTICIPANT_AI := &"AI"

const WIRE_ROOM_KINDS := ["PRACTICE", "PUBLIC_CASUAL"]
const WIRE_ROUND_KINDS := ["EAST", "HANCHAN"]
const WIRE_GAME_MODES := ["STANDARD", "TRASH_TALK"]
const WIRE_PARTICIPANT_KINDS := ["HUMAN", "AI"]

const PRACTICE_PARTICIPANTS := [&"HUMAN", &"AI", &"AI", &"AI"]

const INT64_MAX := 9223372036854775807
const INT64_MIN := -9223372036854775808
## 逐位解析阈值：|INT64| 除以 10 的精确 int，禁止用 INT64_MAX/10 浮点路径。
const INT64_MAX_DIV10 := 922337203685477580
const INT64_MIN_DIV10 := -922337203685477580

# 稳定错误码
const ERR_NULL_INTENT := &"NULL_INTENT"
const ERR_INVALID_ROOM_KIND := &"INVALID_ROOM_KIND"
const ERR_INVALID_ROUND_KIND := &"INVALID_ROUND_KIND"
const ERR_INVALID_GAME_MODE := &"INVALID_GAME_MODE"
const ERR_MISSING_AUTHORITY := &"MISSING_AUTHORITY"
const ERR_AUTHORITY_MISMATCH := &"AUTHORITY_MISMATCH"
const ERR_INVALID_PARTICIPANTS_COUNT := &"INVALID_PARTICIPANTS_COUNT"
const ERR_INVALID_CHARACTER_IDS_COUNT := &"INVALID_CHARACTER_IDS_COUNT"
const ERR_INVALID_PARTICIPANTS := &"INVALID_PARTICIPANTS"
const ERR_EMPTY_SESSION_ID := &"EMPTY_SESSION_ID"
const ERR_EMPTY_RULE_VERSION := &"EMPTY_RULE_VERSION"
const ERR_EMPTY_CHARACTER_ID := &"EMPTY_CHARACTER_ID"
const ERR_UNKNOWN_CHARACTER_ID := &"UNKNOWN_CHARACTER_ID"
const ERR_INVALID_SEED := &"INVALID_SEED"
const ERR_INVALID_WIRE_TYPE := &"INVALID_WIRE_TYPE"
const ERR_DUPLICATE_CHARACTER_IDS := &"DUPLICATE_CHARACTER_IDS"

## 转换结果值对象（避免 launcher / UI 消费裸字典）。
class ConversionResult extends RefCounted:
	var ok: bool = false
	var config: GameSessionConfig = null
	var error_code: StringName = &""

	static func success(cfg: GameSessionConfig) -> ConversionResult:
		var r := ConversionResult.new()
		r.ok = true
		r.config = cfg
		r.error_code = &""
		return r

	static func fail(code: StringName) -> ConversionResult:
		var r := ConversionResult.new()
		r.ok = false
		r.config = null
		r.error_code = code
		return r


var room_kind: StringName = ROOM_PRACTICE
var round_kind: StringName = ROUND_EAST
var game_mode: StringName = MODE_STANDARD
var seed: int = 0
var session_id: String = ""
var rule_version: String = ""

# 私有存储；对外 copy-on-read，防止原地篡改
var _participants: Array = []
var _character_ids: Array = []

var participants: Array:
	get:
		return _participants.duplicate()

var character_ids: Array:
	get:
		return _character_ids.duplicate()


func _init(
	p_room_kind: StringName = ROOM_PRACTICE,
	p_round_kind: StringName = ROUND_EAST,
	p_game_mode: StringName = MODE_STANDARD,
	p_participants: Array = [],
	p_character_ids: Array = [],
	p_seed: int = 0,
	p_session_id: String = "",
	p_rule_version: String = ""
) -> void:
	room_kind = p_room_kind
	round_kind = p_round_kind
	game_mode = p_game_mode
	_participants = _copy_string_name_array(p_participants)
	_character_ids = _copy_string_name_array(p_character_ids)
	seed = p_seed
	session_id = p_session_id
	rule_version = p_rule_version


## 将三维选择稳定还原为 8 个 mode_id 之一（与 SessionIntent.mode_id 同构）。
func mode_id() -> StringName:
	var room_token := "PUBLIC" if room_kind == ROOM_PUBLIC_CASUAL else String(room_kind)
	return StringName("%s_%s_%s" % [room_token, String(round_kind), String(game_mode)])


# ---- enum ↔ wire 映射 ----
static func room_kind_to_wire(e: int) -> StringName:
	match e:
		RoomKind.PRACTICE:
			return ROOM_PRACTICE
		RoomKind.PUBLIC_CASUAL:
			return ROOM_PUBLIC_CASUAL
	return &""


static func round_kind_to_wire(e: int) -> StringName:
	match e:
		RoundKind.EAST:
			return ROUND_EAST
		RoundKind.HANCHAN:
			return ROUND_HANCHAN
	return &""


static func game_mode_to_wire(e: int) -> StringName:
	match e:
		GameMode.STANDARD:
			return MODE_STANDARD
		GameMode.TRASH_TALK:
			return MODE_TRASH_TALK
	return &""


static func participant_kind_to_wire(e: int) -> StringName:
	match e:
		ParticipantKind.HUMAN:
			return PARTICIPANT_HUMAN
		ParticipantKind.AI:
			return PARTICIPANT_AI
	return &""


static func room_kind_from_wire(v: StringName) -> int:
	if v == ROOM_PRACTICE:
		return RoomKind.PRACTICE
	if v == ROOM_PUBLIC_CASUAL:
		return RoomKind.PUBLIC_CASUAL
	return -1


static func round_kind_from_wire(v: StringName) -> int:
	if v == ROUND_EAST:
		return RoundKind.EAST
	if v == ROUND_HANCHAN:
		return RoundKind.HANCHAN
	return -1


static func game_mode_from_wire(v: StringName) -> int:
	if v == MODE_STANDARD:
		return GameMode.STANDARD
	if v == MODE_TRASH_TALK:
		return GameMode.TRASH_TALK
	return -1


static func participant_kind_from_wire(v: StringName) -> int:
	if v == PARTICIPANT_HUMAN:
		return ParticipantKind.HUMAN
	if v == PARTICIPANT_AI:
		return ParticipantKind.AI
	return -1


static func _copy_string_name_array(src: Array) -> Array:
	var out: Array = []
	for item in src:
		out.append(StringName(item) if typeof(item) == TYPE_STRING_NAME else StringName(str(item)))
	return out


static func _is_wire_text(v: Variant) -> bool:
	var t: int = typeof(v)
	return t == TYPE_STRING or t == TYPE_STRING_NAME


static func _wire_text_to_string(v: Variant) -> String:
	if typeof(v) == TYPE_STRING:
		return v
	return String(v)


static func _wire_text_to_string_name(v: Variant) -> StringName:
	if typeof(v) == TYPE_STRING_NAME:
		return v
	return StringName(v)


static func _is_room_kind(v: StringName) -> bool:
	return room_kind_from_wire(v) >= 0


static func _is_round_kind(v: StringName) -> bool:
	return round_kind_from_wire(v) >= 0


static func _is_game_mode(v: StringName) -> bool:
	return game_mode_from_wire(v) >= 0


static func _is_participant_kind(v: StringName) -> bool:
	return participant_kind_from_wire(v) >= 0


## 跨平台稳定 LCG：真正 unsigned 32-bit Numerical Recipes。
## state 规范化为 seed & 0xffffffff；每步 (state*1664525+1013904223)&0xffffffff。
## 乘积在 int64 安全范围；不 abs、不 31-bit mask。
static func _lcrng_next(state: int) -> int:
	var s: int = state & 0xffffffff
	return int((s * 1664525 + 1013904223) & 0xffffffff)


## 从 CharacterPool 中按 seed 确定性抽取 count 个不重复、且排除 excluded 的角色。
static func _pick_unique_characters(excluded: StringName, seed_value: int, count: int) -> Array:
	var pool: Array = []
	for c in CharacterPool.all():
		var cid: StringName = c.id
		if cid == excluded:
			continue
		pool.append(cid)
	pool.sort_custom(func(a: StringName, b: StringName) -> bool:
		return String(a) < String(b)
	)
	var state: int = seed_value & 0xffffffff
	for i in range(pool.size() - 1, 0, -1):
		state = _lcrng_next(state)
		var j: int = state % (i + 1)
		var tmp: StringName = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	var out: Array = []
	for i in range(mini(count, pool.size())):
		out.append(pool[i])
	return out


## 规范十进制字符串 → int64；拒绝非规范形式与溢出。失败返回 null。
static func _parse_canonical_int64_decimal(s: String) -> Variant:
	if s.is_empty():
		return null
	var neg := false
	var start := 0
	if s[0] == "-":
		neg = true
		start = 1
		if s.length() == 1:
			return null
	# 禁止 '+' 前缀、空白、小数点等（仅数字；可选前导 '-'）
	# 禁止前导零；规范零仅为 "0"（拒绝 "-0"）
	if s[start] == "0":
		if neg or s.length() != start + 1:
			return null
		return 0
	var acc: int = 0
	for i in range(start, s.length()):
		var ch: int = s.unicode_at(i)
		if ch < 48 or ch > 57:
			return null
		var digit: int = ch - 48
		if neg:
			# 累加为负数；阈值用精确 int 常量，避免 / 浮点精度问题
			if acc < INT64_MIN_DIV10:
				return null
			if acc == INT64_MIN_DIV10 and digit > 8:
				return null
			acc = acc * 10 - digit
		else:
			if acc > INT64_MAX_DIV10:
				return null
			if acc == INT64_MAX_DIV10 and digit > 7:
				return null
			acc = acc * 10 + digit
	return acc


static func _seed_to_wire(p_seed: int) -> String:
	return str(p_seed)


static func _validate_character_ids(ids: Array, allow_duplicates: bool) -> StringName:
	if ids.size() != 4:
		return ERR_INVALID_CHARACTER_IDS_COUNT
	var seen := {}
	for item in ids:
		if not _is_wire_text(item):
			return ERR_INVALID_WIRE_TYPE
		var cid := _wire_text_to_string_name(item)
		if String(cid).is_empty():
			return ERR_EMPTY_CHARACTER_ID
		if CharacterPool.find(cid) == null:
			return ERR_UNKNOWN_CHARACTER_ID
		if not allow_duplicates:
			var key := String(cid)
			if seen.has(key):
				return ERR_DUPLICATE_CHARACTER_IDS
			seen[key] = true
	return &""


static func _validate_participants_common(parts: Array) -> StringName:
	if parts.size() != 4:
		return ERR_INVALID_PARTICIPANTS_COUNT
	for item in parts:
		if not _is_wire_text(item):
			return ERR_INVALID_WIRE_TYPE
		if not _is_participant_kind(_wire_text_to_string_name(item)):
			return ERR_INVALID_PARTICIPANTS
	return &""


## 已验证字段构造；非法返回 null（供测试边界 / 启动器校验复用）。
static func create_validated(
	p_room_kind: StringName,
	p_round_kind: StringName,
	p_game_mode: StringName,
	p_participants: Array,
	p_character_ids: Array,
	p_seed: int,
	p_session_id: String,
	p_rule_version: String
) -> GameSessionConfig:
	if not _is_room_kind(p_room_kind):
		return null
	if not _is_round_kind(p_round_kind):
		return null
	if not _is_game_mode(p_game_mode):
		return null
	if p_session_id.is_empty():
		return null
	if p_rule_version.is_empty():
		return null
	var part_err := _validate_participants_common(p_participants)
	if part_err != &"":
		return null
	var allow_dup := p_room_kind != ROOM_PRACTICE
	var char_err := _validate_character_ids(p_character_ids, allow_dup)
	if char_err != &"":
		return null
	var parts := _copy_string_name_array(p_participants)
	if p_room_kind == ROOM_PRACTICE:
		if parts != PRACTICE_PARTICIPANTS:
			return null
	else:
		var has_human := false
		for p in parts:
			if p == PARTICIPANT_HUMAN:
				has_human = true
				break
		if not has_human:
			return null
	return GameSessionConfig.new(
		p_room_kind,
		p_round_kind,
		p_game_mode,
		parts,
		p_character_ids,
		p_seed,
		p_session_id,
		p_rule_version
	)


## SessionIntent → GameSessionConfig 唯一转换入口。
## 逐字段白名单；不依赖 intent.mode_id 作合法性闸门。
## seed / session_id / rule_version 由调用方显式传入（练习）或 authority（公共）。
static func from_intent(
	intent: SessionIntent,
	p_seed: int = 0,
	p_session_id: String = "",
	p_rule_version: String = "",
	authority_context: Dictionary = {}
) -> ConversionResult:
	if intent == null:
		return ConversionResult.fail(ERR_NULL_INTENT)

	var room := StringName(intent.room_kind)
	var round_kind_val := StringName(intent.round_kind)
	var mode := StringName(intent.game_mode)

	if not _is_room_kind(room):
		return ConversionResult.fail(ERR_INVALID_ROOM_KIND)
	if not _is_round_kind(round_kind_val):
		return ConversionResult.fail(ERR_INVALID_ROUND_KIND)
	if not _is_game_mode(mode):
		return ConversionResult.fail(ERR_INVALID_GAME_MODE)

	if room == ROOM_PRACTICE:
		return _from_practice_intent(intent, p_seed, p_session_id, p_rule_version)
	return _from_public_intent(intent, authority_context)


static func _from_practice_intent(
	intent: SessionIntent,
	p_seed: int,
	p_session_id: String,
	p_rule_version: String
) -> ConversionResult:
	if p_session_id.is_empty():
		return ConversionResult.fail(ERR_EMPTY_SESSION_ID)
	if p_rule_version.is_empty():
		return ConversionResult.fail(ERR_EMPTY_RULE_VERSION)

	var player_id: StringName = intent.selected_character_id
	if String(player_id).is_empty():
		player_id = CharacterPool.all()[0].id
	elif CharacterPool.find(player_id) == null:
		return ConversionResult.fail(ERR_UNKNOWN_CHARACTER_ID)

	var ai_ids: Array = _pick_unique_characters(player_id, p_seed, 3)
	if ai_ids.size() != 3:
		return ConversionResult.fail(ERR_UNKNOWN_CHARACTER_ID)

	var chars: Array = [player_id, ai_ids[0], ai_ids[1], ai_ids[2]]
	var cfg := create_validated(
		ROOM_PRACTICE,
		StringName(intent.round_kind),
		StringName(intent.game_mode),
		PRACTICE_PARTICIPANTS,
		chars,
		p_seed,
		p_session_id,
		p_rule_version
	)
	if cfg == null:
		return ConversionResult.fail(ERR_INVALID_PARTICIPANTS)
	return ConversionResult.success(cfg)


static func _from_public_intent(
	intent: SessionIntent,
	authority_context: Dictionary
) -> ConversionResult:
	if authority_context == null or authority_context.is_empty():
		return ConversionResult.fail(ERR_MISSING_AUTHORITY)
	# 四席 + 权威元数据 + room/round/mode 必须齐全
	if not authority_context.has("participants") \
		or not authority_context.has("character_ids") \
		or not authority_context.has("seed") \
		or not authority_context.has("session_id") \
		or not authority_context.has("rule_version") \
		or not authority_context.has("room_kind") \
		or not authority_context.has("round_kind") \
		or not authority_context.has("game_mode"):
		return ConversionResult.fail(ERR_MISSING_AUTHORITY)

	# room/round/mode：严格 wire 文本类型
	var auth_room_raw: Variant = authority_context["room_kind"]
	var auth_round_raw: Variant = authority_context["round_kind"]
	var auth_mode_raw: Variant = authority_context["game_mode"]
	if not _is_wire_text(auth_room_raw) or not _is_wire_text(auth_round_raw) \
		or not _is_wire_text(auth_mode_raw):
		return ConversionResult.fail(ERR_INVALID_WIRE_TYPE)

	var auth_room := _wire_text_to_string_name(auth_room_raw)
	var auth_round := _wire_text_to_string_name(auth_round_raw)
	var auth_mode := _wire_text_to_string_name(auth_mode_raw)

	if not _is_room_kind(auth_room):
		return ConversionResult.fail(ERR_INVALID_ROOM_KIND)
	if not _is_round_kind(auth_round):
		return ConversionResult.fail(ERR_INVALID_ROUND_KIND)
	if not _is_game_mode(auth_mode):
		return ConversionResult.fail(ERR_INVALID_GAME_MODE)

	# room 必须 PUBLIC_CASUAL；round/mode 必须与 SessionIntent 一致
	if auth_room != ROOM_PUBLIC_CASUAL:
		return ConversionResult.fail(ERR_AUTHORITY_MISMATCH)
	if auth_round != StringName(intent.round_kind) or auth_mode != StringName(intent.game_mode):
		return ConversionResult.fail(ERR_AUTHORITY_MISMATCH)

	var parts_raw: Variant = authority_context["participants"]
	var chars_raw: Variant = authority_context["character_ids"]
	if typeof(parts_raw) != TYPE_ARRAY:
		return ConversionResult.fail(ERR_INVALID_PARTICIPANTS_COUNT)
	if typeof(chars_raw) != TYPE_ARRAY:
		return ConversionResult.fail(ERR_INVALID_CHARACTER_IDS_COUNT)

	var parts: Array = parts_raw
	var chars: Array = chars_raw

	var part_err := _validate_participants_common(parts)
	if part_err != &"":
		return ConversionResult.fail(part_err)

	var char_err := _validate_character_ids(chars, true)
	if char_err != &"":
		return ConversionResult.fail(char_err)

	# session_id / rule_version：严格 String/StringName
	var sess_raw: Variant = authority_context["session_id"]
	var rv_raw: Variant = authority_context["rule_version"]
	if not _is_wire_text(sess_raw) or not _is_wire_text(rv_raw):
		return ConversionResult.fail(ERR_INVALID_WIRE_TYPE)
	var auth_session_id := _wire_text_to_string(sess_raw)
	var auth_rule_version := _wire_text_to_string(rv_raw)
	if auth_session_id.is_empty():
		return ConversionResult.fail(ERR_EMPTY_SESSION_ID)
	if auth_rule_version.is_empty():
		return ConversionResult.fail(ERR_EMPTY_RULE_VERSION)

	var has_human := false
	for p in parts:
		if _wire_text_to_string_name(p) == PARTICIPANT_HUMAN:
			has_human = true
			break
	if not has_human:
		return ConversionResult.fail(ERR_INVALID_PARTICIPANTS)

	# 本地权威 typed context：seed 只接受真正 TYPE_INT
	var seed_raw: Variant = authority_context["seed"]
	if typeof(seed_raw) != TYPE_INT:
		return ConversionResult.fail(ERR_INVALID_SEED)
	var seed_value: int = seed_raw

	# Config 的 room/round/mode 来自 authority（与匹配 Intent 一致）
	var cfg := create_validated(
		auth_room,
		auth_round,
		auth_mode,
		parts,
		chars,
		seed_value,
		auth_session_id,
		auth_rule_version
	)
	if cfg == null:
		return ConversionResult.fail(ERR_INVALID_PARTICIPANTS)
	return ConversionResult.success(cfg)


func to_dict() -> Dictionary:
	var parts_wire: Array = []
	for p in _participants:
		parts_wire.append(String(p))
	var chars_wire: Array = []
	for c in _character_ids:
		chars_wire.append(String(c))
	return {
		"room_kind": String(room_kind),
		"round_kind": String(round_kind),
		"game_mode": String(game_mode),
		"participants": parts_wire,
		"character_ids": chars_wire,
		"seed": _seed_to_wire(seed),
		"session_id": session_id,
		"rule_version": rule_version,
	}


## 非法输入返回 null，不得产出 Config。
static func from_dict(d: Variant) -> GameSessionConfig:
	if d == null or typeof(d) != TYPE_DICTIONARY:
		return null
	var dict: Dictionary = d
	if dict.is_empty():
		return null
	if not dict.has("room_kind") or not dict.has("round_kind") or not dict.has("game_mode") \
		or not dict.has("participants") or not dict.has("character_ids") \
		or not dict.has("seed") or not dict.has("session_id") or not dict.has("rule_version"):
		return null

	# room/round/mode / session / rule_version：只接受 String/StringName
	if not _is_wire_text(dict["room_kind"]) or not _is_wire_text(dict["round_kind"]) \
		or not _is_wire_text(dict["game_mode"]) or not _is_wire_text(dict["session_id"]) \
		or not _is_wire_text(dict["rule_version"]):
		return null

	if typeof(dict["participants"]) != TYPE_ARRAY or typeof(dict["character_ids"]) != TYPE_ARRAY:
		return null

	# wire seed：仅规范十进制字符串
	var seed_raw: Variant = dict["seed"]
	if typeof(seed_raw) != TYPE_STRING:
		return null
	var seed_parsed: Variant = _parse_canonical_int64_decimal(seed_raw)
	if seed_parsed == null:
		return null

	return create_validated(
		_wire_text_to_string_name(dict["room_kind"]),
		_wire_text_to_string_name(dict["round_kind"]),
		_wire_text_to_string_name(dict["game_mode"]),
		dict["participants"],
		dict["character_ids"],
		int(seed_parsed),
		_wire_text_to_string(dict["session_id"]),
		_wire_text_to_string(dict["rule_version"])
	)
