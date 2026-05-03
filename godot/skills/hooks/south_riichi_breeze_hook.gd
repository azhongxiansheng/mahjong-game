# 南风·风行 — §8.2 加速胡牌系（M6 内容生产）
#
# v1: owner 立直 +1 番于下次自胡
# spec 原效果："立直时多看 1 张牌墙顶"
# v1 简化：用 add_han 表达"额外信息收益 ≈ +1 番"；真"reveal next wall"
# 需 reveal_next_wall_tile_to ctx 扩展（M7）。
# trigger: WIN_DECLARED + owner（最贴近"立直后胡"的可观察事件）
extends SkillHook

# BREEZE_HAN_BONUS 已迁移到 BalanceConstants (&"south_breeze_han_bonus")。

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	ctx.add_han(ctx.beneficiary_seat, int(BalanceConstants.lookup(&"south_breeze_han_bonus")))
