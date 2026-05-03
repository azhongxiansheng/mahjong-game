# 北·一扫 — §8.9 役満 / 终局系（M6 内容生产）
#
# v1: owner 自胡 +3 番（模拟"全场 4 家承担收益 ≈ +3 番加成"）
# spec 原效果："役满时全场 4 家承担"
# v1 简化：用 add_han(+3) 表达"4 家分摊 ≈ 3 番加成"；真"ALL_4_PAY"标记
# 需 PayoutCalculator 端识别 + ctx.mark_all_pay 扩展（M7）。
extends SkillHook

# SWEEP_HAN_BONUS 已迁移到 BalanceConstants (&"north_sweep_han_bonus")。

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	ctx.add_han(ctx.beneficiary_seat, int(BalanceConstants.lookup(&"north_sweep_han_bonus")))
