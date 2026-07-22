# 裘绝 — 角色被动「绝崖翻盘」
# ability_id: char_kaiji_passive_v1（语义冻结）
# 效果：分数 < 15000 时胡牌 +2 番。
extends SkillHook

const THRESHOLD: int = 15000
const BONUS_HAN: int = 2

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	if ctx.get_score(ctx.beneficiary_seat) < THRESHOLD:
		ctx.add_han(ctx.beneficiary_seat, BONUS_HAN)
