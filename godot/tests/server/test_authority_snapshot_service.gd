extends GutTest

# ARCH-02 #392：AuthoritySnapshotService —— snapshot registry 持有、按席
# ROOM_SNAPSHOT payload 组装（ctx 键集 / headless match_authority@1 校验 /
# 顶层四键）与已提交 SNAP hash 回查。LLS 行为不变由 e3_07 / LLS 套件回归。

const VH := "0000000000000000000000000000000000000000000000000000000000000000"


func _bc() -> BattleController:
	return BattleController.new(42, 0, false, TileId.E)


## façade 实际提供的 ctx 键集：state + matching_meta 必需的 roster
## （character_ids / participants）+ match_authority 相关两键。
func _ctx(bc: BattleController, has_match_owner: bool, match_authority: Dictionary) -> Dictionary:
	return {
		"state": bc.state if bc != null else null,
		"character_ids": ["lin_yeche", "qiu_jue", "bai_touli", "hua_ling"],
		"participants": ["HUMAN", "AI", "AI", "AI"],
		"has_match_owner": has_match_owner,
		"match_authority": match_authority,
	}


func test_service_owns_registry_and_builds_standard_payload():
	var svc := AuthoritySnapshotService.new()
	svc.registry = SnapshotModuleRegistry.make_standard()
	var bc := _bc()
	var payload: Dictionary = svc.build_room_snapshot_payload(_ctx(bc, false, {}), 0, 5)
	assert_false(payload.is_empty(), "standard 最小输入应产出合法 payload")
	assert_eq(int(payload.get("snapshot_server_seq", -1)), 5)
	assert_eq(int(payload.get("next_server_seq", -1)), 6)
	assert_eq(int(payload.get("seat_view", -1)), 0)
	assert_false((payload.get("modules", []) as Array).is_empty())


func _valid_match_authority() -> Dictionary:
	return {
		"hand_index": 0, "hand_seq": 0, "next_hand_seq": 1, "dealer_seat": 0,
		"honba": 0, "riichi_sticks": 0, "cumulative_scores": [25000, 25000, 25000, 25000],
		"round_wind": TileId.E, "finished": false, "total_hands": 4, "hands_per_round": 4,
	}


func test_headless_requires_exactly_one_match_authority_module():
	var svc := AuthoritySnapshotService.new()
	svc.registry = SnapshotModuleRegistry.make_standard()
	var bc := _bc()
	# headless（有 match_owner）而 match_authority 为空 → 整 SNAP 失败
	assert_true(svc.build_room_snapshot_payload(_ctx(bc, true, {}), 0, 5).is_empty(),
		"headless 缺 match_authority 必须拒绝")
	# match_authority 存在但非法（provider serialize 返回 null → 模块缺失）→ 同样拒绝
	var bad: Dictionary = _valid_match_authority()
	bad["next_hand_seq"] = 9
	assert_true(svc.build_room_snapshot_payload(_ctx(bc, true, bad), 0, 5).is_empty(),
		"headless match_authority 非法必须拒绝")
	# 合法 match_authority → payload 含恰好一个 match_authority 模块
	var ok_pl: Dictionary = svc.build_room_snapshot_payload(
		_ctx(bc, true, _valid_match_authority()), 0, 5)
	assert_false(ok_pl.is_empty(), "headless 合法 match_authority 应通过")
	var ma_n := 0
	for m in (ok_pl.get("modules", []) as Array):
		if str((m as Dictionary).get("module_key", "")) == "match_authority":
			ma_n += 1
	assert_eq(ma_n, 1)


func test_practice_omits_empty_match_authority_module():
	var svc := AuthoritySnapshotService.new()
	svc.registry = SnapshotModuleRegistry.make_standard()
	var payload: Dictionary = svc.build_room_snapshot_payload(_ctx(_bc(), false, {}), 0, 5)
	assert_false(payload.is_empty())
	for m in (payload.get("modules", []) as Array):
		assert_ne(str((m as Dictionary).get("module_key", "")), "match_authority",
			"非 headless 且 match_authority 为空时不得注入该模块")


func test_null_registry_or_state_rejects():
	var svc := AuthoritySnapshotService.new()
	assert_true(svc.build_room_snapshot_payload(_ctx(null, false, {}), 0, 1).is_empty())
	svc.registry = SnapshotModuleRegistry.make_standard()
	assert_true(svc.build_room_snapshot_payload(_ctx(null, false, {}), 0, 1).is_empty())


func test_last_committed_snapshot_view_hash_scans_journal_backwards():
	assert_eq(AuthoritySnapshotService.last_committed_snapshot_view_hash([]), "")
	var pj: NetworkedEvent = NetworkedEvent.make("PLAYER_JOINED", 1, "room-s", {
		"seat": 0, "participant_kind": "AI", "display_name": "n", "connected": true,
	}, VH)
	assert_not_null(pj)
	assert_eq(AuthoritySnapshotService.last_committed_snapshot_view_hash([pj]), "",
		"无 SNAP 时返回空")
	# 真实 SNAP 事件经 LLS 生产路径拿到（envelope 强制 hash 一致，手工难造）：
	var cfg := GameSessionConfig.create_validated(
		GameSessionConfig.ROOM_PRACTICE, GameSessionConfig.ROUND_EAST,
		GameSessionConfig.MODE_STANDARD,
		[&"HUMAN", &"AI", &"AI", &"AI"],
		[&"lin_yeche", &"qiu_jue", &"bai_touli", &"hua_ling"],
		7, "sess-snap-svc", "rv-snap"
	)
	var server := LocalLoopbackServer.new(cfg, 0)
	assert_true(server.start())
	var journal: Array = server.event_journal(0)
	var expected := ""
	for i in range(journal.size() - 1, -1, -1):
		var ne: NetworkedEvent = journal[i] as NetworkedEvent
		if ne != null and ne.kind == "ROOM_SNAPSHOT":
			expected = ne.view_hash
			break
	assert_ne(expected, "")
	assert_eq(AuthoritySnapshotService.last_committed_snapshot_view_hash(journal), expected)


func test_lls_snapshot_registry_introspection_still_works():
	var cfg := GameSessionConfig.create_validated(
		GameSessionConfig.ROOM_PRACTICE, GameSessionConfig.ROUND_EAST,
		GameSessionConfig.MODE_STANDARD,
		[&"HUMAN", &"AI", &"AI", &"AI"],
		[&"lin_yeche", &"qiu_jue", &"bai_touli", &"hua_ling"],
		9, "sess-snap-lls", "rv-snap2"
	)
	var server := LocalLoopbackServer.new(cfg, 0)
	assert_not_null(server.snapshot_registry, "公开内省面保留")
	assert_true(server.snapshot_registry.is_standard_only())
