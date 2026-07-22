# 安澄青 — 角色被动「无风净界」
# ability_id: char_awai_passive_v1（GAME_BEGIN 身份锁；语义冻结）
# 效果：开局清除自身振听 + reveal 下次摸牌。
extends SkillHook

func on_event(_skill: SkillResource, _event: BattleEvent, ctx: SkillCtx) -> void:
	ctx.clear_furiten(ctx.beneficiary_seat)
	ctx.reveal_next_draw_for_seat(ctx.beneficiary_seat, ctx.beneficiary_seat)
