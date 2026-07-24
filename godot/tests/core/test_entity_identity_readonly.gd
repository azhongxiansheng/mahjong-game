extends GutTest

# E2-02 / #232 P2-1 Red：身份只读构造契约。
# Tile / Meld 在构造时一次性写入 identity；clone/from_dict 保留；
# promote_to_added_kan 为唯一可变升级路径。
# 冻结 API 尚未落地时允许 Parse Red / 加载失败；不在此测非法 property assignment。


func test_tile_constructor_accepts_instance_id_fourth_arg() -> void:
	var t := Tile.new(TileId.W5, true, 2, 42)
	assert_eq(t.id, TileId.W5)
	assert_true(t.is_red_dora)
	assert_eq(t.owner_seat, 2)
	assert_eq(t.instance_id, 42)


func test_tile_constructor_default_instance_id_is_invalid() -> void:
	var t := Tile.new(TileId.W1)
	assert_eq(t.instance_id, Tile.INVALID_INSTANCE_ID)


func test_tile_clone_preserves_instance_id_from_constructor() -> void:
	var t := Tile.new(TileId.S5, true, 1, 77)
	var c: Tile = t.clone()
	assert_ne(c, t)
	assert_eq(c.instance_id, 77)
	assert_eq(c.id, TileId.S5)
	assert_true(c.is_red_dora)
	assert_eq(c.owner_seat, 1)


func test_tile_from_dict_preserves_instance_id() -> void:
	var t := Tile.new(TileId.T5, true, 3, 99)
	var restored: Tile = Tile.from_dict(t.to_dict())
	assert_eq(restored.instance_id, 99)
	assert_eq(restored.id, TileId.T5)
	assert_true(restored.is_red_dora)
	assert_eq(restored.owner_seat, 3)


func test_meld_factory_receives_meld_id_and_called_tile_once() -> void:
	var called := Tile.new(TileId.W5, true, 0, 200)
	var a := Tile.new(TileId.W5, false, 1, 201)
	var b := Tile.new(TileId.W5, false, 2, 202)
	var m := Meld.make_pon([a, called, b], 0, 7, called)
	assert_eq(m.kind, Meld.Kind.PON)
	assert_eq(m.meld_id, 7)
	assert_eq(m.called_tile_instance_id, 200)
	assert_eq(m.from_seat, 0)
	assert_not_null(m.called_tile)
	assert_eq(m.called_tile.instance_id, 200)
	assert_eq(m.added_tile_instance_id, Tile.INVALID_INSTANCE_ID)


func test_meld_constructor_receives_meld_id_and_called_tile_once() -> void:
	var called := Tile.new(TileId.W3, false, 0, 50)
	var a := Tile.new(TileId.W2, false, 1, 51)
	var b := Tile.new(TileId.W4, false, 2, 52)
	var m := Meld.new(Meld.Kind.CHI, [a, called, b], 3, 11, called)
	assert_eq(m.kind, Meld.Kind.CHI)
	assert_eq(m.meld_id, 11)
	assert_eq(m.called_tile_instance_id, 50)
	assert_eq(m.from_seat, 3)
	assert_same(m.called_tile, called)


func test_promote_to_added_kan_success_from_pon() -> void:
	var called := Tile.new(TileId.W5, true, 0, 300)
	var a := Tile.new(TileId.W5, false, 1, 301)
	var b := Tile.new(TileId.W5, false, 2, 302)
	var m := Meld.make_pon([a, called, b], 1, 9, called)
	var fourth := Tile.new(TileId.W5, false, 3, 303)

	assert_true(m.promote_to_added_kan(fourth))
	assert_eq(m.kind, Meld.Kind.ADDED_KAN)
	assert_eq(m.tiles.size(), 4)
	assert_eq(m.added_tile_instance_id, 303)
	assert_eq(m.meld_id, 9, "加杠保留 meld_id")
	assert_eq(m.called_tile_instance_id, 300, "保留 called")
	assert_eq(m.from_seat, 1, "保留 from_seat")
	assert_eq(m.tiles[3].instance_id, 303)


