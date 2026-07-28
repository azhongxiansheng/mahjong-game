class_name MatchingMetaSnapshotProvider
extends SnapshotModuleProvider

# #374：独立匹配元数据（四席角色 roster + participants）。
# STANDARD 与 TRASH_TALK 均注册且必需；不得写入 core_table@1。


const MODULE_KEY := "matching_meta"
const SCHEMA_VERSION := 1
const EXACT_KEYS := ["character_ids", "participants"]


func module_key() -> String:
	return MODULE_KEY


func schema_version() -> int:
	return SCHEMA_VERSION


func is_required() -> bool:
	# #374：STANDARD / TRASH_TALK 均必需。缺失或非法时序列化失败 / 整份 restore 原子拒绝。
	return true


func serialize(ctx: Dictionary, seat: int) -> Variant:
	if seat < 0 or seat > 3:
		return null
	var chars_v: Variant = ctx.get("character_ids", null)
	var parts_v: Variant = ctx.get("participants", null)
	if typeof(chars_v) != TYPE_ARRAY or typeof(parts_v) != TYPE_ARRAY:
		var cfg_v: Variant = ctx.get("config", null)
		if cfg_v is GameSessionConfig:
			var cfg: GameSessionConfig = cfg_v as GameSessionConfig
			chars_v = cfg.character_ids
			parts_v = cfg.participants
	if typeof(chars_v) != TYPE_ARRAY or typeof(parts_v) != TYPE_ARRAY:
		return null
	var chars: Array = chars_v
	var parts: Array = parts_v
	if chars.size() != 4 or parts.size() != 4:
		return null
	var out_chars: Array = []
	var out_parts: Array = []
	for i in range(4):
		var cid := str(chars[i])
		var kind := str(parts[i])
		if cid.is_empty():
			return null
		if CharacterPool.find(StringName(cid)) == null:
			return null
		if kind != "HUMAN" and kind != "AI":
			return null
		out_chars.append(cid)
		out_parts.append(kind)
	return {
		"character_ids": out_chars,
		"participants": out_parts,
	}


func can_restore(payload: Variant, seat: int) -> bool:
	if seat < 0 or seat > 3:
		return false
	if typeof(payload) != TYPE_DICTIONARY:
		return false
	var d: Dictionary = payload
	if not _has_exact_keys(d, EXACT_KEYS):
		return false
	if typeof(d["character_ids"]) != TYPE_ARRAY or typeof(d["participants"]) != TYPE_ARRAY:
		return false
	var chars: Array = d["character_ids"]
	var parts: Array = d["participants"]
	if chars.size() != 4 or parts.size() != 4:
		return false
	for i in range(4):
		if typeof(chars[i]) != TYPE_STRING and typeof(chars[i]) != TYPE_STRING_NAME:
			return false
		if str(chars[i]).is_empty():
			return false
		if CharacterPool.find(StringName(str(chars[i]))) == null:
			return false
		var kind := str(parts[i])
		if kind != "HUMAN" and kind != "AI":
			return false
	return true


func stage_restore(payload: Variant, seat: int) -> Variant:
	if not can_restore(payload, seat):
		return null
	var d: Dictionary = (payload as Dictionary).duplicate(true)
	var chars: Array = []
	var parts: Array = []
	for i in range(4):
		chars.append(str(d["character_ids"][i]))
		parts.append(str(d["participants"][i]))
	return {
		"character_ids": chars,
		"participants": parts,
	}


func commit_restore(staged: Variant, seat: int, target: Object) -> bool:
	if typeof(staged) != TYPE_DICTIONARY:
		return false
	if target == null:
		return false
	if target.has_method("apply_restored_module"):
		return bool(target.call(
			"apply_restored_module",
			MODULE_KEY,
			SCHEMA_VERSION,
			(staged as Dictionary).duplicate(true),
			seat
		))
	return false


func restore(payload: Variant, seat: int, target: Object) -> bool:
	var staged: Variant = stage_restore(payload, seat)
	if staged == null:
		return false
	return commit_restore(staged, seat, target)


static func _has_exact_keys(data: Dictionary, expected: Array) -> bool:
	if data.size() != expected.size():
		return false
	for k in expected:
		if not data.has(k):
			return false
	return true


## 测试/夹具：最小合法 matching_meta 模块条目（与生产 schema 一致）。
static func fixture_module(
	chars: Array = ["lin_yeche", "an_cheng", "bai_touli", "hua_ling"],
	parts: Array = ["HUMAN", "AI", "AI", "AI"]
) -> Dictionary:
	return {
		"module_key": MODULE_KEY,
		"schema_version": SCHEMA_VERSION,
		"payload": {
			"character_ids": chars.duplicate(),
			"participants": parts.duplicate(),
		},
	}


static func fixture_ctx_fields() -> Dictionary:
	return {
		"character_ids": ["lin_yeche", "an_cheng", "bai_touli", "hua_ling"],
		"participants": ["HUMAN", "AI", "AI", "AI"],
	}
