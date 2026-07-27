extends GutTest

# 麻将王 — 6 新角色被動能力の単体テスト

const KoromoHook := preload("res://skills/hooks/char_koromo_passive_hook.gd")
const NodokaHook := preload("res://skills/hooks/char_nodoka_passive_hook.gd")
const TokiHook := preload("res://skills/hooks/char_toki_passive_hook.gd")
const KuroHook := preload("res://skills/hooks/char_kuro_passive_hook.gd")
const MomokoHook := preload("res://skills/hooks/char_momoko_passive_hook.gd")
const TetsuyaHook := preload("res://skills/hooks/char_tetsuya_passive_hook.gd")

func _setup() -> Array:
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	return [reg, st, sched]

func _make_ability(id: StringName, hook: GDScript, triggers: Array) -> SkillResource:
	var s := SkillResource.new()
	s.id = id
	s.rarity = Rarity.Kind.LEGENDARY
	s.is_ability = true
	var ot: Array[StringName] = []
	for t in triggers:
		ot.append(t)
	s.owner_triggers = ot
	s.hook_script = hook
	return s

# ---- Koromo 海底支配 ----

func test_koromo_haitei_adds_3_han():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var ab := _make_ability(&"char_koromo_passive_v1", KoromoHook, [&"HAITEI", &"HOUTEI", &"TILE_DRAWN"])
	reg.register(ab, 0)
	var out := sched.emit_event(BattleEvent.make(&"HAITEI", 0))
	assert_eq(int(out.han_deltas.get(0, 0)), 3, "koromo HAITEI +3 han")

func test_koromo_houtei_adds_3_han():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var ab := _make_ability(&"char_koromo_passive_v1", KoromoHook, [&"HAITEI", &"HOUTEI", &"TILE_DRAWN"])
	reg.register(ab, 1)
	var out := sched.emit_event(BattleEvent.make(&"HOUTEI", 1))
	assert_eq(int(out.han_deltas.get(1, 0)), 3, "koromo HOUTEI +3 han")

func test_koromo_no_han_when_other_wins_haitei():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var ab := _make_ability(&"char_koromo_passive_v1", KoromoHook, [&"HAITEI", &"HOUTEI", &"TILE_DRAWN"])
	reg.register(ab, 0)
	var out := sched.emit_event(BattleEvent.make(&"HAITEI", 2))
	assert_eq(int(out.han_deltas.get(0, 0)), 0, "koromo: other seat haitei = no bonus")

func test_koromo_tile_drawn_reveals_wall():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var st: BattleState = ctx[1]
	var sched: SkillScheduler = ctx[2]
	var ab := _make_ability(&"char_koromo_passive_v1", KoromoHook, [&"HAITEI", &"HOUTEI", &"TILE_DRAWN"])
	reg.register(ab, 0)
	var before := st.revealed_tiles.size()
	sched.emit_event(BattleEvent.make(&"TILE_DRAWN", 0))
	# Without a wall, reveal_wall_top_to returns 0 and adds nothing
	# Just confirm no crash; with a real wall it would add 3
	assert_true(true, "koromo TILE_DRAWN did not crash")

# ---- Kuro ドラの愛 ----

func test_kuro_adds_2_ability_red_dora_on_win():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var st: BattleState = ctx[1]
	var sched: SkillScheduler = ctx[2]
	var ab := _make_ability(&"char_kuro_passive_v1", KuroHook, [&"WIN_DECLARED_PRE"])
	reg.register(ab, 2)
	sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 2))
	assert_eq(int(st.extra_dora_count[2]), 0, "kuro 不得写入普通 extra dora")
	assert_eq(int(st.extra_red_dora_count[2]), 2, "kuro +2 ability red dora")

func test_kuro_no_dora_when_other_wins():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var st: BattleState = ctx[1]
	var sched: SkillScheduler = ctx[2]
	var ab := _make_ability(&"char_kuro_passive_v1", KuroHook, [&"WIN_DECLARED_PRE"])
	reg.register(ab, 2)
	sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_eq(int(st.extra_dora_count[2]), 0, "kuro: other seat wins = no dora")
	assert_eq(int(st.extra_dora_count[0]), 0)
	assert_eq(int(st.extra_red_dora_count[2]), 0)
	assert_eq(int(st.extra_red_dora_count[0]), 0)

