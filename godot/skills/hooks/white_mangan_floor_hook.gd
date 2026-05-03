# 白·役满下限 — §8.9 役満 / 终局系（M6 内容生产）
#
# v1: owner 自胡 +5 番（模拟"任意胡牌至少满贯 ≈ 满贯下限对小役 +5"）
# spec 原效果："任意胡牌至少满贯（消耗品化）"
# v1 简化：用 add_han(+5) 把任何胡牌推到满贯线（满贯 = 5 番阈值）；
# ScoreFormula 端钳制 +5 ≥ 5 即满贯。真"满贯下限保底"需 ensure_mangan
# ctx 扩展 + 消耗品标记（M7）。
extends SkillHook

const MANGAN_FLOOR_HAN_BONUS: int = 5

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	ctx.add_han(ctx.beneficiary_seat, MANGAN_FLOOR_HAN_BONUS)
	ctx.consume_self()  # 消耗品语义
