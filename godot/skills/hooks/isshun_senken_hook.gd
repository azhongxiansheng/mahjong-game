# 一巡先見 — §8.10 #4 神级角色能力（M6 内容生产）
#
# v1: owner 摸牌时 reveal 一张占位 tile（HAKU stub）
# spec 原效果："每巡可花 1 巡看下次摸牌"
# M10 升级：用 ctx.reveal_next_draw_for_seat 拉真牌墙下次摸的牌。
# v1 简化：每次 owner DRAW 都触发（spec "花 1 巡" 消耗机制需 consumable
# 资源管理，待 Phase 2）。
extends SkillHook

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	ctx.reveal_next_draw_for_seat(ctx.beneficiary_seat, ctx.beneficiary_seat)
