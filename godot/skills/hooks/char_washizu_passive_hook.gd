# 鹲巣 — 角色被动
# 每局开始看牌墙顶 3 张（信息型角色核心增益）
extends SkillHook

const PEEK_COUNT: int = 3

func on_event(_skill: SkillResource, _event: BattleEvent, ctx: SkillCtx) -> void:
	ctx.reveal_wall_top_to(ctx.beneficiary_seat, PEEK_COUNT)
