# 西风·镜像 — §8.3 阻胡系（M6 内容生产）
#
# v1: owner 立直时清振听 1 次
# spec 原效果："owner 立直时，此牌防一次振听（清除 FuritenState.permanent）"
# v1 简化：trigger = RIICHI_DECLARED + owner，调 ctx.clear_furiten(owner)。
# "1 次"语义靠 SkillResource.consumed = true 标记（M7 加 ctx.consume_self
# API 后真消耗）。
extends SkillHook

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	# RIICHI_DECLARED: actor = 立直方
	# 仅 owner 自家立直时触发（owner_trigger 已保证 beneficiary_seat = owner_seat）
	if event.actor_seat != ctx.beneficiary_seat:
		return
	ctx.clear_furiten(ctx.beneficiary_seat)
