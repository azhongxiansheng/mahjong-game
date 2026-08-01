extends GutTest

# ARCH-03 #393：NetworkedEvent envelope 与 payload codec 分离。
# 注册表在构造时冻结、按领域拆分 codec、未知 kind 拒绝；协议 fixture 完全兼容
# 由既有 test_networked_event / e5 fixture 套件回归证明。


func test_registry_covers_every_event_kind_with_domain_codec() -> void:
	var registry := EventPayloadCodecRegistry.new()
	for kind in NetworkedEvent.EVENT_KINDS:
		assert_true(registry.has_kind(String(kind)), "kind 缺 codec：%s" % kind)
	assert_eq(registry.kinds().size(), NetworkedEvent.EVENT_KINDS.size(),
		"注册表 kind 集与 EVENT_KINDS 完全一致")


func test_registry_rejects_unknown_and_control_kinds() -> void:
	var registry := EventPayloadCodecRegistry.new()
	for bad in ["", "ERROR", "COMMAND_RESULT", "NOT_A_KIND"]:
		assert_false(registry.has_kind(bad))
		assert_null(registry.validate(bad, {}, 1), "未知 kind 必须拒绝：%s" % bad)


func test_registry_is_frozen_after_construction() -> void:
	var registry := EventPayloadCodecRegistry.new()
	assert_false(registry.has_method("register"), "冻结注册表不得暴露 register")
	var before: int = registry.kinds().size()
	var leaked: Array = registry.kinds()
	leaked.clear()
	assert_eq(registry.kinds().size(), before, "kinds() 必须返回副本")


func test_domain_codecs_validate_their_kinds() -> void:
	# 每个领域 codec 直接可用（静态校验函数签名统一 (payload, server_seq)）
	var item_ok: Variant = RewardItemPayloadCodec.validate_item_consumed({
		"seat": 0,
		"item_id": "wall_peek_v1",
		"item_instance_id": "ii_x",
		"command_id": "550e8400-e29b-41d4-a716-000000000001",
	})
	assert_not_null(item_ok)
	var joined_ok: Variant = PresencePayloadCodec.validate_player_joined({
		"seat": 1,
		"participant_kind": "AI",
		"display_name": "测试",
		"connected": true,
	})
	assert_not_null(joined_ok)
	assert_null(PresencePayloadCodec.validate_player_joined({}))


func test_networked_event_behavior_unchanged_through_registry() -> void:
	var ne := NetworkedEvent.make("ITEM_CONSUMED", 7, "room-1", {
		"seat": 2,
		"item_id": "dora_charm_v1",
		"item_instance_id": "ii_y",
		"command_id": "550e8400-e29b-41d4-a716-000000000002",
	}, "0".repeat(64))
	assert_not_null(ne)
	assert_eq(ne.kind, "ITEM_CONSUMED")
	assert_null(NetworkedEvent.make("ERROR", 1, "room-1", {}, "0".repeat(64)))
	assert_null(NetworkedEvent.make("ITEM_CONSUMED", 1, "room-1", {"seat": 9}, "0".repeat(64)))
