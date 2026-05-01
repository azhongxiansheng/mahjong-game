class_name Ryuuiisou

# 緑一色：14 张全部为绿色牌（2索 / 3索 / 4索 / 6索 / 8索 / 发）
const GREEN_TILES: Dictionary = {
	TileId.S2: true,
	TileId.S3: true,
	TileId.S4: true,
	TileId.S6: true,
	TileId.S8: true,
	TileId.HATSU: true,
}

static func detect(wc: WinContext) -> YakuEntry:
	if not wc.win_result.is_winning:
		return null
	if wc.win_result.is_kokushi:
		return null
	for tid in wc.all_tile_ids():
		if not GREEN_TILES.has(tid):
			return null
	return YakuEntry.new(YakuId.RYUUIISOU, 0, true, 1)
