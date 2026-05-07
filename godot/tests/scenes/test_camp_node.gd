extends GutTest

# US-005 Camp UI 单测：HP heal 逻辑

const CAMP_SCN := preload("res://ui/run/camp_node.tscn")

func _make_run_state(hp: int = 3, max_hp: int = 5) -> RunState:
	var rs := RunState.new(42)
	rs.hp = hp
	rs.max_hp = max_hp
	return rs

func test_apply_heal_increments_by_amount():
	var rs := _make_run_state(3, 5)
	var camp = CAMP_SCN.instantiate()
	add_child_autofree(camp)
	camp.bind_run_state(rs)
	var healed: int = camp.apply_heal()
	assert_eq(healed, 1, "应恢复 1 HP")
	assert_eq(rs.hp, 4, "HP 应从 3 → 4")

func test_apply_heal_caps_at_max_hp():
	var rs := _make_run_state(5, 5)
	var camp = CAMP_SCN.instantiate()
	add_child_autofree(camp)
	camp.bind_run_state(rs)
	var healed: int = camp.apply_heal()
	assert_eq(healed, 0, "HP 已满时应返回 0")
	assert_eq(rs.hp, 5)

func test_apply_heal_only_once():
	var rs := _make_run_state(3, 5)
	var camp = CAMP_SCN.instantiate()
	add_child_autofree(camp)
	camp.bind_run_state(rs)
	camp.apply_heal()
	var second: int = camp.apply_heal()
	assert_eq(second, 0, "二次调用应返回 0（已使用）")
	assert_eq(rs.hp, 4, "HP 应仍为 4")

func test_apply_heal_without_run_state():
	var camp = CAMP_SCN.instantiate()
	add_child_autofree(camp)
	# 未 bind_run_state
	var healed: int = camp.apply_heal()
	assert_eq(healed, 0, "无 run_state 应返回 0 不崩")

func test_done_signal_emitted_on_leave():
	var rs := _make_run_state(3, 5)
	var camp = CAMP_SCN.instantiate()
	add_child_autofree(camp)
	camp.bind_run_state(rs)
	watch_signals(camp)
	camp._on_leave_pressed()
	assert_signal_emitted(camp, "done")
