extends GutTest

# 麻将王 — M5 第 2 步：SaveSystem 真持久化单测（替 M4 占位测）

func _save_system() -> Node:
	return get_tree().root.get_node_or_null("SaveSystem")

func before_each() -> void:
	# 每个测试用例开头清理可能残留的存档
	var ss := _save_system()
	if ss:
		ss.clear_run()

func after_each() -> void:
	# 收尾也清理，避免测试间相互污染
	var ss := _save_system()
	if ss:
		ss.clear_run()

func test_save_system_is_autoload():
	assert_not_null(_save_system())

func test_has_save_starts_false():
	assert_false(_save_system().has_save())

func test_save_run_null_returns_invalid_param():
	var r: int = _save_system().save_run(null)
	assert_eq(r, ERR_INVALID_PARAMETER)

# ---- M8 Step 5: SAVE_VERSION 2 + v1 migration ----

func test_save_version_is_2():
	# M8: 升 SAVE_VERSION 表 NodeRef.session_kind 字段加入
	assert_eq(RunState.SAVE_VERSION, 2, "M8 SAVE_VERSION = 2")

func test_load_v1_dict_migrates_to_v2_with_east_round_default():
	# 模拟 M7 旧档（version=1, 无 session_kind 字段）
	var v1_dict := {
		"version": 1,
		"hp": 4,
		"max_hp": 5,
		"gold": 50,
		"chapter": 2,
		"run_seed": 42,
		"current_map": null,
		"history": [
			{"index": 0, "floor_index": 0, "kind": NodeKind.Kind.NORMAL},
			{"index": 1, "floor_index": 1, "kind": NodeKind.Kind.ELITE},
		],
		"deck": {},
		"player_deck": {},
		"pity_state": {},
		"consumables": [],
		"finished": false,
		"won": false,
	}
	var rs: RunState = RunState.from_dict(v1_dict)
	assert_not_null(rs, "v1 存档应被接受（migration）")
	assert_eq(rs.hp, 4)
	assert_eq(rs.chapter, 2)
	assert_eq(rs.history.size(), 2)
	for n in rs.history:
		assert_eq(n.session_kind, "east_round",
			"v1 history NodeRef session_kind 默认 east_round")

func test_load_v2_dict_roundtrip_preserves_session_kind():
	var rs := RunState.new(42)
	var n := NodeRef.new(7, 3, NodeKind.Kind.BOSS, {}, "hanchan")
	rs.history.append(n)
	var d: Dictionary = rs.to_dict()
	assert_eq(int(d.version), 2, "v2 写出")
	var rs2: RunState = RunState.from_dict(d)
	assert_not_null(rs2)
	assert_eq(rs2.history.size(), 1)
	assert_eq(rs2.history[0].session_kind, "hanchan",
		"v2 hanchan session_kind roundtrip")

func test_load_unknown_future_version_returns_null():
	# 未来版本（v3+）当前代码看不懂 → 安全返 null
	var v99_dict := {"version": 99, "hp": 5}
	assert_null(RunState.from_dict(v99_dict),
		"未来版本不应误读")

func test_save_run_creates_file():
	var rs := RunState.new(42)
	rs.gold = 100
	rs.hp = 3
	var r: int = _save_system().save_run(rs)
	assert_eq(r, OK)
	assert_true(_save_system().has_save())

func test_load_run_returns_null_when_no_save():
	assert_null(_save_system().load_run())

func test_save_load_roundtrip_preserves_basic_fields():
	var rs := RunState.new(42)
	rs.gold = 87
	rs.hp = 2
	rs.chapter = 2
	# 模拟已访问 1 个节点
	rs.history.append(NodeRef.new(0, 0, NodeKind.Kind.NORMAL))
	var ss := _save_system()
	assert_eq(ss.save_run(rs), OK)
	var loaded = ss.load_run()
	assert_not_null(loaded)
	assert_eq(loaded.gold, 87)
	assert_eq(loaded.hp, 2)
	assert_eq(loaded.chapter, 2)
	assert_eq(loaded.run_seed, 42)
	assert_eq(loaded.history.size(), 1)

func test_save_load_roundtrip_preserves_chapter_map_state():
	var rs := RunState.new(42)
	# advance to entry 后 current_node 应保留
	rs.choose_next_node(rs.current_map.entry_node)
	var entry_idx: int = rs.current_map.current_node
	var ss := _save_system()
	ss.save_run(rs)
	var loaded = ss.load_run()
	assert_not_null(loaded.current_map)
	assert_eq(loaded.current_map.current_node, entry_idx, "current_node 跨 save 保留")
	assert_eq(loaded.current_map.node_count(), rs.current_map.node_count())

func test_save_load_preserves_finished_won():
	var rs := RunState.new(42)
	rs.finished = true
	rs.won = true
	var ss := _save_system()
	ss.save_run(rs)
	var loaded = ss.load_run()
	assert_true(loaded.finished)
	assert_true(loaded.won)

func test_clear_run_removes_file():
	var rs := RunState.new(42)
	var ss := _save_system()
	ss.save_run(rs)
	assert_true(ss.has_save())
	ss.clear_run()
	assert_false(ss.has_save())

func test_clear_run_no_save_is_safe():
	# 没存档时 clear 不抛错
	_save_system().clear_run()
	assert_false(_save_system().has_save())

func test_save_run_overwrite():
	var rs1 := RunState.new(42)
	rs1.gold = 50
	var ss := _save_system()
	ss.save_run(rs1)

	var rs2 := RunState.new(42)
	rs2.gold = 200
	ss.save_run(rs2)

	var loaded = ss.load_run()
	assert_eq(loaded.gold, 200, "后存档应覆盖前者")
