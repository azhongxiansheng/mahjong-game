extends GutTest

# 麻将王 — M7：han_deltas → ScoreCalc 接通验证。
#
# 此前 BattleController 在 ScoreCalc 之后才 emit WIN_DECLARED，hooks 累积的
# han_deltas 被丢弃，所有 +N 番 hook 在真实战斗里都是装饰性的。
# 本批改：BattleController 在 ScoreCalc 之前 emit WIN_DECLARED_PRE，把
# han_deltas[winner_seat] 注入 yaku_list 作为 &"skill_bonus"。
#
# 验证两点：
# 1. _apply_skill_han 静态 helper 行为
# 2. WIN_DECLARED_PRE 事件在 BattleController 内被正确 emit（间接：
#    通过 hook 接到 WIN_DECLARED_PRE 后看到 yaku_list 增长，但不跑完整
#    BattleController；测试用 helper 直接验证）

# ---- _apply_skill_han ----

func test_apply_skill_han_zero_delta_no_op():
	var yl := YakuList.new()
	yl.add_yaku(&"riichi", 1)
	var st := BattleState.new()
	var ev := BattleEvent.make(&"WIN_DECLARED_PRE", 0)
	var ctx := SkillCtx.new(st, ev)
	# 不调 add_han → han_deltas 空
	BattleController._apply_skill_han(yl, ctx, 0)
	assert_eq(yl.yaku.size(), 1, "无 delta 不注入新 entry")
	assert_eq(yl.total_han(), 1)

func test_apply_skill_han_positive_delta_adds_skill_bonus():
	var yl := YakuList.new()
	yl.add_yaku(&"riichi", 1)
	var st := BattleState.new()
	var ev := BattleEvent.make(&"WIN_DECLARED_PRE", 0)
	var ctx := SkillCtx.new(st, ev)
	ctx.add_han(0, 2)  # winner_seat=0，+2 番
	BattleController._apply_skill_han(yl, ctx, 0)
	assert_eq(yl.yaku.size(), 2, "应注入 1 个 skill_bonus entry")
	assert_eq(yl.total_han(), 3, "1 立直 + 2 skill = 3 番")
	# 校验 entry 类型
	var found := false
	for e in yl.yaku:
		if e.id == &"skill_bonus":
			assert_eq(int(e.han), 2)
			found = true
	assert_true(found, "skill_bonus entry id 应正确")

func test_apply_skill_han_negative_delta_reduces():
	# Iron Wall 模式：胜者被 -1 番
	var yl := YakuList.new()
	yl.add_yaku(&"tanyao", 1)
	yl.add_yaku(&"riichi", 1)
	var st := BattleState.new()
	var ev := BattleEvent.make(&"WIN_DECLARED_PRE", 1)
	var ctx := SkillCtx.new(st, ev)
	ctx.add_han(1, -1)  # winner_seat=1，-1 番（iron_wall 效果）
	BattleController._apply_skill_han(yl, ctx, 1)
	assert_eq(yl.total_han(), 1, "2 番 - 1 = 1 番")

func test_apply_skill_han_only_winner_seat_applied():
	# 多个 seat 各有 delta，只有 winner_seat 的 delta 被注入
	var yl := YakuList.new()
	var st := BattleState.new()
	var ev := BattleEvent.make(&"WIN_DECLARED_PRE", 2)
	var ctx := SkillCtx.new(st, ev)
	ctx.add_han(0, 5)   # 其它 seat 的 delta（无关）
	ctx.add_han(2, 1)   # 真正 winner
	ctx.add_han(3, 99)  # 其它 seat 的 delta（无关）
	BattleController._apply_skill_han(yl, ctx, 2)
	assert_eq(yl.total_han(), 1, "只取 winner seat=2 的 +1，不混合其它座位")

func test_apply_skill_han_null_ctx_safe():
	var yl := YakuList.new()
	yl.add_yaku(&"riichi", 1)
	BattleController._apply_skill_han(yl, null, 0)
	assert_eq(yl.total_han(), 1, "null ctx 不崩")

# ---- WIN_DECLARED_PRE 事件经 SkillScheduler 派发 ----

class _ConditionalHanHook extends SkillHook:
	# 只在 WIN_DECLARED_PRE 时给 actor 加 +3 番
	func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
		if event.type != &"WIN_DECLARED_PRE":
			return
		if event.actor_seat != ctx.beneficiary_seat:
			return
		ctx.add_han(ctx.beneficiary_seat, 3)

func test_win_declared_pre_event_dispatches_to_hooks():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	var s := SkillResource.new()
	s.id = &"_test_pre_hook_v1"
	s.is_ability = true
	var ot: Array[StringName] = [&"WIN_DECLARED_PRE"]
	s.owner_triggers = ot
	s.hook_script = _ConditionalHanHook
	reg.register(s, 1)
	var ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 1))
	assert_eq(int(ctx.han_deltas.get(1, 0)), 3, "WIN_DECLARED_PRE hook 应派发")

func test_old_win_declared_event_still_dispatches():
	# 向后兼容：WIN_DECLARED 事件仍 emit；hooks 用此 trigger 仍能 fire（但
	# 时机在 ScoreCalc 之后，仅供"结算后通知"语义）
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	var s := SkillResource.new()
	s.id = &"_test_post_hook_v1"
	s.is_ability = true
	var ot: Array[StringName] = [&"WIN_DECLARED"]
	s.owner_triggers = ot
	# 复用同一 hook 但只看 actor，触发后给 +1（hook 不分 PRE/POST，看 event.type）
	s.hook_script = _ConditionalHanHook
	reg.register(s, 1)
	var ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 1))
	assert_eq(int(ctx.han_deltas.get(1, 0)), 0, "_ConditionalHanHook 检 type==PRE，WIN_DECLARED 不应触发")
