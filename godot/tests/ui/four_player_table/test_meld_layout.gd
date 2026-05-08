extends GutTest

# MeldLayout: 纯算法，给定 Meld + claimant_seat → Array[Slot]
# 每 Slot = {tile_id: int, rotated: bool, face_down: bool, stacked_above: bool}

# ---- CHI ----

func test_chi_rotated_at_left():
	# CHI 仅来自上家。tiles 升序 [W2, W3, W4]，from_seat = (claimant - 1) % 4
	var tiles: Array[Tile] = [
		Tile.new(TileId.W2),
		Tile.new(TileId.W3),
		Tile.new(TileId.W4),
	]
	var meld := Meld.make_chi(tiles, 3)  # claimant=0, from=3 (上家)
	var layout: Array = MeldLayout.compute(meld, 0)
	assert_eq(layout.size(), 3, "3 张牌 3 个 Slot")
	assert_true(layout[0]["rotated"], "上家来 → 第 0 张 rotated")
	assert_false(layout[1]["rotated"])
	assert_false(layout[2]["rotated"])
	for s in layout:
		assert_false(s["face_down"], "chi 不该有 face_down")
		assert_false(s["stacked_above"], "chi 不该有 stacked_above")

# ---- PON 三方向 ----

func test_pon_from_kamicha_rotated_at_left():
	# 上家 = (claimant - 1) % 4. claimant=0, kamicha=3
	var tiles: Array[Tile] = [Tile.new(TileId.W5), Tile.new(TileId.W5), Tile.new(TileId.W5)]
	var meld := Meld.make_pon(tiles, 3)
	var layout: Array = MeldLayout.compute(meld, 0)
	assert_eq(layout.size(), 3)
	assert_true(layout[0]["rotated"], "上家来 → 第 0 张")
	assert_false(layout[1]["rotated"])
	assert_false(layout[2]["rotated"])

func test_pon_from_toimen_rotated_at_middle():
	# 对家 = (claimant + 2) % 4. claimant=0, toimen=2
	var tiles: Array[Tile] = [Tile.new(TileId.S7), Tile.new(TileId.S7), Tile.new(TileId.S7)]
	var meld := Meld.make_pon(tiles, 2)
	var layout: Array = MeldLayout.compute(meld, 0)
	assert_false(layout[0]["rotated"])
	assert_true(layout[1]["rotated"], "对家来 → 第 1 张")
	assert_false(layout[2]["rotated"])

func test_pon_from_shimocha_rotated_at_right():
	# 下家 = (claimant + 1) % 4. claimant=0, shimocha=1
	var tiles: Array[Tile] = [Tile.new(TileId.HAKU), Tile.new(TileId.HAKU), Tile.new(TileId.HAKU)]
	var meld := Meld.make_pon(tiles, 1)
	var layout: Array = MeldLayout.compute(meld, 0)
	assert_false(layout[0]["rotated"])
	assert_false(layout[1]["rotated"])
	assert_true(layout[2]["rotated"], "下家来 → 第 2 张")

# ---- MINKAN ----

func test_minkan_4_tiles_rotated_per_source():
	# MINKAN 4 张同 id，旋转索引规则同 PON
	var tiles: Array[Tile] = [
		Tile.new(TileId.T9), Tile.new(TileId.T9),
		Tile.new(TileId.T9), Tile.new(TileId.T9),
	]
	# 对家来 → 第 1 张 rotated
	var meld := Meld.make_minkan(tiles, 2)
	var layout: Array = MeldLayout.compute(meld, 0)
	assert_eq(layout.size(), 4, "MINKAN 4 张 4 个 Slot")
	assert_false(layout[0]["rotated"])
	assert_true(layout[1]["rotated"])
	assert_false(layout[2]["rotated"])
	assert_false(layout[3]["rotated"])
	for s in layout:
		assert_false(s["face_down"], "MINKAN 不该有 face_down")

# ---- ANKAN ----

func test_ankan_face_down_outer_two():
	# 暗杠 4 张同 id，第 0 / 第 3 张 face_down（D1 流派）
	var tiles: Array[Tile] = [
		Tile.new(TileId.W1), Tile.new(TileId.W1),
		Tile.new(TileId.W1), Tile.new(TileId.W1),
	]
	var meld := Meld.make_ankan(tiles)
	var layout: Array = MeldLayout.compute(meld, 0)
	assert_eq(layout.size(), 4)
	assert_true(layout[0]["face_down"], "第 0 张 face_down")
	assert_false(layout[1]["face_down"], "第 1 张正面")
	assert_false(layout[2]["face_down"], "第 2 张正面")
	assert_true(layout[3]["face_down"], "第 3 张 face_down")
	for s in layout:
		assert_false(s["rotated"], "ankan 无旋转牌")

func test_ankan_no_dependency_on_claimant_seat():
	# 暗杠不来自任何人，claimant_seat 不影响 layout
	var tiles: Array[Tile] = [
		Tile.new(TileId.E), Tile.new(TileId.E),
		Tile.new(TileId.E), Tile.new(TileId.E),
	]
	var meld := Meld.make_ankan(tiles)
	var layout_a: Array = MeldLayout.compute(meld, 0)
	var layout_b: Array = MeldLayout.compute(meld, 2)
	for i in range(4):
		assert_eq(layout_a[i]["face_down"], layout_b[i]["face_down"],
			"ankan layout 不随 claimant_seat 变化")

