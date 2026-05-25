# 園城寺怜 — 角色被動「一巡先見」
# 原著：一巡先を見通す未来視の能力。
# 効果：GAME_BEGIN 時、全 4 席の次の摸牌を owner に reveal。
extends SkillHook

func on_event(_skill: SkillResource, _event: BattleEvent, ctx: SkillCtx) -> void:
	for seat in range(4):
		ctx.reveal_next_draw_for_seat(seat, ctx.beneficiary_seat)
