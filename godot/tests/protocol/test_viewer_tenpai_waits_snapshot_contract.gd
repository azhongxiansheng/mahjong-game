extends GutTest

const PROVIDER_PATH := "res://protocol/viewer_tenpai_waits_snapshot_provider.gd"
const JsonTransportDecoder := preload("res://protocol/json_transport_decoder.gd")


func _module(modules: Array, key: String) -> Dictionary:
	for value in modules:
		if typeof(value) == TYPE_DICTIONARY \
				and str((value as Dictionary).get("module_key", "")) == key:
			return value as Dictionary
	return {}


func _registry() -> SnapshotModuleRegistry:
	var registry := SnapshotModuleRegistry.make_standard()
	var provider = load(PROVIDER_PATH).new()
	assert_true(bool(registry.register(provider).get("ok", false)))
	return registry


func _wire(modules: Array, seat: int, seq: int) -> Dictionary:
	var payload := {
		"snapshot_server_seq": seq,
		"next_server_seq": seq + 1,
		"seat_view": seat,
		"modules": modules.duplicate(true),
	}
	return {
		"protocol_version": ProtocolConstants.PROTOCOL_VERSION,
		"server_seq": seq,
		"room_id": "viewer-tenpai-waits-contract",
		"kind": "ROOM_SNAPSHOT",
		"payload": payload,
		"view_hash": ProtocolViewCodec.compute_view_hash(payload),
	}


func test_optional_module_exists_and_coexists_with_existing_viewer_modules() -> void:
	assert_true(ResourceLoader.exists(PROVIDER_PATH),
		"纪枢必须使用独立 viewer_tenpai_waits@1 optional module")
	var registry := SnapshotModuleRegistry.make_trash_talk()
	assert_eq(registry.registered_keys(), [
		"core_table", "item_inventory", "match_authority", "matching_meta", "reward_window",
		"viewer_next_draw", "viewer_seat_draw_forecast",
		"viewer_tenpai_waits", "viewer_wall_top",
	], "core_table@1 + match_authority + matching_meta 与四个 viewer optional module 必须并存")


func test_serialize_is_recipient_private_and_absent_without_authorization() -> void:
	if not ResourceLoader.exists(PROVIDER_PATH):
		return
	var provider = load(PROVIDER_PATH).new()
	var state := BattleState.for_east_round(346, 0, 1, 0, 0, TileId.E, 3)
	state.tenpai_wait_reveals = {2: {0: [TileId.W1], 3: [TileId.T3, TileId.T6]}}
	assert_null(provider.serialize({"state": state}, 2),
		"私有投影与权威听牌门闩矛盾时必须 fail closed")
	state.tenpai_flags = [true, false, false, true]
	var owner_payload: Variant = provider.serialize({"state": state}, 2)
	assert_not_null(owner_payload)
	assert_eq(owner_payload, {
		"recipient_seat": 2,
		"hand_seq": 3,
		"subjects": [
			{"seat": 0, "wait_tile_ids": [TileId.W1]},
			{"seat": 3, "wait_tile_ids": [TileId.T3, TileId.T6]},
		],
	})
	for seat in [0, 1, 3]:
		assert_null(provider.serialize({"state": state}, seat),
			"未授权席位不得获得等待牌模块")


func test_real_wire_json_nbc_restore_and_optional_absence_clears_old_value() -> void:
	var state := BattleState.for_east_round(346, 0, 1, 0, 0, TileId.E, 4)
	state.tenpai_wait_reveals = {2: {1: [TileId.S_WIND]}}
	state.tenpai_flags[1] = true
	var registry := _registry()
	var serialized := registry.serialize_modules({"state": state,
		"character_ids": ["lin_yeche", "an_cheng", "bai_touli", "hua_ling"],
		"participants": ["HUMAN", "AI", "AI", "AI"],
	}, 2)
	assert_true(bool(serialized.get("ok", false)), str(serialized))
	var wire := _wire(serialized.get("modules", []), 2, 1)
	var event := NetworkedEvent.from_dict(wire)
	assert_not_null(event, "viewer_tenpai_waits@1 必须通过真实 wire validator")
	var decoded := JsonTransportDecoder.decode_event(JSON.stringify(wire))
	assert_not_null(decoded, "viewer_tenpai_waits@1 必须通过 JSON transport")
	var nbc := NetworkedBattleController.new("viewer-tenpai-waits-contract", 2)
	nbc.snapshot_registry = registry
	assert_true(nbc.ingest_networked_event(decoded), nbc.last_snapshot_error())
	assert_eq(nbc.get_viewer_tenpai_waits_view().get("subjects", []).size(), 1)
	state.tenpai_wait_reveals.clear()
	var cleared := registry.serialize_modules({"state": state,
		"character_ids": ["lin_yeche", "an_cheng", "bai_touli", "hua_ling"],
		"participants": ["HUMAN", "AI", "AI", "AI"],
	}, 2)
	assert_true(_module(cleared.get("modules", []), "viewer_tenpai_waits").is_empty())
	var cleared_event := NetworkedEvent.from_dict(
		_wire(cleared.get("modules", []), 2, 2))
	assert_not_null(cleared_event)
	assert_true(nbc.ingest_networked_event(cleared_event))
	assert_true(nbc.get_viewer_tenpai_waits_view().is_empty(),
		"下一帧省略 optional 模块必须清除旧等待牌")


func test_wrong_recipient_unsorted_duplicate_and_cross_hand_fail_closed() -> void:
	var state := BattleState.for_east_round(346, 0, 1, 0, 0, TileId.E, 5)
	state.tenpai_wait_reveals = {0: {1: [TileId.T3, TileId.T6]}}
	state.tenpai_flags[1] = true
	var registry := _registry()
	var modules := (registry.serialize_modules({"state": state,
		"character_ids": ["lin_yeche", "an_cheng", "bai_touli", "hua_ling"],
		"participants": ["HUMAN", "AI", "AI", "AI"],
	}, 0)
		.get("modules", []) as Array)
	var cases: Array = []
	var wrong_recipient := modules.duplicate(true)
	(_module(wrong_recipient, "viewer_tenpai_waits").payload as Dictionary).recipient_seat = 1
	cases.append(wrong_recipient)
	var duplicate_wait := modules.duplicate(true)
	var waits := (((_module(duplicate_wait, "viewer_tenpai_waits").payload as Dictionary)
		.subjects as Array)[0] as Dictionary).wait_tile_ids as Array
	waits[1] = waits[0]
	cases.append(duplicate_wait)
	var cross_hand := modules.duplicate(true)
	(_module(cross_hand, "viewer_tenpai_waits").payload as Dictionary).hand_seq = 6
	cases.append(cross_hand)
	for bad in cases:
		assert_null(NetworkedEvent.from_dict(_wire(bad as Array, 0, 1)),
			"非法等待牌投影必须在 wire 层拒绝")
