# 南·先制立直 — §8.6 立直系（M6 内容生产）
#
# v1: owner 自胡 +2 番（模拟"先制立直"得到的双倍立直 + 一发期望收益）
# spec 原效果："第 1 巡未鸣牌即可宣告立直（普通立直需要听牌）"
# v1 简化：用 add_han(+2) 表达"先制立直额外收益 ≈ 双立直 + 一发"；
# 真"第 1 巡立直"需 force_double_riichi_at_first_turn ctx 扩展（M7）。
extends SkillHook

# PREMATURE_RIICHI_HAN_BONUS 已迁移到 BalanceConstants (&"premature_riichi_han_bonus")。

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	ctx.add_han(ctx.beneficiary_seat, int(BalanceConstants.lookup(&"premature_riichi_han_bonus")))
