extends GutTest

# US-007 Event UI 单测：选项应用 + 条件 gating + seed 决定性

const EVENT_SCN := preload("res://ui/run/event_node.tscn")

func _make_run_state(hp: int = 3, max_hp: int = 5, gold: int = 50) -> RunState:
	var rs := RunState.new(42)
	rs.hp = hp
	rs.max_hp = max_hp
	rs.gold = gold
	return rs

func test_apply_option_gold_delta():
	var rs := _make_run_state(3, 5, 50)
	var opt: Dictionary = {"label": "X", "hp_delta": 0, "gold_delta": 30}
	var ok: bool = EventNode.apply_option(opt, rs)
	assert_true(ok)
	assert_eq(rs.gold, 80)

func test_apply_option_hp_delta_clamped():
	var rs := _make_run_state(2, 5, 50)
	var opt: Dictionary = {"label": "X", "hp_delta": -1}
	EventNode.apply_option(opt, rs)
	assert_eq(rs.hp, 1)

func test_apply_option_full_heal_999():
	var rs := _make_run_state(1, 5, 50)
	var opt: Dictionary = {"label": "X", "hp_delta": 999}
	EventNode.apply_option(opt, rs)
	assert_eq(rs.hp, 5, "hp_delta=999 应满血")

func test_apply_option_gold_clamp_at_zero():
	var rs := _make_run_state(3, 5, 10)
	var opt: Dictionary = {"label": "X", "gold_delta": -50}
	EventNode.apply_option(opt, rs)
	assert_eq(rs.gold, 0, "gold 不可为负")

func test_can_apply_require_gold_blocks():
	var rs := _make_run_state(3, 5, 10)
	var opt: Dictionary = {"label": "X", "gold_delta": -30, "require_gold": 30}
	assert_false(EventNode.can_apply(opt, rs), "不够 gold 时 require_gold 阻塞")

func test_can_apply_require_gold_passes_when_enough():
	var rs := _make_run_state(3, 5, 50)
	var opt: Dictionary = {"label": "X", "gold_delta": -30, "require_gold": 30}
	assert_true(EventNode.can_apply(opt, rs))

func test_apply_option_blocked_returns_false():
	var rs := _make_run_state(3, 5, 10)
	var opt: Dictionary = {"label": "X", "gold_delta": -30, "require_gold": 30}
	var ok: bool = EventNode.apply_option(opt, rs)
	assert_false(ok)
	assert_eq(rs.gold, 10, "条件不满足时 RunState 不变")

func test_seed_determinism():
	var rs := _make_run_state()
	var ev1 = EVENT_SCN.instantiate()
	add_child_autofree(ev1)
	ev1.bind_run_state(rs)
	ev1.set_event_seed(123)
	var ev2 = EVENT_SCN.instantiate()
	add_child_autofree(ev2)
	ev2.bind_run_state(rs)
	ev2.set_event_seed(123)
	assert_eq(ev1._event_def.get("id"), ev2._event_def.get("id"),
		"同 seed 应抽到相同事件")
