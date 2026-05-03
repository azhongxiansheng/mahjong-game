# 2 万·诱铳 — §8.7 振听操控系（M6 内容生产）
#
# v1: owner 自胡 +1 番（模拟"伪装听牌诱骗对手，自家反向胡分加成"）
# spec 原效果："弃此牌时伪装听牌型（对手以为 owner 听牌的另一形）"
# v1 简化：emit "FAKE_TENPAI_HINT" 占位无实效；改用 add_han 表达
# 等价收益。真"伪装听牌型"需 set_fake_tenpai_for_seat ctx 扩展（M7）。
extends SkillHook

# LURE_HAN_BONUS 已迁移到 BalanceConstants (&"man2_lure_han_bonus")。

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	ctx.add_han(ctx.beneficiary_seat, int(BalanceConstants.lookup(&"man2_lure_han_bonus")))
