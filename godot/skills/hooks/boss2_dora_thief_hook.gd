# 章 2 Boss 変種 — Dora 泥棒（Dora テーマ v2）
# Boss 自胡時 +2 extra Dora。プレイヤー（seat 0）が胡った場合は効果なし
#（v1 簡略化：マイナス Dora 非対応のため Boss 加算のみ）。
# 触発：WIN_DECLARED_PRE + actor == beneficiary（boss seat）
extends SkillHook

const BOSS_EXTRA_DORA: int = 2

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	ctx.mark_extra_dora_for_seat(ctx.beneficiary_seat, BOSS_EXTRA_DORA)
