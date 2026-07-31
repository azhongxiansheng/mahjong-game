# 墙眼 — 遗物（被动）
# owner 每次摸牌后查看牌墙接下来的牌；1/2/3+ 件分别查看 1/2/3 张，至多 3 张，
# 只向 owner 显示（spec 2026-07-28 §4.1）。不改变牌序。
extends SkillHook

const MAX_DEPTH: int = 3

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	var depth: int = mini(MAX_DEPTH,
		ctx.count_active_ability_instances(&"relic_wall_eye_v1", ctx.beneficiary_seat))
	if depth <= 0:
		return
	ctx.reveal_wall_top_to(ctx.beneficiary_seat, depth)
