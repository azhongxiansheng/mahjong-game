extends GutTest

# 包牌 (PaoCalculator) — 日麻 §11 大三元/大四喜 鸣牌完成时 discarder
# 全额责任。modern dead code:ScoreContext.pao_seat 被 PayoutCalculator
# 读取但生产代码从未设。本测试 cover 检测逻辑。


# Helper:构造一个 open pon meld(from_seat 来自参数)
func _open_pon(tile_id: int, from_seat: int) -> Meld:
	var tiles: Array[Tile] = []
	for _i in range(3):
		tiles.append(Tile.new(tile_id))
	return Meld.make_pon(tiles, from_seat)


func _ankan(tile_id: int) -> Meld:
	var tiles: Array[Tile] = []
	for _i in range(4):
		tiles.append(Tile.new(tile_id))
	return Meld.make_ankan(tiles)


# ---- 无包场景 ----

func test_no_pao_when_yaku_not_daisangen() -> void:
	var melds: Array = [_open_pon(TileId.HAKU, 1)]
	assert_eq(PaoCalculator.detect_pao_seat([YakuId.TOITOI], melds),
		PaoCalculator.NO_SEAT, "无 daisangen 不应有包")


func test_no_pao_when_all_dragons_closed() -> void:
	# 大三元全 ankan(全暗杠)→ 无包
	var melds: Array = [
		_ankan(TileId.HAKU), _ankan(TileId.HATSU), _ankan(TileId.CHUN)]
	assert_eq(PaoCalculator.detect_pao_seat([YakuId.DAISANGEN], melds),
		PaoCalculator.NO_SEAT, "全暗杠不应有包")


# ---- 大三元包 ----

func test_daisangen_pao_with_one_open_dragon() -> void:
	# 2 暗 + 1 明:外鸣的那张是包
	var melds: Array = [
		_ankan(TileId.HAKU),
		_ankan(TileId.HATSU),
		_open_pon(TileId.CHUN, 2),  # seat 2 是包人
	]
	assert_eq(PaoCalculator.detect_pao_seat([YakuId.DAISANGEN], melds), 2,
		"明 CHUN 来自 seat 2 → seat 2 是包")


func test_daisangen_pao_picks_last_open_dragon() -> void:
	# 多个 open dragon:取最后的
	var melds: Array = [
		_open_pon(TileId.HAKU, 1),
		_open_pon(TileId.HATSU, 2),  # 此为最后的 open dragon → 包
		_ankan(TileId.CHUN),
	]
	assert_eq(PaoCalculator.detect_pao_seat([YakuId.DAISANGEN], melds), 2)


# ---- 大四喜包 ----

func test_daisuushi_pao_with_open_wind() -> void:
	var melds: Array = [
		_ankan(TileId.E), _ankan(TileId.S_WIND),
		_open_pon(TileId.W_WIND, 3),
		_ankan(TileId.N),
	]
	assert_eq(PaoCalculator.detect_pao_seat([YakuId.DAISUUSHI], melds), 3,
		"明 W_WIND 来自 seat 3 → 包")


# 小四喜不构成包(只是 single yakuman 不双倍责任)
func test_shousuushi_no_pao() -> void:
	var melds: Array = [
		_open_pon(TileId.E, 1),
		_open_pon(TileId.S_WIND, 2),
		_open_pon(TileId.W_WIND, 3),
	]
	assert_eq(PaoCalculator.detect_pao_seat([YakuId.SHOUSUUSHI], melds),
		PaoCalculator.NO_SEAT, "小四喜不应包")
