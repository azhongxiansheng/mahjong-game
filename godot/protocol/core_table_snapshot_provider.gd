class_name CoreTableSnapshotProvider
extends SnapshotModuleProvider

# #241：必需 core_table@1 provider。payload 由 RecipientViewProjector 生成；
# 组合器不改写业务字段。


const MODULE_KEY := "core_table"
const SCHEMA_VERSION := 1


func module_key() -> String:
	return MODULE_KEY


func schema_version() -> int:
	return SCHEMA_VERSION


func is_required() -> bool:
	return true


func serialize(ctx: Dictionary, seat: int) -> Variant:
	var state: Variant = ctx.get("state", null)
	return RecipientViewProjector.project_core_table(state, seat)


func can_restore(payload: Variant, seat: int) -> bool:
	if typeof(payload) != TYPE_DICTIONARY:
		return false
	if seat < 0 or seat > 3:
		return false
	var d: Dictionary = payload
	if int(d.get("recipient_seat", -1)) != seat:
		return false
	if not d.has("hand_seq") or not d.has("seats") or not d.has("phase"):
		return false
	if typeof(d["seats"]) != TYPE_ARRAY:
		return false
	return (d["seats"] as Array).size() == 4


func stage_restore(payload: Variant, seat: int) -> Variant:
	if not can_restore(payload, seat):
		return null
	return (payload as Dictionary).duplicate(true)


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
