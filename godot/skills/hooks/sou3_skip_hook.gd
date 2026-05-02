# 3 索·跳跃 — §8.2 加速胡牌系（M6 内容生产）
#
# v1: owner 自胡 +1 番（模拟"跳过下家收益"）
# spec 原效果："owner 听牌后弃此牌跳过下家 1 巡"
# v1 简化：emit "TURN_SKIP" 占位无实效；改用 add_han 表达"加速收益"
# 等价。真"跳过下家"需 turn_engine.skip_seat 扩展（M7）。
extends SkillHook

const SKIP_HAN_BONUS: int = 1

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	ctx.add_han(ctx.beneficiary_seat, SKIP_HAN_BONUS)
