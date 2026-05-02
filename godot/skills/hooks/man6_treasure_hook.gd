# 6 万·夺宝 — §8.8 Dora 系（M6 内容生产）
#
# v1: owner 自胡 +1 番（模拟"摸到 6 万触发了额外 Dora 命中"）
# spec 原效果："摸到此牌时翻 1 张额外 Dora 指示牌（仅 owner 享受）"
# v1 简化：用 add_han 表达"额外 1 dora 命中"等价收益；真"翻指示牌"需
# mark_extra_dora_for_seat ctx 扩展（M7）。
extends SkillHook

const TREASURE_HAN_BONUS: int = 1

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	ctx.add_han(ctx.beneficiary_seat, TREASURE_HAN_BONUS)
