extends GutTest

# 麻将王 — M6 内容生产：§8.1 east_dynasty + §8.2 加速 + §8.5 透明牌 单测

const EastDynastyHook := preload("res://skills/hooks/east_dynasty_hook.gd")
const Pin9SpeedHook := preload("res://skills/hooks/pin9_speed_hook.gd")
const Sou3SkipHook := preload("res://skills/hooks/sou3_skip_hook.gd")
const SouthBreezeHook := preload("res://skills/hooks/south_riichi_breeze_hook.gd")
const WhiteOracleHook := preload("res://skills/hooks/white_oracle_hook.gd")
const Pin2BluffHook := preload("res://skills/hooks/pin2_bluff_hook.gd")

func _setup() -> Array:
	# M10：white_oracle 用 reveal_dora_indicator_to 需真 wall（含 dora indicator）
	var reg := SkillRegistry.new()
	var st := BattleState.for_east_round(42, 0, 1, 0, 0)
	var sched := SkillScheduler.new(reg, st)
	return [reg, st, sched]

func _make_tile_skill(id: StringName, hook: GDScript, tile_id: int, triggers: Array) -> SkillResource:
	var s := SkillResource.new()
	s.id = id
	s.attached_tile = tile_id
	s.rarity = Rarity.Kind.EPIC
	var ot: Array[StringName] = []
	for t in triggers:
		ot.append(t)
	s.owner_triggers = ot
	s.hook_script = hook
	return s

func _register_owned_by(reg: SkillRegistry, sk: SkillResource, owner_seat: int) -> void:
	var ti := TileSkillAnchor.make(Tile.new(sk.attached_tile), owner_seat, sk)
	reg.register(sk, ti)

# ---- §8.1 east_dynasty ----

func test_east_dynasty_adds_2_han_when_owner_is_dealer():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var sk := _make_tile_skill(&"east_dynasty_v1", EastDynastyHook, TileId.E, [&"WIN_DECLARED"])
	_register_owned_by(reg, sk, 0)
	var out := sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 0, null, {"dealer_seat": 0}))
	assert_eq(int(out.han_deltas.get(0, 0)), 2)

func test_east_dynasty_no_han_when_owner_not_dealer():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var sk := _make_tile_skill(&"east_dynasty_v1", EastDynastyHook, TileId.E, [&"WIN_DECLARED"])
	_register_owned_by(reg, sk, 1)
	var out := sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 1, null, {"dealer_seat": 0}))
	assert_eq(int(out.han_deltas.get(1, 0)), 0)

func test_east_dynasty_no_han_when_no_dealer_in_extra():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var sk := _make_tile_skill(&"east_dynasty_v1", EastDynastyHook, TileId.E, [&"WIN_DECLARED"])
	_register_owned_by(reg, sk, 0)
	var out := sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 0, null, {}))
	assert_eq(int(out.han_deltas.get(0, 0)), 0, "无 dealer_seat 时安全")

# ---- §8.2 pin9_speed ----

func test_pin9_speed_force_tsumo_for_owner():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var st: BattleState = ctx[1]
	var sched: SkillScheduler = ctx[2]
	var sk := _make_tile_skill(&"pin9_speed_v1", Pin9SpeedHook, TileId.T9, [&"DRAW"])
	_register_owned_by(reg, sk, 2)
	sched.emit_event(BattleEvent.make(&"DRAW", 2))
	assert_eq(st.haitei_forced_seat, 2, "force_tsumo 标记 owner")

func test_pin9_speed_no_effect_for_other_seat_draw():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var st: BattleState = ctx[1]
	var sched: SkillScheduler = ctx[2]
	var sk := _make_tile_skill(&"pin9_speed_v1", Pin9SpeedHook, TileId.T9, [&"DRAW"])
	_register_owned_by(reg, sk, 2)
	sched.emit_event(BattleEvent.make(&"DRAW", 1))
	assert_eq(st.haitei_forced_seat, -1, "其他人摸牌不触发")

# ---- §8.2 sou3_skip ----

func test_sou3_skip_adds_1_han_on_self_win():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var sk := _make_tile_skill(&"sou3_skip_v1", Sou3SkipHook, TileId.S3, [&"WIN_DECLARED"])
	_register_owned_by(reg, sk, 1)
	var out := sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 1))
	assert_eq(int(out.han_deltas.get(1, 0)), 1)

# ---- §8.2 south_riichi_breeze ----

func test_south_breeze_adds_1_han_on_self_win():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var sk := _make_tile_skill(&"south_riichi_breeze_v1", SouthBreezeHook, TileId.S_WIND, [&"WIN_DECLARED"])
	_register_owned_by(reg, sk, 3)
	var out := sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 3))
	assert_eq(int(out.han_deltas.get(3, 0)), 1)

# ---- §8.5 white_oracle ----

func test_white_oracle_reveals_a_tile_to_owner():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var st: BattleState = ctx[1]
	var sched: SkillScheduler = ctx[2]
	var sk := _make_tile_skill(&"white_oracle_v1", WhiteOracleHook, TileId.HAKU, [&"DRAW"])
	_register_owned_by(reg, sk, 0)
	sched.emit_event(BattleEvent.make(&"DRAW", 0))
	assert_eq(st.revealed_tiles.size(), 1)
	var rec: Dictionary = st.revealed_tiles[0]
	assert_eq(int(rec.visible_to[0]), 0, "可见对象 = owner seat")

func test_white_oracle_no_reveal_for_other_seat():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var st: BattleState = ctx[1]
	var sched: SkillScheduler = ctx[2]
	var sk := _make_tile_skill(&"white_oracle_v1", WhiteOracleHook, TileId.HAKU, [&"DRAW"])
	_register_owned_by(reg, sk, 0)
	sched.emit_event(BattleEvent.make(&"DRAW", 2))
	assert_eq(st.revealed_tiles.size(), 0)

# ---- §8.5 pin2_bluff ----

func test_pin2_bluff_adds_1_han_on_self_win():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var sk := _make_tile_skill(&"pin2_bluff_v1", Pin2BluffHook, TileId.T2, [&"WIN_DECLARED"])
	_register_owned_by(reg, sk, 2)
	var out := sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 2))
	assert_eq(int(out.han_deltas.get(2, 0)), 1)
