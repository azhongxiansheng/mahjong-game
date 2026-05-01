extends GutTest

# DoraIndicators 容器（spec §5）：
# - visible: 已翻开的指示牌（开局 1 张 + 每杠 +1）
# - hidden_uradora: 立直胡牌时翻
# 提供综合 dora 数计算（普通 + 赤 + 可选裏）。

func _hand(ids: Array) -> Hand:
	var h := Hand.new()
	for tid in ids:
		h.add(Tile.new(tid))
	return h

func test_default_empty():
	var d := DoraIndicators.new()
	assert_eq(d.visible.size(), 0)
	assert_eq(d.hidden_uradora.size(), 0)
	assert_eq(d.count_total_dora(_hand([TileId.W5]), [], false), 0)

func test_visible_indicator_counts_dora():
	# indicator W4 → dora W5；手中 1 张 W5
	var d := DoraIndicators.new()
	d.add_visible(Tile.new(TileId.W4))
	var h := _hand([TileId.W5, TileId.W3])
	assert_eq(d.count_total_dora(h, [], false), 1)

func test_multiple_visible_indicators_after_kan():
	# 杠后翻新指示牌：W4 + S2 → dora W5 + S3
	var d := DoraIndicators.new()
	d.add_visible(Tile.new(TileId.W4))
	d.add_visible(Tile.new(TileId.S2))
	var h := _hand([TileId.W5, TileId.W5, TileId.S3])
	assert_eq(d.count_total_dora(h, [], false), 3)

func test_red_dora_counted():
	var d := DoraIndicators.new()
	# 没有指示牌也算赤
	var h := Hand.new()
	h.add(Tile.make_red_five_man())
	h.add(Tile.new(TileId.W3))
	assert_eq(d.count_total_dora(h, [], false), 1, "仅赤 dora 1 张")

func test_uradora_included_only_when_requested():
	var d := DoraIndicators.new()
	d.add_visible(Tile.new(TileId.W4))      # dora W5
	d.add_hidden_uradora(Tile.new(TileId.S2))  # uradora S3
	var h := _hand([TileId.W5, TileId.S3])
	assert_eq(d.count_total_dora(h, [], false), 1, "不含裏 dora")
	assert_eq(d.count_total_dora(h, [], true), 2, "含裏 dora")

func test_visible_indicator_ids_helper():
	var d := DoraIndicators.new()
	d.add_visible(Tile.new(TileId.W4))
	d.add_visible(Tile.new(TileId.S2))
	assert_eq(d.visible_indicator_ids(), [TileId.W4, TileId.S2])
