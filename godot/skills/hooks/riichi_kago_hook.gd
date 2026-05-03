# 立直加護 — §8.10 #9 史诗角色能力（M6 内容生产）
#
# v1: owner 自胡 +1 番（模拟"一发窗口延长至 2 巡 ≈ +1 一发期望"）
# spec 原效果："立直一发窗口延长至 2 巡"
# v1 简化：用 add_han(+1) 表达"一发期望加倍 ≈ +1 番"；真"延长一发窗
# 口"需 extend_ippatsu_window ctx 扩展（M7）。
extends SkillHook

# KAGO_HAN_BONUS 已迁移到 BalanceConstants (&"riichi_kago_han_bonus")。

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	ctx.add_han(ctx.beneficiary_seat, int(BalanceConstants.lookup(&"riichi_kago_han_bonus")))
