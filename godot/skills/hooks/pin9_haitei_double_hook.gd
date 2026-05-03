# 9 筒·龙断 — §8.9 役満 / 终局系（M6 内容生产 + M7 ctx B3-mini 升级）
#
# v2 (M7 B3-mini): HAITEI/HOUTEI + holder 自胡 → multiply_han_for_seat(×2)
# spec 原效果："owner 进入海底/河底时役 ×2"
# 触发：HAITEI 或 HOUTEI 事件 + holder（持牌者 = 自胡）
extends SkillHook

const HAITEI_MULTIPLIER: float = 2.0

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	# event.type ∈ {HAITEI, HOUTEI}（由 SkillResource.holder_triggers 过滤）
	# holder 与 actor 一致 = 自胡
	if event.actor_seat != ctx.beneficiary_seat:
		return
	ctx.multiply_han_for_seat(ctx.beneficiary_seat, HAITEI_MULTIPLIER)
