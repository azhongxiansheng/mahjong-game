# 章 2 Boss 签名能力 — 福星（Tempo + Dora 主题）
#
# v2 (M7 ctx B2)：Boss 自胡时 mark_extra_dora_for_seat(boss, +2)，真翻 2 张
# 额外 Dora 给 Boss 享受（更贴近 spec "每局新增 1 张额外 Dora" + Tempo
# 题目）。注：spec 是 1 张但 v1 给 2 张是为了平衡 Boss 强度（待
# BalanceConstants 调整）。
# 'Boss 起手即视为听牌'仍待 force_tenpai_at_start API（独立 PR）。
extends SkillHook

const FORTUNE_DORA_COUNT: int = 2

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	# owner_trigger WIN_DECLARED_PRE：仅 Boss 自胡时给加成（在 ScoreCalc 之前）
	if event.actor_seat != ctx.beneficiary_seat:
		return
	ctx.mark_extra_dora_for_seat(ctx.beneficiary_seat, FORTUNE_DORA_COUNT)
