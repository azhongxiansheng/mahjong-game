# 偷天换日 — §8.10 #12 神级角色能力（M7 收尾）
#
# spec 原效果："每局 1 次手牌 ↔ 弃牌河交换"
# v1 简化：用 add_han(+3) 表达"突破时机限制 ≈ +3 番"等价收益；
# 真"swap_hand_river"需 ctx 扩展（hand 大幅变换 / 弃牌河重写），
# 不在 M7 v1 范围。
#
# 触发：WIN_DECLARED_PRE + 自胡（owner trigger）
# consume_self：spec "每局 1 次"。
extends SkillHook

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	var bonus: int = int(BalanceConstants.lookup(&"tougenkyo_han_bonus"))
	ctx.add_han(ctx.beneficiary_seat, bonus)
	ctx.consume_self()
