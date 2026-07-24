extends GutTest

# #241：SnapshotModuleRegistry + SNAP-01..05 + 测试 provider round-trip。
# 真实 serialize → ROOM_SNAPSHOT → restore → 增量序号；不 mock 核心规则。

const ROOM := "room_snap_reg"


class TestOpaqueProvider extends SnapshotModuleProvider:
	var _blob: Dictionary = {}
	var restore_calls: int = 0
	var fail_restore: bool = false
	var fail_commit: bool = false
	var stage_calls: int = 0
	var commit_calls: int = 0

	func module_key() -> String:
		return "test_opaque"

	func schema_version() -> int:
		return 1

	func is_required() -> bool:
		return false

	func serialize(ctx: Dictionary, seat: int) -> Variant:
		var out := _blob.duplicate(true)
		out["seat"] = seat
		out["marker"] = str(ctx.get("marker", ""))
		return out

	func can_restore(payload: Variant, seat: int) -> bool:
		if fail_restore:
			return false
		if typeof(payload) != TYPE_DICTIONARY:
			return false
		return int((payload as Dictionary).get("seat", -1)) == seat

	func stage_restore(payload: Variant, seat: int) -> Variant:
		stage_calls += 1
		if not can_restore(payload, seat):
			return null
		return (payload as Dictionary).duplicate(true)

	func commit_restore(staged: Variant, seat: int, target: Object) -> bool:
		commit_calls += 1
		if fail_commit:
			return false
		return restore(staged, seat, target)

	func restore(payload: Variant, seat: int, target: Object) -> bool:
		restore_calls += 1
		if fail_restore or not can_restore(payload, seat):
			return false
		if target != null and target.has_method("apply_restored_module"):
			return bool(target.call(
				"apply_restored_module",
				module_key(),
				schema_version(),
				(payload as Dictionary).duplicate(true),
				seat
			))
		return false


class RestoreSink extends RefCounted:
	var applied: Dictionary = {}
	var apply_count: int = 0

	func apply_restored_module(
		module_key: String,
		schema_version: int,
		payload: Dictionary,
		seat: int
	) -> bool:
		apply_count += 1
		applied[module_key] = {
			"schema_version": schema_version,
			"payload": payload.duplicate(true),
			"seat": seat,
		}
		return true

	func capture_module_restore_state() -> Dictionary:
		return applied.duplicate(true)

	func restore_module_restore_state(prev: Variant) -> void:
		applied = {}
		apply_count = 0
		if typeof(prev) == TYPE_DICTIONARY:
			applied = (prev as Dictionary).duplicate(true)
			apply_count = applied.size()


func _core_payload(seat: int) -> Dictionary:
	# 最小可过 NetworkedEvent 校验的 core_table 由真实 projector 更稳；
	# 此处用合法手工 fixture 供纯 registry 测。
	var tile := {
		"instance_id": seat,
		"tile_id": TileId.E,
		"is_red_dora": false,
		"owner_seat": seat,
	}
	var seats: Array = []
	for s in range(4):
		seats.append({
			"seat": s,
			"seat_wind": [TileId.E, TileId.S_WIND, TileId.W_WIND, TileId.N][s],
			"score": 25000,
			"concealed_tiles": [tile] if s == seat else [],
			"concealed_count": 1 if s == seat else 13,
			"last_drawn_tile_instance_id": -1,
			"river": [],
			"melds": [],
			"riichi_declared": false,
			"riichi_double": false,
			"riichi_discard_index": -1,
		})
	return {
		"recipient_seat": seat,
		"hand_seq": 0,
		"dealer_seat": 0,
		"current_seat": 0,
		"phase": "DRAW",
		"round_wind": TileId.E,
		"hand_number": 1,
		"honba": 0,
		"riichi_sticks": 0,
		"live_wall_count": 70,
		"dora_indicators": [{
			"instance_id": 4,
			"tile_id": TileId.W5,
			"is_red_dora": true,
			"owner_seat": 0,
		}],
		"seats": seats,
	}


