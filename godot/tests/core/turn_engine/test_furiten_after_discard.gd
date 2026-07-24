extends GutTest

# 日麻 §5 振听 — turn_engine.discard / draw_for_current 内的 furiten 自动更新。
# 覆盖三型:
#   (1) standard 振听:自家弃牌中含听张 → permanent=true
#   (2) temporary 振听:同巡见逃 → 由 BattleController._try_auto_ron 设置;
#       下次自摸时 turn_engine.draw_for_current 自动 clear_temporary
#   (3) 立直振听:立直后再见逃 → 永久振听(由 BC 处理,本测试验 clear 不会
#       误清 permanent)

func _make_bc() -> BattleController:
	return BattleController.new(42, 0, false, TileId.E)


func _tile(tid: int, iid: int) -> Tile:
	return Tile.new(tid, false, Tile.NO_OWNER, iid)


# 七対子听 W8 单騎,弃 W8 后自家弃牌堆里就有 W8 → 永久振听
func test_standard_furiten_after_discard_into_own_pile() -> void:
	var bc := _make_bc()
	var seat: Seat = bc.state.seats[0]
	seat.hand._tiles.clear()
	# 14 张:6 对 + W8 + W8 → 弃 1 张 W8 后 13 张听 W8 単騎(七対子)
	var iids := [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14]
	var ids := [
		TileId.W1, TileId.W1, TileId.W2, TileId.W2, TileId.W3, TileId.W3,
		TileId.W5, TileId.W5, TileId.W6, TileId.W6, TileId.W7, TileId.W7,
		TileId.W8, TileId.W8,
	]
	for i in range(14):
		seat.hand.add(_tile(ids[i], iids[i]))
	bc.state.current_seat = 0
	bc.state.phase = BattlePhase.Kind.DISCARD
	# 弃一张 W8（iid=13）→ 自家弃牌堆 [W8],hand 13 张听 W8
	assert_true(bc.engine.discard(13))
	# 振听规则:waits 含 W8,自家弃牌堆也含 W8 → permanent
	assert_true(seat.furiten.permanent, "自家弃牌含听张应永久振听")
	assert_true(seat.furiten.is_furiten())


# 听张不在自家弃牌堆 → 不振听
func test_no_furiten_when_wait_not_in_own_discards() -> void:
	var bc := _make_bc()
	var seat: Seat = bc.state.seats[0]
	seat.hand._tiles.clear()
	# 14 张:听 W9,弃 W1(W9 待牌不在自家弃牌)
	var iids := [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14]
	var ids := [
		TileId.W1, TileId.W2, TileId.W2, TileId.W3, TileId.W3, TileId.W4,
		TileId.W4, TileId.W5, TileId.W5, TileId.W6, TileId.W6, TileId.W7,
		TileId.W7, TileId.W9,  # m1 m2m2 m3m3 m4m4 m5m5 m6m6 m7m7 m9
	]
	for i in range(14):
		seat.hand.add(_tile(ids[i], iids[i]))
	bc.state.current_seat = 0
	bc.state.phase = BattlePhase.Kind.DISCARD
	assert_true(bc.engine.discard(1))  # W1 iid=1
	assert_false(seat.furiten.permanent, "弃 W1 但听 W9,不在自家弃 → 不振听")


# draw_for_current 必须 clear temporary 振听(新一巡)。
func test_draw_clears_temporary_furiten() -> void:
	var bc := _make_bc()
	var seat: Seat = bc.state.seats[0]
	seat.furiten.temporary = true
	assert_true(seat.furiten.is_furiten())
	bc.state.current_seat = 0
	# 摸 1 张 → temporary 应被清
	var drawn := bc.engine.draw_for_current()
	assert_not_null(drawn, "wall 应有牌")
	assert_false(seat.furiten.temporary, "自摸后 temporary 应清")


# clear_temporary 不应清 permanent(立直振听等长效振听)。
func test_clear_temporary_keeps_permanent() -> void:
	var fs := FuritenState.new()
	fs.permanent = true
	fs.temporary = true
	fs.clear_temporary()
	assert_false(fs.temporary)
	assert_true(fs.permanent, "permanent 不应被 clear_temporary 误清")
	assert_true(fs.is_furiten(), "permanent 仍在 → 仍振听")


# 自摸不会重置 permanent —— 永久振听一旦命中本局都不解。
func test_draw_does_not_clear_permanent_furiten() -> void:
	var bc := _make_bc()
	var seat: Seat = bc.state.seats[0]
	seat.furiten.permanent = true
	bc.state.current_seat = 0
	bc.engine.draw_for_current()
	assert_true(seat.furiten.permanent, "自摸不应清 permanent")
