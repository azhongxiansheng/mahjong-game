extends GutTest

# M12 新增内容单测 — 遗物 / 消耗品 / 牌技能

const ComebackCrownHook := preload("res://skills/hooks/relic_comeback_crown_hook.gd")
const SpeedDemonHook := preload("res://skills/hooks/relic_speed_demon_hook.gd")
const S7CounterRonHook := preload("res://skills/hooks/s7_counter_ron_hook.gd")
const ChunBloodPactHook := preload("res://skills/hooks/chun_blood_pact_hook.gd")
const W8KanBonusHook := preload("res://skills/hooks/w8_kan_bonus_hook.gd")

func _setup() -> Array:
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	return [reg, st, sched]

func _make_relic(id: StringName, hook: GDScript, triggers: Array[StringName]) -> SkillResource:
	var s := SkillResource.new()
	s.id = id
	s.rarity = Rarity.Kind.EPIC
	s.is_ability = true  # relics register as ability-style (anchor = seat int)
	s.owner_triggers = triggers
	s.hook_script = hook
	return s

func _make_tile_skill(id: StringName, tile_id: int, hook: GDScript, triggers: Array[StringName]) -> SkillResource:
	var s := SkillResource.new()
	s.id = id
	s.attached_tile = tile_id
	s.rarity = Rarity.Kind.EPIC
	s.owner_triggers = triggers
	s.hook_script = hook
	return s

# ==== relic_comeback_crown ====

func test_comeback_crown_adds_2_han_when_owner_lowest():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var st: BattleState = ctx[1]
	var sched: SkillScheduler = ctx[2]
	# seat 0 lowest
	st.scores[0] = 10000
	st.scores[1] = 25000
	st.scores[2] = 30000
	st.scores[3] = 20000
	var triggers: Array[StringName] = [&"WIN_DECLARED_PRE"]
	var sk := _make_relic(&"relic_comeback_crown_v1", ComebackCrownHook, triggers)
	reg.register(sk, 0)
	var out_ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_eq(int(out_ctx.han_deltas.get(0, 0)), 2, "lowest score owner +2 han")

func test_comeback_crown_no_bonus_when_not_lowest():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var st: BattleState = ctx[1]
	var sched: SkillScheduler = ctx[2]
	# seat 0 is NOT lowest (seat 2 is)
	st.scores[0] = 25000
	st.scores[1] = 30000
	st.scores[2] = 10000
	st.scores[3] = 20000
	var triggers: Array[StringName] = [&"WIN_DECLARED_PRE"]
	var sk := _make_relic(&"relic_comeback_crown_v1", ComebackCrownHook, triggers)
	reg.register(sk, 0)
	var out_ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_eq(int(out_ctx.han_deltas.get(0, 0)), 0, "not lowest score = no bonus")

func test_comeback_crown_no_bonus_when_other_wins():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var st: BattleState = ctx[1]
	var sched: SkillScheduler = ctx[2]
	st.scores[0] = 10000
	st.scores[1] = 25000
	st.scores[2] = 30000
	st.scores[3] = 20000
	var triggers: Array[StringName] = [&"WIN_DECLARED_PRE"]
	var sk := _make_relic(&"relic_comeback_crown_v1", ComebackCrownHook, triggers)
	reg.register(sk, 0)
	var out_ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 1))
	assert_eq(int(out_ctx.han_deltas.get(0, 0)), 0, "other wins = no bonus for owner")

# ==== relic_speed_demon ====

func test_speed_demon_adds_1_han_when_turn_low():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var st: BattleState = ctx[1]
	var sched: SkillScheduler = ctx[2]
	st.turn_count = 5
	var triggers: Array[StringName] = [&"WIN_DECLARED_PRE"]
	var sk := _make_relic(&"relic_speed_demon_v1", SpeedDemonHook, triggers)
	reg.register(sk, 0)
	var out_ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_eq(int(out_ctx.han_deltas.get(0, 0)), 1, "turn < 8 = +1 han")

