# 9 筒·速胡 — §8.2 加速胡牌系（M6 内容生产）
#
# v1: owner 摸到此牌 → force_tsumo（owner 进入海底自摸幸运态）
# spec 原效果："弃此牌后下次摸'摸 2 选 1'（双摸）"
# v1 简化：用现有 force_tsumo（标 haitei_forced_seat = owner），
# 玩家在 ScoreFormula 看到 owner 自摸 → 触发海底役加成。
# 真"摸 2 选 1"需 ctx.draw_two_choose_one 扩展（M7）。
extends SkillHook

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	ctx.force_tsumo(ctx.beneficiary_seat)
