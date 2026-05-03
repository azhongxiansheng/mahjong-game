# 白·役满下限 — §8.9 役満 / 终局系（M6 内容生产 + M7 ctx B3-mini 升级）
#
# v2 (M7 B3-mini)：ctx.ensure_mangan_for_seat(owner) 真补差到 5 番下限
# （替代 v1 +5 番粗暴叠加）。
# spec 原效果："任意胡牌至少满贯（消耗品化）"。
# 满贯下限：spec §6.4 / ScoreFormula 5 番 = 满贯阈值；本 hook 标记后由
# BattleController._apply_mangan_floor 在 ScoreCalc 之前补差。
extends SkillHook

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	ctx.ensure_mangan_for_seat(ctx.beneficiary_seat)
	ctx.consume_self()  # 消耗品语义
