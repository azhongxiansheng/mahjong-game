# 影立静 — 角色被动「消影一发」
# ability_id: char_momoko_passive_v1（语义冻结）
# 效果：RIICHI_DECLARED 时 primed；下次 WIN_DECLARED_PRE 自胡 +1 番后清除。
extends SkillHook

const STEALTH_BONUS: int = 1

func on_event(skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.type == &"RIICHI_DECLARED":
		if event.actor_seat == ctx.beneficiary_seat:
			skill.params["primed"] = true
	elif event.type == &"WIN_DECLARED_PRE":
		if bool(skill.params.get("primed", false)):
			if event.actor_seat == ctx.beneficiary_seat:
				ctx.add_han(ctx.beneficiary_seat, STEALTH_BONUS)
			skill.params["primed"] = false
	elif event.type == &"EXHAUSTIVE_DRAW" or event.type == &"ABORTIVE_DRAW":
		if bool(skill.params.get("primed", false)):
			skill.params["primed"] = false
