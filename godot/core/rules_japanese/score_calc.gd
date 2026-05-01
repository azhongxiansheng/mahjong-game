class_name ScoreCalc

# 顶层入口：把 WinPattern.detect 结果 + called_melds + yaku_list + win_ctx
# 算成最终结算 dict。
#
# 返回字段：
#   fu, han, base_points, payout, yakuman_multiplier, winner_seat, winner_total
#
# winner_total = sum(payout.values()) + riichi_sticks*1000
#
# TODO(0b 串接)：多分解时本计划选 fu 最高。0b 落地后改为 (han, fu) 字典序最大
#   —— 因为 yaku 判定依赖具体分解（如平和需要全顺子），不同分解可能不同 han。
#   届时 ScoreCalc.calculate 接口加 yaku_calculator 回调，对每个分解算 yaku 再选 max。

static func calculate(win_pattern_result: Dictionary, called_melds: Array, yaku_list: YakuList, win_ctx: WinContext) -> Dictionary:
	var fu: int
	var han := yaku_list.total_han()

	if yaku_list.is_yakuman:
		# 役满：fu 不参与，base 直接 8000 × multiplier
		fu = 0
	elif win_pattern_result.is_chiitoi:
		fu = 25
	elif win_pattern_result.is_kokushi:
		fu = 0  # 国士役满走 yakuman 路径；若 yaku_list 没标 yakuman → 视为异常但不崩
	else:
		fu = _pick_best_fu(win_pattern_result.standard_decompositions, called_melds, win_ctx, yaku_list)

	var base: int = ScoreFormula.base_points(fu, han, yaku_list.yakuman_multiplier)
	var payout: Dictionary = PayoutCalculator.payout(base, win_ctx)

	var winner_total := 0
	for v in payout.values():
		winner_total += v
	winner_total += win_ctx.riichi_sticks * 1000

	return {
		"fu": fu,
		"han": han,
		"base_points": base,
		"payout": payout,
		"yakuman_multiplier": yaku_list.yakuman_multiplier,
		"winner_seat": win_ctx.winner_seat,
		"winner_total": winner_total,
	}

static func _pick_best_fu(decompositions: Array, called_melds: Array, win_ctx: WinContext, yaku_list: YakuList) -> int:
	var best := 0
	for d in decompositions:
		var fu: int = FuCalculator.calculate(d, called_melds, win_ctx, yaku_list)
		if fu > best:
			best = fu
	return best
