# 鹲巣 — 角色被动「鷲巣麻雀」
# 原著：鷲巣麻雀中 3/4 牌是透明的，对手可看到。鷲巣靠信息压制。
# 效果：开局时看到所有 3 个对手各 2 张手牌（共 6 张透明牌）。
extends SkillHook

const REVEAL_PER_OPPONENT: int = 2

func on_event(_skill: SkillResource, _event: BattleEvent, ctx: SkillCtx) -> void:
	for i in range(4):
		if i == ctx.beneficiary_seat:
			continue
		for _j in range(REVEAL_PER_OPPONENT):
			ctx.reveal_random_from_seat(i, ctx.beneficiary_seat)
