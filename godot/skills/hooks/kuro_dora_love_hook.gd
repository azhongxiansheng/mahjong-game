# 松実玄 — ドラの愛 能力版（拡張）
# WIN_DECLARED_PRE 自胡時 +2 extra Dora。
# DORA_REVEALED 發生時 +1 追加 Dora。
# 触発：WIN_DECLARED_PRE / DORA_REVEALED
extends SkillHook

const WIN_EXTRA_DORA: int = 2
const REVEAL_EXTRA_DORA: int = 1

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.type == &"WIN_DECLARED_PRE":
		if event.actor_seat == ctx.beneficiary_seat:
			ctx.mark_extra_dora_for_seat(ctx.beneficiary_seat, WIN_EXTRA_DORA)
	elif event.type == &"DORA_REVEALED":
		ctx.mark_extra_dora_for_seat(ctx.beneficiary_seat, REVEAL_EXTRA_DORA)
