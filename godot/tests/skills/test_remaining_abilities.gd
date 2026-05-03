extends GutTest

# 麻将王 — M6 内容生产：§8.10 角色能力剩余 8 张单测

const MineuOniHook := preload("res://skills/hooks/mineu_no_oni_hook.gd")
const SanKyokuHook := preload("res://skills/hooks/san_kyoku_kiseki_hook.gd")
const IsshunHook := preload("res://skills/hooks/isshun_senken_hook.gd")
const YamaganHook := preload("res://skills/hooks/yamagan_hook.gd")
const TenpaiSeeHook := preload("res://skills/hooks/tenpai_seethru_hook.gd")
const RyukyokuHook := preload("res://skills/hooks/ryukyoku_yudou_hook.gd")
const TousotsuHook := preload("res://skills/hooks/tousotsu_hook.gd")
const RiichiKagoHook := preload("res://skills/hooks/riichi_kago_hook.gd")

func _setup() -> Array:
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	return [reg, st, sched]

func _make_ability(id: StringName, hook: GDScript, triggers: Array, rarity: int = Rarity.Kind.LEGENDARY) -> SkillResource:
	var s := SkillResource.new()
	s.id = id
	s.rarity = rarity
	s.is_ability = true
	var ot: Array[StringName] = []
	for t in triggers:
		ot.append(t)
	s.owner_triggers = ot
	s.hook_script = hook
	return s

# ---- mineu_no_oni ----

func test_mineu_no_oni_adds_3_han_on_self_win():
	# balance tune-1：mineu_oni_han_bonus 2 → 3
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var ab := _make_ability(&"mineu_no_oni_v1", MineuOniHook, [&"WIN_DECLARED"])
	reg.register(ab, 0)
	var out := sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 0))
	assert_eq(int(out.han_deltas.get(0, 0)), 3)

func test_mineu_no_oni_no_effect_for_other_seat():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var ab := _make_ability(&"mineu_no_oni_v1", MineuOniHook, [&"WIN_DECLARED"])
	reg.register(ab, 0)
	var out := sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 2))
	assert_eq(int(out.han_deltas.get(0, 0)), 0)

# ---- san_kyoku_kiseki ----

func test_san_kyoku_kiseki_adds_1_han_on_self_win():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var ab := _make_ability(&"san_kyoku_kiseki_v1", SanKyokuHook, [&"WIN_DECLARED"])
	reg.register(ab, 1)
	var out := sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 1))
	assert_eq(int(out.han_deltas.get(1, 0)), 1)

# ---- isshun_senken ----

func test_isshun_senken_reveals_on_owner_draw():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var st: BattleState = ctx[1]
	var sched: SkillScheduler = ctx[2]
	var ab := _make_ability(&"isshun_senken_v1", IsshunHook, [&"DRAW"])
	reg.register(ab, 2)
	sched.emit_event(BattleEvent.make(&"DRAW", 2))
	assert_eq(st.revealed_tiles.size(), 1)
	assert_eq(int(st.revealed_tiles[0].visible_to[0]), 2)

func test_isshun_senken_no_reveal_on_other_seat_draw():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var st: BattleState = ctx[1]
	var sched: SkillScheduler = ctx[2]
	var ab := _make_ability(&"isshun_senken_v1", IsshunHook, [&"DRAW"])
	reg.register(ab, 2)
	sched.emit_event(BattleEvent.make(&"DRAW", 1))
	assert_eq(st.revealed_tiles.size(), 0)

# ---- yamagan ----

func test_yamagan_reveals_on_game_begin():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var st: BattleState = ctx[1]
	var sched: SkillScheduler = ctx[2]
	var ab := _make_ability(&"yamagan_v1", YamaganHook, [&"GAME_BEGIN"], Rarity.Kind.EPIC)
	reg.register(ab, 0)
	sched.emit_event(BattleEvent.make(&"GAME_BEGIN", 0))
	assert_eq(st.revealed_tiles.size(), 1)
	assert_eq(int(st.revealed_tiles[0].visible_to[0]), 0)

# ---- tenpai_seethru ----

func test_tenpai_seethru_reveals_when_opponent_hand_formed():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var st: BattleState = ctx[1]
	var sched: SkillScheduler = ctx[2]
	var ab := _make_ability(&"tenpai_seethru_v1", TenpaiSeeHook, [&"HAND_FORMED"], Rarity.Kind.EPIC)
	reg.register(ab, 0)
	sched.emit_event(BattleEvent.make(&"HAND_FORMED", 2))
	assert_eq(st.revealed_tiles.size(), 1)
	assert_eq(int(st.revealed_tiles[0].visible_to[0]), 0, "owner 看到对手听牌占位")

func test_tenpai_seethru_no_reveal_for_self_hand_formed():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var st: BattleState = ctx[1]
	var sched: SkillScheduler = ctx[2]
	var ab := _make_ability(&"tenpai_seethru_v1", TenpaiSeeHook, [&"HAND_FORMED"], Rarity.Kind.EPIC)
	reg.register(ab, 0)
	sched.emit_event(BattleEvent.make(&"HAND_FORMED", 0))
	assert_eq(st.revealed_tiles.size(), 0, "自家听牌不需 reveal")

# ---- ryukyoku_yudou ----

func test_ryukyoku_yudou_adds_1_han_on_self_win():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var ab := _make_ability(&"ryukyoku_yudou_v1", RyukyokuHook, [&"WIN_DECLARED"], Rarity.Kind.EPIC)
	reg.register(ab, 3)
	var out := sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 3))
	assert_eq(int(out.han_deltas.get(3, 0)), 1)

# ---- tousotsu ----

func test_tousotsu_adds_1_han_on_self_win():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var ab := _make_ability(&"tousotsu_v1", TousotsuHook, [&"WIN_DECLARED"], Rarity.Kind.EPIC)
	reg.register(ab, 1)
	var out := sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 1))
	assert_eq(int(out.han_deltas.get(1, 0)), 1)

# ---- riichi_kago ----

func test_riichi_kago_adds_1_han_on_self_win():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var ab := _make_ability(&"riichi_kago_v1", RiichiKagoHook, [&"WIN_DECLARED"], Rarity.Kind.EPIC)
	reg.register(ab, 2)
	var out := sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 2))
	assert_eq(int(out.han_deltas.get(2, 0)), 1)

# ---- pool 注册 ----

func test_all_8_abilities_registered_in_pool():
	var ids: Array = []
	for a in CardPool.all_abilities():
		ids.append(a.id)
	for needed in [&"mineu_no_oni_v1", &"san_kyoku_kiseki_v1", &"isshun_senken_v1",
				   &"yamagan_v1", &"tenpai_seethru_v1", &"ryukyoku_yudou_v1",
				   &"tousotsu_v1", &"riichi_kago_v1"]:
		assert_true(ids.has(needed), "%s 应注册" % needed)
