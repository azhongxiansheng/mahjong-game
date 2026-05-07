extends GutTest

# 麻将王 — M12 端到端集成测：LocalLoopbackServer + PLAYER_ACTION + Replay
#
# 闭环 spec §4.3 的 server-authoritative + client-mirror 架构：
#
#   Server side                     Client side
#   ─────────                       ─────────
#   LocalLoopbackServer.new(seed)
#   server.run_to_end()
#     → emits NetworkedEvents
#     → wraps BC.events，含 PLAYER_ACTION                   ← #131 引入
#                                   ↓
#                           extract_player_actions(events)  ← #131 静态 helper
#                                   ↓
#                           BC.new(same seed)
#                           bc.set_replay_decisions(actions)
#                           bc.run_to_end()
#                                   ↓
#                           assert bc.state.snapshot_hash()
#                                  == server.bc.state.snapshot_hash()  ✅
#
# 这是 M12 alpha 收尾的硬证：把 #127 (protocol) + #129 (server) + #131 (PLAYER_ACTION
# + snapshot_hash + Replay) 三层独立增量拼成一条 client→server 通路。
#
# 不在本测覆盖（留 M13+）：
# - 真网络传输（WebSocket）
# - 多 client 并发提交 Action
# - 分桶 reveal API gating
# - 反作弊 / RNG seed 隐藏

# ---- 端到端：server run + client replay → 终态 byte-identical ----

func test_server_replay_to_client_snapshot_match():
	# Server 跑完一局，client 用 server 的 PLAYER_ACTION decisions replay。
	var server := LocalLoopbackServer.new(42, 0, true)
	server.run_to_end()
	var server_hash: int = server.bc.state.snapshot_hash()
	# Client 抽决策序列
	var server_events: Array = []
	for ne in server.get_all_events():
		server_events.append(ne.event)
	var decisions: Array = BattleController.extract_player_actions(server_events)
	assert_true(decisions.size() > 0, "server 一局至少 1 个 PLAYER_ACTION 决策")
	# Client 同 seed 重建 BC + 注 replay
	var client := BattleController.new(42, 0, true)
	client.set_replay_decisions(decisions)
	client.run_to_end()
	# 终态 hash 一致 = 客户端镜像 server 状态成功
	assert_eq(client.state.snapshot_hash(), server_hash,
		"client replay 终态 == server 终态（spec §4.3 client-mirror 硬证）")

func test_server_replay_to_client_event_count_match():
	# 不仅 hash 一致，事件数也应一致（同一组决策→同一组 event 流）
	var server := LocalLoopbackServer.new(42, 0, true)
	server.run_to_end()
	var server_event_count: int = server.bc.events.size()
	var server_events: Array = []
	for ne in server.get_all_events():
		server_events.append(ne.event)
	var decisions: Array = BattleController.extract_player_actions(server_events)
	var client := BattleController.new(42, 0, true)
	client.set_replay_decisions(decisions)
	client.run_to_end()
	assert_eq(client.events.size(), server_event_count,
		"client replay 事件数 == server 事件数")

# ---- 多 seed 跨场景 ----

func test_multiple_seeds_independently():
	# 跨 3 个 seed 都收敛 — 防 hash 巧合
	for seed in [42, 100, 1000]:
		var server := LocalLoopbackServer.new(seed, 0, true)
		server.run_to_end()
		var server_events: Array = []
		for ne in server.get_all_events():
			server_events.append(ne.event)
		var decisions: Array = BattleController.extract_player_actions(server_events)
		var client := BattleController.new(seed, 0, true)
		client.set_replay_decisions(decisions)
		client.run_to_end()
		assert_eq(client.state.snapshot_hash(), server.bc.state.snapshot_hash(),
			"seed=%d server↔client snapshot 一致" % seed)

# ---- NetworkedEvent server_seq 单调 ----

func test_networked_event_sequences_are_monotonic():
	# server 端 NetworkedEvent 的 server_seq 单调递增（client 重连用）
	var server := LocalLoopbackServer.new(42, 0, true)
	server.run_to_end()
	var events: Array = server.get_all_events()
	for i in range(events.size() - 1):
		assert_lt(events[i].server_seq, events[i + 1].server_seq,
			"NetworkedEvent.server_seq 单调递增")

# ---- Action 协议 round-trip ----

func test_action_serialization_roundtrip_in_e2e():
	# 模拟 client → wire → server 链路上 Action 经过序列化
	var original := Action.discard(0, TileId.W5, 42)
	var d: Dictionary = original.to_dict()
	# 模拟 wire 传输（如 JSON encode/decode）
	var wire_str: String = JSON.stringify(d)
	var parsed: Variant = JSON.parse_string(wire_str)
	assert_not_null(parsed, "wire 传输 JSON parse OK")
	var restored: Action = Action.from_dict(parsed)
	assert_eq(restored.kind, original.kind)
	assert_eq(restored.seat, original.seat)
	assert_eq(int(restored.payload["tile_id"]), TileId.W5)
	assert_eq(restored.client_seq, 42)

# ---- empty replay = 完全 ai 行为（向后兼容性硬证）----

func test_empty_replay_falls_back_to_ai_v1_behavior():
	# 不传 replay decisions 的 BC 应该完全等同 server 的（同 seed → 同 hash）
	var server := LocalLoopbackServer.new(42, 0, true)
	server.run_to_end()
	var solo := BattleController.new(42, 0, true)
	# 不调 set_replay_decisions
	solo.run_to_end()
	assert_eq(solo.state.snapshot_hash(), server.bc.state.snapshot_hash(),
		"空 replay = 完全 AI = 同 seed → 同 hash（M11 兼容性硬证）")