func test_register_rejects_duplicate_module_key() -> void:
	var reg := SnapshotModuleRegistry.make_standard()
	assert_true(reg.is_standard_only())
	var r: Dictionary = reg.register(CoreTableSnapshotProvider.new())
	assert_false(bool(r["ok"]))
	assert_eq(str(r["code"]), SnapshotModuleRegistry.ERR_DUPLICATE_KEY)


func test_standard_does_not_register_fun_keys() -> void:
	var reg := SnapshotModuleRegistry.make_standard()
	for k in ["reward_window", "item_inventory", "character_ability", "armament"]:
		assert_false(reg.has_module(k), "STANDARD 不得注册 %s" % k)
	assert_true(reg.has_module("core_table"))


func test_required_unknown_schema_version_fails_zero_restore() -> void:
	var reg := SnapshotModuleRegistry.make_standard()
	var sink := RestoreSink.new()
	var modules := [{
		"module_key": "core_table",
		"schema_version": 99,
		"payload": _core_payload(0),
	}]
	var r: Dictionary = reg.restore_modules(modules, 0, sink)
	assert_false(bool(r["ok"]))
	assert_eq(str(r["code"]), SnapshotModuleRegistry.ERR_SCHEMA_UNSUPPORTED)
	assert_eq(sink.apply_count, 0, "失败不得部分应用")


func test_restore_failure_is_atomic() -> void:
	var reg := SnapshotModuleRegistry.make_standard()
	var opaque := TestOpaqueProvider.new()
	opaque._blob = {"v": 1}
	opaque.fail_restore = true
	assert_true(bool(reg.register(opaque)["ok"]))
	var sink := RestoreSink.new()
	# modules 须按 key 升序：core_table < test_opaque
	var modules := [
		{
			"module_key": "core_table",
			"schema_version": 1,
			"payload": _core_payload(1),
		},
		{
			"module_key": "test_opaque",
			"schema_version": 1,
			"payload": {"seat": 1, "v": 1},
		},
	]
	var r: Dictionary = reg.restore_modules(modules, 1, sink)
	assert_false(bool(r["ok"]))
	assert_eq(str(r["code"]), SnapshotModuleRegistry.ERR_RESTORE_FAILED)
	assert_eq(sink.apply_count, 0, "preflight 失败不得 restore")


func test_runtime_commit_failure_rolls_back_prior_provider() -> void:
	# 全部 can_restore=true；core_table commit 成功后 test_opaque commit 失败 → 整份回滚
	var reg := SnapshotModuleRegistry.make_standard()
	var opaque := TestOpaqueProvider.new()
	opaque.fail_commit = true
	assert_true(bool(reg.register(opaque)["ok"]))
	var sink := RestoreSink.new()
	# 先成功应用一次，验证回滚回到调用前
	var pre: Dictionary = reg.restore_modules([{
		"module_key": "core_table",
		"schema_version": 1,
		"payload": _core_payload(0),
	}], 0, sink)
	assert_true(bool(pre["ok"]))
	assert_eq(sink.apply_count, 1)
	assert_true(sink.applied.has("core_table"))
	var before: Dictionary = sink.capture_module_restore_state()
	var modules := [
		{
			"module_key": "core_table",
			"schema_version": 1,
			"payload": _core_payload(0),
		},
		{
			"module_key": "test_opaque",
			"schema_version": 1,
			"payload": {"seat": 0, "v": 9},
		},
	]
	var r: Dictionary = reg.restore_modules(modules, 0, sink)
	assert_false(bool(r["ok"]))
	assert_eq(str(r["code"]), SnapshotModuleRegistry.ERR_RESTORE_FAILED)
	assert_gt(opaque.stage_calls, 0)
	assert_gt(opaque.commit_calls, 0)
	# 最终状态完全等于调用前
	assert_eq(JSON.stringify(sink.applied), JSON.stringify(before),
		"运行期 commit 失败须回滚到调用前")
	assert_false(sink.applied.has("test_opaque"))


