extends GutTest

const PROVIDER_PATH := "res://protocol/viewer_next_draw_snapshot_provider.gd"
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
	assert_true(ResourceLoader.exists(PROVIDER_PATH), "须提供独立 viewer_next_draw 模块")
	if not ResourceLoader.exists(PROVIDER_PATH):
		return null
	var script := load(PROVIDER_PATH) as GDScript
	assert_not_null(script)
	return script.new() if script != null else null


func _registry_with_prediction_provider() -> SnapshotModuleRegistry:
	var reg := SnapshotModuleRegistry.make_standard()
	var provider = _provider()
	if provider != null:
		assert_true(bool(reg.register(provider).get("ok", false)))
	return reg


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
		"room_id": "viewer-next-draw-contract",
		"kind": "ROOM_SNAPSHOT",
		"payload": payload,
		"view_hash": ProtocolViewCodec.compute_view_hash(payload),
	}


func test_core_table_v1_stays_exact12_without_prediction_field() -> void:
	var state := BattleState.for_east_round(344, 0, 1, 0, 0)
	var core: Dictionary = RecipientViewProjector.project_core_table(state, 0)
	assert_eq(core.keys().size(), CORE_KEYS_V1.size())
	for key in CORE_KEYS_V1:
		assert_true(core.has(key), "core_table@1 缺字段 %s" % key)
	assert_false(core.has("viewer_next_draw"),
		"同一个 core_table@1 不得同时代表 exact-12 与 exact-13")
	var wire := _wire([{
		"module_key": "core_table",
		"schema_version": 1,
		"payload": core,
	}])
	assert_not_null(NetworkedEvent.from_dict(wire), "旧 core_table@1 wire 必须继续可解析")


func test_optional_prediction_module_omits_empty_and_old_registry_skips_new_module() -> void:
	var state := BattleState.for_east_round(344, 0, 1, 0, 0)
	var reg := _registry_with_prediction_provider()
	var empty_ser := reg.serialize_modules({"state": state}, 0)
	assert_true(bool(empty_ser.get("ok", false)), str(empty_ser))
	assert_true(_module(empty_ser.get("modules", []), "viewer_next_draw").is_empty(),
		"无预知时不得给历史快照增加空模块噪声")

	var registry := SkillRegistry.new()
	var scheduler := SkillScheduler.new(registry, state)
	assert_true(BossAbilityFactory.inject(registry, &"char_awai_passive_v1", 0))
	var expected: Tile = state.wall.peek_next_draw()
	scheduler.emit_event(BattleEvent.make(&"GAME_BEGIN", 0))
	var ser := reg.serialize_modules({"state": state}, 0)
	assert_true(bool(ser.get("ok", false)), str(ser))
	var prediction := _module(ser.get("modules", []), "viewer_next_draw")
	assert_eq(int(prediction.get("schema_version", 0)), 1)
	assert_eq(int((prediction.get("payload", {}) as Dictionary).get("recipient_seat", -1)), 0)
	assert_eq(int((prediction.get("payload", {}) as Dictionary).get("hand_seq", -1)),
		state.hand_seq)
	assert_eq(int(((prediction.get("payload", {}) as Dictionary).get("tile", {}) as Dictionary)
		.get("instance_id", -1)), expected.instance_id)
	var production_reg := SnapshotModuleRegistry.make_trash_talk()
	var production_ser := production_reg.serialize_modules({
		"state": state,
		"item_inventory": ItemInventoryModule.new(),
		"reward_window": RewardWindowModule.new(),
	}, 0)
	assert_true(bool(production_ser.get("ok", false)), str(production_ser))
	assert_false(_module(production_ser.get("modules", []), "viewer_next_draw").is_empty(),
		"TRASH_TALK 生产注册表须发出有效私有预知模块")

	var old_sink := RestoreSink.new()
	var old_restore := SnapshotModuleRegistry.make_standard().restore_modules(
		production_ser.get("modules", []), 0, old_sink)
	assert_true(bool(old_restore.get("ok", false)), str(old_restore))
	assert_true(old_sink.applied.has("core_table"))
	assert_false(old_sink.applied.has("viewer_next_draw"),
		"旧客户端应忽略未知可选模块并继续恢复 core_table@1")


