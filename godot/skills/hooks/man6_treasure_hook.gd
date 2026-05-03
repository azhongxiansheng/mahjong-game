# 6 万·夺宝 — §8.8 Dora 系（M6 内容生产 + M7 ctx B2 升级）
#
# v2 (M7 B2)：mark_extra_dora_for_seat(owner, +1) 真翻一张额外 Dora 给
# owner（spec 原效果"翻 1 张额外 Dora 指示牌仅 owner 享受"）。
# 数值上仍是 +1 番（每张 dora = 1 番），但语义更准；未来 BalanceConstants
# 可独立调整 dora 上限。
extends SkillHook

const TREASURE_DORA_COUNT: int = 1

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	ctx.mark_extra_dora_for_seat(ctx.beneficiary_seat, TREASURE_DORA_COUNT)
