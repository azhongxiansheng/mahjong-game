# 章 2 Boss 签名能力 — 福星（Tempo + Dora 主题）
#
# v1: Boss 自胡时 +2 番（模拟"额外 Dora"加分；spec 原效果是真翻额外
# Dora，需要扩 BattleState API）
# spec 原效果："Boss 起手即视为听牌；每局新增 1 张额外 Dora"
# v1 简化：用 add_han 表达"Dora 加分"等价效果；M7 加 force_tenpai_at_start
# + reveal_extra_dora 真 API 后升级。
extends SkillHook

const FORTUNE_HAN_BONUS: int = 2

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	# owner_trigger WIN_DECLARED：仅 Boss 自胡时给加成
	if event.actor_seat != ctx.beneficiary_seat:
		return
	ctx.add_han(ctx.beneficiary_seat, FORTUNE_HAN_BONUS)
