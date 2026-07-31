# 天命打破 — 遗物（被动；spec 2026-07-28 §5.3）
# 连续两局未胡后充能（由 ItemAuthority.prepare_new_hand 注入 pity_charged）；
# 下一次合法胡牌满贯保底；N 件同时充能追加 N-1 番——聚合番由 session 层
# 预分配到字典序最小实例（pity_extra_han），避免多实例 dispatch 重复叠加。
# 触发后计数重置由 pity_on_hand_completed 在该局完成时执行（胡牌即重置）。
extends SkillHook

func on_event(skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	if not bool(skill.params.get("pity_charged", false)):
		return
	ctx.ensure_mangan_for_seat(ctx.beneficiary_seat)
	var extra: int = int(skill.params.get("pity_extra_han", 0))
	if extra > 0:
		ctx.add_han(ctx.beneficiary_seat, extra)
