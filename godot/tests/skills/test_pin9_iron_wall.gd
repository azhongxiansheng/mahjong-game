extends GutTest

# 麻将王 — M6 内容生产：9 万·铁壁（§8.3 阻胡系）

const Hook := preload("res://skills/hooks/pin9_iron_wall_hook.gd")

func _make_skill() -> SkillResource:
	var s := SkillResource.new()
	s.id = &"pin9_iron_wall_v1"
	s.attached_tile = TileId.W9
	s.rarity = Rarity.Kind.UNCOMMON
	var ot: Array[StringName] = [&"RON_DECLARED"]
	s.owner_triggers = ot
	s.hook_script = Hook
	return s

func _setup() -> Array:
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	return [reg, st, sched]

func test_iron_wall_minus_1_han_when_owner_discards_to_ron():
	# owner = seat 0；actor (winner) = seat 2 荣胡 owner 弃出的牌
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var sk := _make_skill()
	var ti := TileInstance.make(Tile.new(TileId.W9), 0, sk)
	reg.register(sk, ti)
	var out_ctx := sched.emit_event(BattleEvent.make(
		&"RON_DECLARED", 2, null, {"discarder_seat": 0}
	))
	assert_eq(int(out_ctx.han_deltas.get(2, 0)), -1, "winner 应被 -1 番")

func test_iron_wall_no_effect_when_other_seat_discards():
	# owner = seat 0；但 discarder = seat 1（owner 没放铳）→ 不触发
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var sk := _make_skill()
	var ti := TileInstance.make(Tile.new(TileId.W9), 0, sk)
	reg.register(sk, ti)
	var out_ctx := sched.emit_event(BattleEvent.make(
		&"RON_DECLARED", 2, null, {"discarder_seat": 1}
	))
	assert_eq(int(out_ctx.han_deltas.get(2, 0)), 0, "owner 没放铳，不触发")

func test_iron_wall_no_effect_when_no_discarder_in_extra():
	# extra 缺 discarder_seat → 默认 -1，不与 owner 匹配
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var sk := _make_skill()
	var ti := TileInstance.make(Tile.new(TileId.W9), 0, sk)
	reg.register(sk, ti)
	var out_ctx := sched.emit_event(BattleEvent.make(&"RON_DECLARED", 2, null, {}))
	assert_eq(int(out_ctx.han_deltas.get(2, 0)), 0, "无 discarder_seat 时安全")
