class_name WaitFu

# 待牌符（标准日麻）：边/嵌/单骑 +2；双面/双碰 0。
# 一手可能有多种待牌型解释（同一分解内 winning 同时出现在 pair 与 meld）→ 取 max fu。

# decomposition: {melds: Array, pair: int}（含 winning 的 14 张分解）
static func fu_for_wait(decomposition: Dictionary, winning_tile_id: int) -> int:
	var best := 0
	# 单骑：winning 是雀头
	if decomposition.pair == winning_tile_id:
		best = max(best, 2)
	# 各 meld 内：刻子=双碰 0；顺子按 winning 在 [a,a+1,a+2] 中的位置
	for meld_ids in decomposition.melds:
		if not (winning_tile_id in meld_ids):
			continue
		# 刻子（[a,a,a]）
		if meld_ids[0] == meld_ids[1]:
			best = max(best, 0)
			continue
		# 顺子 [a, a+1, a+2]
		var a: int = meld_ids[0]
		var fu := _wait_fu_for_chow(a, winning_tile_id)
		best = max(best, fu)
	return best

# 顺子 [a, a+1, a+2] 内的 winning 位置 → wait fu
static func _wait_fu_for_chow(a: int, winning: int) -> int:
	# 嵌张：winning == a+1
	if winning == a + 1:
		return 2
	# winning == a：原型 (a+1, a+2)，等 a 或 a+3。a+3 越界（a+2==9，即 number(a+2)==9 即 number(a)==7）→ 边张
	if winning == a:
		if TileId.number(a) == 7:  # 原型 (8, 9) 等 7 边张
			return 2
		return 0  # 双面
	# winning == a+2：原型 (a, a+1)，等 a-1 或 a+2。a-1 越界（a==1, number(a)==1）→ 边张
	if winning == a + 2:
		if TileId.number(a) == 1:  # 原型 (1, 2) 等 3 边张
			return 2
		return 0  # 双面
	return 0
