# 統率 — §8.10 #8 史诗角色能力（M6 内容生产）
#
# v1: owner 自胡 +1 番（模拟"統率 buff 让其它 ability 多触发 1 次的等价收益"）
# spec 原效果："其它 ability owner_triggers 触发额度 +1"
# v1 简化：用 add_han(+1) 表达"buff 总收益 ≈ +1 番"；真"提高其它
# ability 触发额度"需 boost_other_abilities ctx 扩展（M7）。
extends SkillHook

const TOUSOTSU_HAN_BONUS: int = 1

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	ctx.add_han(ctx.beneficiary_seat, TOUSOTSU_HAN_BONUS)
