# 白透璃 — 角色被动「万透镜华」
# ability_id: char_washizu_passive_v1（GAME_BEGIN 身份锁；语义冻结）
# 效果：开局看到所有 3 个对手各 2 张手牌（共 6 张）。
extends SkillHook

const REVEAL_PER_OPPONENT: int = 2

func on_event(_skill: SkillResource, _event: BattleEvent, ctx: SkillCtx) -> void:
	for i in range(4):
		if i == ctx.beneficiary_seat:
			continue
		for _j in range(REVEAL_PER_OPPONENT):
			ctx.reveal_random_from_seat(i, ctx.beneficiary_seat, true)
