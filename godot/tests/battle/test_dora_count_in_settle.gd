extends GutTest

# _adapt_yaku_list dora 计数修复回归测试。
# 之前 sc.dora_count = state.dora_indicators.visible_tiles().size() —— 错的(只数
# 指示牌张数,常 1)。修复后调 count_total_dora(hand, melds, include_ura)
# 实际数胡牌手 + 副露里匹配 dora 的牌数。
#
# 本测试用一个有 3 张 W5(5 万)的手牌 + dora 指示牌 W4 → 应得 3 dora han。

const _BC := preload("res://battle/battle_controller.gd")


func _make_bc() -> BattleController:
	return BattleController.new(42, 0, false, TileId.E)


# 构造:dora 指示牌 W4(指向 dora=W5),自家手 14 张含 3 张 W5。
# 调 _adapt_yaku_list,验 dora_count = 3。
func test_dora_count_uses_real_hand_match_not_indicator_size() -> void:
	var bc := _make_bc()
	# 干净 dora 状态:1 个明 dora 指示牌 = W4
	assert_true(bc.state.dora_indicators.restore_pairs(
		[Tile.new(TileId.W4)], [Tile.new(TileId.W1)]))
	# 拼 14 张手:m5 m5 m5 + ...其它 11 张随便凑(本测试只关心 dora_count 不验胡牌型)
	var hand := Hand.new()
	for tid in [
		TileId.W5, TileId.W5, TileId.W5,
		TileId.W1, TileId.W2, TileId.W3, TileId.W6, TileId.W7, TileId.W8,
		TileId.T1, TileId.T2, TileId.T3, TileId.S1, TileId.S1,
	]:
		hand.add(Tile.new(tid))
	# 跑 _adapt_yaku_list(空 yaku_list 也行,只验 dora_count)
	var empty_entries := YakuEntries.new()
	var sc: YakuList = bc._adapt_yaku_list(empty_entries, hand, [], false)
	assert_eq(sc.dora_count, 3,
		"3 张 W5 应给 3 dora han,实际 %d" % sc.dora_count)


# 没匹配 dora → 0(过去 bug 仍 = indicator 张数 1,fix 后 = 0)
func test_no_dora_match_returns_zero() -> void:
	var bc := _make_bc()
	assert_true(bc.state.dora_indicators.restore_pairs(
		[Tile.new(TileId.W4)], [Tile.new(TileId.W1)]))  # dora=W5
	var hand := Hand.new()
	for tid in [
		TileId.W1, TileId.W1, TileId.W2, TileId.W2, TileId.W3, TileId.W3,
		TileId.W6, TileId.W6, TileId.W7, TileId.W7, TileId.W8, TileId.W8,
		TileId.T1, TileId.T1,
	]:
		hand.add(Tile.new(tid))
	var empty_entries := YakuEntries.new()
	var sc: YakuList = bc._adapt_yaku_list(empty_entries, hand, [], false)
	assert_eq(sc.dora_count, 0,
		"手里没 W5 → 应 0 dora han (旧 bug 会返 1 即 indicator 数)")


# 不传 hand → 走旧路径(向后兼容),仍按 indicator 张数。
# 主要为了保护其它老 caller(如有)不爆。
func test_old_api_fallback_still_uses_indicator_count() -> void:
	var bc := _make_bc()
	assert_true(bc.state.dora_indicators.restore_pairs(
		[Tile.new(TileId.W4)], [Tile.new(TileId.W1)]))
	var empty_entries := YakuEntries.new()
	var sc: YakuList = bc._adapt_yaku_list(empty_entries)
	assert_eq(sc.dora_count, 1,
		"不传 hand 走老路径 = indicator size (兼容性)")
