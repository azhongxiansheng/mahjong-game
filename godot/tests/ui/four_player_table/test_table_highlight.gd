extends GutTest

# 全桌同名高亮：FourPlayerTable.highlight_tile_id（河 + 副露）


func test_highlight_and_clear_on_discard_river() -> void:
	var table: FourPlayerTable = load("res://ui/four_player_table/four_player_table.tscn").instantiate()
	add_child_autofree(table)
	await get_tree().process_frame
	assert_gt(table.discard_rivers.size(), 0)
	var dr: DiscardRiver = table.discard_rivers[0]
	# 注入两张弃牌
	var t1 := Tile.new(TileId.W5)
	var t2 := Tile.new(TileId.T1)
	dr.set_tiles([t1, t2], -1)
	await get_tree().process_frame
	table.highlight_tile_id(TileId.W5)
	assert_eq(dr.count_hover_matched(), 1, "河中 1 张五万应高亮")
	table.clear_tile_highlight()
	assert_eq(dr.count_hover_matched(), 0)


func test_highlight_also_covers_meld_area() -> void:
	var table: FourPlayerTable = load("res://ui/four_player_table/four_player_table.tscn").instantiate()
	add_child_autofree(table)
	await get_tree().process_frame
	assert_gt(table.meld_areas.size(), 0)
	var ma: MeldArea = table.meld_areas[0]
	# 碰三张 5 万（来自 seat 1）
	var tiles: Array[Tile] = [Tile.new(TileId.W5), Tile.new(TileId.W5), Tile.new(TileId.W5)]
	var pon := Meld.make_pon(tiles, 1)
	ma.set_melds([pon], 0)
	await get_tree().process_frame
	table.highlight_tile_id(TileId.W5)
	assert_eq(ma.count_hover_matched(), 3, "副露 3 张五万应全部同名高亮")
	table.clear_tile_highlight()
	assert_eq(ma.count_hover_matched(), 0)
