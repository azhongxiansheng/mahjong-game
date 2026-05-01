class_name PayoutCalculator

# 把基本点 + WinContext 转成 {payer_seat: points_owed_to_winner}。
# 立直棒不在字典里（由 ScoreCalc 单独加给 winner）；本场已合并入 payer 出的钱。
#
# 公式：
#   闲自摸：庄出 ceil_to_100(base*2)，2 闲各 ceil_to_100(base*1)；本场每家 +100
#   庄自摸：3 闲各 ceil_to_100(base*2)；本场每家 +100
#   闲荣胡：loser 出 ceil_to_100(base*4) + 本场*300
#   庄荣胡：loser 出 ceil_to_100(base*6) + 本场*300
# 包牌（v1 简化版）：
#   自摸：仅 pao_seat 出全额
#   荣胡：pao_seat 与 loser 各半

static func payout(base_points: int, win_ctx: WinContext) -> Dictionary:
	if win_ctx.is_tsumo:
		return _tsumo_payout(base_points, win_ctx)
	return _ron_payout(base_points, win_ctx)

static func _tsumo_payout(base: int, ctx: WinContext) -> Dictionary:
	var dealer_share: int = _ceil_to_100(base * 2)
	var non_dealer_share: int = _ceil_to_100(base)
	var honba_per_seat: int = ctx.honba * 100  # 自摸 3 家分摊本场

	if ctx.has_pao():
		var total: int
		if ctx.winner_is_dealer():
			total = dealer_share * 3
		else:
			total = dealer_share + non_dealer_share * 2
		total += ctx.honba * 300
		return {ctx.pao_seat: total}

	var result := {}
	for seat in range(4):
		if seat == ctx.winner_seat:
			continue
		if ctx.winner_is_dealer():
			# 庄自摸：3 闲家各 dealer_share
			result[seat] = dealer_share + honba_per_seat
		else:
			# 闲自摸：庄 dealer_share，其他闲 non_dealer_share
			if seat == ctx.dealer_seat:
				result[seat] = dealer_share + honba_per_seat
			else:
				result[seat] = non_dealer_share + honba_per_seat
	return result

static func _ron_payout(base: int, ctx: WinContext) -> Dictionary:
	var multiplier: int = 6 if ctx.winner_is_dealer() else 4
	var loser_total: int = _ceil_to_100(base * multiplier) + ctx.honba * 300

	if ctx.has_pao():
		# 各半（v1 简化）：取 loser_total 一半，整数除法
		var half: int = loser_total / 2
		return {
			ctx.loser_seat: half,
			ctx.pao_seat: loser_total - half,
		}

	return {ctx.loser_seat: loser_total}

static func _ceil_to_100(n: int) -> int:
	return ((n + 99) / 100) * 100
