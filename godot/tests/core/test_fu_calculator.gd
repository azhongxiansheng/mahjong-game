extends GutTest

# FuCalculator 综合符算流程：
#   1. 七対子 → 25 固定
#   2. 平和自摸 → 20 固定；平和荣胡 → 30 固定
#   3. 否则：副底 20 + 自摸 2 + 门清荣胡 10 + 面子符 + 雀头符 + 待牌符
#   4. 向上取整到 10
#
# 门清判定：called_melds 中只允许 ANKAN（暗杠不破坏门清）
# 荣胡完成的刻子算明刻（含 winning 的刻子）— 0c 简化：仅看 decomposition 内的刻子

func _make_yaku_list(yaku_pairs: Array) -> YakuList:
	var y := YakuList.empty()
	for pair in yaku_pairs:
		y.add_yaku(pair[0], pair[1])
	return y

# ---- 七対子固定 25 ----

func test_chiitoi_fixed_25():
	var d := {"melds": [], "pair": -1}  # 七対子不走 standard 分解
	var ctx := ScoreContext.tsumo(Tile.new(TileId.W5), TileId.E, TileId.E, 0, 0)
	var y := _make_yaku_list([[&"chiitoitsu", 2]])
	assert_eq(FuCalculator.calculate(d, [], ctx, y), 25)

# ---- 平和特例 ----

func test_pinfu_tsumo_20():
	# 平和自摸：必门清、全顺子、雀头非役牌、双面待 — 信任 yaku 标记
	var d := {
		"melds": [
			[TileId.W1, TileId.W2, TileId.W3],
			[TileId.W4, TileId.W5, TileId.W6],
			[TileId.T2, TileId.T3, TileId.T4],
			[TileId.T6, TileId.T7, TileId.T8],
		],
		"pair": TileId.S5,
	}
	var ctx := ScoreContext.tsumo(Tile.new(TileId.T8), TileId.E, TileId.S_WIND, 0, 1)
	var y := _make_yaku_list([[&"pinfu", 1]])
	assert_eq(FuCalculator.calculate(d, [], ctx, y), 20, "平和自摸固定 20")

func test_pinfu_ron_30():
	var d := {
		"melds": [
			[TileId.W1, TileId.W2, TileId.W3],
			[TileId.W4, TileId.W5, TileId.W6],
			[TileId.T2, TileId.T3, TileId.T4],
			[TileId.T6, TileId.T7, TileId.T8],
		],
		"pair": TileId.S5,
	}
	var ctx := ScoreContext.ron(Tile.new(TileId.T8), TileId.E, TileId.S_WIND, 0, 1, 2)
	var y := _make_yaku_list([[&"pinfu", 1]])
	assert_eq(FuCalculator.calculate(d, [], ctx, y), 30, "平和荣胡固定 30")

# ---- 一般符算 ----

func test_standard_concealed_tsumo_simple_kanchan():
	# 222m + 234p + 234p + 678s + EE (场风东) 自摸 7s 嵌张
	# 20 副底 + 2 自摸 + 2 雀头(E场风) + 2 待(嵌7) + 4 暗刻 222m = 30
	var d := {
		"melds": [
			[TileId.W2, TileId.W2, TileId.W2],
			[TileId.T2, TileId.T3, TileId.T4],
			[TileId.T2, TileId.T3, TileId.T4],
			[TileId.S6, TileId.S7, TileId.S8],
		],
		"pair": TileId.E,
	}
	var ctx := ScoreContext.tsumo(Tile.new(TileId.S7), TileId.E, TileId.E, 0, 0)
	var y := _make_yaku_list([[&"riichi", 1]])
	assert_eq(FuCalculator.calculate(d, [], ctx, y), 30)

func test_standard_concealed_ron_with_yakuhai_pair():
	# 同上但荣胡：20 + 10 门清荣胡 + 2 雀头 + 2 待 + 4 暗刻 = 38 → 40
	var d := {
		"melds": [
			[TileId.W2, TileId.W2, TileId.W2],
			[TileId.T2, TileId.T3, TileId.T4],
			[TileId.T2, TileId.T3, TileId.T4],
			[TileId.S6, TileId.S7, TileId.S8],
		],
		"pair": TileId.E,
	}
	var ctx := ScoreContext.ron(Tile.new(TileId.S7), TileId.E, TileId.E, 0, 0, 2)
	var y := _make_yaku_list([[&"riichi", 1]])
	assert_eq(FuCalculator.calculate(d, [], ctx, y), 40)

