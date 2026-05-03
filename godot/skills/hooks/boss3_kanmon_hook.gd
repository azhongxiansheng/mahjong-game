# 章 3 Boss 签名能力 — 关门（终局主题）
#
# v1: Boss 在 HAITEI（海底）/ HOUTEI（河底）时自胡 +3 番（模拟"升级为役满"）
# spec 原效果："剩余巡数 < 4 时 Boss 任意胡牌升级为役满"
# v1 简化：取最相近的 trigger（HAITEI/HOUTEI）+ +3 番；真"升级役满"
# 需要 force_yakuman API（M7 加）。
extends SkillHook

# KANMON_HAN_BONUS 已迁移到 BalanceConstants (&"boss3_kanmon_han_bonus")。

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	ctx.add_han(ctx.beneficiary_seat, int(BalanceConstants.lookup(&"boss3_kanmon_han_bonus")))
