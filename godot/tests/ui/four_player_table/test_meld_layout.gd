extends GutTest

# MeldLayout: 纯算法，给定 Meld + claimant_seat → Array[Slot]
# 每 Slot = {tile_id: int, rotated: bool, face_down: bool, stacked_above: bool}
# E2-02：Meld 唯一契约 = (meld_id:int, called:Tile)；called 须合法 instance_id 才能派生。


func _t(tid: int, iid: int, red: bool = false) -> Tile:
	return Tile.new(tid, red, Tile.NO_OWNER, iid)


# ---- CHI ----

func test_chi_rotated_at_left():
	# CHI 仅来自上家。tiles 升序 [W2, W3, W4]，from_seat = (claimant - 1) % 4
	var called := _t(TileId.W3, 2)
	var tiles: Array[Tile] = [_t(TileId.W2, 1), called, _t(TileId.W4, 3)]
	var meld := Meld.make_chi(tiles, 3, 0, called)  # 真正叫来 W3
	var layout: Array = MeldLayout.compute(meld, 0)
	assert_eq(layout.size(), 3, "3 张牌 3 个 Slot")
	assert_true(layout[0]["rotated"], "上家来 → 第 0 张 rotated")
	assert_eq(int(layout[0]["tile_id"]), TileId.W3, "横置的必须是真实 called tile")
	assert_false(layout[1]["rotated"])
	assert_false(layout[2]["rotated"])
	for s in layout:
		assert_false(s["face_down"], "chi 不该有 face_down")
		assert_false(s["stacked_above"], "chi 不该有 stacked_above")

# ---- PON 三方向 ----

func test_pon_from_kamicha_rotated_at_left():
	# 上家 = (claimant - 1) % 4. claimant=0, kamicha=3
	var called := _t(TileId.W5, 10)
	var tiles: Array[Tile] = [called, _t(TileId.W5, 11), _t(TileId.W5, 12)]
	var meld := Meld.make_pon(tiles, 3, 0, called)
	var layout: Array = MeldLayout.compute(meld, 0)
	assert_eq(layout.size(), 3)
	assert_true(layout[0]["rotated"], "上家来 → 第 0 张")
	assert_false(layout[1]["rotated"])
	assert_false(layout[2]["rotated"])

func test_pon_from_toimen_rotated_at_middle():
	# 对家 = (claimant + 2) % 4. claimant=0, toimen=2
	var called := _t(TileId.S7, 20)
	var tiles: Array[Tile] = [called, _t(TileId.S7, 21), _t(TileId.S7, 22)]
	var meld := Meld.make_pon(tiles, 2, 0, called)
	var layout: Array = MeldLayout.compute(meld, 0)
	assert_false(layout[0]["rotated"])
	assert_true(layout[1]["rotated"], "对家来 → 第 1 张")
	assert_false(layout[2]["rotated"])

func test_pon_from_shimocha_rotated_at_right():
	# 下家 = (claimant + 1) % 4. claimant=0, shimocha=1
	var called := _t(TileId.HAKU, 30)
	var tiles: Array[Tile] = [called, _t(TileId.HAKU, 31), _t(TileId.HAKU, 32)]
	var meld := Meld.make_pon(tiles, 1, 0, called)
	var layout: Array = MeldLayout.compute(meld, 0)
	assert_false(layout[0]["rotated"])
	assert_false(layout[1]["rotated"])
	assert_true(layout[2]["rotated"], "下家来 → 第 2 张")

# ---- MINKAN ----

func test_minkan_4_tiles_rotated_per_source():
	# MINKAN 4 张同 id，旋转索引规则同 PON
	var called := _t(TileId.T9, 40)
	var tiles: Array[Tile] = [
		called, _t(TileId.T9, 41), _t(TileId.T9, 42), _t(TileId.T9, 43),
	]
	# 对家来 → 第 1 张 rotated
	var meld := Meld.make_minkan(tiles, 2, 0, called)
	var layout: Array = MeldLayout.compute(meld, 0)
	assert_eq(layout.size(), 4, "MINKAN 4 张 4 个 Slot")
	assert_false(layout[0]["rotated"])
	assert_true(layout[1]["rotated"])
	assert_false(layout[2]["rotated"])
	assert_false(layout[3]["rotated"])
	for s in layout:
		assert_false(s["face_down"], "MINKAN 不该有 face_down")

func test_minkan_from_shimocha_puts_called_tile_at_tail():
	# bundle nV：relativeSource 既非 1 也非 2 时插到 remaining.length；
	# 明杠有 3 张 remaining，所以下家来源必须落在 index 3，而不是 pon 的 index 2。
	var called := _t(TileId.T9, 50)
	var tiles: Array[Tile] = [
		called, _t(TileId.T9, 51), _t(TileId.T9, 52), _t(TileId.T9, 53),
	]
	var meld := Meld.make_minkan(tiles, 1, 0, called)  # claimant=0，下家=1
	var layout: Array = MeldLayout.compute(meld, 0)
	for i in range(3):
		assert_false(layout[i]["rotated"], "前 3 张不是下家打出的牌")
	assert_true(layout[3]["rotated"], "下家明杠的 called tile 位于末尾 index 3")

# ---- ANKAN ----

