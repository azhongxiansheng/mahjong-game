# 龙印 — 遗物（被动）
# WIN_DECLARED_PRE：owner 胡牌含白/发/中刻子（杠子）役时 +1 番；
# 同一手牌不因多种三元牌重复触发单件（spec 2026-07-28 §4.1）。
extends SkillHook

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	var yaku_ids: Array = event.extra.get("yaku_ids", [])
	for yid in [YakuId.YAKUHAI_HAKU, YakuId.YAKUHAI_HATSU, YakuId.YAKUHAI_CHUN]:
		if yaku_ids.has(yid):
			ctx.add_han(ctx.beneficiary_seat, 1)
			return
