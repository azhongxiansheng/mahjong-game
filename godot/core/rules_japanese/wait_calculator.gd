class_name WaitCalculator

# 听牌张计算：枚举 34 张候选 winning_tile，复用 WinPattern.detect 判断 is_winning。
# 输入：13 张暗手牌 + 副露列表（hand.size + 3*called_melds.size == 13）
# 输出：升序 id 数组

static func wait_tiles(hand: Hand, called_melds: Array) -> Array:
	var typed_called: Array[Meld] = []
	for m in called_melds:
		typed_called.append(m)

	var waits: Array = []
	for candidate_id in TileId.ALL:
		var win_tile := Tile.new(candidate_id)
		var r := WinPattern.detect(hand, typed_called, win_tile)
		if r.is_winning:
			waits.append(candidate_id)
	return waits

# M10：HeuristicAi tenpai-first 决策用早退检查（不需要完整 wait list）。
# 返 true 表示存在至少 1 张合 winning_tile（即 13-hand 听牌）。
# 性能：worst case = 34 detects（与 wait_tiles 相同）；典型 tenpai 立即返。
static func is_tenpai(hand: Hand, called_melds: Array) -> bool:
	var typed_called: Array[Meld] = []
	for m in called_melds:
		typed_called.append(m)
	for candidate_id in TileId.ALL:
		var win_tile := Tile.new(candidate_id)
		var r := WinPattern.detect(hand, typed_called, win_tile)
		if r.is_winning:
			return true
	return false
