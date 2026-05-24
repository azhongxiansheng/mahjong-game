extends GutTest

# ClaimValidator: 鸣牌 / 荣胡 / 自摸合法性纯函数。
# 不修改 state，只判 bool（或返候选列表）。

func _hand(ids: Array) -> Hand:
	var h := Hand.new()
	for tid in ids:
		h.add(Tile.new(tid))
	return h

# ---- can_chi ----

func test_chi_only_by_next_seat():
	# discarder=0，claimant=1（下家）→ 允许（如果 hand 构成）
	var h := _hand([TileId.W2, TileId.W4])  # 等 W3 完成 234
	assert_true(ClaimValidator.can_chi(1, 0, h, TileId.W3), "下家可吃")

func test_chi_blocked_for_non_next_seat():
	var h := _hand([TileId.W2, TileId.W4])
	assert_false(ClaimValidator.can_chi(2, 0, h, TileId.W3), "对家不可吃")
	assert_false(ClaimValidator.can_chi(3, 0, h, TileId.W3), "上家不可吃")

func test_chi_blocked_for_self_discarder():
	var h := _hand([TileId.W2, TileId.W4])
	assert_false(ClaimValidator.can_chi(0, 0, h, TileId.W3))

func test_chi_low_end_meld():
	# discard W1，hand 含 W2 W3 → 完成 1-2-3
	var h := _hand([TileId.W2, TileId.W3])
	assert_true(ClaimValidator.can_chi(1, 0, h, TileId.W1))

func test_chi_high_end_meld():
	# discard W9，hand 含 W7 W8 → 完成 7-8-9
	var h := _hand([TileId.W7, TileId.W8])
	assert_true(ClaimValidator.can_chi(1, 0, h, TileId.W9))

func test_chi_honor_tile_blocked():
	# 字牌（东风）不能吃
	var h := _hand([TileId.E, TileId.S_WIND])
	assert_false(ClaimValidator.can_chi(1, 0, h, TileId.W_WIND), "字牌无顺子")

func test_chi_missing_companion():
	# hand 只有 W4，缺 W2 → 不能吃 W3
	var h := _hand([TileId.W4])
	assert_false(ClaimValidator.can_chi(1, 0, h, TileId.W3))

# ---- can_pon ----

func test_pon_with_two_in_hand():
	var h := _hand([TileId.W5, TileId.W5, TileId.T3])
	assert_true(ClaimValidator.can_pon(2, 0, h, TileId.W5))

func test_pon_blocked_with_one_in_hand():
	var h := _hand([TileId.W5, TileId.T3])
	assert_false(ClaimValidator.can_pon(2, 0, h, TileId.W5))

func test_pon_blocked_self_discard():
	var h := _hand([TileId.W5, TileId.W5])
	assert_false(ClaimValidator.can_pon(0, 0, h, TileId.W5))

# ---- can_minkan ----

func test_minkan_with_three_in_hand():
	var h := _hand([TileId.W5, TileId.W5, TileId.W5, TileId.T3])
	assert_true(ClaimValidator.can_minkan(2, 0, h, TileId.W5))

func test_minkan_blocked_with_two():
	var h := _hand([TileId.W5, TileId.W5])
	assert_false(ClaimValidator.can_minkan(2, 0, h, TileId.W5))

# ---- ankan_candidates ----

func test_ankan_candidates_one_id():
	var h := _hand([TileId.W5, TileId.W5, TileId.W5, TileId.W5, TileId.T3])
	var c := ClaimValidator.ankan_candidates(h)
	assert_eq(c, [TileId.W5])

func test_ankan_candidates_multiple():
	var h := _hand([
		TileId.W5, TileId.W5, TileId.W5, TileId.W5,
		TileId.E, TileId.E, TileId.E, TileId.E,
	])
	var c := ClaimValidator.ankan_candidates(h)
	assert_true(TileId.W5 in c)
	assert_true(TileId.E in c)