func test_unknown_unregistered_module_skipped() -> void:
	var reg := SnapshotModuleRegistry.make_standard()
	var sink := RestoreSink.new()
	var modules := [
		{
			"module_key": "core_table",
			"schema_version": 1,
			"payload": _core_payload(0),
		},
		{
			"module_key": "future_fun",
			"schema_version": 3,
			"payload": {"x": 1},
		},
	]
	var r: Dictionary = reg.restore_modules(modules, 0, sink)
	assert_true(bool(r["ok"]), str(r))
	assert_true(sink.applied.has("core_table"))
	assert_false(sink.applied.has("future_fun"), "未知模块不应用")


func test_snap_01_to_05_field_contract_and_round_trip() -> void:
	# SNAP-01：字段名冻结
	var seat := 0
	var reg := SnapshotModuleRegistry.make_standard()
	var opaque := TestOpaqueProvider.new()
	opaque._blob = {"note": "rt"}
	assert_true(bool(reg.register(opaque)["ok"]))

	# 真实 BattleState 投影
	var bc := BattleController.new(42, 0, false)
	assert_not_null(bc)
	assert_not_null(bc.state)
	var ser: Dictionary = reg.serialize_modules({"state": bc.state, "marker": "m1"}, seat)
	assert_true(bool(ser["ok"]), str(ser))
	var modules: Array = ser["modules"]
	assert_gte(modules.size(), 1)
	assert_eq(str((modules[0] as Dictionary)["module_key"]), "core_table")

	var snap_seq := 7
	var payload := {
		"snapshot_server_seq": snap_seq,
		"next_server_seq": snap_seq + 1,
		"seat_view": seat,
		"modules": modules,
	}
	# SNAP-01
	assert_true(payload.has("snapshot_server_seq"))
	assert_true(payload.has("next_server_seq"))
	assert_false(payload.has("last_server_seq"))

	var vh: String = ProtocolViewCodec.compute_view_hash(payload)
	assert_eq(vh.length(), 64)
	var ne: NetworkedEvent = NetworkedEvent.make(
		"ROOM_SNAPSHOT", snap_seq, ROOM, payload, vh
	)
	assert_not_null(ne, "合法 ROOM_SNAPSHOT 须可构造")

	# SNAP-02
	assert_eq(int(ne.server_seq), int(ne.payload["snapshot_server_seq"]))
	assert_eq(int(ne.payload["next_server_seq"]), int(ne.payload["snapshot_server_seq"]) + 1)

	# SNAP-05：round-trip 字段不变
	var wire: Dictionary = ne.to_dict()
	var back: NetworkedEvent = NetworkedEvent.from_dict(wire)
	assert_not_null(back)
	assert_eq(int(back.server_seq), snap_seq)
	assert_eq(int(back.payload["snapshot_server_seq"]), snap_seq)
	assert_eq(int(back.payload["next_server_seq"]), snap_seq + 1)

	var sink := RestoreSink.new()
	var rr: Dictionary = reg.restore_modules(back.payload["modules"], seat, sink)
	assert_true(bool(rr["ok"]), str(rr))
	assert_true(sink.applied.has("core_table"))
	assert_true(sink.applied.has("test_opaque"))
	assert_eq(int((sink.applied["test_opaque"]["payload"] as Dictionary)["seat"]), seat)

	# 增量：下一条 server_seq 必须 == next_server_seq（SNAP-03 由 NBC 消费覆盖）
	var next_seq: int = int(back.payload["next_server_seq"])
	assert_eq(next_seq, snap_seq + 1)

	# SNAP-04：仅 last_server_seq 无冻结字段 → 解析失败
	var legacy := {
		"protocol_version": 1,
		"server_seq": 3,
		"room_id": ROOM,
		"kind": "ROOM_SNAPSHOT",
		"payload": {
			"last_server_seq": 3,
			"seat_view": 0,
			"modules": modules,
		},
		"view_hash": "a".repeat(64),
	}
	assert_null(NetworkedEvent.from_dict(legacy), "SNAP-04: last_server_seq 别名必须拒绝")


