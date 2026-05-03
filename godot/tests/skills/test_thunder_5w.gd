extends GutTest

const Hook := preload("res://skills/hooks/thunder_5w_hook.gd")

func _make_skill() -> SkillResource:
	var s := SkillResource.new()
	s.id = &"thunder_5w_v1"
	s.attached_tile = TileId.W5
	s.rarity = 2
	var ot: Array[StringName] = [&"WIN_DECLARED"]
	s.owner_triggers = ot
	s.hook_script = Hook
	return s

func _setup() -> Array:
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	return [reg, st, sched]

func test_thunder_adds_2_han_when_owner_is_actor():
	# tune-2: thunder_5w_han_bonus 1 → 2
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var sk := _make_skill()
	var ti := TileInstance.make(Tile.new(TileId.W5), 0, sk)
	reg.register(sk, ti)
	var out_ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 0))
	assert_eq(int(out_ctx.han_deltas.get(0, 0)), 2)

func test_thunder_does_not_add_han_when_actor_is_not_owner():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var sk := _make_skill()
	var ti := TileInstance.make(Tile.new(TileId.W5), 0, sk)
	reg.register(sk, ti)
	var out_ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 1))
	assert_eq(int(out_ctx.han_deltas.get(0, 0)), 0)