func test_promote_to_added_kan_rejects_non_pon_zero_mod() -> void:
	var called := Tile.new(TileId.W2, false, 0, 400)
	var a := Tile.new(TileId.W3, false, 1, 401)
	var b := Tile.new(TileId.W4, false, 2, 402)
	var m := Meld.make_chi([a, called, b], 0, 5, called)
	var snap_kind := m.kind
	var snap_size: int = m.tiles.size()
	var snap_added: int = m.added_tile_instance_id
	var snap_meld: int = m.meld_id
	var snap_called: int = m.called_tile_instance_id
	var fourth := Tile.new(TileId.W2, false, 3, 403)

	assert_false(m.promote_to_added_kan(fourth))
	assert_eq(m.kind, snap_kind)
	assert_eq(m.tiles.size(), snap_size)
	assert_eq(m.added_tile_instance_id, snap_added)
	assert_eq(m.meld_id, snap_meld)
	assert_eq(m.called_tile_instance_id, snap_called)


func test_promote_to_added_kan_rejects_wrong_tile_id_zero_mod() -> void:
	var called := Tile.new(TileId.W5, false, 0, 500)
	var a := Tile.new(TileId.W5, false, 1, 501)
	var b := Tile.new(TileId.W5, false, 2, 502)
	var m := Meld.make_pon([a, called, b], 2, 8, called)
	var wrong := Tile.new(TileId.S1, false, 3, 503)
	var snap_size: int = m.tiles.size()
	var snap_kind := m.kind
	var snap_added: int = m.added_tile_instance_id

	assert_false(m.promote_to_added_kan(wrong))
	assert_eq(m.tiles.size(), snap_size)
	assert_eq(m.kind, snap_kind)
	assert_eq(m.added_tile_instance_id, snap_added)


func test_promote_to_added_kan_rejects_invalid_instance_id_zero_mod() -> void:
	var called := Tile.new(TileId.W5, false, 0, 600)
	var a := Tile.new(TileId.W5, false, 1, 601)
	var b := Tile.new(TileId.W5, false, 2, 602)
	var m := Meld.make_pon([a, called, b], 0, 3, called)
	var bad := Tile.new(TileId.W5, false, 3, Tile.INVALID_INSTANCE_ID)
	var snap_size: int = m.tiles.size()
	var snap_kind := m.kind
	var snap_added: int = m.added_tile_instance_id

	assert_false(m.promote_to_added_kan(bad))
	assert_eq(m.tiles.size(), snap_size)
	assert_eq(m.kind, snap_kind)
	assert_eq(m.added_tile_instance_id, snap_added)


func test_promote_to_added_kan_only_once_second_fails_zero_mod() -> void:
	var called := Tile.new(TileId.W5, false, 0, 700)
	var a := Tile.new(TileId.W5, false, 1, 701)
	var b := Tile.new(TileId.W5, false, 2, 702)
	var m := Meld.make_pon([a, called, b], 1, 12, called)
	var fourth := Tile.new(TileId.W5, false, 3, 703)
	assert_true(m.promote_to_added_kan(fourth))

	var fifth := Tile.new(TileId.W5, false, 0, 704)
	var snap_size: int = m.tiles.size()
	var snap_kind := m.kind
	var snap_added: int = m.added_tile_instance_id
	var snap_meld: int = m.meld_id
	var snap_called: int = m.called_tile_instance_id
	var snap_from: int = m.from_seat

	assert_false(m.promote_to_added_kan(fifth), "已加杠不可再 promote")
	assert_eq(m.tiles.size(), snap_size)
	assert_eq(m.kind, snap_kind)
	assert_eq(m.added_tile_instance_id, snap_added)
	assert_eq(m.meld_id, snap_meld)
	assert_eq(m.called_tile_instance_id, snap_called)
	assert_eq(m.from_seat, snap_from)
