extends GutTest

const Hook := preload("res://skills/hooks/seal_chun_hook.gd")

func _make_skill() -> SkillResource:
	var s := SkillResource.new()
	s.id = &"seal_chun_v1"
	s.attached_tile = TileId.CHUN
	s.rarity = 2
	var ot: Array[StringName] = [&"RON_DECLARED"]
	s.owner_triggers = ot
	s.hook_script = Hook
	return s

func _setup() -> Array:
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	return [reg, st, sched]

func test_seal_cancels_ron_when_owner_is_discarder():
	var arr := _setup()
	var reg: SkillRegistry = arr[0]
	var st: BattleState = arr[1]
	var sched: SkillScheduler = arr[2]
	var sk := _make_skill()
	var ti := TileSkillAnchor.make(Tile.new(TileId.CHUN), 0, sk)
	reg.register(sk, ti)
	# actor=1 荣胡;owner_seat=0 是出铳方
	sched.emit_event(BattleEvent.make(&"RON_DECLARED", 1, ti, {"discarder_seat": 0}))
	assert_true(st.ron_cancelled[1])
	assert_true(sk.consumed, "skill 触发后被消耗")

func test_seal_does_not_fire_when_owner_is_not_discarder():
	var arr := _setup()
	var reg: SkillRegistry = arr[0]
	var st: BattleState = arr[1]
	var sched: SkillScheduler = arr[2]
	var sk := _make_skill()
	var ti := TileSkillAnchor.make(Tile.new(TileId.CHUN), 0, sk)
	reg.register(sk, ti)
	sched.emit_event(BattleEvent.make(&"RON_DECLARED", 1, ti, {"discarder_seat": 2}))
	assert_false(st.ron_cancelled[1])
	assert_false(sk.consumed)

func test_seal_consumed_after_first_fire_does_not_fire_again():
	var arr := _setup()
	var reg: SkillRegistry = arr[0]
	var st: BattleState = arr[1]
	var sched: SkillScheduler = arr[2]
	var sk := _make_skill()
	var ti := TileSkillAnchor.make(Tile.new(TileId.CHUN), 0, sk)
	reg.register(sk, ti)
	sched.emit_event(BattleEvent.make(&"RON_DECLARED", 1, ti, {"discarder_seat": 0}))
	# 重置 ron_cancelled 以验证第二次确实没改它
	st.ron_cancelled[1] = false
	sched.emit_event(BattleEvent.make(&"RON_DECLARED", 1, ti, {"discarder_seat": 0}))
	assert_false(st.ron_cancelled[1], "consumed 后第二次不再触发")
