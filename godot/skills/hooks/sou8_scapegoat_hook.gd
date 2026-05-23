# 8 索·替罪 — §8.4 抓马反向得分系
#
# v2: owner 放铳时，从另一个对手转 2000 点给 owner（替罪羊代付一部分损失）。
# 选最高分的非胜者/非 owner 对手承担。
extends SkillHook

const SCAPEGOAT_AMOUNT: int = 2000

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	var discarder: int = int(event.extra.get("discarder_seat", -1))
	if discarder != ctx.beneficiary_seat:
		return
	var best_seat: int = -1
	var best_score: int = -1
	for i in range(4):
		if i == ctx.beneficiary_seat or i == event.actor_seat:
			continue
		var s: int = ctx.get_score(i)
		if s > best_score:
			best_score = s
			best_seat = i
	if best_seat >= 0:
		ctx.transfer_points(best_seat, ctx.beneficiary_seat, SCAPEGOAT_AMOUNT)
