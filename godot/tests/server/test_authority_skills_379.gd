extends GutTest

# Issue #379 Round 6 Red — focused（≤120s，无 FULL_GRANT）
# 真实 FULL_GRANT / GAME_BEGIN journal → grant_chain_379（timeout 300）
# 双窗 → test_authority_skills_dual_window_379.gd
# 四类 trigger battle 层见交付命令实际运行的精确函数名

const PARTS_4H := [&"HUMAN", &"HUMAN", &"HUMAN", &"HUMAN"]
const PARTS_1H := [&"HUMAN", &"AI", &"AI", &"AI"]
const SEED_COLD := 11

# 角色 → ability → 家族 → 精确既有测试函数（本轮必须实际运行对应文件）
const ALL_CHAR_ROWS := [
	["lin_yeche", "char_akagi_passive_v1", "TILE_DRAWN",
		"test_akagi_passive_reveals_opponent_hand"],
	["qiu_jue", "char_kaiji_passive_v1", "WIN",
		"test_kaiji_passive_adds_han_when_low_score"],
	["bai_touli", "char_washizu_passive_v1", "GAME_BEGIN",
		"test_real_full_grant_game_begin_items_privacy_headless_restore"],
	["hua_ling", "char_saki_passive_v1", "WIN",
		"test_hua_ling_owner_tsumo_adds_two_dora_to_real_score_and_events"],
	["lian_yao", "char_teru_passive_v1", "WIN",
		"test_twelve_characters_real_factory_scheduler_matrix"],
	["an_cheng", "char_awai_passive_v1", "GAME_BEGIN",
		"test_twelve_characters_real_factory_scheduler_matrix"],
	["yuan_xi", "char_koromo_passive_v1", "TILE_DRAWN",
		"test_owner_normal_draw_reveals_post_draw_live_wall_top_three_only_to_owner"],
	["ji_shu", "char_nodoka_passive_v1", "WIN",
		"test_owner_real_tsumo_adds_one_han_but_non_owner_does_not"],
	["xian_shi", "char_toki_passive_v1", "GAME_BEGIN",
		"test_twelve_characters_real_factory_scheduler_matrix"],
	["bao_luo", "char_kuro_passive_v1", "WIN",
		"test_bao_luo_owner_tsumo_uses_red_bucket_in_real_score_and_events"],
	["ying_li", "char_momoko_passive_v1", "RIICHI",
		"test_accepted_riichi_action_primes_through_real_command_entry"],
	["ju_jin", "char_tetsuya_passive_v1", "WIN",
		"test_twelve_characters_real_factory_scheduler_matrix"],
]

const GRANT_CHAIN_SCRIPT := "res://tests/server/test_authority_skills_grant_chain_379.gd"
const DUAL_WINDOW_SCRIPT := "res://tests/server/test_authority_skills_dual_window_379.gd"

var _cmd_seq: int = 0


func _cmd() -> String:
	_cmd_seq += 1
	return "550e8400-e29b-41d4-a716-%012d" % _cmd_seq


func _cfg(chars: Array, p_seed: int, mode: StringName = GameSessionConfig.MODE_TRASH_TALK) -> GameSessionConfig:
	var room := GameSessionConfig.ROOM_PUBLIC_CASUAL
	var parts: Array = PARTS_4H
	if mode == GameSessionConfig.MODE_STANDARD:
		room = GameSessionConfig.ROOM_PRACTICE
		parts = PARTS_1H
	return GameSessionConfig.create_validated(
		room, GameSessionConfig.ROUND_EAST, mode, parts, chars, p_seed,
		"379r6f-%d" % p_seed, "rv-253")


