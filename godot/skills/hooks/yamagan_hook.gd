# 山眼 — §8.10 #3 史诗角色能力（M6 内容生产）
#
# v1: GAME_BEGIN 时 reveal 一张占位 tile（HAKU stub）
# spec 原效果："GAME_BEGIN 时看牌墙顶 10 张顺序"
# M10 升级：用 ctx.reveal_wall_top_to 拉真牌墙顶 10 张顺序。
extends SkillHook

const TOP_N: int = 10

func on_event(_skill: SkillResource, _event: BattleEvent, ctx: SkillCtx) -> void:
	# GAME_BEGIN 不限 actor_seat（不同实现可能传 -1 或 dealer）
	# 仅当 trigger 命中（owner_trigger 已过滤）就触发
	ctx.reveal_wall_top_to(ctx.beneficiary_seat, TOP_N)
