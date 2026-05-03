# 白·赤变 — §8.8 Dora 系（M6 内容生产 + M7 ctx B2 升级）
#
# v2 (M7 B2)：mark_red_dora_for_seat(owner, +1) 真给 owner 额外 1 张
# 赤 Dora（spec 原效果："5m/5p/5s 之一改为赤 Dora，永久效果，每 Run 1 张"）。
# v2 简化：仍用计数器表达，"改 5m/5p/5s 牌字段为 red"需更深的 Tile.is_red_dora
# 路径升级（独立 PR）；当前等价收益 +1 番已在结算正确反映。
extends SkillHook

const RED_DORA_COUNT: int = 1

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	ctx.mark_red_dora_for_seat(ctx.beneficiary_seat, RED_DORA_COUNT)
