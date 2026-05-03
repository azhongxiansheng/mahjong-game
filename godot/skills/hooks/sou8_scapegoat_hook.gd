# 8 索·替罪 — §8.4 抓马反向得分系（M6 内容生产）
#
# v1: owner 放铳时给胜者 -1 番（模拟"将放铳责任转嫁部分"）
# spec 原效果："CHAMBO 触发时转嫁责任（替罪羊代付）"
# v1 简化：用 add_han(winner, -1) 表达"对方收益减少 ≈ 责任转嫁"；
# 真"指定对手承担放铳"需 mark_pao_transfer ctx 扩展（M7）。
extends SkillHook

# SCAPEGOAT_HAN_PENALTY 已迁移到 BalanceConstants (&"sou8_scapegoat_han_penalty")。

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	var discarder: int = int(event.extra.get("discarder_seat", -1))
	if discarder != ctx.beneficiary_seat:
		return
	ctx.add_han(event.actor_seat, int(BalanceConstants.lookup(&"sou8_scapegoat_han_penalty")))
