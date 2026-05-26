# 1万·透视 — §8.5 透明牌系
# owner 摸到此牌时，从下家手牌随机 reveal 1 张给自己。
extends SkillHook

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	var next_seat: int = (ctx.beneficiary_seat + 1) % 4
	ctx.reveal_random_from_seat(next_seat, ctx.beneficiary_seat)
