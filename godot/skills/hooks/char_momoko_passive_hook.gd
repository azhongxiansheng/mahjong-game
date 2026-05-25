# 東横桃子 — 角色被動「ステルス」
# 原著：存在感を消して、他家に認知されにくいステルス能力。
# 効果：RIICHI_DECLARED 時、primed フラグを立てる。
#       次の WIN_DECLARED_PRE 自胡時 +1 番（ステルス立直の優位性）。
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
