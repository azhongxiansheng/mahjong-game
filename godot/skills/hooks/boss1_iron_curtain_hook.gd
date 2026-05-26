# 章 1 Boss 签名能力 — 铁幕（防御主题）
#
# Boss owner 受到 RON 时强制取消第 1 次（用 ctx.cancel_ron）。
# 触发：RON_DECLARED + extra.discarder_seat == owner_seat（boss 是放铳者）
# consume_self 保证每局只触发 1 次。
extends SkillHook

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	var discarder: int = int(event.extra.get("discarder_seat", -1))
	if discarder != ctx.beneficiary_seat:
		return
	ctx.cancel_ron(event.actor_seat)
	ctx.consume_self()
