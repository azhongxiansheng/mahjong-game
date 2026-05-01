extends GutTest

# 日麻面子符（标准）：
#   顺子：0
#   明刻 中张：2 / 幺九：4
#   暗刻 中张：4 / 幺九：8
#   明杠 中张：8 / 幺九：16
#   暗杠 中张：16 / 幺九：32
# fu_for_decomp_meld 处理 StandardDecomposer 输出（[a,a,a] 刻 / [a,a+1,a+2] 顺）
# fu_for_called_meld 处理已副露的 Meld 对象

# ---- decomp meld（来自 StandardDecomposer 暗牌分解） ----

func test_decomp_chow_is_zero():
	var fu := MeldFu.fu_for_decomp_meld([TileId.W2, TileId.W3, TileId.W4], true)
	assert_eq(fu, 0)

func test_decomp_concealed_simple_triplet():
	var fu := MeldFu.fu_for_decomp_meld([TileId.W5, TileId.W5, TileId.W5], true)
	assert_eq(fu, 4, "暗刻中张 4")

func test_decomp_concealed_yaochu_triplet():
	var fu := MeldFu.fu_for_decomp_meld([TileId.W1, TileId.W1, TileId.W1], true)
	assert_eq(fu, 8, "暗刻幺九 8")
	var fu2 := MeldFu.fu_for_decomp_meld([TileId.E, TileId.E, TileId.E], true)
	assert_eq(fu2, 8, "暗刻字牌 8")

func test_decomp_open_simple_triplet():
	# 注：分解出来的刻子也可能是"碰"得来的（is_concealed=false 表示来自副露 PON 转回的刻子）
	var fu := MeldFu.fu_for_decomp_meld([TileId.T6, TileId.T6, TileId.T6], false)
	assert_eq(fu, 2, "明刻中张 2")

func test_decomp_open_yaochu_triplet():
	var fu := MeldFu.fu_for_decomp_meld([TileId.T9, TileId.T9, TileId.T9], false)
	assert_eq(fu, 4, "明刻幺九 4")
	var fu2 := MeldFu.fu_for_decomp_meld([TileId.HAKU, TileId.HAKU, TileId.HAKU], false)
	assert_eq(fu2, 4, "明刻字牌 4")

# ---- called meld（已副露的 Meld 对象） ----

func test_called_chi_is_zero():
	var m := Meld.make_chi(
		[Tile.new(TileId.W2), Tile.new(TileId.W3), Tile.new(TileId.W4)], 0)
	assert_eq(MeldFu.fu_for_called_meld(m), 0)

func test_called_pon_simple():
	var m := Meld.make_pon(
		[Tile.new(TileId.S5), Tile.new(TileId.S5), Tile.new(TileId.S5)], 1)
	assert_eq(MeldFu.fu_for_called_meld(m), 2, "明刻中张")

func test_called_pon_yaochu():
	var m := Meld.make_pon(
		[Tile.new(TileId.W1), Tile.new(TileId.W1), Tile.new(TileId.W1)], 1)
	assert_eq(MeldFu.fu_for_called_meld(m), 4, "明刻幺九")

func test_called_minkan_simple():
	var m := Meld.make_minkan(
		[Tile.new(TileId.T7), Tile.new(TileId.T7), Tile.new(TileId.T7), Tile.new(TileId.T7)], 2)
	assert_eq(MeldFu.fu_for_called_meld(m), 8, "明杠中张")

func test_called_minkan_yaochu():
	var m := Meld.make_minkan(
		[Tile.new(TileId.S9), Tile.new(TileId.S9), Tile.new(TileId.S9), Tile.new(TileId.S9)], 2)
	assert_eq(MeldFu.fu_for_called_meld(m), 16, "明杠幺九")

func test_called_added_kan_simple():
	# 加杠（小明杠）算明杠
	var m := Meld.make_added_kan(
		[Tile.new(TileId.T3), Tile.new(TileId.T3), Tile.new(TileId.T3), Tile.new(TileId.T3)], 0)
	assert_eq(MeldFu.fu_for_called_meld(m), 8, "加杠按明杠 中张")

func test_called_ankan_simple():
	var m := Meld.make_ankan(
		[Tile.new(TileId.W5), Tile.new(TileId.W5), Tile.new(TileId.W5), Tile.new(TileId.W5)])
	assert_eq(MeldFu.fu_for_called_meld(m), 16, "暗杠中张")

func test_called_ankan_yaochu():
	var m := Meld.make_ankan(
		[Tile.new(TileId.E), Tile.new(TileId.E), Tile.new(TileId.E), Tile.new(TileId.E)])
	assert_eq(MeldFu.fu_for_called_meld(m), 32, "暗杠幺九/字")

func test_decomp_meld_size_2_returns_zero():
	# 防御：传入异常长度返 0
	var fu := MeldFu.fu_for_decomp_meld([TileId.W5, TileId.W5], true)
	assert_eq(fu, 0)
