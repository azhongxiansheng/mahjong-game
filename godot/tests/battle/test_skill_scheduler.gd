extends GutTest

const SpyHook := preload("res://tests/_fixtures/spy_hook.gd")

var _reg: SkillRegistry
var _state: BattleState
var _sched: SkillScheduler

func before_each() -> void:
	SpyHook.reset()
	_reg = SkillRegistry.new()
	_state = BattleState.new()
	_sched = SkillScheduler.new(_reg, _state)

func _make_skill(
	id: StringName,
	owner_triggers: Array,
	holder_triggers: Array = [],
	rarity: int = 0,
	is_ability: bool = false
) -> SkillResource:
	var s := SkillResource.new()
	s.id = id
	# Array[StringName] 转换 — Array literal 推导为 Array,需手工转
	var ot: Array[StringName] = []
	for x in owner_triggers: ot.append(x)
	var ht: Array[StringName] = []
	for x in holder_triggers: ht.append(x)
	s.owner_triggers = ot
	s.holder_triggers = ht
	s.rarity = rarity
	s.is_ability = is_ability
	s.hook_script = SpyHook
	return s

func _attach_tile(skill: SkillResource, owner_seat: int, holder_seat: int = -1) -> TileInstance:
	var ti := TileInstance.make(Tile.new(TileId.W5), owner_seat, skill)
	ti.holder_seat = holder_seat
	return ti

# ---- 排序(6) ----

func test_owner_group_fires_before_holder_group():
	# 同一个 tile,既有 owner_trigger 又有 holder_trigger → 收集 2 项,owner 先
	var sk_o := _make_skill(&"o", [&"WIN_DECLARED"])
	var sk_h := _make_skill(&"h", [], [&"WIN_DECLARED"])
	var ti_o := _attach_tile(sk_o, 0, 0)
	var ti_h := _attach_tile(sk_h, 1, 1)
	_reg.register(sk_o, ti_o)
	_reg.register(sk_h, ti_h)
	_sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 0))
	assert_eq(SpyHook.trace.size(), 2)
	assert_eq(SpyHook.trace[0].skill_id, &"o", "owner 组在前")
	assert_eq(SpyHook.trace[1].skill_id, &"h")

func test_higher_rarity_fires_before_lower_within_owner_group():
	var sk_low := _make_skill(&"low", [&"WIN_DECLARED"], [], 0)
	var sk_high := _make_skill(&"high", [&"WIN_DECLARED"], [], 3)
	_reg.register(sk_low, _attach_tile(sk_low, 0))
	_reg.register(sk_high, _attach_tile(sk_high, 0))
	_sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 0))
	assert_eq(SpyHook.trace[0].skill_id, &"high")
	assert_eq(SpyHook.trace[1].skill_id, &"low")

func test_registration_order_tiebreak_within_same_rarity():
	var sk_a := _make_skill(&"a", [&"WIN_DECLARED"], [], 1)
	var sk_b := _make_skill(&"b", [&"WIN_DECLARED"], [], 1)
	_reg.register(sk_a, _attach_tile(sk_a, 0))
	_reg.register(sk_b, _attach_tile(sk_b, 0))
	_sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 0))
	assert_eq(SpyHook.trace[0].skill_id, &"a", "先注册者先")
	assert_eq(SpyHook.trace[1].skill_id, &"b")

func test_ability_fires_in_owner_group_slot():
	# ability 应进 owner 组(group=0),普通 holder 在后
	var ab := _make_skill(&"ab", [&"WIN_DECLARED"], [], 0, true)
	var sk_h := _make_skill(&"h", [], [&"WIN_DECLARED"])
	_reg.register(ab, 0)
	_reg.register(sk_h, _attach_tile(sk_h, 1, 1))
	_sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 0))
	assert_eq(SpyHook.trace[0].skill_id, &"ab")
	assert_eq(SpyHook.trace[1].skill_id, &"h")