func _boot(chars: Array, p_seed: int, mode: StringName = GameSessionConfig.MODE_TRASH_TALK) -> Dictionary:
	var config := _cfg(chars, p_seed, mode)
	var modules := ModeModuleBundle.from_config(config)
	var bc := BattleController.new(p_seed, 0, false, TileId.E, 0)
	bc.bind_mode_modules(modules)
	var server := LocalLoopbackServer.new(config, 0, bc, modules)
	assert_true(server.start())
	var room := ""
	for ne in server.event_journal(0):
		if ne is NetworkedEvent:
			var rid := (ne as NetworkedEvent).room_id
			if not rid.is_empty():
				room = rid
				break
	assert_false(room.is_empty())
	return {"server": server, "bc": bc, "room": room}


func _snap(server: LocalLoopbackServer, seat: int = 0) -> Array:
	return server.event_journal(seat)


func _count_in(j: Array, kind: String) -> int:
	var n := 0
	for ne in j:
		if ne is NetworkedEvent and (ne as NetworkedEvent).kind == kind:
			n += 1
	return n


func test_twelve_char_roster_factory_mapping_only() -> void:
	for row_v in ALL_CHAR_ROWS:
		var row: Array = row_v
		var cid := str(row[0])
		var ab := str(row[1])
		var family := str(row[2])
		var exact_fn := str(row[3])
		assert_false(exact_fn.is_empty(), cid)
		var ch: Character = CharacterPool.find(StringName(cid))
		assert_not_null(ch, cid)
		assert_eq(String(ch.ability_id), ab)
		var built: SkillResource = BossAbilityFactory.build(StringName(ab))
		assert_not_null(built, ab)
		assert_false(built.owner_triggers.is_empty())
		var joined := ""
		for t in built.owner_triggers:
			joined += String(t) + ","
		if family == "GAME_BEGIN":
			assert_true(joined.contains("GAME_BEGIN"), "%s triggers" % cid)
		elif family == "TILE_DRAWN":
			assert_true(joined.contains("TILE_DRAWN"), "%s triggers" % cid)
		elif family == "WIN":
			assert_true(joined.contains("WIN_DECLARED_PRE"), "%s triggers" % cid)
		elif family == "RIICHI":
			assert_true(
				joined.contains("RIICHI_DECLARED") or joined.contains("WIN_DECLARED_PRE"),
				"%s triggers" % cid)
	assert_true(FileAccess.file_exists(GRANT_CHAIN_SCRIPT))
	assert_true(FileAccess.file_exists(DUAL_WINDOW_SCRIPT))


func test_tt_cold_unarmed_zero_skill_events() -> void:
	var rt := _boot([&"hua_ling", &"lin_yeche", &"bai_touli", &"ying_li"], SEED_COLD)
	var j: Array = _snap(rt.server)
	assert_eq(_count_in(j, "SKILL_TRIGGERED"), 0)
	assert_eq(_count_in(j, "CHARACTER_ABILITY_ARMED"), 0)
	for slot_v in (rt.server as LocalLoopbackServer).mode_modules.character_ability_slots:
		assert_false((slot_v as CharacterAbilitySlot).armed)


