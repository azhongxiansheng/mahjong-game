extends GutTest

# 麻将王 — M11 net foundation: NetworkedBattleController stub 端到端测试
# spec §4.3 Phase 2 联机的硬证：local 录制 → JSON 序列化 → networked
# ingest → 终态 snapshot_hash byte-identical 于原 local 录制

# ---- ingest_event_stream e2e ----

func test_networked_ingest_reproduces_local_state():
	# 1) Local 录制
	var local_bc := BattleController.new(42, 0, true)
	local_bc.run_to_end()
	var local_hash: int = local_bc.state.snapshot_hash()
	# 2) 序列化事件流（JSON 友好）
	var events_dicts: Array = []
	for ev in local_bc.events:
		events_dicts.append(ev.to_dict())
	# 3) Networked ingest
	var net_bc := NetworkedBattleController.new(42, 0, true)
	net_bc.ingest_event_stream(events_dicts)
	# 4) 终态 hash 必须等于原 local 录制
	assert_eq(net_bc.state.snapshot_hash(), local_hash,
		"NetworkedBC ingest 后终态 hash 必须等于原 LocalBC（联机收敛硬证）")

func test_networked_ingest_event_count_matches_local():
	var local_bc := BattleController.new(123, 0, true)
	local_bc.run_to_end()
	var events_dicts: Array = []
	for ev in local_bc.events:
		events_dicts.append(ev.to_dict())
	var net_bc := NetworkedBattleController.new(123, 0, true)
	net_bc.ingest_event_stream(events_dicts)
	assert_eq(local_bc.events.size(), net_bc.events.size(),
		"事件总数一致（无丢失或多余）")

func test_networked_ingest_event_stream_byte_identical():
	# 强证：每个事件 dict 都 byte-identical
	var local_bc := BattleController.new(7, 0, true)
	local_bc.run_to_end()
	var events_dicts: Array = []
	for ev in local_bc.events:
		events_dicts.append(ev.to_dict())
	var net_bc := NetworkedBattleController.new(7, 0, true)
	net_bc.ingest_event_stream(events_dicts)
	for i in range(mini(local_bc.events.size(), net_bc.events.size())):
		assert_eq(JSON.stringify(local_bc.events[i].to_dict()),
			JSON.stringify(net_bc.events[i].to_dict()),
			"event %d byte-identical" % i)

# ---- desync_check ----

func test_desync_check_matches_when_state_identical():
	var bc := NetworkedBattleController.new(42, 0, true)
	bc.run_to_end()
	# 自己跟自己比 → 必须匹配
	var h: int = bc.state.snapshot_hash()
	assert_true(bc.desync_check(h), "本地 hash 与 remote hash 等同时返 true")

func test_desync_check_mismatch_when_remote_diverges():
	var bc := NetworkedBattleController.new(42, 0, true)
	bc.run_to_end()
	# 假设 server 推一个不同的 hash → 应判定 desync
	assert_false(bc.desync_check(0xDEADBEEF), "remote hash 不同 → 返 false")

# ---- BattleControllerInterface 契约：第二个实现验证 ----

func test_networked_bc_satisfies_interface_contract():
	# spec §4.3 BC 公共契约必须有 ≥ 2 个实现验证
	# (LocalBattleController = BattleController 已有契约测试；本测试加 NetworkedBC)
	var bc := NetworkedBattleController.new(42, 0, true)
	assert_not_null(bc.state, "state 字段必须暴露")
	assert_typeof(bc.events, TYPE_ARRAY, "events 必须 Array")
	assert_not_null(bc.registry, "registry 字段必须暴露")
	assert_not_null(bc.scheduler, "scheduler 字段必须暴露")
	assert_true(bc.has_method("run_to_end"), "run_to_end 必须存在")
	# NetworkedBC 特有 API
	assert_true(bc.has_method("ingest_event_stream"))
	assert_true(bc.has_method("desync_check"))
