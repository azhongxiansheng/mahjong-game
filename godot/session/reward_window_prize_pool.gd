class_name RewardWindowPrizePool extends RefCounted

# E5-04 / #252：开窗奖池确定性选择（纯函数）。
# 输入 seed + hand_seq + window_index + rule_version → 恰好 4 个互不重复 item_id。
# 目录先字典序规范化，再按整数 rank 排序取前 4；禁止浮点/随机/遍历顺序依赖。


## catalog 可注入（测扰动）；默认 TrashTalkRuleCatalog.grantable_item_ids()。
## 成功返回长度 4 的 Array[String]；失败返回 []。
static func select_four(
	match_seed: int,
	p_hand_seq: int,
	p_window_index: int,
	p_rule_version: String,
	catalog: Array = []
) -> Array:
	if p_hand_seq < 0 or p_window_index < 0:
		return []
	if p_rule_version.strip_edges().is_empty():
		return []
	var source: Array = catalog
	if source.is_empty():
		source = TrashTalkRuleCatalog.grantable_item_ids()
	var normalized: Array = _normalize_catalog(source)
	if normalized.size() < 4:
		return []

	var ranked: Array = []
	for id_v in normalized:
		var item_id := String(id_v)
		var rank: int = _rank_for(
			match_seed, p_hand_seq, p_window_index, p_rule_version, item_id
		)
		ranked.append({"id": item_id, "rank": rank})

	ranked.sort_custom(func(a, b):
		var ra: int = int(a["rank"])
		var rb: int = int(b["rank"])
		if ra != rb:
			return ra < rb
		return String(a["id"]) < String(b["id"])
	)

	var out: Array = []
	var seen: Dictionary = {}
	for row in ranked:
		var id2 := String(row["id"])
		if seen.has(id2):
			continue
		seen[id2] = true
		out.append(id2)
		if out.size() == 4:
			break
	if out.size() != 4:
		return []
	# 契约：公开奖池顺序即 rank 决胜序（同输入字节一致）；重复 item 已拒绝
	return out


static func _normalize_catalog(catalog: Array) -> Array:
	var seen: Dictionary = {}
	var out: Array = []
	for v in catalog:
		var id := String(v).strip_edges()
		if id.is_empty() or seen.has(id):
			continue
		# 必须是可发奖道具（规则目录有 def）
		if TrashTalkRuleCatalog.item_def(StringName(id)).is_empty():
			continue
		seen[id] = true
		out.append(id)
	out.sort()
	return out


static func _rank_for(
	match_seed: int,
	hand_seq: int,
	window_index: int,
	rule_version: String,
	item_id: String
) -> int:
	var state: int = match_seed & 0xffffffff
	state = _lcrng_next(state ^ (hand_seq & 0xffffffff))
	state = _lcrng_next(state ^ (window_index & 0xffffffff))
	state = _lcrng_next(state ^ _stable_hash(rule_version))
	state = _lcrng_next(state ^ _stable_hash(item_id))
	return state & 0xffffffff


static func _lcrng_next(state: int) -> int:
	var s: int = state & 0xffffffff
	return int((s * 1664525 + 1013904223) & 0xffffffff)


static func _stable_hash(text: String) -> int:
	var h: int = 2166136261
	for i in range(text.length()):
		h = int((h ^ text.unicode_at(i)) * 16777619) & 0xffffffff
	return h
