# 1万·透视 — §8.5 透明牌系
# owner 摸到此牌时,强制将下家手牌 1 张设为对 owner 可见
extends SkillHook

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	# milestone 1 stub:合成一张代表"下家手牌 1 张"的占位 TileInstance
	var next_seat := (ctx.beneficiary_seat + 1) % 4
	var stub_tile := TileInstance.make(Tile.new(TileId.W2), next_seat)
	stub_tile.holder_seat = next_seat
	ctx.reveal_tile_to(stub_tile, ctx.beneficiary_seat)
