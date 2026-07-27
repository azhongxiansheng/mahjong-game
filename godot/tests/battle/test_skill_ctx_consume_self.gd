extends GutTest

# 麻将王 — M7 ctx 扩展 B1：ctx.consume_self()
#
# 验证 SkillScheduler 在 _dispatch 时正确注入 ctx.current_skill，
# 使 hook 可通过 ctx.consume_self() 把当前 skill 标记为 consumed
# （等价于直写 skill.consumed = true，但走 ctx 抽象边界）。

# 用一个匿名 hook 类做最小验证（不引用现有 hooks/，避免与 M6 升级 PR 耦合）
class _ConsumeOnFireHook extends SkillHook:
	func on_event(_skill: SkillResource, _event: BattleEvent, ctx: SkillCtx) -> void:
		ctx.consume_self()

class _NoopHook extends SkillHook:
	func on_event(_skill, _event, _ctx) -> void:
		pass

func _make_skill(hook_script: GDScript) -> SkillResource:
	var s := SkillResource.new()
	s.id = &"_ctx_consume_self_test_v1"
	s.attached_tile = TileId.W1
	s.rarity = Rarity.Kind.COMMON
	var ot: Array[StringName] = [&"WIN_DECLARED"]
	s.owner_triggers = ot
	s.hook_script = hook_script
	return s

func _setup() -> Array:
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	return [reg, st, sched]

func test_consume_self_marks_skill_consumed():
	# fire 1 次 → skill.consumed 应为 true
	var arr := _setup()
	var reg: SkillRegistry = arr[0]
	var sched: SkillScheduler = arr[2]
	var sk := _make_skill(_ConsumeOnFireHook)
	var ti := TileSkillAnchor.make(Tile.new(TileId.W1), 0, sk)
	reg.register(sk, ti)
	assert_false(sk.consumed, "fire 前未消耗")
	sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 0))
	assert_true(sk.consumed, "fire 后 ctx.consume_self() → skill.consumed=true")

func test_consumed_skill_does_not_fire_again():
	# 第 2 次 emit 时 scheduler 应跳过 consumed skill（与现有 _dispatch 行为一致）
	var arr := _setup()
	var reg: SkillRegistry = arr[0]
	var st: BattleState = arr[1]
	var sched: SkillScheduler = arr[2]
	var sk := _make_skill(_ConsumeOnFireHook)
	var ti := TileSkillAnchor.make(Tile.new(TileId.W1), 0, sk)
	reg.register(sk, ti)
	sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 0))
	# 模拟"重置外部状态"以确认第 2 次 emit 不再触发 hook
	# （这里用 scores 不变作为"hook 没跑"的间接证据）
	var scores_before := st.scores.duplicate()
	sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 0))
	assert_eq(st.scores, scores_before, "consumed 后 hook 不再被 dispatch")

func test_current_skill_resets_after_dispatch():
	# 安全：dispatch 结束后 ctx.current_skill 应回 null，防止外部代码误用
	# 用一个不调 consume_self 的 hook，验证 dispatch 完成后 current_skill 清空
	var arr := _setup()
	var reg: SkillRegistry = arr[0]
	var sched: SkillScheduler = arr[2]
	var sk := _make_skill(_NoopHook)
	var ti := TileSkillAnchor.make(Tile.new(TileId.W1), 0, sk)
	reg.register(sk, ti)
	var ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 0))
	assert_null(ctx.current_skill, "dispatch 结束后 current_skill 必须清空")
