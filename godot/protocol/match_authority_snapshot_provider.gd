class_name MatchAuthoritySnapshotProvider
extends SnapshotModuleProvider

# #376：整场 match 权威投影（hand_index/finished/cumulative 等）。
# 严格 exact schema：禁止额外键；内部一致性校验。


const MODULE_KEY := "match_authority"
const SCHEMA_VERSION := 1
const EXACT_KEYS := [
	"hand_index", "hand_seq", "next_hand_seq", "dealer_seat",
	"honba", "riichi_sticks", "cumulative_scores", "round_wind",
	"finished", "total_hands", "hands_per_round",
]


func module_key() -> String:
	return MODULE_KEY


func schema_version() -> int:
	return SCHEMA_VERSION


func is_required() -> bool:
	return false


func serialize(ctx: Dictionary, seat: int) -> Variant:
	if seat < 0 or seat > 3:
		return null
	var raw: Variant = ctx.get("match_authority", null)
	if typeof(raw) != TYPE_DICTIONARY:
		return null
	var d: Dictionary = raw
	if not can_restore(d, seat):
		return null
	return _normalize(d)


func can_restore(payload: Variant, seat: int) -> bool:
	if seat < 0 or seat > 3:
		return false
	if typeof(payload) != TYPE_DICTIONARY:
		return false
	var d: Dictionary = payload
	# #376 P2-3：exact keys — 禁止缺键/额外键
	if d.size() != EXACT_KEYS.size():
		return false
	for k in EXACT_KEYS:
		if not d.has(k):
			return false
	for k2 in d.keys():
		var found := false
		for ek in EXACT_KEYS:
			if str(k2) == str(ek):
				found = true
				break
		if not found:
			return false
	if typeof(d["hand_index"]) != TYPE_INT or int(d["hand_index"]) < 0:
		return false
	if typeof(d["hand_seq"]) != TYPE_INT or int(d["hand_seq"]) < 0:
		return false
	if typeof(d["next_hand_seq"]) != TYPE_INT or int(d["next_hand_seq"]) < 0:
		return false
	if typeof(d["dealer_seat"]) != TYPE_INT:
		return false
	var dealer: int = int(d["dealer_seat"])
	if dealer < 0 or dealer > 3:
		return false
	if typeof(d["honba"]) != TYPE_INT or int(d["honba"]) < 0:
		return false
	if typeof(d["riichi_sticks"]) != TYPE_INT or int(d["riichi_sticks"]) < 0:
		return false
	if typeof(d["round_wind"]) != TYPE_INT:
		return false
	var rw: int = int(d["round_wind"])
	if rw != TileId.E and rw != TileId.S_WIND and rw != TileId.W_WIND and rw != TileId.N:
		return false
	if typeof(d["finished"]) != TYPE_BOOL:
		return false
	if typeof(d["total_hands"]) != TYPE_INT or int(d["total_hands"]) < 1:
		return false
	if typeof(d["hands_per_round"]) != TYPE_INT or int(d["hands_per_round"]) < 1:
		return false
	if typeof(d["cumulative_scores"]) != TYPE_ARRAY:
		return false
	var scores: Array = d["cumulative_scores"]
	if scores.size() != 4:
		return false
	for s in scores:
		if typeof(s) != TYPE_INT:
			return false
	# #376 R4/R5：对齐 GameDriver.export_match_state 生产不变量（无经验余量）
	var hi: int = int(d["hand_index"])
	var hs: int = int(d["hand_seq"])
	var nhs: int = int(d["next_hand_seq"])
	var total: int = int(d["total_hands"])
	var hpr: int = int(d["hands_per_round"])
	var finished: bool = bool(d["finished"])
	# 本项目仅 EAST{total=4,hpr=4} / HANCHAN{total=8,hpr=4}
	var east_ok: bool = total == 4 and hpr == 4
	var hanchan_ok: bool = total == 8 and hpr == 4
	if not east_ok and not hanchan_ok:
		return false
	# next_hand_seq 恒为已分配下一序号 = 当前/上一 hand_seq + 1
	if nhs != hs + 1:
		return false
	if finished:
		# 非连庄终场：hand_index 恰等于 total_hands
		if hi != total:
			return false
	else:
		if hi < 0 or hi >= total:
			return false
	# round_wind 由有效局索引推导：进行中用 hand_index；终场用最后完成局 hand_index-1
	# GameDriver 仅导出东/南
	var wind_idx: int = hi
	if finished:
		wind_idx = maxi(0, hi - 1)
	var expect_wind: int = TileId.E if wind_idx < hpr else TileId.S_WIND
	if rw != expect_wind:
		return false
	return true


func stage_restore(payload: Variant, seat: int) -> Variant:
	if not can_restore(payload, seat):
		return null
	return _normalize(payload as Dictionary)


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


static func _normalize(d: Dictionary) -> Dictionary:
	var scores: Array = []
	for s in d["cumulative_scores"]:
		scores.append(int(s))
	return {
		"hand_index": int(d["hand_index"]),
		"hand_seq": int(d["hand_seq"]),
		"next_hand_seq": int(d["next_hand_seq"]),
		"dealer_seat": int(d["dealer_seat"]),
		"honba": int(d["honba"]),
		"riichi_sticks": int(d["riichi_sticks"]),
		"cumulative_scores": scores,
		"round_wind": int(d["round_wind"]),
		"finished": bool(d["finished"]),
		"total_hands": int(d["total_hands"]),
		"hands_per_round": int(d["hands_per_round"]),
	}


## 从 GameDriver.export_match_state 规范化为模块 payload。
static func from_export(export_state: Dictionary) -> Dictionary:
	if export_state.is_empty():
		return {}
	var scores: Array = []
	var raw_scores: Variant = export_state.get("cumulative_scores", [])
	if typeof(raw_scores) == TYPE_ARRAY:
		for s in raw_scores:
			scores.append(int(s))
	if scores.size() != 4:
		return {}
	var dealer: int = int(export_state.get("dealer_seat", export_state.get("dealer", 0)))
	return {
		"hand_index": int(export_state.get("hand_index", 0)),
		"hand_seq": int(export_state.get("hand_seq", 0)),
		"next_hand_seq": int(export_state.get("next_hand_seq", 0)),
		"dealer_seat": dealer,
		"honba": int(export_state.get("honba", 0)),
		"riichi_sticks": int(export_state.get("riichi_sticks", 0)),
		"cumulative_scores": scores,
		"round_wind": int(export_state.get("round_wind", TileId.E)),
		"finished": bool(export_state.get("finished", false)),
		"total_hands": int(export_state.get("total_hands", 4)),
		"hands_per_round": int(export_state.get("hands_per_round", 4)),
	}
