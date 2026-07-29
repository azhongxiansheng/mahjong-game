extends GutTest

# #376 P2-3：match_authority@1 exact schema + NBC 原子 restore


func _valid_payload() -> Dictionary:
	return {
		"hand_index": 0,
		"hand_seq": 0,
		"next_hand_seq": 1,
		"dealer_seat": 0,
		"honba": 0,
		"riichi_sticks": 0,
		"cumulative_scores": [25000, 25000, 25000, 25000],
		"round_wind": TileId.E,
		"finished": false,
		"total_hands": 4,
		"hands_per_round": 4,
	}


func test_exact_keys_reject_extra_and_missing() -> void:
	var p := MatchAuthoritySnapshotProvider.new()
	var good: Dictionary = _valid_payload()
	assert_true(p.can_restore(good, 0))
	var extra: Dictionary = good.duplicate(true)
	extra["forged"] = 1
	assert_false(p.can_restore(extra, 0), "额外键必须拒绝")
	var missing: Dictionary = good.duplicate(true)
	missing.erase("finished")
	assert_false(p.can_restore(missing, 0), "缺键必须拒绝")


func test_reject_impossible_combinations() -> void:
	var p := MatchAuthoritySnapshotProvider.new()
	var bad_dealer: Dictionary = _valid_payload()
	bad_dealer["dealer_seat"] = 9
	assert_false(p.can_restore(bad_dealer, 0))
	var bad_wind_east: Dictionary = _valid_payload()
	bad_wind_east["round_wind"] = TileId.S_WIND
	assert_false(p.can_restore(bad_wind_east, 0), "东风战不得南风")
	var bad_nhs: Dictionary = _valid_payload()
	bad_nhs["next_hand_seq"] = 3
	bad_nhs["hand_seq"] = 0
	assert_false(p.can_restore(bad_nhs, 0), "next_hand_seq 必须 hand_seq+1")
	var bad_hi: Dictionary = _valid_payload()
	bad_hi["hand_index"] = 4
	bad_hi["finished"] = false
	assert_false(p.can_restore(bad_hi, 0), "未终场 hand_index 须 < total_hands")
	var bad_hi_over: Dictionary = _valid_payload()
	bad_hi_over["hand_index"] = 5
	bad_hi_over["finished"] = false
	assert_false(p.can_restore(bad_hi_over, 0), "未终场 hand_index 不得 > total")
	var bad_fin: Dictionary = _valid_payload()
	bad_fin["finished"] = true
	bad_fin["hand_index"] = 3
	assert_false(p.can_restore(bad_fin, 0), "终场 hand_index 须 == total_hands")
	var bad_fin_over: Dictionary = _valid_payload()
	bad_fin_over["finished"] = true
	bad_fin_over["hand_index"] = 5
	bad_fin_over["hand_seq"] = 4
	bad_fin_over["next_hand_seq"] = 5
	assert_false(p.can_restore(bad_fin_over, 0), "终场 hand_index 不得 > total")
	var ok_fin: Dictionary = _valid_payload()
	ok_fin["finished"] = true
	ok_fin["hand_index"] = 4
	ok_fin["hand_seq"] = 3
	ok_fin["next_hand_seq"] = 4
	assert_true(p.can_restore(ok_fin, 0), "东风终场合法")
	var hanchan: Dictionary = _valid_payload()
	hanchan["total_hands"] = 8
	hanchan["hand_index"] = 4
	hanchan["round_wind"] = TileId.S_WIND
	hanchan["hand_seq"] = 4
	hanchan["next_hand_seq"] = 5
	assert_true(p.can_restore(hanchan, 0), "半庄南一场")
	hanchan["round_wind"] = TileId.E
	assert_false(p.can_restore(hanchan, 0), "南场 index 不得东风")
	# 终场半庄：wind 用最后完成局 index=total-1 → 南
	var han_fin: Dictionary = _valid_payload()
	han_fin["total_hands"] = 8
	han_fin["hands_per_round"] = 4
	han_fin["finished"] = true
	han_fin["hand_index"] = 8
	han_fin["hand_seq"] = 7
	han_fin["next_hand_seq"] = 8
	han_fin["round_wind"] = TileId.S_WIND
	assert_true(p.can_restore(han_fin, 0), "半庄终场南风")
	han_fin["round_wind"] = TileId.E
	assert_false(p.can_restore(han_fin, 0), "半庄终场不得误报东风")
	# hpr > total 非法
	var bad_hpr: Dictionary = _valid_payload()
	bad_hpr["hands_per_round"] = 8
	bad_hpr["total_hands"] = 4
	assert_false(p.can_restore(bad_hpr, 0))
	# 仅 EAST{4,4}/HANCHAN{8,4}
	var bad_combo: Dictionary = _valid_payload()
	bad_combo["total_hands"] = 6
	bad_combo["hands_per_round"] = 3
	assert_false(p.can_restore(bad_combo, 0), "非 EAST/HANCHAN 组合拒绝")
	var bad_hpr2: Dictionary = _valid_payload()
	bad_hpr2["total_hands"] = 8
	bad_hpr2["hands_per_round"] = 8
	assert_false(p.can_restore(bad_hpr2, 0), "半庄 hpr 必须 4")