# ---- ADDED_KAN ----

func test_added_kan_4_slots_with_stacked():
	# 加杠 = 原 pon 3 张 + 第 4 张叠在 rotated 位置上方
	# 上家 来源（rotated_idx=0），加杠后第 4 个 slot stacked_above=true 且 rotated=true
	var tiles: Array[Tile] = [
		Tile.new(TileId.S5), Tile.new(TileId.S5),
		Tile.new(TileId.S5), Tile.new(TileId.S5),
	]
	var meld := Meld.make_added_kan(tiles, 3)  # claimant=0, from=上家
	var layout: Array = MeldLayout.compute(meld, 0)
	assert_eq(layout.size(), 4, "加杠 4 个 Slot")
	# 原 pon 3 张
	assert_true(layout[0]["rotated"], "原 rotated 仍在 idx 0")
	assert_false(layout[1]["rotated"])
	assert_false(layout[2]["rotated"])
	assert_false(layout[0]["stacked_above"])
	# 第 4 张：叠加 + 旋转
	assert_true(layout[3]["stacked_above"], "第 4 张 stacked_above")
	assert_true(layout[3]["rotated"], "第 4 张 rotated")
	assert_false(layout[3]["face_down"])

func test_added_kan_stacked_position_matches_source():
	# 对家来 → rotated_idx=1；加杠 stacked 仍是第 4 个 Slot；rendering 时叠在 idx=1 上方
	var tiles: Array[Tile] = [
		Tile.new(TileId.T3), Tile.new(TileId.T3),
		Tile.new(TileId.T3), Tile.new(TileId.T3),
	]
	var meld := Meld.make_added_kan(tiles, 2)  # 对家
	var layout: Array = MeldLayout.compute(meld, 0)
	assert_true(layout[1]["rotated"], "对家来 → idx 1 rotated")
	assert_true(layout[3]["stacked_above"])
	assert_true(layout[3]["rotated"])

# ---- tile_id 顺序 ----

func test_tile_ids_preserved_in_order():
	# CHI 顺子 tile_id 顺序保持（W2 → W3 → W4）
	var tiles: Array[Tile] = [
		Tile.new(TileId.W2),
		Tile.new(TileId.W3),
		Tile.new(TileId.W4),
	]
	var meld := Meld.make_chi(tiles, 3)
	var layout: Array = MeldLayout.compute(meld, 0)
	assert_eq(int(layout[0]["tile_id"]), TileId.W2)
	assert_eq(int(layout[1]["tile_id"]), TileId.W3)
	assert_eq(int(layout[2]["tile_id"]), TileId.W4)

# ---- 红 dora 标识 ----

func test_red_dora_propagates_in_chi():
	# CHI 234m 含红 5m 的同 mid，红 5 设 is_red_dora=true
	var tiles: Array[Tile] = [
		Tile.new(TileId.W3),
		Tile.new(TileId.W4),
		Tile.new(TileId.W5, true),  # 红 5m
	]
	var meld := Meld.make_chi(tiles, 3)
	var layout: Array = MeldLayout.compute(meld, 0)
	assert_false(bool(layout[0]["is_red_dora"]))
	assert_false(bool(layout[1]["is_red_dora"]))
	assert_true(bool(layout[2]["is_red_dora"]), "W5 红 dora 标识透传")

func test_red_dora_default_false_when_not_set():
	# 普通 CHI 无红 dora — 所有 slot is_red_dora 应 false
	var tiles: Array[Tile] = [
		Tile.new(TileId.W2),
		Tile.new(TileId.W3),
		Tile.new(TileId.W4),
	]
	var meld := Meld.make_chi(tiles, 3)
	var layout: Array = MeldLayout.compute(meld, 0)
	for s in layout:
		assert_false(bool(s["is_red_dora"]), "默认 is_red_dora=false")

func test_red_dora_propagates_in_pon():
	# PON W5 同 id 三张，其中 1 张红 5m
	var tiles: Array[Tile] = [
		Tile.new(TileId.W5, false),
		Tile.new(TileId.W5, true),  # 红 5
		Tile.new(TileId.W5, false),
	]
	var meld := Meld.make_pon(tiles, 3)
	var layout: Array = MeldLayout.compute(meld, 0)
	assert_false(bool(layout[0]["is_red_dora"]))
	assert_true(bool(layout[1]["is_red_dora"]), "PON 内红 5 标识透传")
	assert_false(bool(layout[2]["is_red_dora"]))

func test_red_dora_propagates_in_added_kan_4th_slot():
	# 加杠：原 pon 3 张 + 第 4 张是红 5
	var tiles: Array[Tile] = [
		Tile.new(TileId.W5, false),
		Tile.new(TileId.W5, false),
		Tile.new(TileId.W5, false),
		Tile.new(TileId.W5, true),  # 第 4 张是红 5（加杠抓上来）
	]
	var meld := Meld.make_added_kan(tiles, 3)
	var layout: Array = MeldLayout.compute(meld, 0)
	assert_eq(layout.size(), 4)
	assert_true(bool(layout[3]["is_red_dora"]), "加杠第 4 张红 dora 透传")
	assert_true(bool(layout[3]["stacked_above"]))
