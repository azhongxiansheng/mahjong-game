# 听牌看穿 — §8.10 #5 史诗角色能力（M6 内容生产）
#
# v1: HAND_FORMED 时 reveal 一张占位 tile（模拟"看对手听牌张"）
# spec 原效果："对手 HAND_FORMED 时看其听牌张"
# M10 升级：用 ctx.reveal_random_from_seat 从对手真手牌拉 1 张（v1 简化为
# 随机 — 真"读对手听牌候选张"需调 WaitCalculator.wait_tiles 后过滤，待
# Phase 2）。
extends SkillHook

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	# HAND_FORMED 由对手触发；不限 actor 是否 == owner
	# owner_trigger 模式下 ctx.beneficiary_seat = ability owner
	if event.actor_seat == ctx.beneficiary_seat:
		return  # 自家听牌不需要看穿
	ctx.reveal_random_from_seat(event.actor_seat, ctx.beneficiary_seat)
