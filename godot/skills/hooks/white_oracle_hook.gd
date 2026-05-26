# 白·占卜 — §8.5 透明牌 / 信息系
# owner DRAW 时 reveal 第 1 张未翻 Dora 指示牌给自己。
extends SkillHook

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	ctx.reveal_dora_indicator_to(ctx.beneficiary_seat, 0)
