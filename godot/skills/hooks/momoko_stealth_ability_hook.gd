# 東横桃子 — ステルス能力版
# RIICHI_DECLARED 時にフラグを立て、次の WIN_DECLARED_PRE 自胡時 +1 番。
# skill.params["primed"] でステータス追跡。
# 触発：RIICHI_DECLARED / WIN_DECLARED_PRE
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
