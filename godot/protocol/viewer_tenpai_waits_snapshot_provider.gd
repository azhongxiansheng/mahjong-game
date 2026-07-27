class_name ViewerTenpaiWaitsSnapshotProvider
extends SnapshotModuleProvider

# Issue #346：recipient 私有对手等待牌种集合。无授权时省略 optional 模块。

const MODULE_KEY := "viewer_tenpai_waits"
const SCHEMA_VERSION := 1
const PAYLOAD_KEYS := ["recipient_seat", "hand_seq", "subjects"]
const SUBJECT_KEYS := ["seat", "wait_tile_ids"]


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
	var subjects := RecipientViewProjector.project_viewer_tenpai_waits(state, seat)
	if subjects.is_empty():
		return null
	return {
		"recipient_seat": seat,
		"hand_seq": int(state.hand_seq),
		"subjects": subjects,
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
	if typeof(data.recipient_seat) != TYPE_INT or int(data.recipient_seat) != seat \
			or typeof(data.hand_seq) != TYPE_INT or int(data.hand_seq) < 0 \
			or typeof(data.subjects) != TYPE_ARRAY:
		return false
	var subjects := data.subjects as Array
	if subjects.is_empty() or subjects.size() > 3:
		return false
	var previous_seat := -1
	for subject_value in subjects:
		if typeof(subject_value) != TYPE_DICTIONARY:
			return false
		var subject := subject_value as Dictionary
		if subject.keys().size() != SUBJECT_KEYS.size() \
				or not subject.has("seat") or not subject.has("wait_tile_ids") \
				or typeof(subject.seat) != TYPE_INT or typeof(subject.wait_tile_ids) != TYPE_ARRAY:
			return false
		var subject_seat := int(subject.seat)
		if subject_seat <= previous_seat or subject_seat < 0 or subject_seat > 3 \
				or subject_seat == seat:
			return false
		previous_seat = subject_seat
		var waits := subject.wait_tile_ids as Array
		if waits.is_empty() or waits.size() > TileId.ALL.size():
			return false
		var previous_tile := -1
		for tile_id in waits:
			if typeof(tile_id) != TYPE_INT or not TileId.ALL.has(tile_id) \
					or int(tile_id) <= previous_tile:
				return false
			previous_tile = int(tile_id)
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
