# 大星淡 — 角色被动「絶対安全圏」
# 原著：前 4 巡其他玩家无法和了。
# 效果：开局时清除自身振听 + reveal 下次摸牌（信息优势模拟安全圈）。
extends SkillHook

func on_event(_skill: SkillResource, _event: BattleEvent, ctx: SkillCtx) -> void:
	ctx.clear_furiten(ctx.beneficiary_seat)
	ctx.reveal_next_draw_for_seat(ctx.beneficiary_seat, ctx.beneficiary_seat)
