# 白·占卜 — §8.5 透明牌 / 信息系（M6 内容生产）
#
# v1: owner 摸牌时 reveal 一张 dora 占位 tile 到 owner（信息收益）
# spec 原效果："每巡看 1 张未翻 Dora 指示牌"
# v1 简化：用 reveal_tile_to 把"未翻 Dora 指示牌"占位（HAKU stub）暴露
# 给 owner；真"读 wall.dora_indicators 切片"需 reveal_wall_segment_to
# ctx 扩展（M7）。
extends SkillHook

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	# 占位：用 HAKU 代表"未翻 Dora 指示"
	var stub_tile := TileInstance.make(Tile.new(TileId.HAKU), ctx.beneficiary_seat)
	stub_tile.holder_seat = -1  # 牌墙位置
	ctx.reveal_tile_to(stub_tile, ctx.beneficiary_seat)
