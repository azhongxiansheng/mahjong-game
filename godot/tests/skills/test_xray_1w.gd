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
	# M10：reveal_random_from_seat 需要真 seat.hand，用 for_east_round 构造
	# 完整的 BattleState（4 seats，每家 13 张起始手牌）
	var reg := SkillRegistry.new()
	var st := BattleState.for_east_round(42, 0, 1, 0, 0)
	var sched := SkillScheduler.new(reg, st)
	return [reg, st, sched]

func test_xray_reveals_to_owner_when_owner_draws():
	var arr := _setup()
	var reg: SkillRegistry = arr[0]
	var st: BattleState = arr[1]
	var sched: SkillScheduler = arr[2]
	var sk := _make_skill()
	var ti := TileSkillAnchor.make(Tile.new(TileId.W1), 0, sk)
	reg.register(sk, ti)
	sched.emit_event(BattleEvent.make(&"TILE_DRAWN", 0))
	assert_eq(st.revealed_tiles.size(), 1)
	assert_true(st.revealed_tiles[0]["visible_to"].has(0))
	# M10 升级验证：reveal 的 tile 来自下家（seat 1）真手牌，holder_seat=1
	var revealed_ti: TileSkillAnchor = st.revealed_tiles[0]["tile"]
	assert_eq(revealed_ti.holder_seat, 1, "tile 来自下家手牌")

func test_xray_does_not_fire_for_other_seats_draw():
	var arr := _setup()
	var reg: SkillRegistry = arr[0]
	var st: BattleState = arr[1]
	var sched: SkillScheduler = arr[2]
	var sk := _make_skill()
	var ti := TileSkillAnchor.make(Tile.new(TileId.W1), 0, sk)
	reg.register(sk, ti)
	sched.emit_event(BattleEvent.make(&"TILE_DRAWN", 2))
	assert_eq(st.revealed_tiles.size(), 0)
