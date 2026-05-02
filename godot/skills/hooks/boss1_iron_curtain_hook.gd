# 章 1 Boss 签名能力 — 铁幕（防御主题）
#
# v1: Boss owner 受到 RON 时强制取消第 1 次（用 ctx.cancel_ron）
# spec 原效果："Boss 受到 RON 时强制取消第 1 次"
# 触发：RON_DECLARED + extra.discarder_seat == owner_seat（boss 是放铳者）
#
# v1 简化：不做"第 1 次"消耗追踪（需扩 SkillResource.consumed 或 Run state
# counter）；每次都触发。M7 加 consume_self API 后改为 1 次/局。
extends SkillHook

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	var discarder: int = int(event.extra.get("discarder_seat", -1))
	if discarder != ctx.beneficiary_seat:
		return  # 非 Boss 放铳，不动
	# Boss 放铳被荣胡 → 强制取消（cancel_ron 标 actor 不能成立）
	ctx.cancel_ron(event.actor_seat)