func test_speed_demon_no_bonus_when_turn_high():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var st: BattleState = ctx[1]
	var sched: SkillScheduler = ctx[2]
	st.turn_count = 8
	var triggers: Array[StringName] = [&"WIN_DECLARED_PRE"]
	var sk := _make_relic(&"relic_speed_demon_v1", SpeedDemonHook, triggers)
	reg.register(sk, 0)
	var out_ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_eq(int(out_ctx.han_deltas.get(0, 0)), 0, "turn >= 8 = no bonus")

func test_speed_demon_no_bonus_when_other_wins():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var st: BattleState = ctx[1]
	var sched: SkillScheduler = ctx[2]
	st.turn_count = 3
	var triggers: Array[StringName] = [&"WIN_DECLARED_PRE"]
	var sk := _make_relic(&"relic_speed_demon_v1", SpeedDemonHook, triggers)
	reg.register(sk, 0)
	var out_ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 2))
	assert_eq(int(out_ctx.han_deltas.get(0, 0)), 0, "other wins = no bonus")

# ==== s7_counter_ron ====

func test_s7_counter_ron_steals_20_percent():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var st: BattleState = ctx[1]
	var sched: SkillScheduler = ctx[2]
	var triggers: Array[StringName] = [&"RON_DECLARED"]
	var sk := _make_tile_skill(&"s7_counter_ron_v1", TileId.S7, S7CounterRonHook, triggers)
	var ti := TileSkillAnchor.make(Tile.new(TileId.S7), 0, sk)
	reg.register(sk, ti)
	# seat 1 ron, seat 0 is discarder (owner)
	sched.emit_event(BattleEvent.make(&"RON_DECLARED", 1, null, {"discarder_seat": 0}))
	# 20% of seat 1's 25000 = 5000
	assert_eq(st.scores[0], 25000 + 5000, "owner steals 20% back")
	assert_eq(st.scores[1], 25000 - 5000, "winner loses 20%")

func test_s7_counter_ron_no_steal_when_not_discarder():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var st: BattleState = ctx[1]
	var sched: SkillScheduler = ctx[2]
	var triggers: Array[StringName] = [&"RON_DECLARED"]
	var sk := _make_tile_skill(&"s7_counter_ron_v1", TileId.S7, S7CounterRonHook, triggers)
	var ti := TileSkillAnchor.make(Tile.new(TileId.S7), 0, sk)
	reg.register(sk, ti)
	# seat 1 ron, seat 2 is discarder (not owner)
	sched.emit_event(BattleEvent.make(&"RON_DECLARED", 1, null, {"discarder_seat": 2}))
	assert_eq(st.scores[0], 25000, "owner not discarder = no steal")
	assert_eq(st.scores[1], 25000, "winner unchanged")

# ==== chun_blood_pact ====

func test_chun_blood_pact_transfers_1000_from_each():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var st: BattleState = ctx[1]
	var sched: SkillScheduler = ctx[2]
	var triggers: Array[StringName] = [&"WIN_DECLARED"]
	var sk := _make_tile_skill(&"chun_blood_pact_v1", TileId.CHUN, ChunBloodPactHook, triggers)
	var ti := TileSkillAnchor.make(Tile.new(TileId.CHUN), 0, sk)
	reg.register(sk, ti)
	sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 0))
	assert_eq(st.scores[0], 25000 + 3000, "owner gains 3000 total")
	assert_eq(st.scores[1], 25000 - 1000, "opponent 1 loses 1000")
	assert_eq(st.scores[2], 25000 - 1000, "opponent 2 loses 1000")
	assert_eq(st.scores[3], 25000 - 1000, "opponent 3 loses 1000")

