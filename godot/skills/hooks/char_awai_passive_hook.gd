# 安澄青 — 角色被动「无风净界」
# ability_id: char_awai_passive_v1（奖励窗武装时等价触发一次 GAME_BEGIN）
# 效果：清除自身权威振听 + 仅向本人 reveal 当前墙顶的下一摸。
extends SkillHook

func on_event(_skill: SkillResource, _event: BattleEvent, ctx: SkillCtx) -> void:
	ctx.clear_furiten(ctx.beneficiary_seat)
	ctx.reveal_next_draw_for_seat(ctx.beneficiary_seat, ctx.beneficiary_seat)