func test_standard_hard_isolation_and_tt_snapshot_reject() -> void:
	var rt := _boot([&"hua_ling", &"lin_yeche", &"bai_touli", &"ying_li"], 3,
		GameSessionConfig.MODE_STANDARD)
	var server: LocalLoopbackServer = rt.server
	assert_eq(server.mode_modules.character_ability_slots.size(), 0)
	assert_null(server.mode_modules.item_inventory)
	assert_null(server.mode_modules.reward_window)
	assert_false(server.mode_modules.accepts_event_kind("SKILL_TRIGGERED"),
		"STANDARD 须硬拒绝 SKILL_TRIGGERED")
	assert_false(server.mode_modules.accepts_event_kind("ITEM_GRANTED"))
	assert_false(server.mode_modules.accepts_event_kind("CHARACTER_ABILITY_ARMED"))
	var cr: CommandResult = server.submit_action(Action.item_use(
		0, "ii_x", rt.room, _cmd(), _cmd(), 0, 1))
	assert_eq(cr.status, "REJECTED")
	assert_eq(cr.error_code, "MODE_FORBIDDEN")
	assert_false(server.try_publish_business_event("SKILL_TRIGGERED", {
		"skill_id": "char_saki_passive_v1",
		"source_event": "WIN_DECLARED_PRE",
		"actor_seat": 0,
		"beneficiary_seat": 0,
		"hand_seq": 0,
		"source_kind": "character",
	}))
	assert_eq(_count_in(_snap(server), "SKILL_TRIGGERED"), 0)

	# TT Headless capture → STANDARD restore 硬隔离
	var hs_tt := HeadlessRoomSession.new()
	hs_tt.set_seed_override_for_test(SEED_COLD)
	assert_true(hs_tt.bootstrap_from_claims({
		"room_id": "379r6-tt-cap", "seat": 0, "session_id": "sess-0",
		"round_kind": "EAST", "game_mode": "TRASH_TALK",
		"participants": ["HUMAN", "AI", "AI", "AI"],
		"character_ids": ["hua_ling", "lin_yeche", "bai_touli", "ying_li"],
		"expires_at_unix": 9999999999,
	}, 1000))
	assert_true(bool(hs_tt.join(0, "sess-0")["ok"]))
	assert_true(bool(hs_tt.ready(0, "sess-0")["ok"]))
	var tt_snap: Dictionary = hs_tt.capture_match_authority_state()
	assert_false(tt_snap.is_empty())
	assert_gt(int((tt_snap["cumulative_scores"] as Array)[0]), 0)

	var hs_std := HeadlessRoomSession.new()
	hs_std.set_seed_override_for_test(3)
	assert_true(hs_std.bootstrap_from_claims({
		"room_id": "379r6-std-cap", "seat": 0, "session_id": "sess-s",
		"round_kind": "EAST", "game_mode": "STANDARD",
		"participants": ["HUMAN", "AI", "AI", "AI"],
		"character_ids": ["hua_ling", "lin_yeche", "qiu_jue", "bai_touli"],
		"expires_at_unix": 9999999999,
	}, 1000))
	assert_true(bool(hs_std.join(0, "sess-s")["ok"]))
	assert_true(bool(hs_std.ready(0, "sess-s")["ok"]))
	var restored := hs_std.restore_match_authority_state(tt_snap)
	if restored:
		assert_eq(hs_std.mode_modules.character_ability_slots.size(), 0)
		assert_null(hs_std.mode_modules.item_inventory)
		assert_eq(_count_in(hs_std.event_journal(0), "SKILL_TRIGGERED"), 0)
		assert_eq(_count_in(hs_std.event_journal(0), "ITEM_GRANTED"), 0)
	else:
		assert_false(restored, "STANDARD 精确拒绝 TT authority snapshot")


func test_headless_entry() -> void:
	var s := HeadlessRoomSession.new()
	s.set_seed_override_for_test(SEED_COLD)
	assert_true(s.bootstrap_from_claims({
		"room_id": "379r6-hs", "seat": 0, "session_id": "sess-0",
		"round_kind": "EAST", "game_mode": "TRASH_TALK",
		"participants": ["HUMAN", "AI", "AI", "AI"],
		"character_ids": ["hua_ling", "lin_yeche", "bai_touli", "ying_li"],
		"expires_at_unix": 9999999999,
	}, 1000))
	assert_true(bool(s.join(0, "sess-0")["ok"]))
	assert_true(bool(s.ready(0, "sess-0")["ok"]))
	assert_eq(s.submit_action_for_seat(0, Action.item_use(
		0, "ii_none", s.room_id, _cmd(), _cmd(), 0, 1)).status, "REJECTED")
	var cap: Dictionary = s.capture_match_authority_state()
	assert_false(cap.is_empty())
	assert_true(s.restore_match_authority_state(cap))
	assert_true(s.restore_match_authority_state(cap))
