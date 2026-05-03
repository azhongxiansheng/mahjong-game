# 海底狩人 — §8.10 #2 角色能力
# 牌墙最后 1 张被摸时强制改为 owner 自摸;1 次/节点
extends SkillHook

func on_event(_skill: SkillResource, _event: BattleEvent, ctx: SkillCtx) -> void:
	ctx.force_tsumo(ctx.beneficiary_seat)
	ctx.consume_self()
