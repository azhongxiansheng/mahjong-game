class_name PairFu

# 雀头符：役牌雀头 +2，否则 0。连风牌按 +2（plan assumption #3，与天凤一致）。

static func fu_for_pair(pair_id: int, round_wind: int, seat_wind: int) -> int:
	# 三元牌：白发中
	if pair_id == TileId.HAKU or pair_id == TileId.HATSU or pair_id == TileId.CHUN:
		return 2
	# 场风 / 自风
	if pair_id == round_wind or pair_id == seat_wind:
		return 2
	return 0
