# 可抽能力「潜影立直」— id: momoko_stealth_ability_v1（非角色被动）
extends SkillHook

const STEALTH_BONUS: int = 1

func on_event(skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.type == &"RIICHI_DECLARED":
		if event.actor_seat == ctx.beneficiary_seat:
			skill.params["primed"] = true
	elif event.type == &"WIN_DECLARED_PRE":
		if event.actor_seat == ctx.beneficiary_seat:
			if bool(skill.params.get("primed", false)):
				ctx.add_han(ctx.beneficiary_seat, STEALTH_BONUS)
				skill.params["primed"] = false
