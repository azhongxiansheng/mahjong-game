extends GutTest

const PROVIDER_PATH := "res://protocol/viewer_seat_draw_forecast_snapshot_provider.gd"
const MODULE_KEY := "viewer_seat_draw_forecast"


func _provider():
	assert_true(ResourceLoader.exists(PROVIDER_PATH), "须提供独立四席私有 optional provider")
	if not ResourceLoader.exists(PROVIDER_PATH):
		return null
	var script := load(PROVIDER_PATH) as GDScript
	assert_not_null(script)
	return script.new() if script != null else null


func _module(modules: Array, key: String) -> Dictionary:
	for value in modules:
		if typeof(value) == TYPE_DICTIONARY \
				and str((value as Dictionary).get("module_key", "")) == key:
			return value as Dictionary
	return {}


func _wire(modules: Array, seat: int, seq: int = 1) -> Dictionary:
	var payload := {
		"snapshot_server_seq": seq,
		"next_server_seq": seq + 1,
		"seat_view": seat,
		"modules": modules.duplicate(true),
	}
	return {
		"protocol_version": ProtocolConstants.PROTOCOL_VERSION,
		"server_seq": seq,
		"room_id": "xian-shi-forecast-contract",
		"kind": "ROOM_SNAPSHOT",
		"payload": payload,
		"view_hash": ProtocolViewCodec.compute_view_hash(payload),
	}


func _activated_state(viewer: int, hand_seq: int = 6) -> BattleState:
	var state := BattleState.for_east_round(347, 2, 1, 0, 0, TileId.E, hand_seq)
	var registry := SkillRegistry.new()
	var scheduler := SkillScheduler.new(registry, state)
	assert_true(BossAbilityFactory.inject(registry, &"char_toki_passive_v1", viewer))
	var ctx := scheduler.emit_event(BattleEvent.make(&"GAME_BEGIN", viewer))
	assert_eq(ctx.triggered_skills.size(), 1)
	return state


func test_provider_serializes_four_unique_target_bound_tiles_only_for_owner() -> void:
	var provider = _provider()
	if provider == null:
		return
	var state := _activated_state(3)
	var payload: Variant = provider.serialize({"state": state}, 3)
	assert_not_null(payload)
	var data := payload as Dictionary
	assert_eq(data.keys().size(), 3)
	assert_eq(int(data.recipient_seat), 3)
	assert_eq(int(data.hand_seq), 6)
	var predictions := data.predictions as Array
	assert_eq(predictions.size(), 4)
	var targets: Dictionary = {}
	var instances: Dictionary = {}
	for prediction in predictions:
		var row := prediction as Dictionary
		assert_eq(row.keys().size(), 2)
		targets[int(row.target_seat)] = true
		instances[int((row.tile as Dictionary).instance_id)] = true
	assert_eq(targets.size(), 4)
	assert_eq(instances.size(), 4)
	assert_null(provider.serialize({"state": state}, 0),
		"未授权 recipient 必须省略整个 optional 模块")


func test_new_module_keeps_core_and_viewer_next_draw_v1_unchanged() -> void:
	var state := _activated_state(1, 0)
	var provider = _provider()
	if provider == null:
		return
	var reg := SnapshotModuleRegistry.make_trash_talk()
	assert_true(reg.has_module(MODULE_KEY), "生产 TRASH_TALK registry 须注册四席模块")
	var ser := reg.serialize_modules({
		"state": state,
		"item_inventory": ItemInventoryModule.new(),
		"reward_window": RewardWindowModule.new(),
		"character_ids": ["lin_yeche", "an_cheng", "bai_touli", "hua_ling"],
		"participants": ["HUMAN", "AI", "AI", "AI"],
	}, 1)
	assert_true(bool(ser.get("ok", false)), str(ser))
	var modules := ser.get("modules", []) as Array
	var core := _module(modules, "core_table")
	assert_eq(((core.payload as Dictionary).keys() as Array).size(), 12,
		"core_table@1 必须继续 exact-12")
	assert_true(_module(modules, "viewer_next_draw").is_empty(),
		"先示不得伪造或复用安澄青 viewer_next_draw@1")
	var forecast := _module(modules, MODULE_KEY)
	assert_eq(int(forecast.schema_version), 1)
	assert_eq((forecast.payload as Dictionary).predictions.size(), 4)
	var old_restore := SnapshotModuleRegistry.make_standard().restore_modules(
		modules, 1, NetworkedBattleController.new("xian-shi-forecast-contract", 1))
	assert_true(bool(old_restore.get("ok", false)), "旧 registry 应跳过未知 optional 模块")


func test_wire_and_nbc_restore_atomically_reject_cross_hand_or_duplicate_target() -> void:
	var provider = _provider()
	if provider == null:
		return
	var state := _activated_state(2, 11)
	var reg := SnapshotModuleRegistry.make_trash_talk()
	var ser := reg.serialize_modules({
		"state": state,
		"item_inventory": ItemInventoryModule.new(),
		"reward_window": RewardWindowModule.new(),
		"character_ids": ["lin_yeche", "an_cheng", "bai_touli", "hua_ling"],
		"participants": ["HUMAN", "AI", "AI", "AI"],
	}, 2)
	assert_true(bool(ser.get("ok", false)), str(ser))
	var modules := ser.get("modules", []) as Array
	var wire := _wire(modules, 2)
	var event := NetworkedEvent.from_dict(wire)
	assert_not_null(event)
	var nbc := NetworkedBattleController.new("xian-shi-forecast-contract", 2)
	nbc.snapshot_registry = reg
	assert_true(nbc.ingest_networked_event(event))
	assert_eq((nbc.get_viewer_seat_draw_forecast_view().get("predictions", []) as Array).size(), 4)

	var duplicate_modules := modules.duplicate(true)
	var duplicate_payload := _module(duplicate_modules, MODULE_KEY).payload as Dictionary
	var duplicate_rows := duplicate_payload.predictions as Array
	(duplicate_rows[1] as Dictionary).target_seat = int(
		(duplicate_rows[0] as Dictionary).target_seat)
	assert_null(NetworkedEvent.from_dict(_wire(duplicate_modules, 2)),
		"同一目标席重复预测必须被 wire 拒绝")

	var cross_hand_modules := modules.duplicate(true)
	var cross_payload := _module(cross_hand_modules, MODULE_KEY).payload as Dictionary
	cross_payload.hand_seq = 12
	for row in cross_payload.predictions as Array:
		(row as Dictionary).tile.instance_id = int((row as Dictionary).tile.instance_id) + 136
	assert_null(NetworkedEvent.from_dict(_wire(cross_hand_modules, 2)),
		"私有模块 hand_seq 必须与同帧 core_table@1 一致")

	var empty_state := BattleState.for_east_round(999, 0, 1, 0, 0, TileId.E, 11)
	var empty_ser := reg.serialize_modules({
		"state": empty_state,
		"item_inventory": ItemInventoryModule.new(),
		"reward_window": RewardWindowModule.new(),
		"character_ids": ["lin_yeche", "an_cheng", "bai_touli", "hua_ling"],
		"participants": ["HUMAN", "AI", "AI", "AI"],
	}, 2)
	var empty_wire := _wire(empty_ser.get("modules", []), 2, 2)
	assert_true(nbc.ingest_networked_event(NetworkedEvent.from_dict(empty_wire)))
	assert_true(nbc.get_viewer_seat_draw_forecast_view().is_empty(),
		"下一快照省略 optional 模块时必须清除旧投影")
