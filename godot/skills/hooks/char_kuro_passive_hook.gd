# 松実玄 — 角色被動「ドラの愛」
# 原著：ドラが自然と集まってくる体質。
# 効果：WIN_DECLARED_PRE 自胡時、+2 extra Dora。
extends SkillHook

const EXTRA_DORA: int = 2

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	ctx.mark_extra_dora_for_seat(ctx.beneficiary_seat, EXTRA_DORA)
