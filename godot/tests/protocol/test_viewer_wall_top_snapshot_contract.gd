extends GutTest

const PROVIDER_PATH := "res://protocol/viewer_wall_top_snapshot_provider.gd"
const JsonTransportDecoder := preload("res://protocol/json_transport_decoder.gd")
const CORE_KEYS_V1 := [
	"recipient_seat", "hand_seq", "dealer_seat", "current_seat", "phase",
	"round_wind", "hand_number", "honba", "riichi_sticks", "live_wall_count",
	"dora_indicators", "seats",
]


class RestoreSink extends RefCounted:
	var applied: Dictionary = {}

	func capture_module_restore_state() -> Dictionary:
		return applied.duplicate(true)

	func restore_module_restore_state(state: Variant) -> void:
		applied = (state as Dictionary).duplicate(true)

	func apply_restored_module(
		module_key: String, schema_version: int, payload: Dictionary, seat: int
	) -> bool:
		applied[module_key] = {
			"schema_version": schema_version,
			"payload": payload.duplicate(true),
			"seat": seat,
		}
		return true


func _provider():
	assert_true(ResourceLoader.exists(PROVIDER_PATH), "须提供独立 viewer_wall_top@1 模块")
	if not ResourceLoader.exists(PROVIDER_PATH):
		return null
	var script := load(PROVIDER_PATH) as GDScript
	assert_not_null(script)
	return script.new() if script != null else null


func _registry() -> SnapshotModuleRegistry:
	var reg := SnapshotModuleRegistry.make_standard()
	var provider = _provider()
	if provider != null:
		assert_true(bool(reg.register(provider).get("ok", false)))
	return reg


func _state_with_wall_top(viewer: int = 0, hand_seq: int = 0) -> BattleState:
	var state := BattleState.for_east_round(345, 0, 1, 0, 0, TileId.E, hand_seq)
	var registry := SkillRegistry.new()
	var scheduler := SkillScheduler.new(registry, state)
	assert_true(BossAbilityFactory.inject(registry, &"char_koromo_passive_v1", viewer))
	var ctx := scheduler.emit_event(BattleEvent.make(&"TILE_DRAWN", viewer))
	assert_eq(ctx.triggered_skills.size(), 1)
	return state


func _module(modules: Array, key: String) -> Dictionary:
	for value in modules:
		if typeof(value) == TYPE_DICTIONARY \
				and String((value as Dictionary).get("module_key", "")) == key:
			return value as Dictionary
	return {}


func _wire(modules: Array, seat: int = 0, seq: int = 1) -> Dictionary:
	var payload := {
		"snapshot_server_seq": seq,
		"next_server_seq": seq + 1,
		"seat_view": seat,
		"modules": modules.duplicate(true),
	}
	return {
		"protocol_version": ProtocolConstants.PROTOCOL_VERSION,
		"server_seq": seq,
		"room_id": "viewer-wall-top-contract",
		"kind": "ROOM_SNAPSHOT",
		"payload": payload,
		"view_hash": ProtocolViewCodec.compute_view_hash(payload),
	}


func test_core_table_and_viewer_next_draw_contracts_stay_unchanged() -> void:
	var state := _state_with_wall_top()
	var core: Dictionary = RecipientViewProjector.project_core_table(state, 0)
	assert_eq(core.keys().size(), CORE_KEYS_V1.size())
	for key in CORE_KEYS_V1:
		assert_true(core.has(key), "core_table@1 缺字段 %s" % key)
	assert_false(core.has("viewer_wall_top"))
	var next_provider := ViewerNextDrawSnapshotProvider.new()
	assert_eq(next_provider.module_key(), "viewer_next_draw")
	assert_eq(next_provider.schema_version(), 1)


