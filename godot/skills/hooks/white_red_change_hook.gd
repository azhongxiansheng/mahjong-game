# 白·赤变 — §8.8 Dora 系（M6 内容生产）
#
# v1: owner 自胡 +1 番（模拟"5 万 / 5 筒 / 5 索任一改赤 Dora"等价 +1 番）
# spec 原效果："5m/5p/5s 之一改为赤 Dora（永久效果，每 Run 1 张）"
# v1 简化：用 add_han(+1) 表达红 5 收益；真"改 5 字段为 red"需
# mark_red_dora ctx 扩展（M7）。
extends SkillHook

const RED_DORA_HAN_BONUS: int = 1

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	ctx.add_han(ctx.beneficiary_seat, RED_DORA_HAN_BONUS)