func test_prediction_module_new_registry_restores_atomically_and_wire_rejects_bad_shape() -> void:
	var state := BattleState.for_east_round(344, 0, 1, 0, 0)
	var skill_registry := SkillRegistry.new()
	var scheduler := SkillScheduler.new(skill_registry, state)
	assert_true(BossAbilityFactory.inject(skill_registry, &"char_awai_passive_v1", 0))
	scheduler.emit_event(BattleEvent.make(&"GAME_BEGIN", 0))
	var reg := _registry_with_prediction_provider()
	var ser := reg.serialize_modules({"state": state}, 0)
	assert_true(bool(ser.get("ok", false)), str(ser))
	var modules: Array = ser.get("modules", [])
	var wire := _wire(modules)
	assert_not_null(NetworkedEvent.from_dict(wire), "新模块须通过真实 ROOM_SNAPSHOT validator")
	var decoded: NetworkedEvent = JsonTransportDecoder.decode_event(JSON.stringify(wire))
	assert_not_null(decoded, "新模块须通过真实 JSON transport decoder")
	if decoded != null:
		var decoded_prediction := _module(decoded.payload.get("modules", []),
			"viewer_next_draw")
		var decoded_payload := decoded_prediction.get("payload", {}) as Dictionary
		assert_eq(typeof(decoded_payload.get("hand_seq")), TYPE_INT)
		assert_eq(typeof((decoded_payload.get("tile", {}) as Dictionary).get("instance_id")),
			TYPE_INT)
	var nbc := NetworkedBattleController.new("viewer-next-draw-contract", 0)
	nbc.snapshot_registry = reg
	assert_true(nbc.ingest_networked_event(decoded),
		"真实 NBC/registry 恢复链须应用 optional 模块：%s" % nbc.last_snapshot_error())
	assert_eq(int((nbc.get_viewer_next_draw_view().get("tile", {}) as Dictionary)
		.get("instance_id", -1)), state.wall.peek_next_draw().instance_id)
	state.wall.draw()
	var expired_ser := reg.serialize_modules({"state": state}, 0)
	assert_true(bool(expired_ser.get("ok", false)), str(expired_ser))
	assert_true(_module(expired_ser.get("modules", []), "viewer_next_draw").is_empty())
	var expired_wire := _wire(expired_ser.get("modules", []), 0, 2)
	var expired_event := NetworkedEvent.from_dict(expired_wire)
	assert_not_null(expired_event)
	assert_true(nbc.ingest_networked_event(expired_event))
	assert_true(nbc.get_viewer_next_draw_view().is_empty(),
		"摸牌后下一帧省略 optional 模块，NBC 必须清除旧私有投影")

	var sink := RestoreSink.new()
	var restored := reg.restore_modules(modules, 0, sink)
	assert_true(bool(restored.get("ok", false)), str(restored))
	assert_true(sink.applied.has("core_table"))
	assert_true(sink.applied.has("viewer_next_draw"))

	var bad_modules := modules.duplicate(true)
	var bad_prediction := _module(bad_modules, "viewer_next_draw")
	bad_prediction["payload"] = {
		"recipient_seat": 1,
		"hand_seq": state.hand_seq,
		"tile": (bad_prediction.get("payload", {}) as Dictionary).get("tile", {}),
	}
	assert_null(NetworkedEvent.from_dict(_wire(bad_modules)),
		"viewer_next_draw@1 recipient 与 seat_view 不一致必须拒绝")
	var cross_hand_modules := modules.duplicate(true)
	var cross_hand_prediction := _module(cross_hand_modules, "viewer_next_draw")
	var cross_hand_payload := cross_hand_prediction.get("payload", {}) as Dictionary
	cross_hand_payload["hand_seq"] = state.hand_seq + 1
	var cross_hand_tile := cross_hand_payload.get("tile", {}) as Dictionary
	cross_hand_tile["instance_id"] = int(cross_hand_tile["instance_id"]) \
		+ ProtocolConstants.TILES_PER_HAND
	assert_null(NetworkedEvent.from_dict(_wire(cross_hand_modules)),
		"optional 模块 hand_seq 与同帧 core_table@1 不一致必须拒绝")
	var before := sink.capture_module_restore_state()
	var failed := reg.restore_modules(bad_modules, 0, sink)
	assert_false(bool(failed.get("ok", true)))
	assert_eq(sink.applied, before, "可选模块预检失败不得部分覆盖已恢复模块")
