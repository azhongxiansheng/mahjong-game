# 9万·铁壁 — §8.3 阻止对方胡牌系
#
# v1: owner 持此牌被荣胡时，对胡牌方役 -1 番。
# spec 原效果："本局对其荣胡的役 -1 番；若降至 0 番（无役）→ 取消胡牌"。
# v1 简化：只 add_han(-1)，"降至 0 番 → cancel ron" 由 ScoreFormula 钳制
# （ron-without-yaku 本就不合法，规则引擎会自然拒绝）。
extends SkillHook

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	# owner_trigger 模式：beneficiary_seat 是 owner（牌的拥有者）
	# RON_DECLARED.actor_seat 是胡牌方；event.extra.discarder_seat 是出铳方
	# owner 必须是出铳方才触发（owner 自己被荣胡 = owner 出铳）
	var discarder: int = int(event.extra.get("discarder_seat", -1))
	if discarder != ctx.beneficiary_seat:
		return
	ctx.add_han(event.actor_seat, -1)