func test_optional_module_projects_ordered_tiles_only_to_recipient_and_old_registry_skips_it() -> void:
	var state := _state_with_wall_top(2, 7)
	var reg := _registry()
	var owner_ser := reg.serialize_modules({"state": state}, 2)
	assert_true(bool(owner_ser.get("ok", false)), str(owner_ser))
	assert_true(_module(owner_ser.get("modules", []), "viewer_next_draw").is_empty(),
		"渊汐墙顶序列不得冒充 #344 安澄青下一摸模块")
	var module := _module(owner_ser.get("modules", []), "viewer_wall_top")
	assert_eq(int(module.get("schema_version", 0)), 1)
	var payload := module.get("payload", {}) as Dictionary
	assert_eq(int(payload.get("recipient_seat", -1)), 2)
	assert_eq(int(payload.get("hand_seq", -1)), 7)
	var tiles := payload.get("tiles", []) as Array
	assert_eq(tiles.size(), 3)
	var expected := state.wall.peek_top_n(3)
	for index in range(3):
		var entry := tiles[index] as Dictionary
		assert_eq(int(entry.get("offset", -1)), index)
		assert_eq(int((entry.get("tile", {}) as Dictionary).get("instance_id", -1)),
			(expected[index] as Tile).instance_id)
	var other_ser := reg.serialize_modules({"state": state}, 1)
	assert_true(_module(other_ser.get("modules", []), "viewer_wall_top").is_empty(),
		"非 recipient 不得收到空壳或私有牌面")
	var old_sink := RestoreSink.new()
	var old_restore := SnapshotModuleRegistry.make_standard().restore_modules(
		owner_ser.get("modules", []), 2, old_sink)
	assert_true(bool(old_restore.get("ok", false)), str(old_restore))
	assert_true(old_sink.applied.has("core_table"))
	assert_false(old_sink.applied.has("viewer_wall_top"),
		"旧 registry 必须跳过未知 optional 模块")


func test_real_wire_json_and_nbc_restore_then_clear_omitted_module() -> void:
	var state := _state_with_wall_top(0, 9)
	var reg := _registry()
	var ser := reg.serialize_modules({"state": state}, 0)
	var wire := _wire(ser.get("modules", []))
	var event := NetworkedEvent.from_dict(wire)
	assert_not_null(event, "viewer_wall_top@1 必须通过真实 wire validator")
	var decoded := JsonTransportDecoder.decode_event(JSON.stringify(wire))
	assert_not_null(decoded, "viewer_wall_top@1 必须通过 JSON transport")
	var nbc := NetworkedBattleController.new("viewer-wall-top-contract", 0)
	nbc.snapshot_registry = reg
	assert_true(nbc.ingest_networked_event(decoded), nbc.last_snapshot_error())
	assert_eq((nbc.call("get_viewer_wall_top_view") as Dictionary)
		.get("tiles", []).size(), 3)
	for _index in range(3):
		state.wall.draw()
	var expired := reg.serialize_modules({"state": state}, 0)
	assert_true(_module(expired.get("modules", []), "viewer_wall_top").is_empty())
	var expired_event := NetworkedEvent.from_dict(
		_wire(expired.get("modules", []), 0, 2))
	assert_not_null(expired_event)
	assert_true(nbc.ingest_networked_event(expired_event))
	assert_true((nbc.call("get_viewer_wall_top_view") as Dictionary).is_empty(),
		"下一帧省略 optional 模块必须清除客户端旧投影")


func test_bad_recipient_order_namespace_and_cross_hand_fail_atomically() -> void:
	var state := _state_with_wall_top(0, 10)
	var reg := _registry()
	var ser := reg.serialize_modules({"state": state}, 0)
	var modules := ser.get("modules", []) as Array
	var sink := RestoreSink.new()
	assert_true(bool(reg.restore_modules(modules, 0, sink).get("ok", false)))
	var before := sink.capture_module_restore_state()
	var bad_cases: Array = []

	var bad_recipient := modules.duplicate(true)
	(_module(bad_recipient, "viewer_wall_top").payload as Dictionary)["recipient_seat"] = 1
	bad_cases.append(bad_recipient)

	var bad_order := modules.duplicate(true)
	var order_tiles := (_module(bad_order, "viewer_wall_top").payload as Dictionary).tiles as Array
	(order_tiles[1] as Dictionary)["offset"] = 0
	bad_cases.append(bad_order)

	var cross_hand := modules.duplicate(true)
	var cross_payload := _module(cross_hand, "viewer_wall_top").payload as Dictionary
	cross_payload["hand_seq"] = 11
	for entry_value in cross_payload.tiles as Array:
		var tile := (entry_value as Dictionary).tile as Dictionary
		tile["instance_id"] = int(tile.instance_id) + Tile.TILES_PER_HAND
	bad_cases.append(cross_hand)

	for case_index in range(bad_cases.size()):
		var bad := bad_cases[case_index] as Array
		assert_null(NetworkedEvent.from_dict(_wire(bad as Array)),
			"非法私有墙顶模块必须在 wire 层 fail closed，case=%d" % case_index)
		# 同帧 hand_seq 由 ROOM_SNAPSHOT validator 对照 core_table；provider 独立
		# restore 只校验自身 namespace，因此跨帧 case 不伪装成 registry 职责。
		if case_index == 2:
			continue
		var failed := reg.restore_modules(bad as Array, 0, sink)
		assert_false(bool(failed.get("ok", true)), "case=%d %s" % [case_index, str(failed)])
		assert_eq(sink.applied, before,
			"恢复预检失败不得部分覆盖旧状态，case=%d" % case_index)
