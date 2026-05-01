# 9万·铁壁 — §8.3 阻止对方胡牌系（M6 内容生产）
#
# v1: owner 被荣胡时（actor 荣胡 owner 弃出的牌）役 -1 番
# spec 原效果："对其荣胡的役-1 番；若降至 0 番（无役）→ 取消胡牌"
# v1 简化：仅 -1 番；无役钳制由 ScoreFormula 处理。
#
# 触发：RON_DECLARED + owner_seat（owner = 弃牌者）
# extra.discarder_seat == owner_seat 时才生效（避免对家荣胡误触发）。
extends SkillHook

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	# RON_DECLARED 事件：actor = 胡牌者，extra.discarder_seat = 放铳者
	var discarder: int = int(event.extra.get("discarder_seat", -1))
	if discarder != ctx.beneficiary_seat:
		return  # 不是 owner 弃出导致的荣胡
	ctx.add_han(event.actor_seat, -1)
