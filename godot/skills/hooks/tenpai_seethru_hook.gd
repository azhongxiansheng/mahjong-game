# 听牌看穿 — §8.10 #5 史诗角色能力（M6 内容生产）
#
# v1: HAND_FORMED 时 reveal 一张占位 tile（模拟"看对手听牌张"）
# spec 原效果："对手 HAND_FORMED 时看其听牌张"
# v1 简化：reveal 占位 tile 给 owner；真"读对手 hand 听牌候选"需
# reveal_tenpai_tiles ctx 扩展（M7）。
extends SkillHook

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	# HAND_FORMED 由对手触发；不限 actor 是否 == owner
	# owner_trigger 模式下 ctx.beneficiary_seat = ability owner
	if event.actor_seat == ctx.beneficiary_seat:
		return  # 自家听牌不需要看穿
	var stub_tile := TileInstance.make(Tile.new(TileId.HAKU), event.actor_seat)
	stub_tile.holder_seat = event.actor_seat
	ctx.reveal_tile_to(stub_tile, ctx.beneficiary_seat)
