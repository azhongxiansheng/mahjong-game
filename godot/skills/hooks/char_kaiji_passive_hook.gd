# 开司 — 角色被动
# 被荣胡时 50% 概率取消（防御型角色核心增益）
# 用 event chain depth + turn_count 做确定性随机
extends SkillHook

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	var discarder: int = int(event.extra.get("discarder_seat", -1))
	if discarder != ctx.beneficiary_seat:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = ctx.get_event().chain_id * 37 + discarder * 13
	if rng.randf() < 0.5:
		ctx.cancel_ron(event.actor_seat)
