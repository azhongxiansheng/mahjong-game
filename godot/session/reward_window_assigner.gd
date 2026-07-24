class_name RewardWindowAssigner extends RefCounted

# E5-04 / #252：4×4 双射一对一分配（纯函数）。
# 枚举 4! = 24 种双射；最大化四席 total_score 之和；并列取 seat0..3 的 item_id 向量字典序最小。
# 只用整数；不依赖浮点、随机或容器遍历顺序。

const ASSIGNMENT_VERSION := "assign_v1"


## matrix: 16 行 {seat, item_id, total_score, ...}；pool: 恰好 4 个互异 item_id。
## 成功 → {ok:true, assignment:{"0":id,...}, assignment_version, total_score_sum}
## 失败 → {ok:false, reason:...}
static func assign_bijection(matrix: Array, pool: Array) -> Dictionary:
	var pool_norm: Array = _normalize_pool(pool)
	if pool_norm.is_empty():
		return {"ok": false, "reason": "INVALID_POOL", "assignment": {}}

	var scores: Dictionary = _build_score_map(matrix, pool_norm)
	if scores.is_empty():
		return {"ok": false, "reason": "INVALID_MATRIX", "assignment": {}}

	var perms: Array = _all_permutations(pool_norm)
	if perms.size() != 24:
		return {"ok": false, "reason": "PERMUTATION_COUNT", "assignment": {}}

	var best_sum: int = -1
	var best_vec: Array = []
	for perm_v in perms:
		var perm: Array = perm_v
		var sum: int = 0
		for seat in range(4):
			var item_id: String = String(perm[seat])
			var key := "%d|%s" % [seat, item_id]
			sum += int(scores.get(key, 0))
		if best_vec.is_empty() or sum > best_sum or (sum == best_sum and _lex_less(perm, best_vec)):
			best_sum = sum
			best_vec = perm.duplicate()

	if best_vec.size() != 4:
		return {"ok": false, "reason": "NO_ASSIGNMENT", "assignment": {}}

	return {
		"ok": true,
		"assignment": {
			"0": String(best_vec[0]),
			"1": String(best_vec[1]),
			"2": String(best_vec[2]),
			"3": String(best_vec[3]),
		},
		"assignment_version": ASSIGNMENT_VERSION,
		"total_score_sum": best_sum,
	}


## 从 scorer 矩阵构建 4×4 scores 摘要（行=seat，列=pool 顺序）。
static func matrix_summary_from_scorer(matrix: Array, pool: Array) -> Dictionary:
	var pool_norm: Array = _normalize_pool(pool)
	var scores_map: Dictionary = _build_score_map(matrix, pool_norm)
	var rows: Array = []
	for seat in range(4):
		var row: Array = []
		for item_id in pool_norm:
			var key := "%d|%s" % [seat, String(item_id)]
			row.append(int(scores_map.get(key, 0)))
		rows.append(row)
	return {"scores": rows}


static func _normalize_pool(pool: Array) -> Array:
	if pool == null or pool.size() != 4:
		return []
	var seen: Dictionary = {}
	var out: Array = []
	for v in pool:
		var id := String(v).strip_edges()
		if id.is_empty() or seen.has(id):
			return []
		seen[id] = true
		out.append(id)
	return out


static func _build_score_map(matrix: Array, pool: Array) -> Dictionary:
	if matrix == null or matrix.size() != 16:
		return {}
	var need: Dictionary = {}
	for seat in range(4):
		for item_id in pool:
			need["%d|%s" % [seat, String(item_id)]] = true
	var out: Dictionary = {}
	for row_v in matrix:
		if typeof(row_v) != TYPE_DICTIONARY:
			return {}
		var row: Dictionary = row_v
		if not _is_int(row.get("seat", null)) or not _is_int(row.get("total_score", null)):
			return {}
		var seat: int = int(row["seat"])
		if seat < 0 or seat > 3:
			return {}
		var item_id := String(row.get("item_id", "")).strip_edges()
		if item_id.is_empty():
			return {}
		var key := "%d|%s" % [seat, item_id]
		if not need.has(key):
			# 允许矩阵含奖池外 item 时仍忽略；但最终 need 必须全覆盖
			continue
		out[key] = int(row["total_score"])
	for k in need.keys():
		if not out.has(k):
			return {}
	return out


static func _all_permutations(items: Array) -> Array:
	var out: Array = []
	_permute_rec(items.duplicate(), 0, out)
	# 稳定排序：按序列字典序，消除递归生成顺序依赖
	out.sort_custom(func(a, b): return _lex_less(a, b))
	return out


static func _permute_rec(arr: Array, start: int, out: Array) -> void:
	if start >= arr.size():
		out.append(arr.duplicate())
		return
	for i in range(start, arr.size()):
		var tmp = arr[start]
		arr[start] = arr[i]
		arr[i] = tmp
		_permute_rec(arr, start + 1, out)
		tmp = arr[start]
		arr[start] = arr[i]
		arr[i] = tmp


static func _lex_less(a: Array, b: Array) -> bool:
	var n: int = mini(a.size(), b.size())
	for i in range(n):
		var sa := String(a[i])
		var sb := String(b[i])
		if sa < sb:
			return true
		if sa > sb:
			return false
	return a.size() < b.size()


static func _is_int(v: Variant) -> bool:
	return typeof(v) == TYPE_INT