func test_ankan_candidates_none():
	var h := _hand([TileId.W5, TileId.W5, TileId.W5])
	assert_eq(ClaimValidator.ankan_candidates(h), [])

# ---- can_added_kan ----

func test_added_kan_with_existing_pon_and_4th():
	var pon := Meld.make_pon(
		[Tile.new(TileId.W5), Tile.new(TileId.W5), Tile.new(TileId.W5)], 1)
	var h := _hand([TileId.W5, TileId.T3])
	assert_true(ClaimValidator.can_added_kan([pon], h, TileId.W5))

func test_added_kan_no_pon():
	var h := _hand([TileId.W5, TileId.T3])
	assert_false(ClaimValidator.can_added_kan([], h, TileId.W5))

func test_added_kan_pon_different_id():
	var pon := Meld.make_pon(
		[Tile.new(TileId.W5), Tile.new(TileId.W5), Tile.new(TileId.W5)], 1)
	var h := _hand([TileId.T3])
	assert_false(ClaimValidator.can_added_kan([pon], h, TileId.T3), "PON 是 W5，不是 T3")

# ---- can_ron / can_tsumo ----

func test_can_ron_winning_not_furiten():
	# 13 张听 W5（嵌张）→ 荣胡 W5
	var h := _hand([
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.W4, TileId.W6,    # 等 W5 嵌张
		TileId.S5, TileId.S5,
	])
	var fs := FuritenState.new()
	assert_true(ClaimValidator.can_ron(h, [], Tile.new(TileId.W5), fs))

func test_can_ron_blocked_by_furiten():
	var h := _hand([
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.W4, TileId.W6,
		TileId.S5, TileId.S5,
	])
	var fs := FuritenState.new()
	fs.permanent = true
	assert_false(ClaimValidator.can_ron(h, [], Tile.new(TileId.W5), fs))

func test_can_ron_not_winning():
	var h := _hand([
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.W4, TileId.W6,
		TileId.S5, TileId.S5,
	])
	var fs := FuritenState.new()
	assert_false(ClaimValidator.can_ron(h, [], Tile.new(TileId.HAKU), fs), "白板不完成此型")

func test_can_tsumo_winning():
	var h := _hand([
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.W4, TileId.W6,
		TileId.S5, TileId.S5,
	])
	assert_true(ClaimValidator.can_tsumo(h, [], Tile.new(TileId.W5)))

func test_can_tsumo_not_winning():
	var h := _hand([
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.W4, TileId.W6,
		TileId.S5, TileId.S5,
	])
	assert_false(ClaimValidator.can_tsumo(h, [], Tile.new(TileId.HAKU)))

# ---- chi_companion_options（v1 玩家 chi UI 候选） ----

func test_chi_companion_options_low_only():
	# 弃 W4，手中有 W2 W3 → 仅 [W2,W3] 一组
	var h := _hand([TileId.W2, TileId.W3])
	var opts := ClaimValidator.chi_companion_options(h, TileId.W4)
	assert_eq(opts.size(), 1, "1 组合法")
	assert_eq(opts[0], [TileId.W2, TileId.W3])

func test_chi_companion_options_middle_only():
	# 弃 W4，手中有 W3 W5 → 仅 [W3, W5] 嵌张
	var h := _hand([TileId.W3, TileId.W5])
	var opts := ClaimValidator.chi_companion_options(h, TileId.W4)
	assert_eq(opts.size(), 1)
	assert_eq(opts[0], [TileId.W3, TileId.W5])

func test_chi_companion_options_high_only():
	# 弃 W4，手中有 W5 W6 → 仅 [W5, W6]
	var h := _hand([TileId.W5, TileId.W6])
	var opts := ClaimValidator.chi_companion_options(h, TileId.W4)
	assert_eq(opts.size(), 1)
	assert_eq(opts[0], [TileId.W5, TileId.W6])

