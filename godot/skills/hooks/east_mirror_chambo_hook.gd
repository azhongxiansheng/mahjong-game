# 东·镜抓 — §8.4 抓马反向得分系（M6 内容生产）
#
# v1: owner 放铳时给胜者 -1 番（模拟"对方得分减半"）
# spec 原效果："owner 放铳时对方得分 ×0.5"
# v1 简化：用 add_han(winner, -1) 表达"该役 -1 番 ≈ 半分"；ScoreFormula
# 钳制 < 0 时按 0 算。真"乘 0.5"需 ctx.scale_payout(winner, factor) 扩展（M7）。
extends SkillHook

const CHAMBO_HAN_PENALTY: int = -1

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	var discarder: int = int(event.extra.get("discarder_seat", -1))
	if discarder != ctx.beneficiary_seat:
		return
	# event.actor_seat = winner（RON_DECLARED 的 actor）
	ctx.add_han(event.actor_seat, CHAMBO_HAN_PENALTY)