func test_from_export_matches_game_driver_invariants() -> void:
	var d := GameDriver.new(7, 4, 4)
	# 生产投影仅在 start_hand 后出现：battle.hand_seq + next_hand_seq=hs+1
	var bc: IAuthoritativeBattleController = d.start_hand()
	assert_not_null(bc)
	var export0: Dictionary = d.export_match_state()
	var payload: Dictionary = MatchAuthoritySnapshotProvider.from_export(export0)
	var p := MatchAuthoritySnapshotProvider.new()
	assert_true(p.can_restore(payload, 0), "export 开局态须合法")
	assert_eq(int(payload["hand_seq"]) + 1, int(payload["next_hand_seq"]))
	assert_eq(int(payload["hand_index"]), 0)
	assert_false(bool(payload["finished"]))
	# 推进至终场（对齐 export 不变量）
	d.battle = null
	d.hand_index = 4
	d.finished = true
	d.next_hand_seq = 4
	var export_fin: Dictionary = d.export_match_state()
	var payload2: Dictionary = MatchAuthoritySnapshotProvider.from_export(export_fin)
	assert_true(p.can_restore(payload2, 0), "export 终场须合法")
	assert_eq(int(payload2["hand_index"]), 4)
	assert_eq(int(payload2["round_wind"]), TileId.E)
	assert_eq(int(payload2["hand_seq"]) + 1, int(payload2["next_hand_seq"]))



func test_nbc_restore_rejects_bad_without_pollution() -> void:
	var cfg := GameSessionConfig.create_validated(
		GameSessionConfig.ROOM_PUBLIC_CASUAL,
		GameSessionConfig.ROUND_EAST,
		GameSessionConfig.MODE_STANDARD,
		[&"HUMAN", &"AI", &"AI", &"AI"],
		[&"lin_yeche", &"an_cheng", &"bai_touli", &"hua_ling"],
		1, "room-ma", "rv"
	)
	var server := LocalLoopbackServer.new(cfg, 0)
	assert_true(server.start())
	var snap: NetworkedEvent = null
	for e in server.event_journal(0):
		if e is NetworkedEvent and (e as NetworkedEvent).kind == "ROOM_SNAPSHOT":
			snap = e as NetworkedEvent
			break
	assert_not_null(snap)
	# 篡改 match_authority 加额外键
	var payload: Dictionary = snap.payload.duplicate(true)
	var mods: Array = []
	for m0 in payload.get("modules", []):
		if typeof(m0) != TYPE_DICTIONARY:
			continue
		var m: Dictionary = (m0 as Dictionary).duplicate(true)
		if str(m.get("module_key", "")) == "match_authority":
			var pl: Dictionary = (m.get("payload", {}) as Dictionary).duplicate(true)
			pl["forged"] = 1
			m["payload"] = pl
		mods.append(m)
	payload["modules"] = mods
	var bad_ev: NetworkedEvent = NetworkedEvent.make(
		"ROOM_SNAPSHOT", int(snap.server_seq), "room-ma", payload, str(snap.view_hash)
	)
	var nbc := NetworkedBattleController.new("room-ma", 0)
	nbc.configure_snapshot_registry_for_mode("STANDARD")
	assert_false(nbc.ingest_networked_event(bad_ev), "额外键须拒绝 restore")
	# 合法 SNAP 可应用（新 NBC 未污染）
	var nbc2 := NetworkedBattleController.new("room-ma", 0)
	nbc2.configure_snapshot_registry_for_mode("STANDARD")
	assert_true(nbc2.ingest_networked_event(snap), "合法 SNAP 须成功")