func test_holder_group_sorted_by_rarity_desc():
	var sk_low := _make_skill(&"hlow", [], [&"WIN_DECLARED"], 1)
	var sk_high := _make_skill(&"hhigh", [], [&"WIN_DECLARED"], 3)
	_reg.register(sk_low, _attach_tile(sk_low, 0, 0))
	_reg.register(sk_high, _attach_tile(sk_high, 0, 0))
	_sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 0))
	assert_eq(SpyHook.trace[0].skill_id, &"hhigh")

func test_holder_group_reg_order_tiebreak_within_same_rarity():
	# 同 rarity 的 holder 组按注册顺序稳定排序。
	var sk_a := _make_skill(&"ha", [], [&"WIN_DECLARED"], 1)
	var sk_b := _make_skill(&"hb", [], [&"WIN_DECLARED"], 1)
	_reg.register(sk_a, _attach_tile(sk_a, 0, 0))
	_reg.register(sk_b, _attach_tile(sk_b, 0, 0))
	_sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 0))
	assert_eq(SpyHook.trace[0].skill_id, &"ha", "holder 组同 rarity 先注册者先")
	assert_eq(SpyHook.trace[1].skill_id, &"hb")

func test_ability_and_normal_owner_sort_by_rarity_then_reg_order():
	# ability 与普通 owner 牌技能均落入 group=0；先按 rarity 降序，再按 reg_order。
	# 注册：rarity=2 ability 'ab2' / rarity=3 owner 'on3' / rarity=2 owner 'on2'
	# 期望顺序：on3(高 rarity 先) → ab2(同 rarity 先注册) → on2(同 rarity 后注册)
	var ab2 := _make_skill(&"ab2", [&"WIN_DECLARED"], [], 2, true)
	var on3 := _make_skill(&"on3", [&"WIN_DECLARED"], [], 3)
	var on2 := _make_skill(&"on2", [&"WIN_DECLARED"], [], 2)
	_reg.register(ab2, 0)
	_reg.register(on3, _attach_tile(on3, 0))
	_reg.register(on2, _attach_tile(on2, 0))
	_sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 0))
	assert_eq(SpyHook.trace.size(), 3)
	assert_eq(SpyHook.trace[0].skill_id, &"on3", "rarity=3 最先")
	assert_eq(SpyHook.trace[1].skill_id, &"ab2", "rarity=2 同分先注册的 ability")
	assert_eq(SpyHook.trace[2].skill_id, &"on2", "rarity=2 后注册的普通牌")

func test_empty_registry_emit_does_not_error():
	_sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 0))
	assert_eq(SpyHook.trace.size(), 0)
	assert_eq(_state.event_chain_depth, 0)

# ---- 链深度(4) ----

func test_chain_depth_increments_during_dispatch():
	var sk := _make_skill(&"x", [&"WIN_DECLARED"])
	_reg.register(sk, _attach_tile(sk, 0))
	_sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 0))
	assert_eq(SpyHook.trace[0].depth_seen, 1, "派发期间 depth=1")

func test_chain_depth_decrements_after_dispatch():
	var sk := _make_skill(&"x", [&"WIN_DECLARED"])
	_reg.register(sk, _attach_tile(sk, 0))
	_sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 0))
	assert_eq(_state.event_chain_depth, 0)

func test_chain_depth_15_to_16_runs_normally():
	_state.event_chain_depth = 15
	var sk := _make_skill(&"x", [&"WIN_DECLARED"])
	_reg.register(sk, _attach_tile(sk, 0))
	_sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 0))
	assert_eq(SpyHook.trace.size(), 1, "depth 升至 16 仍允许")
	assert_eq(_state.event_chain_depth, 15)

func test_chain_depth_overflow_aborts_remaining_skills():
	_state.event_chain_depth = 16
	var sk := _make_skill(&"x", [&"WIN_DECLARED"])
	_reg.register(sk, _attach_tile(sk, 0))
	_sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 0))
	assert_eq(SpyHook.trace.size(), 0, "depth>16 时不派发")
	assert_eq(_state.event_chain_depth, 16, "depth 不应被本次 emit 永久污染")

