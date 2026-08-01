class_name AuthoritySnapshotService extends RefCounted

# ARCH-02 #392（spec 2026-07-29 §5.3）：权威快照服务组件。
# 唯一职责：snapshot registry 持有、按席 ROOM_SNAPSHOT payload 组装
#（modules 序列化 + headless match_authority@1 校验 + 顶层四键）与已提交
# SNAP hash 回查。禁止承担：内部完整 replay snapshot（仍属 ARS）。
# ctx 组装（roster/config/RW/库存/match_authority 导出与测试 seam）
# 仍由 façade 负责；本组件只做组合与校验，语义与拆分前逐字一致。

var registry: SnapshotModuleRegistry = null


## ctx 约定：除 registry serialize 所需键外，额外读取
## - "has_match_owner": bool —— headless 时 match_authority 缺失/非法必须整 SNAP 失败
## - "match_authority": Dictionary —— 空时不注入模块（Practice optional）
func build_room_snapshot_payload(ctx_in: Dictionary, seat: int, seq: int) -> Dictionary:
	if registry == null:
		return {}
	var ctx: Dictionary = ctx_in.duplicate()
	var has_match_owner: bool = bool(ctx.get("has_match_owner", false))
	ctx.erase("has_match_owner")
	var match_pl: Dictionary = ctx.get("match_authority", {}) as Dictionary
	if has_match_owner:
		# #376 R5：Headless（match_owner）必须有合法 match_authority；失败整 SNAP 失败。
		if match_pl.is_empty():
			return {}
	elif match_pl.is_empty():
		ctx.erase("match_authority")
	if ctx.get("state", null) == null:
		return {}
	var ser: Dictionary = registry.serialize_modules(ctx, seat)
	if not bool(ser.get("ok", false)):
		return {}
	var modules: Array = ser.get("modules", [])
	if typeof(modules) != TYPE_ARRAY or (modules as Array).is_empty():
		return {}
	# Headless：committed SNAP 必须恰好含 match_authority@1（禁静默省略）
	if has_match_owner:
		var ma_n := 0
		for m in modules:
			if typeof(m) == TYPE_DICTIONARY \
					and str((m as Dictionary).get("module_key", "")) == "match_authority":
				ma_n += 1
		if ma_n != 1:
			return {}
	return {
		"snapshot_server_seq": seq,
		"next_server_seq": seq + 1,
		"seat_view": seat,
		"modules": modules,
	}


## journal 倒扫最近一条 ROOM_SNAPSHOT 的 view_hash；无/非法返 ""。
static func last_committed_snapshot_view_hash(journal: Array) -> String:
	for i in range(journal.size() - 1, -1, -1):
		var item = journal[i]
		if not (item is NetworkedEvent):
			continue
		var ne: NetworkedEvent = item as NetworkedEvent
		if ne.kind != "ROOM_SNAPSHOT":
			continue
		var vh: String = str(ne.view_hash)
		if vh.is_empty() or vh.length() != 64:
			return ""
		return vh
	return ""
