# 2 筒·诈和 — §8.5 透明牌 / 信息系（M6 内容生产）
#
# v1: owner 自胡 +1 番（模拟"伪装手牌迷惑对手 → 自家更易胡"）
# spec 原效果："副露时手牌 2 张伪装"
# v1 简化：emit "BLUFF_TILES" 占位无实效；改用 add_han 表达等价收益。
# 真"伪装手牌"需 mask_hand_tiles_for_opponents ctx 扩展（M7）。
extends SkillHook

const BLUFF_HAN_BONUS: int = 1

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	ctx.add_han(ctx.beneficiary_seat, BLUFF_HAN_BONUS)
