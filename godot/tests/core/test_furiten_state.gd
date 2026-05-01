extends GutTest

# FuritenState (spec §5)：一座位的振听状态。
# permanent: 立直后含弃牌张 → 永久振听本局
# temporary: 听牌期间见和未荣胡 → 暂时振听到下次自摸
# waits: 当前听牌张数组

func test_default_not_furiten():
	var s := FuritenState.new()
	assert_false(s.permanent)
	assert_false(s.temporary)
	assert_eq(s.waits.size(), 0)
	assert_false(s.is_furiten())

func test_permanent_makes_furiten():
	var s := FuritenState.new()
	s.permanent = true
	assert_true(s.is_furiten())

func test_temporary_makes_furiten():
	var s := FuritenState.new()
	s.temporary = true
	assert_true(s.is_furiten())

func test_clear_temporary_keeps_permanent():
	var s := FuritenState.new()
	s.permanent = true
	s.temporary = true
	s.clear_temporary()
	assert_false(s.temporary)
	assert_true(s.permanent)
	assert_true(s.is_furiten(), "permanent 仍在")

func test_clear_temporary_when_only_temporary_clears_furiten():
	var s := FuritenState.new()
	s.temporary = true
	s.clear_temporary()
	assert_false(s.is_furiten())

func test_update_waits_replaces_array():
	var s := FuritenState.new()
	s.update_waits([TileId.S5, TileId.S8])
	assert_eq(s.waits, [TileId.S5, TileId.S8])
	s.update_waits([TileId.W3])
	assert_eq(s.waits, [TileId.W3])
