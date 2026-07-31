# 铁盾 — 战斗消耗品
# 武装后，owner 下一次打出的牌若产生荣和，取消该弃牌产生的全部荣和
# （以同一弃牌实体为边界的多家荣和集合），保护窗结束后消耗
# （spec 2026-07-28 §3.1 / §2.2）。对自摸无效（自摸不发 RON_DECLARED）。
# 保护窗结束信号：另一弃牌的荣和 / 下一次摸牌 / 本局终局事件。
extends SkillHook

const PROTECTED_KEY := "shield_protected_iid"

func on_event(skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.type == &"RON_DECLARED":
		var iid: int = Tile.INVALID_INSTANCE_ID
		if event.tile_anchor != null and event.tile_anchor.tile != null:
			iid = event.tile_anchor.tile.instance_id
		if not skill.params.has(PROTECTED_KEY):
			# 尚未触发：只保护 owner 自己放铳的弃牌
			var discarder: int = int(event.extra.get("discarder_seat", -1))
			if discarder != ctx.beneficiary_seat:
				return
			skill.params = skill.params.duplicate(true)
			skill.params[PROTECTED_KEY] = iid
			ctx.cancel_ron(event.actor_seat)
			return
		if iid == int(skill.params[PROTECTED_KEY]):
			# 同一弃牌的后续荣和：继续取消（多家荣和整组保护）
			ctx.cancel_ron(event.actor_seat)
		else:
			# 另一弃牌产生的荣和：保护窗已结束 → 消耗且不取消
			ctx.consume_self()
		return
	# 非荣和事件（下一次摸牌 / 局终局）：保护已发生则收尾消耗
	if skill.params.has(PROTECTED_KEY):
		ctx.consume_self()
