extends GutTest

const Hook := preload("res://skills/hooks/unfuriten_5p_hook.gd")

func _make_skill() -> SkillResource:
	var s := SkillResource.new()
	s.id = &"unfuriten_5p_v1"
	s.attached_tile = TileId.T5
	s.rarity = 2
	var ot: Array[StringName] = [&"FURITEN_TRIGGERED"]
	s.owner_triggers = ot
	s.hook_script = Hook
	return s

func _setup() -> Array:
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	return [reg, st, sched]

func test_unfuriten_clears_furiten_on_owner_event():
	var arr := _setup()
	var reg: SkillRegistry = arr[0]
	var st: BattleState = arr[1]
	var sched: SkillScheduler = arr[2]
	var sk := _make_skill()
	st.furiten_flags[0] = true
	var ti := TileSkillAnchor.make(Tile.new(TileId.T5), 0, sk)
	reg.register(sk, ti)
	sched.emit_event(BattleEvent.make(&"FURITEN_TRIGGERED", 0))
	assert_false(st.furiten_flags[0])
	assert_true(sk.consumed)

func test_unfuriten_skip_when_not_in_furiten():
	var arr := _setup()
	var reg: SkillRegistry = arr[0]
	var sched: SkillScheduler = arr[2]
	var sk := _make_skill()
	# furiten_flags[0] 默认 false
	var ti := TileSkillAnchor.make(Tile.new(TileId.T5), 0, sk)
	reg.register(sk, ti)
	sched.emit_event(BattleEvent.make(&"FURITEN_TRIGGERED", 0))
	assert_false(sk.consumed, "未振听不应消耗")

func test_unfuriten_consumed_after_fire_does_not_clear_again():
	var arr := _setup()
	var reg: SkillRegistry = arr[0]
	var st: BattleState = arr[1]
	var sched: SkillScheduler = arr[2]
	var sk := _make_skill()
	st.furiten_flags[0] = true
	var ti := TileSkillAnchor.make(Tile.new(TileId.T5), 0, sk)
	reg.register(sk, ti)
	sched.emit_event(BattleEvent.make(&"FURITEN_TRIGGERED", 0))
	st.furiten_flags[0] = true  # 模拟再次振听
	sched.emit_event(BattleEvent.make(&"FURITEN_TRIGGERED", 0))
	assert_true(st.furiten_flags[0], "consumed 后不再清除")
