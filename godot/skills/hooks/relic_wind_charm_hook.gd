# 风铃 — 遗物（被动）
# WIN_DECLARED_PRE：owner 胡牌含自风或场风役时 +1 番；连风牌单件仍只 +1
# （spec 2026-07-28 §4.1）。
extends SkillHook

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	var yaku_ids: Array = event.extra.get("yaku_ids", [])
	for yid in [YakuId.YAKUHAI_BAKAZE, YakuId.YAKUHAI_JIKAZE]:
		if yaku_ids.has(yid):
			ctx.add_han(ctx.beneficiary_seat, 1)
			return
