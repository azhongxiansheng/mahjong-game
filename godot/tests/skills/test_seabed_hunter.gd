extends GutTest

const Hook := preload("res://skills/hooks/seabed_hunter_hook.gd")

func _make_ability() -> SkillResource:
	var s := SkillResource.new()
	s.id = &"seabed_hunter_v1"
	s.is_ability = true
	s.rarity = 3
	# ability seat-bound;同时挂 owner / holder triggers 验证 dedup
	var ot: Array[StringName] = [&"HAITEI"]
	var ht: Array[StringName] = [&"HAITEI"]
	s.owner_triggers = ot
	s.holder_triggers = ht
	s.hook_script = Hook
	return s

func _setup() -> Array:
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	return [reg, st, sched]

func test_seabed_forces_tsumo_to_owner_seat_on_haitei():
	var arr := _setup()
	var reg: SkillRegistry = arr[0]
	var st: BattleState = arr[1]
	var sched: SkillScheduler = arr[2]
	var sk := _make_ability()
	reg.register(sk, 0)  # ability 锚点 = 座位 0
	sched.emit_event(BattleEvent.make(&"HAITEI", 1))  # actor=1 摸最后一张
	assert_eq(st.haitei_forced_seat, 0)
	assert_true(sk.consumed)

func test_seabed_consumed_after_one_use():
	var arr := _setup()
	var reg: SkillRegistry = arr[0]
	var st: BattleState = arr[1]
	var sched: SkillScheduler = arr[2]
	var sk := _make_ability()
	reg.register(sk, 0)
	sched.emit_event(BattleEvent.make(&"HAITEI", 1))
	st.haitei_forced_seat = -1  # 重置
	sched.emit_event(BattleEvent.make(&"HAITEI", 2))
	assert_eq(st.haitei_forced_seat, -1, "consumed 后第二次不再 force_tsumo")
