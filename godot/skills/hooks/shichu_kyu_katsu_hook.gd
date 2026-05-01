# 死中求活 — §8.10 #11 角色能力（M6 内容生产）
#
# 灵感原型：アカギ「無謀の極」。实装命名中性化（avoid IP risk per spec §15）。
#
# v1: owner 点棒 < 5000 时，自胡所有役 +2 番（含 Dora 加分）
# spec 原效果（同）。
# 是 ability（is_ability=true，绑 Seat 而非 Tile）。
# 触发：WIN_DECLARED + actor=beneficiary（自胡）+ get_score(beneficiary) < 5000
extends SkillHook

const SHICHU_THRESHOLD: int = 5000
const SHICHU_HAN_BONUS: int = 2

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	# 仅 owner 自胡时触发（角色能力 owner_seat = beneficiary_seat）
	if event.actor_seat != ctx.beneficiary_seat:
		return
	# 点棒阈值检查：< 5000 才激活
	if ctx.get_score(ctx.beneficiary_seat) >= SHICHU_THRESHOLD:
		return
	ctx.add_han(ctx.beneficiary_seat, SHICHU_HAN_BONUS)