func test_serialize_compose_does_not_rewrite_payload() -> void:
	var reg := SnapshotModuleRegistry.new()
	var opaque := TestOpaqueProvider.new()
	opaque._blob = {"frozen": 42, "nested": {"a": 1}}
	assert_true(bool(reg.register(opaque)["ok"]))
	var ser: Dictionary = reg.serialize_modules({"marker": "x"}, 2)
	assert_true(bool(ser["ok"]))
	var mod: Dictionary = (ser["modules"] as Array)[0]
	assert_eq(int((mod["payload"] as Dictionary)["frozen"]), 42)
	assert_eq(str(mod["module_key"]), "test_opaque")
	assert_eq(int(mod["schema_version"]), 1)


func test_optional_unknown_schema_skipped_required_unknown_rejected() -> void:
	var reg := SnapshotModuleRegistry.make_standard()
	var opaque := TestOpaqueProvider.new()
	assert_true(bool(reg.register(opaque)["ok"]))
	var sink := RestoreSink.new()
	# 可选 test_opaque schema 99：跳过；core 仍恢复
	var modules_opt := [
		{
			"module_key": "core_table",
			"schema_version": 1,
			"payload": _core_payload(0),
		},
		{
			"module_key": "test_opaque",
			"schema_version": 99,
			"payload": {"seat": 0, "v": 1},
		},
	]
	var r1: Dictionary = reg.restore_modules(modules_opt, 0, sink)
	assert_true(bool(r1["ok"]), str(r1))
	assert_true(sink.applied.has("core_table"))
	assert_false(sink.applied.has("test_opaque"), "可选未知 schema 不应用")
	# 必需 core_table schema 99：稳定拒绝、零应用
	var sink2 := RestoreSink.new()
	var modules_req := [{
		"module_key": "core_table",
		"schema_version": 99,
		"payload": _core_payload(0),
	}]
	var r2: Dictionary = reg.restore_modules(modules_req, 0, sink2)
	assert_false(bool(r2["ok"]))
	assert_eq(str(r2["code"]), SnapshotModuleRegistry.ERR_SCHEMA_UNSUPPORTED)
	assert_eq(sink2.apply_count, 0)


class NoRollbackSink extends RefCounted:
	var apply_count: int = 0
	var applied: Dictionary = {}

	func apply_restored_module(
		module_key: String,
		schema_version: int,
		payload: Dictionary,
		_seat: int
	) -> bool:
		apply_count += 1
		applied[module_key] = payload.duplicate(true)
		return true


func test_target_without_rollback_protocol_zero_commit() -> void:
	# 无 capture/restore 的 target：不得发生任何 commit
	var reg := SnapshotModuleRegistry.make_standard()
	var opaque := TestOpaqueProvider.new()
	opaque.fail_commit = true
	assert_true(bool(reg.register(opaque)["ok"]))
	var sink := NoRollbackSink.new()
	var modules := [
		{
			"module_key": "core_table",
			"schema_version": 1,
			"payload": _core_payload(0),
		},
		{
			"module_key": "test_opaque",
			"schema_version": 1,
			"payload": {"seat": 0, "v": 1},
		},
	]
	var r: Dictionary = reg.restore_modules(modules, 0, sink)
	assert_false(bool(r["ok"]))
	assert_eq(str(r["code"]), SnapshotModuleRegistry.ERR_INVALID)
	assert_eq(sink.apply_count, 0, "无回滚协议时零 commit")
	assert_true(sink.applied.is_empty())
