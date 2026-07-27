class_name ViewerWallTopSnapshotProvider
extends SnapshotModuleProvider

# Issue #345：recipient 私有 live-wall 顶部有序序列。保持 core_table@1 与
# viewer_next_draw@1 不变；无有效序列时省略整个 optional 模块。

const MODULE_KEY := "viewer_wall_top"
const SCHEMA_VERSION := 1
const PAYLOAD_KEYS := ["recipient_seat", "hand_seq", "tiles"]
const ENTRY_KEYS := ["offset", "tile"]
const MAX_TILES := 3


func module_key() -> String:
	return MODULE_KEY


func schema_version() -> int:
	return SCHEMA_VERSION


func is_required() -> bool:
	return false


func serialize(ctx: Dictionary, seat: int) -> Variant:
	var state_value: Variant = ctx.get("state", null)
	if not (state_value is BattleState) or seat < 0 or seat > 3:
		return null
	var state := state_value as BattleState
	var projected: Array = RecipientViewProjector.project_viewer_wall_top(state, seat)
	if projected.is_empty():
		return null
	var entries: Array = []
	for index in range(projected.size()):
		entries.append({"offset": index, "tile": projected[index]})
	return {
		"recipient_seat": seat,
		"hand_seq": int(state.hand_seq),
		"tiles": entries,
	}


func can_restore(payload: Variant, seat: int) -> bool:
	if typeof(payload) != TYPE_DICTIONARY or seat < 0 or seat > 3:
		return false
	var data := payload as Dictionary
	if data.keys().size() != PAYLOAD_KEYS.size():
		return false
	for key in PAYLOAD_KEYS:
		if not data.has(key):
			return false
	if typeof(data["recipient_seat"]) != TYPE_INT \
			or int(data["recipient_seat"]) != seat:
		return false
	if typeof(data["hand_seq"]) != TYPE_INT or int(data["hand_seq"]) < 0 \
			or typeof(data["tiles"]) != TYPE_ARRAY:
		return false
	var entries := data["tiles"] as Array
	if entries.is_empty() or entries.size() > MAX_TILES:
		return false
	var seen: Dictionary = {}
	for index in range(entries.size()):
		if typeof(entries[index]) != TYPE_DICTIONARY:
			return false
		var entry := entries[index] as Dictionary
		if entry.keys().size() != ENTRY_KEYS.size() \
				or not entry.has("offset") or not entry.has("tile") \
				or typeof(entry["offset"]) != TYPE_INT or int(entry["offset"]) != index:
			return false
		var tile_view: Variant = ProtocolViewCodec.tile_view_from_dict(entry["tile"])
		if tile_view == null:
			return false
		var iid := int((tile_view as Dictionary)["instance_id"])
		if seen.has(iid) or not Tile.is_instance_id_in_hand_seq(
			iid, int(data["hand_seq"])):
			return false
		seen[iid] = true
	return true


func stage_restore(payload: Variant, seat: int) -> Variant:
	if not can_restore(payload, seat):
		return null
	return (payload as Dictionary).duplicate(true)


func commit_restore(staged: Variant, seat: int, target: Object) -> bool:
	if typeof(staged) != TYPE_DICTIONARY or target == null \
			or not target.has_method("apply_restored_module"):
		return false
	return bool(target.call(
		"apply_restored_module", MODULE_KEY, SCHEMA_VERSION,
		(staged as Dictionary).duplicate(true), seat))


func restore(payload: Variant, seat: int, target: Object) -> bool:
	var staged: Variant = stage_restore(payload, seat)
	if staged == null:
		return false
	return commit_restore(staged, seat, target)