func test_chun_blood_pact_no_transfer_when_other_wins():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var st: BattleState = ctx[1]
	var sched: SkillScheduler = ctx[2]
	var triggers: Array[StringName] = [&"WIN_DECLARED"]
	var sk := _make_tile_skill(&"chun_blood_pact_v1", TileId.CHUN, ChunBloodPactHook, triggers)
	var ti := TileSkillAnchor.make(Tile.new(TileId.CHUN), 0, sk)
	reg.register(sk, ti)
	sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 2))
	assert_eq(st.scores[0], 25000, "owner unchanged when other wins")
	assert_eq(st.scores[1], 25000, "seat 1 unchanged")
	assert_eq(st.scores[2], 25000, "seat 2 unchanged")
	assert_eq(st.scores[3], 25000, "seat 3 unchanged")

# ==== w8_kan_bonus ====

func test_w8_kan_bonus_adds_2_han_with_kan():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var st: BattleState = ctx[1]
	var sched: SkillScheduler = ctx[2]
	# Set up a seat with a kan meld
	var seat := Seat.new(0, TileId.E)
	var kan_tiles: Array[Tile] = [
		Tile.new(TileId.W1), Tile.new(TileId.W1),
		Tile.new(TileId.W1), Tile.new(TileId.W1),
	]
	seat.melds.add_existing(Meld.make_ankan(kan_tiles))
	st.seats = [seat, Seat.new(1, TileId.S_WIND), Seat.new(2, TileId.W_WIND), Seat.new(3, TileId.N)]
	var triggers: Array[StringName] = [&"WIN_DECLARED_PRE"]
	var sk := _make_tile_skill(&"w8_kan_bonus_v1", TileId.W8, W8KanBonusHook, triggers)
	var ti := TileSkillAnchor.make(Tile.new(TileId.W8), 0, sk)
	reg.register(sk, ti)
	var out_ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_eq(int(out_ctx.han_deltas.get(0, 0)), 2, "kan meld = +2 han")

func test_w8_kan_bonus_no_bonus_without_kan():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var st: BattleState = ctx[1]
	var sched: SkillScheduler = ctx[2]
	# Set up a seat with only pon meld (no kan)
	var seat := Seat.new(0, TileId.E)
	var pon_tiles: Array[Tile] = [
		Tile.new(TileId.W1), Tile.new(TileId.W1), Tile.new(TileId.W1),
	]
	seat.melds.add_existing(Meld.make_pon(pon_tiles, 1))
	st.seats = [seat, Seat.new(1, TileId.S_WIND), Seat.new(2, TileId.W_WIND), Seat.new(3, TileId.N)]
	var triggers: Array[StringName] = [&"WIN_DECLARED_PRE"]
	var sk := _make_tile_skill(&"w8_kan_bonus_v1", TileId.W8, W8KanBonusHook, triggers)
	var ti := TileSkillAnchor.make(Tile.new(TileId.W8), 0, sk)
	reg.register(sk, ti)
	var out_ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_eq(int(out_ctx.han_deltas.get(0, 0)), 0, "pon only = no kan bonus")

func test_w8_kan_bonus_no_bonus_when_other_wins():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var st: BattleState = ctx[1]
	var sched: SkillScheduler = ctx[2]
	var seat := Seat.new(0, TileId.E)
	var kan_tiles: Array[Tile] = [
		Tile.new(TileId.W1), Tile.new(TileId.W1),
		Tile.new(TileId.W1), Tile.new(TileId.W1),
	]
	seat.melds.add_existing(Meld.make_ankan(kan_tiles))
	st.seats = [seat, Seat.new(1, TileId.S_WIND), Seat.new(2, TileId.W_WIND), Seat.new(3, TileId.N)]
	var triggers: Array[StringName] = [&"WIN_DECLARED_PRE"]
	var sk := _make_tile_skill(&"w8_kan_bonus_v1", TileId.W8, W8KanBonusHook, triggers)
	var ti := TileSkillAnchor.make(Tile.new(TileId.W8), 0, sk)
	reg.register(sk, ti)
	var out_ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 3))
	assert_eq(int(out_ctx.han_deltas.get(0, 0)), 0, "other wins = no bonus for owner")
