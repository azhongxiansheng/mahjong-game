class_name ItemInventorySnapshotProvider
extends SnapshotModuleProvider

# #253：按席 ItemInstance[] + active/pending 快照 provider。
# 仅该席完整库存与武装；不含他席/seed/隐藏牌。STANDARD 不注册。

const MODULE_KEY := "item_inventory"
const SCHEMA_VERSION := ItemInventoryModule.SCHEMA_VERSION


func module_key() -> String:
	return MODULE_KEY


func schema_version() -> int:
	return SCHEMA_VERSION


func is_required() -> bool:
	return true


func serialize(ctx: Dictionary, seat: int) -> Variant:
	if seat < 0 or seat > 3:
		return null
	var inv_v: Variant = ctx.get("item_inventory", null)
	if inv_v == null or not (inv_v is ItemInventoryModule):
		return null
	var inv: ItemInventoryModule = inv_v as ItemInventoryModule
	var dto: Dictionary = inv.to_seat_snapshot_dto(seat)
	if str(dto.get("module_key", "")) != MODULE_KEY:
		return null
	if int(dto.get("schema_version", -1)) != SCHEMA_VERSION:
		return null
	var payload: Variant = dto.get("payload", null)
	if typeof(payload) != TYPE_DICTIONARY:
		return null
	return (payload as Dictionary).duplicate(true)


func can_restore(payload: Variant, seat: int) -> bool:
	if seat < 0 or seat > 3:
		return false
	if typeof(payload) != TYPE_DICTIONARY:
		return false
	var p: Dictionary = payload
	if int(p.get("seat", -1)) != seat:
		return false
	if typeof(p.get("items", null)) != TYPE_ARRAY:
		return false
	var act = p.get("active_window_id", null)
	var pen = p.get("pending_window_id", null)
	if act != null and (typeof(act) != TYPE_STRING or String(act).is_empty()):
		return false
	if pen != null and (typeof(pen) != TYPE_STRING or String(pen).is_empty()):
		return false
	for raw in p["items"]:
		if typeof(raw) != TYPE_DICTIONARY:
			return false
		var row: Dictionary = (raw as Dictionary).duplicate(true)
		if not row.has("seat"):
			row["seat"] = seat
		var st := String(row.get("status", ItemInstance.STATUS_HELD))
		if st != ItemInstance.STATUS_HELD and st != ItemInstance.STATUS_ARMED:
			return false
		row["status"] = st
		var inst: ItemInstance = ItemInstance.from_dict(row)
		if inst == null or inst.seat != seat:
			return false
	return true


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