func test_chi_companion_options_three_combos():
	# 弃 W4，手中有 W2 W3 W5 W6 → 3 组合法 [W2,W3] / [W3,W5] / [W5,W6]
	var h := _hand([TileId.W2, TileId.W3, TileId.W5, TileId.W6])
	var opts := ClaimValidator.chi_companion_options(h, TileId.W4)
	assert_eq(opts.size(), 3, "3 组合法 companion")
	assert_eq(opts[0], [TileId.W2, TileId.W3])
	assert_eq(opts[1], [TileId.W3, TileId.W5])
	assert_eq(opts[2], [TileId.W5, TileId.W6])

func test_chi_companion_options_honor_returns_empty():
	# 字牌 (CHUN) 不能吃
	var h := _hand([TileId.W2, TileId.W3])
	assert_eq(ClaimValidator.chi_companion_options(h, TileId.CHUN), [])

func test_chi_companion_options_no_match_returns_empty():
	# 弃 W4 但手中无任何相邻数牌
	var h := _hand([TileId.T1, TileId.S9])
	assert_eq(ClaimValidator.chi_companion_options(h, TileId.W4), [])

func test_chi_companion_options_edge_w1():
	# 弃 W1，仅 [W2, W3] 一种（无 W-1 / W0）
	var h := _hand([TileId.W2, TileId.W3])
	var opts := ClaimValidator.chi_companion_options(h, TileId.W1)
	assert_eq(opts.size(), 1)
	assert_eq(opts[0], [TileId.W2, TileId.W3])

func test_chi_companion_options_edge_w9():
	# 弃 W9，仅 [W7, W8] 一种
	var h := _hand([TileId.W7, TileId.W8])
	var opts := ClaimValidator.chi_companion_options(h, TileId.W9)
	assert_eq(opts.size(), 1)
	assert_eq(opts[0], [TileId.W7, TileId.W8])

# ---- kuikae_restricted_ids ----

func test_kuikae_chi_restricts_claimed_and_suji():
	# Chi [2,3,4] with claimed W4, companions W2,W3
	# Restricted: W4 (claimed) + W1 (suji: 1-2-3 sequence)
	var restricted := ClaimValidator.kuikae_restricted_ids(
		TileId.W4, [TileId.W2, TileId.W3], true)
	assert_true(TileId.W4 in restricted, "cannot discard claimed tile")
	assert_true(TileId.W1 in restricted, "suji restriction: W1")

func test_kuikae_chi_middle_wait_restricts_only_claimed():
	# Chi [3,4,5] with claimed W4 (kanchan middle)
	var restricted := ClaimValidator.kuikae_restricted_ids(
		TileId.W4, [TileId.W3, TileId.W5], true)
	assert_true(TileId.W4 in restricted)
	assert_eq(restricted.size(), 1, "middle: only claimed tile restricted")

func test_kuikae_chi_high_end():
	# Chi [4,5,6] with claimed W4 (low end of meld)
	# Restricted: W4 + W7 (suji: 5-6-7)
	var restricted := ClaimValidator.kuikae_restricted_ids(
		TileId.W4, [TileId.W5, TileId.W6], true)
	assert_true(TileId.W4 in restricted)
	assert_true(TileId.W7 in restricted, "suji restriction: W7")

func test_kuikae_chi_edge_w7_w8_w9():
	# Chi [7,8,9] with claimed W7 (low end)
	# Restricted: W7 only (W10 doesn't exist)
	var restricted := ClaimValidator.kuikae_restricted_ids(
		TileId.W7, [TileId.W8, TileId.W9], true)
	assert_true(TileId.W7 in restricted)
	assert_eq(restricted.size(), 1)

func test_kuikae_pon_restricts_4th_copy():
	var restricted := ClaimValidator.kuikae_restricted_ids(
		TileId.W5, [], false)
	assert_eq(restricted, [TileId.W5])
