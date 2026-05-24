# 1万·透视+ — 升级版
# 基础版 reveal 下家 1 张 → 升级版 reveal 下家 + 对家各 1 张
extends SkillHook

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	var next: int = (ctx.beneficiary_seat + 1) % 4
	var across: int = (ctx.beneficiary_seat + 2) % 4
	ctx.reveal_random_from_seat(next, ctx.beneficiary_seat)
	ctx.reveal_random_from_seat(across, ctx.beneficiary_seat)
