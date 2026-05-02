# 东·迷踪 — §8.7 振听操控系（M6 内容生产）
#
# v1: owner 弃东被对手荣胡时取消（同形 seal_chun，但 tile 限定为东）
# spec 原效果："弃此牌后下家暂时振听 1 巡"
# v1 简化：用现 ctx API 表达"对手乱弃 → 取消荣胡"等价。
# 真"对家振听 1 巡"需 set_furiten(seat, turns) ctx 扩展（M7）。
extends SkillHook

func on_event(skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	var discarder: int = int(event.extra.get("discarder_seat", -1))
	if discarder != ctx.beneficiary_seat:
		return
	ctx.cancel_ron(event.actor_seat)
	skill.consumed = true
