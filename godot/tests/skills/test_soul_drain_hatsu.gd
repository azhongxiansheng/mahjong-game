extends GutTest

const Hook := preload("res://skills/hooks/soul_drain_hatsu_hook.gd")

func _make_skill() -> SkillResource:
	var s := SkillResource.new()
	s.id = &"soul_drain_hatsu_v1"
	s.attached_tile = TileId.HATSU
	s.rarity = 3
	var ht: Array[StringName] = [&"WIN_DECLARED"]
	s.holder_triggers = ht
	s.hook_script = Hook
	return s

func _setup() -> Array:
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	return [reg, st, sched]

func test_drain_transfers_12_percent_on_opponent_win():
	# balance tune-3：soul_drain_fraction 0.20 → 0.12
	var arr := _setup()
	var reg: SkillRegistry = arr[0]
	var st: BattleState = arr[1]
	var sched: SkillScheduler = arr[2]
	var sk := _make_skill()
	# holder_seat=0 持牌；座位 1 胡 8000 → 0 拿 12% × 8000 = 960
	var ti := TileSkillAnchor.make(Tile.new(TileId.HATSU), 2, sk)
	ti.holder_seat = 0
	reg.register(sk, ti)
	sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 1, null, {"points_won": 8000}))
	assert_eq(st.scores[0], 25000 + 960)
	assert_eq(st.scores[1], 25000 - 960)

func test_drain_does_not_fire_when_holder_is_winner():
	var arr := _setup()
	var reg: SkillRegistry = arr[0]
	var st: BattleState = arr[1]
	var sched: SkillScheduler = arr[2]
	var sk := _make_skill()
	var ti := TileSkillAnchor.make(Tile.new(TileId.HATSU), 2, sk)
	ti.holder_seat = 0
	reg.register(sk, ti)
	sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 0, null, {"points_won": 8000}))
	assert_eq(st.scores[0], 25000, "自胡不触发抓马")
