extends GutTest

# 麻将王 — M6 内容生产：§8.7 振听操控 + §8.8 Dora 牌技能单测

const EastPhantomHook := preload("res://skills/hooks/east_phantom_hook.gd")
const Man2LureHook := preload("res://skills/hooks/man2_lure_hook.gd")
const ChunSubHook := preload("res://skills/hooks/chun_substitute_hook.gd")
const Man6TreasureHook := preload("res://skills/hooks/man6_treasure_hook.gd")
const WhiteRedHook := preload("res://skills/hooks/white_red_change_hook.gd")
const Sou4UradoraHook := preload("res://skills/hooks/sou4_uradora_pick_hook.gd")

func _setup() -> Array:
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	return [reg, st, sched]

func _make_tile_skill(id: StringName, hook: GDScript, tile_id: int, triggers: Array, rarity: int = Rarity.Kind.EPIC) -> SkillResource:
	var s := SkillResource.new()
	s.id = id
	s.attached_tile = tile_id
	s.rarity = rarity
	var ot: Array[StringName] = []
	for t in triggers:
		ot.append(t)
	s.owner_triggers = ot
	s.hook_script = hook
	return s

func _register_owned_by(reg: SkillRegistry, sk: SkillResource, owner_seat: int) -> void:
	var ti := TileInstance.make(Tile.new(sk.attached_tile), owner_seat, sk)
	reg.register(sk, ti)

# ---- §8.7 east_phantom ----

func test_east_phantom_cancels_ron_when_owner_discards():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var st: BattleState = ctx[1]
	var sched: SkillScheduler = ctx[2]
	var sk := _make_tile_skill(&"east_phantom_v1", EastPhantomHook, TileId.E, [&"RON_DECLARED"])
	_register_owned_by(reg, sk, 0)
	sched.emit_event(BattleEvent.make(&"RON_DECLARED", 1, null, {"discarder_seat": 0}))
	assert_true(st.ron_cancelled[1], "owner 出铳时荣胡被取消")
	assert_true(sk.consumed, "card 标 consumed")

func test_east_phantom_no_cancel_when_other_discards():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var st: BattleState = ctx[1]
	var sched: SkillScheduler = ctx[2]
	var sk := _make_tile_skill(&"east_phantom_v1", EastPhantomHook, TileId.E, [&"RON_DECLARED"])
	_register_owned_by(reg, sk, 0)
	sched.emit_event(BattleEvent.make(&"RON_DECLARED", 1, null, {"discarder_seat": 2}))
	assert_false(st.ron_cancelled[1], "其他人放铳，owner 不触发")

# ---- §8.7 man2_lure ----

func test_man2_lure_adds_1_han_on_self_win():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var sk := _make_tile_skill(&"man2_lure_v1", Man2LureHook, TileId.W2, [&"WIN_DECLARED"])
	_register_owned_by(reg, sk, 1)
	var out := sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 1))
	assert_eq(int(out.han_deltas.get(1, 0)), 1)

func test_man2_lure_no_han_when_other_wins():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var sk := _make_tile_skill(&"man2_lure_v1", Man2LureHook, TileId.W2, [&"WIN_DECLARED"])
	_register_owned_by(reg, sk, 1)
	var out := sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 2))
	assert_eq(int(out.han_deltas.get(1, 0)), 0)

# ---- §8.7 chun_substitute ----

func test_chun_substitute_clears_furiten_on_win():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var st: BattleState = ctx[1]
	var sched: SkillScheduler = ctx[2]
	st.furiten_flags[2] = true
	var sk := _make_tile_skill(&"chun_substitute_v1", ChunSubHook, TileId.CHUN, [&"WIN_DECLARED"], Rarity.Kind.UNCOMMON)
	_register_owned_by(reg, sk, 2)
	sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 2))
	assert_false(st.furiten_flags[2], "owner 自胡时清振听")

func test_chun_substitute_no_op_when_not_furiten():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var st: BattleState = ctx[1]
	var sched: SkillScheduler = ctx[2]
	var sk := _make_tile_skill(&"chun_substitute_v1", ChunSubHook, TileId.CHUN, [&"WIN_DECLARED"], Rarity.Kind.UNCOMMON)
	_register_owned_by(reg, sk, 2)
	sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 2))
	assert_false(st.furiten_flags[2])

# ---- §8.8 man6_treasure ----

func test_man6_treasure_marks_1_extra_dora_on_self_win():
	# M7 B2 升级：从 add_han(+1) 改为 mark_extra_dora_for_seat(+1)
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var st: BattleState = ctx[1]
	var sched: SkillScheduler = ctx[2]
	var sk := _make_tile_skill(&"man6_treasure_v1", Man6TreasureHook, TileId.W6, [&"WIN_DECLARED"], Rarity.Kind.LEGENDARY)
	_register_owned_by(reg, sk, 0)
	sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 0))
	assert_eq(int(st.extra_dora_count[0]), 1, "owner 自胡 → +1 额外 dora")

func test_man6_treasure_no_dora_for_other_seat():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var st: BattleState = ctx[1]
	var sched: SkillScheduler = ctx[2]
	var sk := _make_tile_skill(&"man6_treasure_v1", Man6TreasureHook, TileId.W6, [&"WIN_DECLARED"], Rarity.Kind.LEGENDARY)
	_register_owned_by(reg, sk, 0)
	sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 3))
	assert_eq(int(st.extra_dora_count[0]), 0)

# ---- §8.8 white_red_change ----

func test_white_red_change_marks_1_red_dora_on_win():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var st: BattleState = ctx[1]
	var sched: SkillScheduler = ctx[2]
	var sk := _make_tile_skill(&"white_red_change_v1", WhiteRedHook, TileId.HAKU, [&"WIN_DECLARED"], Rarity.Kind.UNCOMMON)
	_register_owned_by(reg, sk, 3)
	sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 3))
	assert_eq(int(st.extra_red_dora_count[3]), 1, "owner 自胡 → +1 赤 dora")

# ---- §8.8 sou4_uradora_pick ----

func test_sou4_uradora_marks_extra_dora_on_win():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var st: BattleState = ctx[1]
	var sched: SkillScheduler = ctx[2]
	var sk := _make_tile_skill(&"sou4_uradora_pick_v1", Sou4UradoraHook, TileId.S4, [&"WIN_DECLARED_PRE"])
	_register_owned_by(reg, sk, 1)
	sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 1))
	assert_gt(st.extra_dora_count[1], 0, "v2: sou4 应 mark_extra_dora 而非 add_han")

func test_sou4_uradora_no_dora_for_other_seat():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var st: BattleState = ctx[1]
	var sched: SkillScheduler = ctx[2]
	var sk := _make_tile_skill(&"sou4_uradora_pick_v1", Sou4UradoraHook, TileId.S4, [&"WIN_DECLARED_PRE"])
	_register_owned_by(reg, sk, 1)
	sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 2))
	assert_eq(st.extra_dora_count[1], 0, "非 owner 自胡不增 dora")
