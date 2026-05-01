extends GutTest

const Hook := preload("res://skills/hooks/xray_1w_hook.gd")

func _make_skill() -> SkillResource:
	var s := SkillResource.new()
	s.id = &"xray_1w_v1"
	s.attached_tile = TileId.W1
	s.rarity = 1
	var ot: Array[StringName] = [&"TILE_DRAWN"]
	s.owner_triggers = ot
	s.hook_script = Hook
	return s

func _setup() -> Array:
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	return [reg, st, sched]

func test_xray_reveals_to_owner_when_owner_draws():
	var arr := _setup()
	var reg: SkillRegistry = arr[0]
	var st: BattleState = arr[1]
	var sched: SkillScheduler = arr[2]
	var sk := _make_skill()
	var ti := TileInstance.make(Tile.new(TileId.W1), 0, sk)
	reg.register(sk, ti)
	sched.emit_event(BattleEvent.make(&"TILE_DRAWN", 0))
	assert_eq(st.revealed_tiles.size(), 1)
	assert_true(st.revealed_tiles[0]["visible_to"].has(0))

func test_xray_does_not_fire_for_other_seats_draw():
	var arr := _setup()
	var reg: SkillRegistry = arr[0]
	var st: BattleState = arr[1]
	var sched: SkillScheduler = arr[2]
	var sk := _make_skill()
	var ti := TileInstance.make(Tile.new(TileId.W1), 0, sk)
	reg.register(sk, ti)
	sched.emit_event(BattleEvent.make(&"TILE_DRAWN", 2))
	assert_eq(st.revealed_tiles.size(), 0)
