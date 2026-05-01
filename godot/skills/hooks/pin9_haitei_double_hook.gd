# 9 筒·龙断 — §8.9 役満 / 终局系（M6 内容生产）
#
# v1: HAITEI（海底）/ HOUTEI（河底）触发 + holder 自胡 → +1 番
# spec 原效果："owner 进入海底/河底时役 ×2"
# v1 简化：×2 → +1 番（按 plan-6 v1 数值简化策略；M7 加 multiply_han API 后升级）
# 触发：HAITEI 或 HOUTEI 事件 + holder（持牌者 = 自胡）
extends SkillHook

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	# event.type ∈ {HAITEI, HOUTEI}（由 SkillResource.holder_triggers 过滤）
	# holder 与 actor 一致 = 自胡
	if event.actor_seat != ctx.beneficiary_seat:
		return
	ctx.add_han(ctx.beneficiary_seat, 1)
