# 一巡先見 — §8.10 #4 神级角色能力（M6 内容生产）
#
# v1: owner 摸牌时 reveal 一张占位 tile（模拟"看到下次摸牌"）
# spec 原效果："每巡可花 1 巡看下次摸牌"
# v1 简化：每次 owner DRAW 时 reveal 一张占位 tile（HAKU stub）给 owner，
# 表达"信息预览"语义。真"花 1 巡看下次摸"需 reveal_next_draw_for_seat
# ctx 扩展（M7）。
extends SkillHook

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	var stub_tile := TileInstance.make(Tile.new(TileId.HAKU), ctx.beneficiary_seat)
	stub_tile.holder_seat = -1
	ctx.reveal_tile_to(stub_tile, ctx.beneficiary_seat)
