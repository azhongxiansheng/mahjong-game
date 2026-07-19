extends GutTest

# T2 单牌状态系统(spec 2026-06-11 G2)— CardTileBack 五状态 + SeatPanel 接线。

func _make_face_up_tile(tid: int = TileId.W5) -> CardTileBack:
	var tile := CardTileBack.new()
	add_child_autofree(tile)
	tile.set_face_up(tid)
	return tile

# ---- dora 扫光 ----

func test_dora_creates_sweep_on_face_up():
	var tile := _make_face_up_tile()
	tile.set_dora(true)
	assert_not_null(tile._dora_sweep, "宝牌应有扫光层")
	assert_true(tile._dora_sweep.visible)
	assert_true(tile.clip_contents, "扫光需裁切在牌内")
	tile.set_dora(false)
	assert_false(tile._dora_sweep.visible)

func test_dora_noop_on_back_tile():
	var tile := CardTileBack.new()
	add_child_autofree(tile)
	tile.set_owner_seat(2)  # 牌背模式
	tile.set_dora(true)
	assert_false(tile._is_dora, "牌背不标宝牌(对手牌不可见)")

# ---- dim 不动 modulate(项目硬约束) ----

func test_dim_uses_mask_not_modulate():
	var tile := _make_face_up_tile()
	tile.set_dim(true)
	assert_true(tile.is_dim())
	assert_eq(tile.modulate, Color.WHITE, "dim 必须用蒙版,不能动 modulate(CLAUDE.md 约束)")
	assert_not_null(tile._dim_mask)
	assert_true(tile._dim_mask.visible)
	tile.set_dim(false)
	assert_false(tile._dim_mask.visible)

# ---- hover match / lifted / win ----

func test_hover_match_mask_toggles():
	var tile := _make_face_up_tile()
	tile.set_hover_match(true)
	assert_true(tile._match_mask.visible)
	tile.set_hover_match(false)
	assert_false(tile._match_mask.visible)

func test_win_tile_pulse_restores_scale_on_disable():
	var tile := _make_face_up_tile()
	var base := tile.scale
	tile.set_win_tile(true)
	await wait_physics_frames(8)
	tile.set_win_tile(false)
	assert_eq(tile.scale, base, "关闭后 scale 还原")

func test_states_are_stackable():
	var tile := _make_face_up_tile()
	tile.set_dora(true)
	tile.set_dim(true)
	tile.set_hover_match(true)
	tile.set_lifted(true)
	assert_true(tile._is_dora and tile.is_dim() and tile._is_hover_match and tile._is_lifted,
		"状态可叠加互不覆盖")

# ---- SeatPanel 接线 ----

func _make_player_panel_with_hand(ids: Array) -> SeatPanel:
	var sp := SeatPanel.new()
	sp.set_seat_id(0)
	add_child_autofree(sp)
	var hand := Hand.new()
	for tid in ids:
		hand.add(Tile.new(tid))
	var seat := Seat.new(0, TileId.E)
	for t in hand._tiles:
		seat.hand.add(t)
	sp.bind_seat(seat)
	return sp

# 手牌增量后：CardTileBack 挂在 slot 容器内，经 _hand_slots 访问。
func _iter_hand_tiles(sp: SeatPanel) -> Array:
	var tiles: Array = []
	for s in sp._hand_slots:
		if s == null or not is_instance_valid(s):
			continue
		var tile: CardTileBack = s.get_node_or_null("Tile") as CardTileBack
		if tile:
			tiles.append(tile)
	return tiles


func test_seat_panel_marks_dora_from_ids():
	var sp := SeatPanel.new()
	sp.set_seat_id(0)
	add_child_autofree(sp)
	sp.set_dora_ids([TileId.W5])
	var seat := Seat.new(0, TileId.E)
	for tid in [TileId.W5, TileId.T1, TileId.S9]:
		seat.hand.add(Tile.new(tid))
	sp.bind_seat(seat)
	var dora_count := 0
	for tile in _iter_hand_tiles(sp):
		if tile._is_dora:
			dora_count += 1
	assert_eq(dora_count, 1, "手牌中 1 张 W5 实宝牌应标扫光")

func test_seat_panel_dim_except_and_clear():
	var sp := _make_player_panel_with_hand([TileId.W1, TileId.W2, TileId.T5])
	sp.dim_hand_except([TileId.W1, TileId.W2])
	var dimmed: Array = []
	for tile in _iter_hand_tiles(sp):
		if tile.is_dim():
			dimmed.append(tile._tile_id)
	assert_eq(dimmed, [TileId.T5], "候选外的 T5 压暗")
	sp.clear_hand_dim()
	for tile in _iter_hand_tiles(sp):
		assert_false(tile.is_dim())

func test_seat_panel_mark_win_tile():
	var sp := _make_player_panel_with_hand([TileId.W1, TileId.CHUN])
	sp.mark_win_tile(TileId.CHUN)
	var marked := 0
	for tile in _iter_hand_tiles(sp):
		if tile._is_win_tile:
			marked += 1
			assert_eq(tile._tile_id, TileId.CHUN)
	assert_eq(marked, 1)


# 雀魂式：结算前翻开对手手牌
func test_seat_panel_reveal_hand_face_up():
	var sp := SeatPanel.new()
	sp.set_seat_id(2)  # 对手
	add_child_autofree(sp)
	await get_tree().process_frame
	var hand := Hand.new()
	for tid in [TileId.W1, TileId.W2, TileId.T5, TileId.S9]:
		hand.add(Tile.new(tid))
	sp.reveal_hand_face_up(hand, false)
	assert_eq(sp.count_revealed_face_up(), 4, "应翻开 4 张正面")
	sp.clear_hand_reveal()
	assert_eq(sp.count_revealed_face_up(), 0, "clear 后计数清零")


# 听牌候补条：仅 seat 0 + tenpai 时显示
func test_seat_panel_wait_tiles_strip():
	var sp := SeatPanel.new()
	sp.set_seat_id(0)
	add_child_autofree(sp)
	await get_tree().process_frame
	sp.set_tenpai(true)
	sp.set_wait_tiles([TileId.W1, TileId.W4, TileId.W7])
	assert_eq(sp.count_wait_tiles_shown(), 3, "应显示 3 张候补")
	sp.set_tenpai(false)
	assert_eq(sp.count_wait_tiles_shown(), 0, "非听应隐藏候补")
	# 对手 seat 不显示
	var sp2 := SeatPanel.new()
	sp2.set_seat_id(1)
	add_child_autofree(sp2)
	await get_tree().process_frame
	sp2.set_tenpai(true)
	sp2.set_wait_tiles([TileId.CHUN])
	assert_eq(sp2.count_wait_tiles_shown(), 0, "对手不露候补")