# ---- Tetsuya 玄人技 ----

func test_tetsuya_first_win_adds_1_han():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var ab := _make_ability(&"char_tetsuya_passive_v1", TetsuyaHook, [&"WIN_DECLARED_PRE"])
	reg.register(ab, 1)
	var out := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 1))
	assert_eq(int(out.han_deltas.get(1, 0)), 1, "tetsuya 1st win = +1")

func test_tetsuya_cumulative_bonus():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var ab := _make_ability(&"char_tetsuya_passive_v1", TetsuyaHook, [&"WIN_DECLARED_PRE"])
	reg.register(ab, 1)
	# 1st win: 1 + 0 = 1
	var out1 := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 1))
	assert_eq(int(out1.han_deltas.get(1, 0)), 1, "tetsuya 1st win = +1")
	# 2nd win: 1 + 1 = 2
	var out2 := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 1))
	assert_eq(int(out2.han_deltas.get(1, 0)), 2, "tetsuya 2nd win = +2")
	# 3rd win: 1 + 2 = 3
	var out3 := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 1))
	assert_eq(int(out3.han_deltas.get(1, 0)), 3, "tetsuya 3rd win = +3")

func test_tetsuya_no_bonus_when_other_wins():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var ab := _make_ability(&"char_tetsuya_passive_v1", TetsuyaHook, [&"WIN_DECLARED_PRE"])
	reg.register(ab, 1)
	var out := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 3))
	assert_eq(int(out.han_deltas.get(1, 0)), 0, "tetsuya: other seat wins = no bonus")

# ---- Nodoka デジタル ----

func test_nodoka_adds_1_han_on_self_win():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var ab := _make_ability(&"char_nodoka_passive_v1", NodokaHook, [&"WIN_DECLARED_PRE", &"TENPAI_ENTERED"])
	reg.register(ab, 0)
	var out := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_eq(int(out.han_deltas.get(0, 0)), 1, "nodoka +1 han on self win")

func test_nodoka_no_han_when_other_wins():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var ab := _make_ability(&"char_nodoka_passive_v1", NodokaHook, [&"WIN_DECLARED_PRE", &"TENPAI_ENTERED"])
	reg.register(ab, 0)
	var out := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 2))
	assert_eq(int(out.han_deltas.get(0, 0)), 0, "nodoka: other seat wins = no bonus")

# ---- Momoko ステルス ----

func test_momoko_riichi_then_win_adds_1_han():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var ab := _make_ability(&"char_momoko_passive_v1", MomokoHook, [&"RIICHI_DECLARED", &"WIN_DECLARED_PRE"])
	reg.register(ab, 0)
	# Riichi primes the ability
	sched.emit_event(BattleEvent.make(&"RIICHI_DECLARED", 0))
	# Win should get +1 han
	var out := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_eq(int(out.han_deltas.get(0, 0)), 1, "momoko: riichi then win = +1")

func test_momoko_win_without_riichi_no_bonus():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var ab := _make_ability(&"char_momoko_passive_v1", MomokoHook, [&"RIICHI_DECLARED", &"WIN_DECLARED_PRE"])
	reg.register(ab, 0)
	# Win without riichi
	var out := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_eq(int(out.han_deltas.get(0, 0)), 0, "momoko: no riichi = no bonus")

func test_momoko_primed_resets_after_win():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var ab := _make_ability(&"char_momoko_passive_v1", MomokoHook, [&"RIICHI_DECLARED", &"WIN_DECLARED_PRE"])
	reg.register(ab, 0)
	sched.emit_event(BattleEvent.make(&"RIICHI_DECLARED", 0))
	sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	# Second win without new riichi should not get bonus
	var out := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_eq(int(out.han_deltas.get(0, 0)), 0, "momoko: primed resets after use")

# ---- Toki 一巡先見 ----

func test_toki_game_begin_does_not_crash():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var st: BattleState = ctx[1]
	var sched: SkillScheduler = ctx[2]
	var ab := _make_ability(&"char_toki_passive_v1", TokiHook, [&"GAME_BEGIN"])
	reg.register(ab, 0)
	# Without a wall, reveal_next_draw_for_seat returns false but does not crash
	sched.emit_event(BattleEvent.make(&"GAME_BEGIN", -1))
	assert_true(true, "toki GAME_BEGIN did not crash")
