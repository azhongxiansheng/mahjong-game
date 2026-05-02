# 山眼 — §8.10 #3 史诗角色能力（M6 内容生产）
#
# v1: GAME_BEGIN 时 reveal 一张占位 tile（模拟"看牌墙顶 10 张顺序"）
# spec 原效果："GAME_BEGIN 时看牌墙顶 10 张顺序"
# v1 简化：1 张 reveal 占位代表预览能力；真"读 wall.draw_pile[0..9]"需
# reveal_wall_segment_to ctx 扩展（M7）。
extends SkillHook

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	# GAME_BEGIN 不限 actor_seat（不同实现可能传 -1 或 dealer）
	# 仅当 trigger 命中（owner_trigger 已过滤）就触发
	var stub_tile := TileInstance.make(Tile.new(TileId.HAKU), ctx.beneficiary_seat)
	stub_tile.holder_seat = -1
	ctx.reveal_tile_to(stub_tile, ctx.beneficiary_seat)
