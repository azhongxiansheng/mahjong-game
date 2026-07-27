class_name ViewerNextDrawSnapshotProvider
extends SnapshotModuleProvider

# #344：recipient 私有下一摸投影。独立于稳定的 core_table@1；无有效预知时
# optional provider 返回 null，由 registry 省略整个模块。

const MODULE_KEY := "viewer_next_draw"
const SCHEMA_VERSION := 1
const PAYLOAD_KEYS := ["recipient_seat", "hand_seq", "tile"]


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
	var tile_view: Variant = RecipientViewProjector.project_viewer_next_draw(state, seat)
	if tile_view == null:
		return null
	return {
		"recipient_seat": seat,
		"hand_seq": int(state.hand_seq),
		"tile": (tile_view as Dictionary).duplicate(true),
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
	if typeof(data["hand_seq"]) != TYPE_INT or int(data["hand_seq"]) < 0:
		return false
	var tile_view: Variant = ProtocolViewCodec.tile_view_from_dict(data["tile"])
	if tile_view == null:
		return false
	return Tile.is_instance_id_in_hand_seq(
		int((tile_view as Dictionary)["instance_id"]), int(data["hand_seq"]))


func stage_restore(payload: Variant, seat: int) -> Variant:
	if not can_restore(payload, seat):
		return null
	return (payload as Dictionary).duplicate(true)


func commit_restore(staged: Variant, seat: int, target: Object) -> bool:
	if typeof(staged) != TYPE_DICTIONARY or target == null:
		return false
	if not target.has_method("apply_restored_module"):
		return false
	return bool(target.call(
		"apply_restored_module",
		MODULE_KEY,
		SCHEMA_VERSION,
		(staged as Dictionary).duplicate(true),
		seat
	))


func restore(payload: Variant, seat: int, target: Object) -> bool:
	var staged: Variant = stage_restore(payload, seat)
	if staged == null:
		return false
	return commit_restore(staged, seat, target)
