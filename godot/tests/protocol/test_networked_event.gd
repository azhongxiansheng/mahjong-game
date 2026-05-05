extends GutTest

# 麻将王 — M12 Path C 第 1 步：NetworkedEvent 协议数据类型测试。

func test_wrap_helper_sets_seq_and_event():
	var be := BattleEvent.make(&"TILE_DISCARDED", 0, null, {"x": 1})
	var ne := NetworkedEvent.wrap(be, 42, 17, 1234567890)
	assert_eq(ne.server_seq, 42)
	assert_eq(ne.causing_action_id, 17)
	assert_eq(ne.server_ts_ms, 1234567890)
	assert_same(ne.event, be)

func test_wrap_default_optional_args():
	var be := BattleEvent.make(&"TILE_DRAWN", 0, null, {})
	var ne := NetworkedEvent.wrap(be, 1)
	assert_eq(ne.server_seq, 1)
	assert_eq(ne.causing_action_id, 0)
	assert_eq(ne.server_ts_ms, 0)

# ---- 序列化 ----

func test_to_from_dict_roundtrip():
	var be := BattleEvent.make(&"WIN_DECLARED", 0, null, {"han": 3, "fu": 30})
	var ne := NetworkedEvent.wrap(be, 100, 5, 9999)
	var d: Dictionary = ne.to_dict()
	var ne2: NetworkedEvent = NetworkedEvent.from_dict(d)
	assert_eq(ne2.server_seq, 100)
	assert_eq(ne2.causing_action_id, 5)
	assert_eq(ne2.server_ts_ms, 9999)
	assert_not_null(ne2.event)
	assert_eq(String(ne2.event.type), "WIN_DECLARED")
	assert_eq(int(ne2.event.extra["han"]), 3)

func test_from_dict_empty_returns_null():
	assert_null(NetworkedEvent.from_dict({}))

func test_seq_monotonic_simulation():
	# 模拟 server 端连续 emit 多个 events，seq 单调递增
	var seq_counter: int = 0
	var events: Array = []
	for kind in [&"TILE_DRAWN", &"TILE_DISCARDED", &"WIN_DECLARED"]:
		seq_counter += 1
		var be := BattleEvent.make(kind, 0, null, {})
		events.append(NetworkedEvent.wrap(be, seq_counter))
	for i in range(events.size() - 1):
		assert_lt(events[i].server_seq, events[i + 1].server_seq, "seq 单调递增")

func test_describe_handles_null_event():
	var ne := NetworkedEvent.new()
	ne.server_seq = 99
	# event 是 null
	var s: String = ne.describe()
	assert_true(s.contains("seq=99"), "describe 含 seq")
	assert_true(s.contains("<null>"), "describe 处理 null event")

func test_describe_includes_event_type():
	var be := BattleEvent.make(&"TILE_DISCARDED", 2, null, {})
	var ne := NetworkedEvent.wrap(be, 7, 0)
	var s: String = ne.describe()
	assert_true(s.contains("TILE_DISCARDED"), "describe 含 event type")
	assert_true(s.contains("actor=2"), "describe 含 actor")