func test_open_hand_minimum_fu():
	# 副露 1 个明刻 (PON 5p) + 暗牌 3 面子 + 雀头
	# is_concealed = false (含非 ANKAN 副露)
	# 20 副底 + 2 自摸 + 0 雀头(数牌) + 0 待(双面) + 0 顺子*3 + 2 明刻5p = 24 → 30
	var d := {
		"melds": [
			[TileId.W1, TileId.W2, TileId.W3],
			[TileId.W4, TileId.W5, TileId.W6],
			[TileId.S2, TileId.S3, TileId.S4],
		],
		"pair": TileId.S6,
	}
	var pon := Meld.make_pon(
		[Tile.new(TileId.T5), Tile.new(TileId.T5), Tile.new(TileId.T5)], 1)
	var ctx := ScoreContext.tsumo(Tile.new(TileId.W3), TileId.E, TileId.S_WIND, 0, 1)
	var y := _make_yaku_list([[&"tanyao", 1]])
	# winning W3 是 [W1,W2,W3] 的端，a=W1, number(a)=1 → 边？不对：
	# winning=a (W1) ? 不是。winning=W3=a+2, number(a)=1 → 边张 +2
	# 所以总 fu = 20+2+0+2(边张)+2(明刻)= 26 → 30
	assert_eq(FuCalculator.calculate(d, [pon], ctx, y), 30)

func test_ankan_keeps_concealed():
	# 暗杠不破坏门清 → 仍可门清荣胡 +10
	# 暗牌 234m 234p 567s + EE，暗杠 1m
	# 荣胡 W4? 这里只测 fu 累加，winning 选个无影响的端
	# 20 + 10 门清荣 + 2 雀头E + 0 待(选个双面) + 0顺*3 + 32 暗杠幺九 = 64 → 70
	var d := {
		"melds": [
			[TileId.W2, TileId.W3, TileId.W4],
			[TileId.T2, TileId.T3, TileId.T4],
			[TileId.S5, TileId.S6, TileId.S7],
		],
		"pair": TileId.E,
	}
	var ankan := Meld.make_ankan([
		Tile.new(TileId.W1), Tile.new(TileId.W1),
		Tile.new(TileId.W1), Tile.new(TileId.W1)])
	# winning S5: 在 [S5,S6,S7], a=S5, winning=a, number(a)=5 → 双面 0
	var ctx := ScoreContext.ron(Tile.new(TileId.S5), TileId.E, TileId.E, 0, 0, 2)
	var y := _make_yaku_list([[&"riichi", 1]])
	assert_eq(FuCalculator.calculate(d, [ankan], ctx, y), 70)

func test_minkan_breaks_concealed():
	# 明杠 → 不算门清，无门清荣胡 +10
	# 同上场景但用 minkan
	# 20 + 0 (非门清) + 2 雀头 + 0 待 + 0 顺*3 + 16 明杠幺九 = 38 → 40
	var d := {
		"melds": [
			[TileId.W2, TileId.W3, TileId.W4],
			[TileId.T2, TileId.T3, TileId.T4],
			[TileId.S5, TileId.S6, TileId.S7],
		],
		"pair": TileId.E,
	}
	var minkan := Meld.make_minkan([
		Tile.new(TileId.W1), Tile.new(TileId.W1),
		Tile.new(TileId.W1), Tile.new(TileId.W1)], 2)
	var ctx := ScoreContext.ron(Tile.new(TileId.S5), TileId.E, TileId.E, 0, 0, 2)
	var y := _make_yaku_list([[&"yakuhai_east", 1]])
	assert_eq(FuCalculator.calculate(d, [minkan], ctx, y), 40)

func test_concealed_triplet_in_decomp_when_tsumo():
	# 自摸时含 winning 的刻子算暗刻
	# 333m 暗刻自摸 + 其他
	# 20 + 2 自摸 + 0 雀头 + 0 双面 + 4 暗刻333m + 0顺*3 = 26 → 30
	var d := {
		"melds": [
			[TileId.W3, TileId.W3, TileId.W3],
			[TileId.T2, TileId.T3, TileId.T4],
			[TileId.S5, TileId.S6, TileId.S7],
			[TileId.W6, TileId.W7, TileId.W8],
		],
		"pair": TileId.S2,
	}
	var ctx := ScoreContext.tsumo(Tile.new(TileId.S5), TileId.E, TileId.S_WIND, 0, 1)
	var y := _make_yaku_list([[&"riichi", 1]])
	# winning S5 在 [S5,S6,S7] a=S5, number=5 → 双面 0
	assert_eq(FuCalculator.calculate(d, [], ctx, y), 30)

