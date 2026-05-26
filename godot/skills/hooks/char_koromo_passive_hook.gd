# 天江衣 — 角色被动「海底支配」
# 原著：衣は海底を支配する。海底摸月 / 河底撈魚を完全コントロール。
# 効果 1：HAITEI / HOUTEI 自胡時 +3 番。
# 効果 2：TILE_DRAWN 時、牌墙残り 3 枚を owner に reveal（海底タイミング読み）。
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
