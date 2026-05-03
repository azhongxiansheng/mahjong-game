# 嶺上の鬼 — §8.10 #1 神级角色能力（M6 内容生产）
#
# v1: owner 自胡 +2 番（模拟"杠后岭上摸 5 选 1"得到好牌的等价收益）
# spec 原效果："owner 杠后从 5 张候选中选 1 张作为岭上摸牌"
# v1 简化：用 add_han(+2) 表达"5 选 1 比单摸 ≈ 平均 +2 番"；
# 真"5 选 1 摸牌"需 draw_choose_n_of_m ctx 扩展（M7）。
extends SkillHook

# ONI_HAN_BONUS 已迁移到 BalanceConstants (&"mineu_oni_han_bonus")。

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	ctx.add_han(ctx.beneficiary_seat, int(BalanceConstants.lookup(&"mineu_oni_han_bonus")))