func test_open_triplet_in_decomp_when_ron():
	# 荣胡时含 winning 的刻子算明刻（玩家从对手放铳完成）
	# 333m 荣胡 → 333m 算明刻
	# 20 + 10 门清荣 + 0 雀头 + 0 双碰 + 2 明刻333m(中) + 0顺*3 = 32 → 40
	# 注意：333m 含 winning W3，按明刻算
	var d := {
		"melds": [
			[TileId.W3, TileId.W3, TileId.W3],
			[TileId.T2, TileId.T3, TileId.T4],
			[TileId.S5, TileId.S6, TileId.S7],
			[TileId.W6, TileId.W7, TileId.W8],
		],
		"pair": TileId.S2,
	}
	var ctx := ScoreContext.ron(Tile.new(TileId.W3), TileId.E, TileId.S_WIND, 0, 1, 2)
	var y := _make_yaku_list([[&"riichi", 1]])
	# winning W3 在 [W3,W3,W3] 刻子 → 双碰 0；门清→+10
	# 但 W3 也在 [W6,W7,W8]? 不在。也在 [T2,T3,T4]? 不在 (T3 != W3)
	# WaitFu max(0(双碰)) = 0
	# Meld fu: 333 是含 winning 的刻子, 荣胡 → 明刻 W3(中) = 2
	# fu = 20 + 10 + 0 + 0 + 2 + 0*3 = 32 → 40
	assert_eq(FuCalculator.calculate(d, [], ctx, y), 40)

func test_yakuhai_pair_adds_2_fu():
	# 雀头是三元牌
	# 20 + 2 自摸 + 2 雀头(白) + 0 待 + 0 顺*4 = 24 → 30
	var d := {
		"melds": [
			[TileId.W1, TileId.W2, TileId.W3],
			[TileId.W4, TileId.W5, TileId.W6],
			[TileId.T2, TileId.T3, TileId.T4],
			[TileId.S6, TileId.S7, TileId.S8],
		],
		"pair": TileId.HAKU,
	}
	var ctx := ScoreContext.tsumo(Tile.new(TileId.T2), TileId.E, TileId.S_WIND, 0, 1)
	var y := _make_yaku_list([[&"riichi", 1]])
	# winning T2 在 [T2,T3,T4] a=T2, winning=a, number=2 ≠ 7 → 双面 0
	assert_eq(FuCalculator.calculate(d, [], ctx, y), 30)

func test_yakuman_returns_zero():
	# 役满走 score_formula 不算 fu，FuCalculator 返 0 即可
	var d := {"melds": [], "pair": -1}
	var ctx := ScoreContext.tsumo(Tile.new(TileId.HAKU), TileId.E, TileId.E, 0, 0)
	var y := YakuList.empty()
	y.is_yakuman = true
	y.yakuman_multiplier = 1
	y.add_yaku(&"daisangen", 13)
	assert_eq(FuCalculator.calculate(d, [], ctx, y), 0, "役满 fu 不参与")


func test_breakdown_exposes_authoritative_fu_components_and_rounding():
	var d := {
		"melds": [
			[TileId.W2, TileId.W2, TileId.W2],
			[TileId.T2, TileId.T3, TileId.T4],
			[TileId.T2, TileId.T3, TileId.T4],
			[TileId.S6, TileId.S7, TileId.S8],
		],
		"pair": TileId.E,
	}
	var ctx := ScoreContext.ron(Tile.new(TileId.S7), TileId.E, TileId.E, 0, 0, 2)
	var y := _make_yaku_list([[&"riichi", 1]])
	var breakdown: Dictionary = FuCalculator.breakdown(d, [], ctx, y)
	assert_eq(breakdown.get("kind"), "standard")
	assert_eq(breakdown.get("raw_fu"), 38)
	assert_eq(breakdown.get("rounded_fu"), 40)
	var items: Array = breakdown.get("items", [])
	assert_eq(items.map(func(item: Dictionary): return item.get("key")), [
		"base", "menzen_ron", "pair", "wait", "meld",
	])
	assert_eq(items.map(func(item: Dictionary): return item.get("fu")), [20, 10, 2, 2, 4])
	for item in items:
		assert_false(String(item.get("label", "")).is_empty(), "每项符必须有玩家可读标签")


func test_breakdown_keeps_fixed_fu_special_cases_explicit():
	var d := {"melds": [], "pair": -1}
	var ctx := ScoreContext.tsumo(Tile.new(TileId.W5), TileId.E, TileId.E, 0, 0)
	var chiitoi := _make_yaku_list([[&"chiitoitsu", 2]])
	var breakdown: Dictionary = FuCalculator.breakdown(d, [], ctx, chiitoi)
	assert_eq(breakdown.get("kind"), "chiitoi")
	assert_eq(breakdown.get("raw_fu"), 25)
	assert_eq(breakdown.get("rounded_fu"), 25)
	assert_eq(breakdown.get("items"), [{"key": "chiitoi", "label": "七对子固定", "fu": 25}])
