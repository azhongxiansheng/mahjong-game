# 赤木 — 角色被动「鬼読み」
# 原著：赤木しげる读取对手"背中の気配"，从不振込。
# 效果：每次摸牌后 reveal 1 张对手手牌（读心能力）。
extends SkillHook

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	var target: int = (ctx.beneficiary_seat + 1) % 4
	ctx.reveal_random_from_seat(target, ctx.beneficiary_seat)
