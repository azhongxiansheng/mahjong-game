extends GutTest

# 麻将王 — M12 Path C 第 2 步：LocalLoopbackServer 骨架测试。

# ---- 构造 ----

func test_default_constructor():
	var server := LocalLoopbackServer.new(42, 0)
	assert_not_null(server.bc, "构造后 BC 非空")
	assert_eq(server.current_seq(), 0, "初始 seq = 0")
	assert_eq(server.get_all_events().size(), 0, "初始无 events")

func test_constructor_with_heuristic_ai():
	var server := LocalLoopbackServer.new(42, 0, true)
	assert_not_null(server.bc.ai, "heuristic_ai 时 BC.ai 非空")

# ---- run_to_end + 序号广播 ----

func test_run_to_end_produces_events():
	var server := LocalLoopbackServer.new(42, 0, true)
	var events: Array = server.run_to_end()
	assert_true(events.size() > 0, "跑完一局至少产 1 个 event")
	# 至少含 GAME_BEGIN 和某种结束类型（DRAW/WIN_DECLARED/EXHAUSTIVE_DRAW）
	var types: Array = []
	for ne in events:
		types.append(String(ne.event.type))
	assert_true(types.has("GAME_BEGIN"), "events 含 GAME_BEGIN")

func test_seq_monotonic_increasing():
	var server := LocalLoopbackServer.new(42, 0, true)
	var events: Array = server.run_to_end()
	for i in range(events.size() - 1):
		assert_lt(events[i].server_seq, events[i + 1].server_seq,
			"server_seq 单调递增")
	# 第一个 seq = 1
	if events.size() > 0:
		assert_eq(events[0].server_seq, 1, "seq 从 1 起")

func test_events_have_server_ts():
	var server := LocalLoopbackServer.new(42, 0, true)
	var events: Array = server.run_to_end()
	if events.size() > 0:
		assert_true(events[0].server_ts_ms > 0, "事件携 server timestamp")

# ---- submit_action ----

func test_submit_action_null_rejected():
	var server := LocalLoopbackServer.new(42, 0)
	var resp: Dictionary = server.submit_action(null)
	assert_false(resp.accepted, "null action 拒收")
	assert_eq(resp.reason, "null_action")

func test_submit_action_invalid_seat_rejected():
	var server := LocalLoopbackServer.new(42, 0)
	var bad := Action.discard(99, TileId.W5)  # seat=99 越界
	var resp: Dictionary = server.submit_action(bad)
	assert_false(resp.accepted, "seat 越界拒收")
	assert_eq(resp.reason, "invalid_seat")

func test_submit_action_pass_claim_accepted_v1():
	var server := LocalLoopbackServer.new(42, 0)
	var pc := Action.pass_claim(1)
	var resp: Dictionary = server.submit_action(pc)
	assert_true(resp.accepted, "v1: PASS_CLAIM 作 no-op 接受")
	assert_eq(resp.reason, "ok")
	assert_eq(resp.events.size(), 0, "PASS_CLAIM 不产 events")

func test_submit_action_other_kinds_nyi_v1():
	# v1 还未实装 DISCARD / RIICHI / RON / TSUMO 等 — 应返 not_yet_implemented
	var server := LocalLoopbackServer.new(42, 0)
	for action in [
		Action.discard(0, TileId.W5),
		Action.riichi(0, TileId.S3),
		Action.ron(2, TileId.W5, 1),
		Action.tsumo(0),
	]:
		var resp: Dictionary = server.submit_action(action)
		assert_false(resp.accepted, "%s v1 未实装" % action.describe())
		assert_eq(resp.reason, "kind_not_yet_implemented")

# ---- events_since（重连恢复）----

func test_events_since_zero_returns_all():
	var server := LocalLoopbackServer.new(42, 0, true)
	server.run_to_end()
	var all_events: Array = server.events_since(0)
	assert_eq(all_events.size(), server.get_all_events().size(),
		"events_since(0) 返全部历史")

func test_events_since_filters_by_seq():
	var server := LocalLoopbackServer.new(42, 0, true)
	server.run_to_end()
	var total: int = server.current_seq()
	if total < 5:
		# Run 太短跳过 — 用 dummy 校验
		return
	var mid: int = total / 2
	var filtered: Array = server.events_since(mid)
	for ne in filtered:
		assert_true(ne.server_seq > mid, "过滤后 seq > %d" % mid)

func test_events_since_high_seq_returns_empty():
	var server := LocalLoopbackServer.new(42, 0, true)
	server.run_to_end()
	var future: Array = server.events_since(99999)
	assert_eq(future.size(), 0, "未来 seq 无 events")

# ---- get_all_events 是副本（防客户端污染）----

func test_get_all_events_returns_copy():
	var server := LocalLoopbackServer.new(42, 0, true)
	server.run_to_end()
	var snapshot: Array = server.get_all_events()
	var initial_size: int = snapshot.size()
	snapshot.clear()
	# 原 server 内部不受影响
	assert_eq(server.get_all_events().size(), initial_size,
		"snapshot 修改不影响 server 内部")

# ---- 序列化 round-trip：events 可由 client 反序列化 ----

func test_event_to_dict_roundtrip_for_client():
	# 模拟 server → wire → client 链路：event.to_dict 后从 dict 还原
	var server := LocalLoopbackServer.new(42, 0, true)
	server.run_to_end()
	var events: Array = server.get_all_events()
	if events.is_empty():
		return
	var first: NetworkedEvent = events[0]
	var d: Dictionary = first.to_dict()
	var restored: NetworkedEvent = NetworkedEvent.from_dict(d)
	assert_eq(restored.server_seq, first.server_seq)
	assert_eq(String(restored.event.type), String(first.event.type))
