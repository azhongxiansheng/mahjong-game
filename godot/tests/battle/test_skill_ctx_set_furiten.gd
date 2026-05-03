extends GutTest

# 麻将王 — M7 ctx 扩展 B1：ctx.set_furiten(seat, value)
#
# 与 ctx.clear_furiten 配对的 setter；hook 通过它主动把对手置振听。
# 当前只切 bool 标记；"振听 N 巡倒计时"留 M7 后续 PR（需 furiten_turns_remaining
# 状态字段 + turn_engine 在 turn 结束清振听）。

class _SetFuritenHook extends SkillHook:
	# 触发时把 event.extra.target_seat 置振听
	func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
		var target: int = int(event.extra.get("target_seat", -1))
		if target < 0:
			return
		ctx.set_furiten(target, true)

class _ClearFuritenViaSetHook extends SkillHook:
	# 用 set_furiten(seat, false) 清除振听（验证 alias 等价 clear_furiten）
	func on_event(_skill: SkillResource, _event: BattleEvent, ctx: SkillCtx) -> void:
		ctx.set_furiten(ctx.beneficiary_seat, false)

func _setup() -> Array:
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	return [reg, st, sched]

func _make_skill(hook_script: GDScript) -> SkillResource:
	var s := SkillResource.new()
	s.id = &"_set_furiten_test_v1"
	s.attached_tile = TileId.W1
	s.rarity = Rarity.Kind.COMMON
	var ot: Array[StringName] = [&"WIN_DECLARED"]
	s.owner_triggers = ot
	s.hook_script = hook_script
	return s

# ---- set_furiten(seat, true) ----

func test_set_furiten_true_marks_seat_furiten():
	var arr := _setup()
	var reg: SkillRegistry = arr[0]
	var st: BattleState = arr[1]
	var sched: SkillScheduler = arr[2]
	var sk := _make_skill(_SetFuritenHook)
	var ti := TileInstance.make(Tile.new(TileId.W1), 0, sk)
	reg.register(sk, ti)
	assert_false(st.furiten_flags[2], "初始未振听")
	sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 0, null, {"target_seat": 2}))
	assert_true(st.furiten_flags[2], "set_furiten(2, true) 后置振听")
	# 不影响其它 seat
	assert_false(st.furiten_flags[0])
	assert_false(st.furiten_flags[1])
	assert_false(st.furiten_flags[3])

# ---- set_furiten(seat, false) = clear_furiten 等价 ----

func test_set_furiten_false_clears():
	var arr := _setup()
	var reg: SkillRegistry = arr[0]
	var st: BattleState = arr[1]
	var sched: SkillScheduler = arr[2]
	st.furiten_flags[1] = true
	var sk := _make_skill(_ClearFuritenViaSetHook)
	var ti := TileInstance.make(Tile.new(TileId.W1), 1, sk)
	reg.register(sk, ti)
	sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 1))
	assert_false(st.furiten_flags[1], "set_furiten(seat, false) 等价 clear_furiten")

# ---- 默认参数 value=true ----

func test_set_furiten_default_value_is_true():
	# 直接调 ctx.set_furiten(seat) 应等价 set_furiten(seat, true)
	var st := BattleState.new()
	var ev := BattleEvent.make(&"NOOP", -1)
	var ctx := SkillCtx.new(st, ev)
	ctx.set_furiten(2)
	assert_true(st.furiten_flags[2])
	assert_false(st.furiten_flags[0])
