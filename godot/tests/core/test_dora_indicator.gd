extends GutTest

# DoraIndicator: indicator → dora id 转换 + 手牌+副露中 dora 张数统计。
# 复用 TileId.next_for_dora。赤 dora 由 Tile.is_red_dora 标记。

func _hand(ids: Array) -> Hand:
	var h := Hand.new()
	for tid in ids:
		h.add(Tile.new(tid))
	return h

# ---- 单 indicator ----

func test_dora_from_man_indicator():
	assert_eq(DoraIndicator.dora_from_indicator(TileId.W4), TileId.W5)

func test_dora_from_man_9_wraps_to_1():
	assert_eq(DoraIndicator.dora_from_indicator(TileId.W9), TileId.W1)

func test_dora_from_wind_cycles():
	assert_eq(DoraIndicator.dora_from_indicator(TileId.E), TileId.S_WIND)
	assert_eq(DoraIndicator.dora_from_indicator(TileId.N), TileId.E)

func test_dora_from_dragon_cycles():
	assert_eq(DoraIndicator.dora_from_indicator(TileId.HAKU), TileId.HATSU)
	assert_eq(DoraIndicator.dora_from_indicator(TileId.CHUN), TileId.HAKU)

# ---- count_normal_dora ----

func test_count_zero_when_no_dora():
	var h := _hand([TileId.W1, TileId.W2, TileId.W3])
	assert_eq(DoraIndicator.count_normal_dora(h, [], [TileId.S5]), 0)

func test_count_dora_in_hand():
	# indicator W4 → dora W5。手中 2 张 W5
	var h := _hand([TileId.W5, TileId.W5, TileId.W3])
	assert_eq(DoraIndicator.count_normal_dora(h, [], [TileId.W4]), 2)

func test_count_dora_in_called_meld():
	# indicator W4 → dora W5。副露 PON W5W5W5 → 3 张 dora
	var pon := Meld.make_pon(
		[Tile.new(TileId.W5), Tile.new(TileId.W5), Tile.new(TileId.W5)], 0)
	var h := _hand([TileId.W3])
	assert_eq(DoraIndicator.count_normal_dora(h, [pon], [TileId.W4]), 3)

func test_count_dora_combines_hand_and_meld():
	var pon := Meld.make_pon(
		[Tile.new(TileId.W5), Tile.new(TileId.W5), Tile.new(TileId.W5)], 0)
	var h := _hand([TileId.W5, TileId.W3])
	# 手 1 + 副露 3 = 4
	assert_eq(DoraIndicator.count_normal_dora(h, [pon], [TileId.W4]), 4)

func test_count_multiple_indicators():
	# 杠成立后翻新指示牌：W4 + S2 → dora W5 + S3
	# 手中 2 张 W5 + 1 张 S3
	var h := _hand([TileId.W5, TileId.W5, TileId.S3, TileId.T1])
	assert_eq(DoraIndicator.count_normal_dora(h, [], [TileId.W4, TileId.S2]), 3)

# ---- count_red_dora ----

func test_count_red_dora_in_hand():
	var h := Hand.new()
	h.add(Tile.make_red_five_man())
	h.add(Tile.new(TileId.W3))
	h.add(Tile.make_red_five_pin())
	assert_eq(DoraIndicator.count_red_dora(h, []), 2)

func test_count_red_dora_zero():
	var h := _hand([TileId.W5, TileId.T5, TileId.S5])  # 普通 5 不是赤
	assert_eq(DoraIndicator.count_red_dora(h, []), 0)

func test_count_red_dora_in_called_meld():
	# Meld 含 1 张赤 5
	var pon := Meld.make_pon(
		[Tile.make_red_five_sou(), Tile.new(TileId.S5), Tile.new(TileId.S5)], 0)
	var h := Hand.new()
	assert_eq(DoraIndicator.count_red_dora(h, [pon]), 1)
