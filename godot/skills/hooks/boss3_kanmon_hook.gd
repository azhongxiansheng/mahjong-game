# 章 3 Boss 签名能力 — 关门（终局主题）
#
# v2 (M9 B3 ctx)：Boss 在 HAITEI（海底）/ HOUTEI（河底）时自胡 → 真升级为役满
# spec 原效果："剩余巡数 < 4 时 Boss 任意胡牌升级为役满"
# v1 → v2 升级路径：从 add_han(+3) 桩 → ctx.force_yakuman_for_seat（PR M9 加）
# trigger 仍是 HAITEI/HOUTEI（非完整"剩余巡数 < 4"，需 turn_engine 暴露巡数 API
# 后再扩；目前用 endgame 事件触发是合理近似）
extends SkillHook

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	ctx.force_yakuman_for_seat(ctx.beneficiary_seat)
