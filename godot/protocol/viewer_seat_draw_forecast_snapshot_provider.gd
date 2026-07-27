class_name ViewerSeatDrawForecastSnapshotProvider
extends SnapshotModuleProvider

const MODULE_KEY := "viewer_seat_draw_forecast"
const SCHEMA_VERSION := 1
const PAYLOAD_KEYS := ["recipient_seat", "hand_seq", "predictions"]
const ROW_KEYS := ["target_seat", "tile"]


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
	var predictions: Variant = RecipientViewProjector.project_viewer_seat_draw_forecast(
		state, seat)
	if typeof(predictions) != TYPE_ARRAY or (predictions as Array).is_empty():
		return null
	return {
		"recipient_seat": seat,
		"hand_seq": int(state.hand_seq),
		"predictions": (predictions as Array).duplicate(true),
	}


func can_restore(payload: Variant, seat: int) -> bool:
	if typeof(payload) != TYPE_DICTIONARY or seat < 0 or seat > 3:
		return false
	var data := payload as Dictionary
	if not _has_exact_keys(data, PAYLOAD_KEYS):
		return false
	if typeof(data["recipient_seat"]) != TYPE_INT \
			or int(data["recipient_seat"]) != seat:
		return false
	if typeof(data["hand_seq"]) != TYPE_INT or int(data["hand_seq"]) < 0:
		return false
	if typeof(data["predictions"]) != TYPE_ARRAY:
		return false
	var rows := data["predictions"] as Array
	if rows.is_empty() or rows.size() > 4:
		return false
	var targets: Dictionary = {}
	var instances: Dictionary = {}
	for value in rows:
		if typeof(value) != TYPE_DICTIONARY:
			return false
		var row := value as Dictionary
		if not _has_exact_keys(row, ROW_KEYS) or typeof(row["target_seat"]) != TYPE_INT:
			return false
		var target := int(row["target_seat"])
		if target < 0 or target > 3 or targets.has(target):
			return false
		var tile_view: Variant = ProtocolViewCodec.tile_view_from_dict(row["tile"])
		if tile_view == null:
			return false
		var iid := int((tile_view as Dictionary)["instance_id"])
		if instances.has(iid) or not Tile.is_instance_id_in_hand_seq(
			iid, int(data["hand_seq"])):
			return false
		targets[target] = true
		instances[iid] = true
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
	return staged != null and commit_restore(staged, seat, target)


static func _has_exact_keys(data: Dictionary, expected: Array) -> bool:
	if data.keys().size() != expected.size():
		return false
	for key in expected:
		if not data.has(key):
			return false
	return true
