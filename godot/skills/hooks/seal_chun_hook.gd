# 中·封印 — §8.3 阻胡系
# owner 弃中被对手荣胡时,可消耗此牌取消荣胡
# event.extra: {"discarder_seat": int}(由场景或回合引擎填)
extends SkillHook

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	var discarder: int = int(event.extra.get("discarder_seat", -1))
	if discarder != ctx.beneficiary_seat:
		return  # owner 不是出铳方,不触发
	ctx.cancel_ron(event.actor_seat)
	ctx.consume_self()
