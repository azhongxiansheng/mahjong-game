# 白·占卜 — §8.5 透明牌 / 信息系（M6 内容生产）
#
# v1: owner 摸牌时 reveal 一张 dora 占位 tile（HAKU stub）
# spec 原效果："每巡看 1 张未翻 Dora 指示牌"
# M10 升级：用 ctx.reveal_dora_indicator_to 拉真牌墙未翻 dora 指示。
# v1 简化：固定 reveal indicator[0]（开局 dora 指示），未来按"未翻 = 已开过
# 杠的 indicator[k]"动态 pick。
extends SkillHook

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	ctx.reveal_dora_indicator_to(ctx.beneficiary_seat, 0)
