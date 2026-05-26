# 原村和 — 角色被動「デジタル」
# 原著：デジタル打法の申し子。確率論と数理で戦う。
# 効果 1：WIN_DECLARED_PRE 自胡時 +1 番（安定した打牌精度）。
# 効果 2：HAND_FORMED（対手聴牌）時、対手の手牌 1 枚を owner に reveal。
extends SkillHook

const DIGITAL_BONUS: int = 1

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.type == &"WIN_DECLARED_PRE":
		if event.actor_seat == ctx.beneficiary_seat:
			ctx.add_han(ctx.beneficiary_seat, DIGITAL_BONUS)
	elif event.type == &"HAND_FORMED":
		if event.actor_seat != ctx.beneficiary_seat:
			ctx.reveal_random_from_seat(event.actor_seat, ctx.beneficiary_seat)
