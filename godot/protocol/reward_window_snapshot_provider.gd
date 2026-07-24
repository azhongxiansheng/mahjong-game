class_name RewardWindowSnapshotProvider
extends SnapshotModuleProvider

# #252：RewardWindow 快照 provider（E5-04）。
# 权威 serialize 使用真实 RewardWindowModule 公开 DTO；不含 seed/隐藏牌/ARS。
# 客户端两阶段 restore 仅投影公共状态；不重建权威计时器或第二套窗口。


const MODULE_KEY := "reward_window"
const SCHEMA_VERSION := RewardWindowModule.SCHEMA_VERSION


func module_key() -> String:
	return MODULE_KEY


func schema_version() -> int:
	return SCHEMA_VERSION


func is_required() -> bool:
	# TRASH_TALK 注册表内为必需；STANDARD 根本不注册本 provider
	return true


func serialize(ctx: Dictionary, seat: int) -> Variant:
	if seat < 0 or seat > 3:
		return null
	var rw_v: Variant = ctx.get("reward_window", null)
	if rw_v == null or not (rw_v is RewardWindowModule):
		return null
	var rw: RewardWindowModule = rw_v as RewardWindowModule
	var dto: Dictionary = rw.to_snapshot_dto()
	if str(dto.get("module_key", "")) != MODULE_KEY:
		return null
	if int(dto.get("schema_version", -1)) != SCHEMA_VERSION:
		return null
	var payload: Variant = dto.get("payload", null)
	if typeof(payload) != TYPE_DICTIONARY:
		return null
	# 公开 DTO 已剥离 seed；再扫一遍禁止键，按席视图同公开内容
	if not _payload_hides_secrets(payload as Dictionary):
		return null
	return (payload as Dictionary).duplicate(true)


func can_restore(payload: Variant, seat: int) -> bool:
	if seat < 0 or seat > 3:
		return false
	if typeof(payload) != TYPE_DICTIONARY:
		return false
	if not _payload_hides_secrets(payload as Dictionary):
		return false
	# 复用 RewardWindowModule 真实公开 DTO 校验（临时实例，无副作用落到权威）
	var probe := RewardWindowModule.new()
	var r: Dictionary = probe.restore_from_snapshot_dto({
		"module_key": MODULE_KEY,
		"schema_version": SCHEMA_VERSION,
		"payload": (payload as Dictionary).duplicate(true),
	})
	return bool(r.get("ok", false))


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


func _payload_hides_secrets(p: Dictionary) -> bool:
	# 公开 payload 不得含 seed / 私有手牌 / 隐藏墙
	for k in p.keys():
		var ks := String(k)
		if ks == "seed" or ks == "match_seed" or ks == "_match_seed":
			return false
		if ks == "hand" or ks == "private_hand" or ks == "wall" or ks == "hidden_tiles":
			return false
	# 深度扫常见嵌套
	if p.has("public_events") and typeof(p["public_events"]) == TYPE_ARRAY:
		for ev in p["public_events"]:
			if typeof(ev) == TYPE_DICTIONARY and not _dict_hides_secrets(ev as Dictionary):
				return false
	if p.has("utterances_by_seat") and typeof(p["utterances_by_seat"]) == TYPE_DICTIONARY:
		if not _dict_hides_secrets(p["utterances_by_seat"] as Dictionary):
			return false
	return true


func _dict_hides_secrets(d: Dictionary) -> bool:
	for k in d.keys():
		var ks := String(k)
		if ks == "seed" or ks == "match_seed" or ks == "_match_seed":
			return false
		if ks == "hand" or ks == "private_hand" or ks == "wall" or ks == "hidden_tiles":
			return false
		var v: Variant = d[k]
		if typeof(v) == TYPE_DICTIONARY:
			if not _dict_hides_secrets(v as Dictionary):
				return false
		elif typeof(v) == TYPE_ARRAY:
			for item in v as Array:
				if typeof(item) == TYPE_DICTIONARY \
						and not _dict_hides_secrets(item as Dictionary):
					return false
	return true
