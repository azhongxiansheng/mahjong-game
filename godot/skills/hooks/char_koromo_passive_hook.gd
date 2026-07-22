# 渊汐 — 角色被动「底牌潮掌」
# ability_id: char_koromo_passive_v1（语义冻结）
# 效果 1：HAITEI / HOUTEI 自胡时 +3 番。
# 效果 2：TILE_DRAWN 时，牌墙顶 3 枚 reveal 给 owner。
extends SkillHook

const HAITEI_BONUS: int = 3
const REVEAL_COUNT: int = 3

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.type == &"HAITEI" or event.type == &"HOUTEI":
		if event.actor_seat == ctx.beneficiary_seat:
			ctx.add_han(ctx.beneficiary_seat, HAITEI_BONUS)
	elif event.type == &"TILE_DRAWN":
		if event.actor_seat == ctx.beneficiary_seat:
			ctx.reveal_wall_top_to(ctx.beneficiary_seat, REVEAL_COUNT)