func test_ankan_face_down_middle_two():
	# bundle nV：暗杠 index 1 / 2 牌背，index 0 / 3 正面。
	var tiles: Array[Tile] = [
		_t(TileId.W1, 60), _t(TileId.W1, 61),
		_t(TileId.W1, 62), _t(TileId.W1, 63),
	]
	var meld := Meld.make_ankan(tiles)
	var layout: Array = MeldLayout.compute(meld, 0)
	assert_eq(layout.size(), 4)
	assert_false(layout[0]["face_down"], "第 0 张正面")
	assert_true(layout[1]["face_down"], "第 1 张 face_down")
	assert_true(layout[2]["face_down"], "第 2 张 face_down")
	assert_false(layout[3]["face_down"], "第 3 张正面")
	for s in layout:
		assert_false(s["rotated"], "ankan 无旋转牌")

func test_ankan_no_dependency_on_claimant_seat():
	# 暗杠不来自任何人，claimant_seat 不影响 layout
	var tiles: Array[Tile] = [
		_t(TileId.E, 70), _t(TileId.E, 71),
		_t(TileId.E, 72), _t(TileId.E, 73),
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
	var called := _t(TileId.S5, 80)
	var tiles: Array[Tile] = [
		called, _t(TileId.S5, 81), _t(TileId.S5, 82), _t(TileId.S5, 83),
	]
	var meld := Meld.make_added_kan(tiles, 3, 0, called)  # claimant=0, from=上家
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
	var called := _t(TileId.T3, 90)
	var tiles: Array[Tile] = [
		called, _t(TileId.T3, 91), _t(TileId.T3, 92), _t(TileId.T3, 93),
	]
	var meld := Meld.make_added_kan(tiles, 2, 0, called)  # 对家
	var layout: Array = MeldLayout.compute(meld, 0)
	assert_true(layout[1]["rotated"], "对家来 → idx 1 rotated")
	assert_true(layout[3]["stacked_above"])
	assert_true(layout[3]["rotated"])

# ---- tile_id 顺序 ----

func test_chi_moves_exact_called_tile_to_bundle_insertion_position():
	# nV 先移除真实 called W3，再把它插到 index 0；remaining 保持 W2/W4 顺序。
	var called := _t(TileId.W3, 102)
	var tiles: Array[Tile] = [_t(TileId.W2, 101), called, _t(TileId.W4, 103)]
	var meld := Meld.make_chi(tiles, 3, 0, called)
	var layout: Array = MeldLayout.compute(meld, 0)
	assert_eq(int(layout[0]["tile_id"]), TileId.W3)
	assert_eq(int(layout[1]["tile_id"]), TileId.W2)
	assert_eq(int(layout[2]["tile_id"]), TileId.W4)

# ---- 红 dora 标识 ----

func test_red_dora_propagates_in_chi():
	# CHI 234m 含红 5m 的同 mid，红 5 设 is_red_dora=true
	var called := _t(TileId.W3, 110)
	var tiles: Array[Tile] = [
		called,
		_t(TileId.W4, 111),
		_t(TileId.W5, 112, true),  # 红 5m
	]
	var meld := Meld.make_chi(tiles, 3, 0, called)
	var layout: Array = MeldLayout.compute(meld, 0)
	assert_false(bool(layout[0]["is_red_dora"]))
	assert_false(bool(layout[1]["is_red_dora"]))
	assert_true(bool(layout[2]["is_red_dora"]), "W5 红 dora 标识透传")

func test_red_dora_default_false_when_not_set():
	# 普通 CHI 无红 dora — 所有 slot is_red_dora 应 false
	var called := _t(TileId.W2, 120)
	var tiles: Array[Tile] = [called, _t(TileId.W3, 121), _t(TileId.W4, 122)]
	var meld := Meld.make_chi(tiles, 3, 0, called)
	var layout: Array = MeldLayout.compute(meld, 0)
	for s in layout:
		assert_false(bool(s["is_red_dora"]), "默认 is_red_dora=false")

func test_red_dora_propagates_in_pon():
	# PON W5 同 id 三张，其中 1 张红 5m
	var called := _t(TileId.W5, 130, false)
	var tiles: Array[Tile] = [
		called,
		_t(TileId.W5, 131, true),  # 红 5
		_t(TileId.W5, 132, false),
	]
	var meld := Meld.make_pon(tiles, 3, 0, called)
	var layout: Array = MeldLayout.compute(meld, 0)
	assert_false(bool(layout[0]["is_red_dora"]))
	assert_true(bool(layout[1]["is_red_dora"]), "PON 内红 5 标识透传")
	assert_false(bool(layout[2]["is_red_dora"]))

func test_added_kan_stack_duplicates_called_tile_like_bundle():
	# rV 的 meld__stack 第二张再次渲染 w.t（called tile），而不是另取第 4 个对象。
	var called := _t(TileId.W5, 140, false)
	var tiles: Array[Tile] = [
		called,
		_t(TileId.W5, 141, false),
		_t(TileId.W5, 142, false),
		_t(TileId.W5, 143, true),  # 第 4 张是红 5（加杠抓上来）
	]
	var meld := Meld.make_added_kan(tiles, 3, 0, called)
	var layout: Array = MeldLayout.compute(meld, 0)
	assert_eq(layout.size(), 4)
	assert_false(bool(layout[3]["is_red_dora"]), "叠牌复制非赤的 called tile")
	assert_true(bool(layout[3]["stacked_above"]))
