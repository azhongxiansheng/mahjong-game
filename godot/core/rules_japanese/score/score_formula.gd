class_name ScoreFormula

# 基本点公式：base = fu × 2^(2+han)，按番数钳到满贯档；役满走单独路径。
# spec §14: 役满倍数上限 2 倍。
# 不实施"切上満貫"（30符4番=1920 按 1920 算，与天凤一致）。

const MAX_YAKUMAN_MULTIPLIER: int = 2

# 基本点。base × 4 = 闲家荣胡总额，× 6 = 庄家荣胡总额，× 1/2 = 自摸单家份额。
static func base_points(fu: int, han: int, yakuman_multiplier: int = 0) -> int:
	if yakuman_multiplier > 0:
		var m: int = mini(yakuman_multiplier, MAX_YAKUMAN_MULTIPLIER)
		return 8000 * m
	if han >= 13:
		return 8000  # 累计役满
	if han >= 11:
		return 6000  # 三倍满
	if han >= 8:
		return 4000  # 倍满
	if han >= 6:
		return 3000  # 跳满
	if han == 5:
		return 2000  # 满贯
	# han 1-4：raw 公式 + 满贯钳制
	var raw: int = fu * (1 << (2 + han))
	if raw > 2000:
		return 2000
	return raw
