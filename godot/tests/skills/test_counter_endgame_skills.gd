extends GutTest

# 麻将王 — M6 内容生产：§8.4 抓马 + §8.6 立直续 + §8.9 终局续 单测

const EastMirrorHook := preload("res://skills/hooks/east_mirror_chambo_hook.gd")
const Sou8ScapegoatHook := preload("res://skills/hooks/sou8_scapegoat_hook.gd")
const PrematureRiichiHook := preload("res://skills/hooks/south_premature_riichi_hook.gd")
const RefundHook := preload("res://skills/hooks/hatsu_stick_refund_hook.gd")
const NorthSweepHook := preload("res://skills/hooks/north_sweep_hook.gd")
const ManganFloorHook := preload("res://skills/hooks/white_mangan_floor_hook.gd")

func _setup() -> Array:
	var reg := SkillRegistry.new()
	var st := BattleState.new()
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
	var ti := TileInstance.make(Tile.new(sk.attached_tile), owner_seat, sk)
	reg.register(sk, ti)

# ---- §8.4 east_mirror_chambo ----

func test_east_mirror_chambo_minus_1_to_winner_when_owner_discards():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var sk := _make_tile_skill(&"east_mirror_chambo_v1", EastMirrorHook, TileId.E, [&"RON_DECLARED"])
	_register_owned_by(reg, sk, 0)
	var out := sched.emit_event(BattleEvent.make(&"RON_DECLARED", 2, null, {"discarder_seat": 0}))
	assert_eq(int(out.han_deltas.get(2, 0)), -1)

func test_east_mirror_chambo_no_effect_when_other_discards():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var sk := _make_tile_skill(&"east_mirror_chambo_v1", EastMirrorHook, TileId.E, [&"RON_DECLARED"])
	_register_owned_by(reg, sk, 0)
	var out := sched.emit_event(BattleEvent.make(&"RON_DECLARED", 2, null, {"discarder_seat": 1}))
	assert_eq(int(out.han_deltas.get(2, 0)), 0)

# ---- §8.4 sou8_scapegoat ----

func test_sou8_scapegoat_minus_1_to_winner_when_owner_discards():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var sk := _make_tile_skill(&"sou8_scapegoat_v1", Sou8ScapegoatHook, TileId.S8, [&"RON_DECLARED"])
	_register_owned_by(reg, sk, 1)
	var out := sched.emit_event(BattleEvent.make(&"RON_DECLARED", 3, null, {"discarder_seat": 1}))
	assert_eq(int(out.han_deltas.get(3, 0)), -1)

# ---- §8.6 south_premature_riichi ----

func test_premature_riichi_adds_2_han_on_self_win():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var sk := _make_tile_skill(&"south_premature_riichi_v1", PrematureRiichiHook, TileId.S_WIND, [&"WIN_DECLARED"])
	_register_owned_by(reg, sk, 0)
	var out := sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 0))
	assert_eq(int(out.han_deltas.get(0, 0)), 2)

# ---- §8.6 hatsu_stick_refund ----

func test_stick_refund_adds_1_han_on_self_win():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var sk := _make_tile_skill(&"hatsu_stick_refund_v1", RefundHook, TileId.HATSU, [&"WIN_DECLARED"])
	_register_owned_by(reg, sk, 2)
	var out := sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 2))
	assert_eq(int(out.han_deltas.get(2, 0)), 1)

# ---- §8.9 north_sweep ----

func test_north_sweep_adds_3_han_on_self_win():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var sk := _make_tile_skill(&"north_sweep_v1", NorthSweepHook, TileId.N, [&"WIN_DECLARED"])
	_register_owned_by(reg, sk, 1)
	var out := sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 1))
	assert_eq(int(out.han_deltas.get(1, 0)), 3)

# ---- §8.9 white_mangan_floor ----

func test_mangan_floor_adds_5_han_and_consumes():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var sk := _make_tile_skill(&"white_mangan_floor_v1", ManganFloorHook, TileId.HAKU, [&"WIN_DECLARED"])
	_register_owned_by(reg, sk, 3)
	var out := sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 3))
	assert_eq(int(out.han_deltas.get(3, 0)), 5)
	assert_true(sk.consumed)

func test_mangan_floor_no_effect_when_other_wins():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var sk := _make_tile_skill(&"white_mangan_floor_v1", ManganFloorHook, TileId.HAKU, [&"WIN_DECLARED"])
	_register_owned_by(reg, sk, 3)
	var out := sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 2))
	assert_eq(int(out.han_deltas.get(3, 0)), 0)
	assert_false(sk.consumed)