# ---- 静默(3) ----

func test_throwing_hook_does_not_stop_next_skill():
	var sk_a := _make_skill(&"a", [&"WIN_DECLARED"], [], 1)
	var sk_b := _make_skill(&"b", [&"WIN_DECLARED"], [], 0)
	SpyHook.error_on_skill_ids = [&"a"]
	_reg.register(sk_a, _attach_tile(sk_a, 0))
	_reg.register(sk_b, _attach_tile(sk_b, 0))
	_sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 0))
	assert_eq(SpyHook.trace.size(), 2, "前一个错误不影响后一个")

func test_throwing_hook_does_not_corrupt_chain_depth():
	var sk := _make_skill(&"a", [&"WIN_DECLARED"])
	SpyHook.error_on_skill_ids = [&"a"]
	_reg.register(sk, _attach_tile(sk, 0))
	_sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 0))
	assert_eq(_state.event_chain_depth, 0)

func test_skill_with_null_hook_script_skipped_gracefully():
	var sk := SkillResource.new()
	sk.id = &"no_hook"
	var ot: Array[StringName] = [&"WIN_DECLARED"]
	sk.owner_triggers = ot
	# 不设 hook_script
	_reg.register(sk, _attach_tile(sk, 0))
	# 不应崩溃
	_sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 0))
	assert_eq(SpyHook.trace.size(), 0)
	assert_eq(_state.event_chain_depth, 0)

# ---- 过滤(4) ----

func test_owner_trigger_does_not_fire_for_wrong_event():
	var sk := _make_skill(&"a", [&"WIN_DECLARED"])
	_reg.register(sk, _attach_tile(sk, 0))
	_sched.emit_event(BattleEvent.make(&"TILE_DRAWN", 0))
	assert_eq(SpyHook.trace.size(), 0)

func test_holder_trigger_does_not_fire_when_holder_seat_unset():
	var sk := _make_skill(&"a", [], [&"WIN_DECLARED"])
	_reg.register(sk, _attach_tile(sk, 0, -1))
	_sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 0))
	assert_eq(SpyHook.trace.size(), 0, "holder_seat=-1 不触发 holder 组")

func test_holder_trigger_fires_when_holder_seat_set():
	var sk := _make_skill(&"a", [], [&"WIN_DECLARED"])
	_reg.register(sk, _attach_tile(sk, 0, 2))
	_sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 0))
	assert_eq(SpyHook.trace.size(), 1)

func test_skill_with_no_matching_triggers_never_fires():
	var sk := _make_skill(&"empty", [], [])
	_reg.register(sk, _attach_tile(sk, 0))
	_sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 0))
	assert_eq(SpyHook.trace.size(), 0)

# ---- ability dedup(3) ----

func test_ability_with_both_owner_and_holder_triggers_fires_once():
	var ab := _make_skill(&"ab", [&"WIN_DECLARED"], [&"WIN_DECLARED"], 0, true)
	_reg.register(ab, 0)
	_sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 0))
	assert_eq(SpyHook.trace.size(), 1, "ability 两组 trigger 共触发 1 次")

func test_two_different_abilities_each_fire_once():
	var a1 := _make_skill(&"a1", [&"WIN_DECLARED"], [&"WIN_DECLARED"], 0, true)
	var a2 := _make_skill(&"a2", [&"WIN_DECLARED"], [&"WIN_DECLARED"], 0, true)
	_reg.register(a1, 0)
	_reg.register(a2, 1)
	_sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 0))
	assert_eq(SpyHook.trace.size(), 2)

func test_consumed_skill_does_not_fire():
	var sk := _make_skill(&"a", [&"WIN_DECLARED"])
	sk.consumed = true
	_reg.register(sk, _attach_tile(sk, 0))
	_sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 0))
	assert_eq(SpyHook.trace.size(), 0, "consumed=true 跳过")
