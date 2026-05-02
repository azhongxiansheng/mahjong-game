# 东·镜抓 — §8.4 抓马反向得分系
#
# v1: owner 放铳被荣胡时，胡牌方得分 ×0.5（owner 拿回 50%）。
# 对照 soul_drain_hatsu 的 transfer_points 模式，但触发条件不同：
#   soul_drain：holder_trigger，任意对手胡（含 tsumo）→ holder 拿 30%
#   东·镜抓：  owner_trigger，**owner 出铳被 RON** → owner 拿回 50%
#
# event.extra: {"discarder_seat": int, "points_won": int}
# 由 turn_engine / scene 在结算 RON 时填好。
extends SkillHook

const REFUND_FRACTION := 0.5

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	# owner_trigger 模式：beneficiary_seat = owner（出铳方候选）
	var discarder: int = int(event.extra.get("discarder_seat", -1))
	if discarder != ctx.beneficiary_seat:
		return  # owner 不是出铳方
	var points_won: int = int(event.extra.get("points_won", 0))
	if points_won <= 0:
		return
	var refund := int(points_won * REFUND_FRACTION)
	ctx.transfer_points(event.actor_seat, ctx.beneficiary_seat, refund)
