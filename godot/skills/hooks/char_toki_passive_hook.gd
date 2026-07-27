# 先示 — 角色被动「四席窥运」
# ability_id: char_toki_passive_v1（GAME_BEGIN 身份锁；语义冻结）
# 效果：GAME_BEGIN 时，建立全 4 席的权威条件预测给 owner。
# 不得改绑 toki_foresight_v1 等近义卡池能力。
extends SkillHook

func on_event(_skill: SkillResource, _event: BattleEvent, ctx: SkillCtx) -> void:
	ctx.activate_seat_draw_forecast(ctx.beneficiary_seat)
