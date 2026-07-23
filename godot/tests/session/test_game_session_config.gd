extends GutTest

# E2-01（#231）：正式 GameSessionConfig 契约。
# Intent 属 #228；Config / 转换 / 序列化属本 Issue。

const CONFIG_SCRIPT := "res://session/game_session_config.gd"
const LAUNCHER_SCRIPT := "res://session/practice_session_launcher.gd"

const WIRE_ROOM := ["PRACTICE", "PUBLIC_CASUAL"]
const WIRE_ROUND := ["EAST", "HANCHAN"]
const WIRE_MODE := ["STANDARD", "TRASH_TALK"]
const WIRE_PARTICIPANT := ["HUMAN", "AI"]

const INT64_MAX := 9223372036854775807
const INT64_MIN := -9223372036854775808

const EIGHT_INTENTS := [
	[&"PRACTICE", &"EAST", &"STANDARD"],
	[&"PRACTICE", &"EAST", &"TRASH_TALK"],
	[&"PRACTICE", &"HANCHAN", &"STANDARD"],
	[&"PRACTICE", &"HANCHAN", &"TRASH_TALK"],
	[&"PUBLIC_CASUAL", &"EAST", &"STANDARD"],
	[&"PUBLIC_CASUAL", &"EAST", &"TRASH_TALK"],
	[&"PUBLIC_CASUAL", &"HANCHAN", &"STANDARD"],
	[&"PUBLIC_CASUAL", &"HANCHAN", &"TRASH_TALK"],
]

# LCG unsigned-32 Numerical Recipes 黄金向量（player=lin_yeche）
const GOLD_SEED_0 := [&"lin_yeche", &"xian_shi", &"hua_ling", &"ying_li"]
const GOLD_SEED_12345 := [&"lin_yeche", &"an_cheng", &"bao_luo", &"ji_shu"]
const GOLD_SEED_NEG1 := [&"lin_yeche", &"an_cheng", &"bao_luo", &"lian_yao"]
const GOLD_SEED_HIGH := [&"lin_yeche", &"bai_touli", &"ju_jin", &"hua_ling"]


func _load_config_script() -> GDScript:
	if not ResourceLoader.exists(CONFIG_SCRIPT):
		return null
	return load(CONFIG_SCRIPT) as GDScript


func _make_intent(
	room: StringName,
	p_round_kind: StringName,
	mode: StringName,
	char_id: StringName = &""
) -> SessionIntent:
	return SessionIntent.new(room, p_round_kind, mode, char_id)


func _practice_ok_args() -> Dictionary:
	return {
		"seed": 42,
		"session_id": "practice-sess-001",
		"rule_version": "riichi-v1",
	}


func _public_authority(
	participants: Array = ["HUMAN", "HUMAN", "AI", "AI"],
	character_ids: Array = ["lin_yeche", "qiu_jue", "bai_touli", "hua_ling"],
	p_seed: int = 7,
	session_id: String = "public-sess-001",
	rule_version: String = "riichi-v1",
	p_room_kind: String = "PUBLIC_CASUAL",
	p_round_kind: String = "EAST",
	p_game_mode: String = "STANDARD"
) -> Dictionary:
	return {
		"room_kind": p_room_kind,
		"round_kind": p_round_kind,
		"game_mode": p_game_mode,
		"participants": participants.duplicate(),
		"character_ids": character_ids.duplicate(),
		"seed": p_seed,
		"session_id": session_id,
		"rule_version": rule_version,
	}


func _from_intent(
	script: GDScript,
	intent: Variant,
	p_seed: int,
	session_id: String,
	rule_version: String,
	authority: Dictionary = {}
) -> Variant:
	return script.call(
		"from_intent",
		intent,
		p_seed,
		session_id,
		rule_version,
		authority
	)


func test_config_script_exists_as_pure_session_value() -> void:
	assert_true(ResourceLoader.exists(CONFIG_SCRIPT), "#231 应新增 GameSessionConfig 正式配置")
	var script := _load_config_script()
	assert_not_null(script, "GameSessionConfig 脚本应可加载")
	if script == null:
		return
	assert_true(
		String(script.source_code).contains("class_name GameSessionConfig"),
		"必须暴露 class_name GameSessionConfig"
	)


func test_named_enums_exist_with_stable_int_values_and_wire_map() -> void:
	var script := _load_config_script()
	assert_not_null(script)
	if script == null:
		return
	# 加载后 class_name 注册；真正的命名 enum（非整散 const 冒充）
	assert_not_null(script.new())

	# 显式稳定整数值（经 class_name 访问命名 enum）
	assert_eq(GameSessionConfig.GameMode.STANDARD, 0)
	assert_eq(GameSessionConfig.GameMode.TRASH_TALK, 1)
	assert_eq(GameSessionConfig.RoomKind.PRACTICE, 0)
	assert_eq(GameSessionConfig.RoomKind.PUBLIC_CASUAL, 1)
	assert_eq(GameSessionConfig.RoundKind.EAST, 0)
	assert_eq(GameSessionConfig.RoundKind.HANCHAN, 1)
	assert_eq(GameSessionConfig.ParticipantKind.HUMAN, 0)
	assert_eq(GameSessionConfig.ParticipantKind.AI, 1)

	# enum keys 与冻结 wire 一致
	assert_eq(GameSessionConfig.GameMode.keys(), WIRE_MODE)
	assert_eq(GameSessionConfig.RoomKind.keys(), WIRE_ROOM)
	assert_eq(GameSessionConfig.RoundKind.keys(), WIRE_ROUND)
	assert_eq(GameSessionConfig.ParticipantKind.keys(), WIRE_PARTICIPANT)

	# wire 字符串常量仍冻结
	assert_eq(script.ROOM_PRACTICE, &"PRACTICE")
	assert_eq(script.ROOM_PUBLIC_CASUAL, &"PUBLIC_CASUAL")
	assert_eq(script.ROUND_EAST, &"EAST")
	assert_eq(script.ROUND_HANCHAN, &"HANCHAN")
	assert_eq(script.MODE_STANDARD, &"STANDARD")
	assert_eq(script.MODE_TRASH_TALK, &"TRASH_TALK")
	assert_eq(script.PARTICIPANT_HUMAN, &"HUMAN")
	assert_eq(script.PARTICIPANT_AI, &"AI")
	assert_eq(script.WIRE_ROOM_KINDS, WIRE_ROOM)
	assert_eq(script.WIRE_ROUND_KINDS, WIRE_ROUND)
	assert_eq(script.WIRE_GAME_MODES, WIRE_MODE)
	assert_eq(script.WIRE_PARTICIPANT_KINDS, WIRE_PARTICIPANT)

	# 映射双向锁定
	assert_eq(script.call("room_kind_to_wire", GameSessionConfig.RoomKind.PRACTICE), &"PRACTICE")
	assert_eq(script.call("room_kind_to_wire", GameSessionConfig.RoomKind.PUBLIC_CASUAL), &"PUBLIC_CASUAL")
	assert_eq(script.call("round_kind_to_wire", GameSessionConfig.RoundKind.EAST), &"EAST")
	assert_eq(script.call("round_kind_to_wire", GameSessionConfig.RoundKind.HANCHAN), &"HANCHAN")
	assert_eq(script.call("game_mode_to_wire", GameSessionConfig.GameMode.STANDARD), &"STANDARD")
	assert_eq(script.call("game_mode_to_wire", GameSessionConfig.GameMode.TRASH_TALK), &"TRASH_TALK")
	assert_eq(script.call("participant_kind_to_wire", GameSessionConfig.ParticipantKind.HUMAN), &"HUMAN")
	assert_eq(script.call("participant_kind_to_wire", GameSessionConfig.ParticipantKind.AI), &"AI")

	assert_eq(script.call("room_kind_from_wire", &"PRACTICE"), GameSessionConfig.RoomKind.PRACTICE)
	assert_eq(script.call("room_kind_from_wire", &"PUBLIC_CASUAL"), GameSessionConfig.RoomKind.PUBLIC_CASUAL)
	assert_eq(script.call("round_kind_from_wire", &"EAST"), GameSessionConfig.RoundKind.EAST)
	assert_eq(script.call("round_kind_from_wire", &"HANCHAN"), GameSessionConfig.RoundKind.HANCHAN)
	assert_eq(script.call("game_mode_from_wire", &"STANDARD"), GameSessionConfig.GameMode.STANDARD)
	assert_eq(script.call("game_mode_from_wire", &"TRASH_TALK"), GameSessionConfig.GameMode.TRASH_TALK)
	assert_eq(script.call("participant_kind_from_wire", &"HUMAN"), GameSessionConfig.ParticipantKind.HUMAN)
	assert_eq(script.call("participant_kind_from_wire", &"AI"), GameSessionConfig.ParticipantKind.AI)
	assert_eq(script.call("room_kind_from_wire", &"RANKED"), -1)


func test_all_eight_intents_convert_with_mode_id_and_field_whitelist() -> void:
	var script := _load_config_script()
	assert_not_null(script)
	if script == null:
		return
	var args := _practice_ok_args()
	for row in EIGHT_INTENTS:
		var intent := _make_intent(row[0], row[1], row[2])
		var authority := {}
		var p_seed: int = int(args["seed"])
		var session_id: String = str(args["session_id"])
		var rule_version: String = str(args["rule_version"])
		if intent.room_kind == &"PUBLIC_CASUAL":
			authority = _public_authority(
				["HUMAN", "HUMAN", "AI", "AI"],
				["lin_yeche", "qiu_jue", "bai_touli", "hua_ling"],
				7,
				"public-sess-001",
				"riichi-v1",
				"PUBLIC_CASUAL",
				String(row[1]),
				String(row[2])
			)
			p_seed = 0
			session_id = ""
			rule_version = ""
		var result: Variant = _from_intent(
			script, intent, p_seed, session_id, rule_version, authority
		)
		assert_not_null(result, "8 种 Intent 都必须返回 Result")
		assert_true(result.ok, "合法 Intent 必须转换成功: %s" % intent.mode_id())
		assert_eq(result.error_code, &"")
		var cfg: Variant = result.config
		assert_not_null(cfg)
		assert_eq(cfg.room_kind, row[0])
		assert_eq(cfg.round_kind, row[1])
		assert_eq(cfg.game_mode, row[2])
		assert_eq(cfg.participants.size(), 4)
		assert_eq(cfg.character_ids.size(), 4)
		assert_eq(
			cfg.mode_id(),
			intent.mode_id(),
			"cfg.mode_id() 必须稳定还原 8 个 mode_id 且等于 intent.mode_id()"
		)


func test_practice_forces_human_ai_ai_ai_and_defaults_player_character() -> void:
	var script := _load_config_script()
	assert_not_null(script)
	if script == null:
		return
	var intent := _make_intent(&"PRACTICE", &"EAST", &"STANDARD")
	var result: Variant = _from_intent(
		script, intent, 99, "s-practice", "rv1"
	)
	assert_true(result.ok)
	var cfg: Variant = result.config
	assert_eq(cfg.participants, [&"HUMAN", &"AI", &"AI", &"AI"])
	var default_id: StringName = CharacterPool.all()[0].id
	assert_eq(default_id, &"lin_yeche")
	assert_eq(cfg.character_ids[0], default_id)
	assert_eq(cfg.seed, 99)
	assert_eq(cfg.session_id, "s-practice")
	assert_eq(cfg.rule_version, "rv1")


func test_practice_explicit_player_character_is_honored() -> void:
	var script := _load_config_script()
	assert_not_null(script)
	if script == null:
		return
	var intent := _make_intent(&"PRACTICE", &"HANCHAN", &"TRASH_TALK", &"qiu_jue")
	var result: Variant = _from_intent(script, intent, 11, "s2", "rv1")
	assert_true(result.ok)
	assert_eq(result.config.character_ids[0], &"qiu_jue")


func test_practice_ai_selection_stable_unique_and_excludes_player() -> void:
	var script := _load_config_script()
	assert_not_null(script)
	if script == null:
		return
	var intent := _make_intent(&"PRACTICE", &"EAST", &"STANDARD", &"lin_yeche")
	var r1: Variant = _from_intent(script, intent, 12345, "s-a", "rv1")
	var r2: Variant = _from_intent(script, intent, 12345, "s-b", "rv1")
	assert_true(r1.ok and r2.ok)
	var ids1: Array = r1.config.character_ids.duplicate()
	var ids2: Array = r2.config.character_ids.duplicate()
	assert_eq(ids1, ids2, "同 seed + 同玩家角色 → 三 AI 选择必须稳定")
	assert_eq(ids1[0], &"lin_yeche")
	var seen := {}
	for i in range(4):
		var cid: StringName = ids1[i]
		assert_false(String(cid).is_empty(), "角色 id 不得为空")
		assert_not_null(CharacterPool.find(cid), "角色必须在 CharacterPool: %s" % cid)
		if i > 0:
			assert_ne(cid, &"lin_yeche", "三 AI 不得等于玩家角色")
		assert_false(seen.has(cid), "练习四席角色不得重复: %s" % cid)
		seen[cid] = true
	var r3: Variant = _from_intent(script, intent, 99999, "s-c", "rv1")
	assert_true(r3.ok)
	assert_ne(
		str(r1.config.character_ids),
		str(r3.config.character_ids),
		"不同 seed 应改变练习 AI 角色选择"
	)


func test_lcg_unsigned32_gold_vectors_for_character_ids() -> void:
	var script := _load_config_script()
	assert_not_null(script)
	if script == null:
		return
	var intent := _make_intent(&"PRACTICE", &"EAST", &"STANDARD", &"lin_yeche")
	var cases: Array = [
		[0, GOLD_SEED_0],
		[12345, GOLD_SEED_12345],
		[-1, GOLD_SEED_NEG1],
		[0x80000000, GOLD_SEED_HIGH],  # 2147483648
		[-2147483648, GOLD_SEED_HIGH],  # 同高位 state
	]
	for row in cases:
		var p_seed: int = row[0]
		var expected: Array = row[1]
		var result: Variant = _from_intent(script, intent, p_seed, "gold", "rv1")
		assert_true(result.ok, "seed=%s 必须成功" % p_seed)
		assert_eq(
			result.config.character_ids,
			expected,
			"LCG u32 黄金向量 seed=%s" % p_seed
		)


func test_both_modes_record_character_ids_scheme_a() -> void:
	var script := _load_config_script()
	assert_not_null(script)
	if script == null:
		return
	for mode in [&"STANDARD", &"TRASH_TALK"]:
		var intent := _make_intent(&"PRACTICE", &"EAST", mode, &"bai_touli")
		var result: Variant = _from_intent(script, intent, 5, "s-mode", "rv1")
		assert_true(result.ok, "模式 %s 必须记录四席角色" % mode)
		assert_eq(result.config.character_ids.size(), 4)
		assert_eq(result.config.character_ids[0], &"bai_touli")
	# STANDARD 后续绝不创建角色能力：本类不得实例化技能/能力对象
	var source: String = script.source_code
	for forbidden in ["SkillScheduler", "char_akagi_passive", "ability_id", "create_ability"]:
		assert_false(
			source.contains(forbidden),
			"Config 只记录身份/外观，不得创建能力：%s" % forbidden
		)


func test_public_requires_authority_context_and_does_not_client_derive() -> void:
	var script := _load_config_script()
	assert_not_null(script)
	if script == null:
		return
	var intent := _make_intent(&"PUBLIC_CASUAL", &"EAST", &"STANDARD", &"lin_yeche")
	var missing: Variant = _from_intent(script, intent, 42, "client-sess", "rv1", {})
	assert_false(missing.ok)
	assert_eq(missing.error_code, &"MISSING_AUTHORITY")
	assert_null(missing.config)

	var authority := _public_authority(
		["HUMAN", "AI", "HUMAN", "AI"],
		["hua_ling", "lin_yeche", "qiu_jue", "lin_yeche"],
		777,
		"auth-sess",
		"rv-public",
		"PUBLIC_CASUAL",
		"EAST",
		"STANDARD"
	)
	var ok_result: Variant = _from_intent(script, intent, 0, "", "", authority)
	assert_true(ok_result.ok)
	var cfg: Variant = ok_result.config
	assert_eq(cfg.participants, [&"HUMAN", &"AI", &"HUMAN", &"AI"])
	assert_eq(cfg.character_ids[0], &"hua_ling")
	assert_eq(cfg.character_ids[3], &"lin_yeche", "公共席允许同角色重复")
	assert_eq(cfg.seed, 777)
	assert_eq(cfg.session_id, "auth-sess")
	assert_eq(cfg.rule_version, "rv-public")
	var hijack: Variant = _from_intent(
		script, intent, 1, "hijack", "hijack-rv", authority
	)
	assert_true(hijack.ok)
	assert_eq(hijack.config.seed, 777)
	assert_eq(hijack.config.session_id, "auth-sess")
	assert_eq(hijack.config.rule_version, "rv-public")


func test_public_authority_binds_room_round_mode_and_rejects_mismatch() -> void:
	var script := _load_config_script()
	assert_not_null(script)
	if script == null:
		return
	var intent := _make_intent(&"PUBLIC_CASUAL", &"EAST", &"STANDARD")

	# 缺 room/round/mode → MISSING_AUTHORITY
	var incomplete := {
		"participants": ["HUMAN", "AI", "AI", "AI"],
		"character_ids": ["lin_yeche", "qiu_jue", "bai_touli", "hua_ling"],
		"seed": 1,
		"session_id": "s",
		"rule_version": "rv",
	}
	assert_eq(
		_from_intent(script, intent, 0, "", "", incomplete).error_code,
		&"MISSING_AUTHORITY"
	)

	# room 非 PUBLIC_CASUAL
	var bad_room := _public_authority(
		["HUMAN", "AI", "AI", "AI"],
		["lin_yeche", "qiu_jue", "bai_touli", "hua_ling"],
		1, "s", "rv", "PRACTICE", "EAST", "STANDARD"
	)
	assert_eq(
		_from_intent(script, intent, 0, "", "", bad_room).error_code,
		&"AUTHORITY_MISMATCH"
	)

	# authority round 与 Intent 不一致：客户端不得用 Intent 伪造成功
	var bad_round := _public_authority(
		["HUMAN", "AI", "AI", "AI"],
		["lin_yeche", "qiu_jue", "bai_touli", "hua_ling"],
		1, "s", "rv", "PUBLIC_CASUAL", "HANCHAN", "STANDARD"
	)
	var mismatch_round: Variant = _from_intent(script, intent, 0, "", "", bad_round)
	assert_false(mismatch_round.ok)
	assert_eq(mismatch_round.error_code, &"AUTHORITY_MISMATCH")
	assert_null(mismatch_round.config)

	# authority mode 与 Intent 不一致
	var bad_mode := _public_authority(
		["HUMAN", "AI", "AI", "AI"],
		["lin_yeche", "qiu_jue", "bai_touli", "hua_ling"],
		1, "s", "rv", "PUBLIC_CASUAL", "EAST", "TRASH_TALK"
	)
	assert_eq(
		_from_intent(script, intent, 0, "", "", bad_mode).error_code,
		&"AUTHORITY_MISMATCH"
	)

	# 成功时 Config 的 room/round/mode 来自 authority（与匹配 Intent 一致）
	var auth_ok := _public_authority(
		["HUMAN", "AI", "AI", "AI"],
		["lin_yeche", "qiu_jue", "bai_touli", "hua_ling"],
		9, "auth", "rv1", "PUBLIC_CASUAL", "EAST", "STANDARD"
	)
	var ok_r: Variant = _from_intent(script, intent, 0, "", "", auth_ok)
	assert_true(ok_r.ok)
	assert_eq(ok_r.config.room_kind, &"PUBLIC_CASUAL")
	assert_eq(ok_r.config.round_kind, &"EAST")
	assert_eq(ok_r.config.game_mode, &"STANDARD")

	# 非法类型：room/round/mode 不得 str() 静默强转
	var type_bad := _public_authority()
	type_bad["room_kind"] = 1
	assert_eq(
		_from_intent(script, intent, 0, "", "", type_bad).error_code,
		&"INVALID_WIRE_TYPE"
	)
	type_bad = _public_authority()
	type_bad["round_kind"] = null
	assert_eq(
		_from_intent(script, intent, 0, "", "", type_bad).error_code,
		&"INVALID_WIRE_TYPE"
	)
	type_bad = _public_authority()
	type_bad["game_mode"] = true
	assert_eq(
		_from_intent(script, intent, 0, "", "", type_bad).error_code,
		&"INVALID_WIRE_TYPE"
	)


func test_stable_error_codes_for_illegal_inputs() -> void:
	var script := _load_config_script()
	assert_not_null(script)
	if script == null:
		return
	var null_r: Variant = _from_intent(script, null, 1, "s", "rv")
	assert_false(null_r.ok)
	assert_eq(null_r.error_code, &"NULL_INTENT")
	assert_null(null_r.config)

	var bad_room := _make_intent(&"RANKED", &"EAST", &"STANDARD")
	assert_eq(
		_from_intent(script, bad_room, 1, "s", "rv").error_code,
		&"INVALID_ROOM_KIND"
	)
	var bad_round := _make_intent(&"PRACTICE", &"TONPUU", &"STANDARD")
	assert_eq(
		_from_intent(script, bad_round, 1, "s", "rv").error_code,
		&"INVALID_ROUND_KIND"
	)
	var bad_mode := _make_intent(&"PRACTICE", &"EAST", &"FUN")
	assert_eq(
		_from_intent(script, bad_mode, 1, "s", "rv").error_code,
		&"INVALID_GAME_MODE"
	)

	var practice := _make_intent(&"PRACTICE", &"EAST", &"STANDARD")
	assert_eq(
		_from_intent(script, practice, 1, "", "rv").error_code,
		&"EMPTY_SESSION_ID"
	)
	assert_eq(
		_from_intent(script, practice, 1, "s", "").error_code,
		&"EMPTY_RULE_VERSION"
	)

	var empty_char := _make_intent(&"PRACTICE", &"EAST", &"STANDARD", &"")
	assert_true(_from_intent(script, empty_char, 1, "s", "rv").ok)
	var unknown := _make_intent(&"PRACTICE", &"EAST", &"STANDARD", &"not_a_character")
	assert_eq(
		_from_intent(script, unknown, 1, "s", "rv").error_code,
		&"UNKNOWN_CHARACTER_ID"
	)

	var pub := _make_intent(&"PUBLIC_CASUAL", &"EAST", &"STANDARD")
	var auth_bad_count := _public_authority(["HUMAN", "AI", "AI"], ["a", "b", "c"])
	assert_eq(
		_from_intent(script, pub, 0, "", "", auth_bad_count).error_code,
		&"INVALID_PARTICIPANTS_COUNT"
	)
	var auth_chars_count := {
		"room_kind": "PUBLIC_CASUAL",
		"round_kind": "EAST",
		"game_mode": "STANDARD",
		"participants": ["HUMAN", "AI", "AI", "AI"],
		"character_ids": ["lin_yeche", "qiu_jue"],
		"seed": 1,
		"session_id": "s",
		"rule_version": "rv",
	}
	assert_eq(
		_from_intent(script, pub, 0, "", "", auth_chars_count).error_code,
		&"INVALID_CHARACTER_IDS_COUNT"
	)
	var auth_empty_char := _public_authority(
		["HUMAN", "AI", "AI", "AI"],
		["lin_yeche", "", "qiu_jue", "bai_touli"]
	)
	assert_eq(
		_from_intent(script, pub, 0, "", "", auth_empty_char).error_code,
		&"EMPTY_CHARACTER_ID"
	)
	var auth_unknown := _public_authority(
		["HUMAN", "AI", "AI", "AI"],
		["lin_yeche", "ghost", "qiu_jue", "bai_touli"]
	)
	assert_eq(
		_from_intent(script, pub, 0, "", "", auth_unknown).error_code,
		&"UNKNOWN_CHARACTER_ID"
	)
	var auth_no_human := _public_authority(
		["AI", "AI", "AI", "AI"],
		["lin_yeche", "qiu_jue", "bai_touli", "hua_ling"]
	)
	assert_eq(
		_from_intent(script, pub, 0, "", "", auth_no_human).error_code,
		&"INVALID_PARTICIPANTS"
	)
	var auth_empty_session := _public_authority()
	auth_empty_session["session_id"] = ""
	assert_eq(
		_from_intent(script, pub, 0, "", "", auth_empty_session).error_code,
		&"EMPTY_SESSION_ID"
	)
	var auth_empty_rv := _public_authority()
	auth_empty_rv["rule_version"] = ""
	assert_eq(
		_from_intent(script, pub, 0, "", "", auth_empty_rv).error_code,
		&"EMPTY_RULE_VERSION"
	)


func test_authority_and_from_dict_strict_wire_types() -> void:
	var script := _load_config_script()
	assert_not_null(script)
	if script == null:
		return
	var pub := _make_intent(&"PUBLIC_CASUAL", &"EAST", &"STANDARD")

	# authority seed 只接受真正 TYPE_INT
	var auth := _public_authority()
	auth["seed"] = "7"
	assert_eq(
		_from_intent(script, pub, 0, "", "", auth).error_code,
		&"INVALID_SEED"
	)
	auth = _public_authority()
	auth["seed"] = 7.5
	assert_eq(
		_from_intent(script, pub, 0, "", "", auth).error_code,
		&"INVALID_SEED"
	)
	auth = _public_authority()
	auth["seed"] = null
	assert_eq(
		_from_intent(script, pub, 0, "", "", auth).error_code,
		&"INVALID_SEED"
	)
	auth = _public_authority()
	auth["seed"] = true
	assert_eq(
		_from_intent(script, pub, 0, "", "", auth).error_code,
		&"INVALID_SEED"
	)

	# session_id / rule_version 拒绝非 String/StringName
	auth = _public_authority()
	auth["session_id"] = 123
	assert_eq(
		_from_intent(script, pub, 0, "", "", auth).error_code,
		&"INVALID_WIRE_TYPE"
	)
	auth = _public_authority()
	auth["rule_version"] = null
	assert_eq(
		_from_intent(script, pub, 0, "", "", auth).error_code,
		&"INVALID_WIRE_TYPE"
	)

	# participants / character_ids item 拒绝 null/数值/布尔/对象
	auth = _public_authority(
		["HUMAN", 1, "AI", "AI"],
		["lin_yeche", "qiu_jue", "bai_touli", "hua_ling"]
	)
	assert_eq(
		_from_intent(script, pub, 0, "", "", auth).error_code,
		&"INVALID_WIRE_TYPE"
	)
	auth = _public_authority(
		["HUMAN", "AI", "AI", "AI"],
		["lin_yeche", null, "bai_touli", "hua_ling"]
	)
	assert_eq(
		_from_intent(script, pub, 0, "", "", auth).error_code,
		&"INVALID_WIRE_TYPE"
	)
	auth = _public_authority(
		["HUMAN", "AI", "AI", "AI"],
		["lin_yeche", true, "bai_touli", "hua_ling"]
	)
	assert_eq(
		_from_intent(script, pub, 0, "", "", auth).error_code,
		&"INVALID_WIRE_TYPE"
	)
	auth = _public_authority(
		["HUMAN", "AI", "AI", "AI"],
		["lin_yeche", {"id": "qiu_jue"}, "bai_touli", "hua_ling"]
	)
	assert_eq(
		_from_intent(script, pub, 0, "", "", auth).error_code,
		&"INVALID_WIRE_TYPE"
	)

	# from_dict：wire 字段严格类型，不得 str()/int() 静默强转
	var good: Dictionary = {
		"room_kind": "PRACTICE",
		"round_kind": "EAST",
		"game_mode": "STANDARD",
		"participants": ["HUMAN", "AI", "AI", "AI"],
		"character_ids": ["lin_yeche", "qiu_jue", "bai_touli", "hua_ling"],
		"seed": "42",
		"session_id": "from",
		"rule_version": "rv",
	}
	assert_not_null(script.call("from_dict", good))

	var bad: Dictionary = good.duplicate(true)
	bad["room_kind"] = 0
	assert_null(script.call("from_dict", bad))
	bad = good.duplicate(true)
	bad["session_id"] = 99
	assert_null(script.call("from_dict", bad))
	bad = good.duplicate(true)
	bad["rule_version"] = false
	assert_null(script.call("from_dict", bad))
	bad = good.duplicate(true)
	bad["participants"] = ["HUMAN", 2, "AI", "AI"]
	assert_null(script.call("from_dict", bad))
	bad = good.duplicate(true)
	bad["character_ids"] = ["lin_yeche", null, "bai_touli", "hua_ling"]
	assert_null(script.call("from_dict", bad))
	# seed 拒绝 JSON number / float / null
	bad = good.duplicate(true)
	bad["seed"] = 42
	assert_null(script.call("from_dict", bad), "seed 不得接受 JSON number")
	bad = good.duplicate(true)
	bad["seed"] = 1.5
	assert_null(script.call("from_dict", bad))
	bad = good.duplicate(true)
	bad["seed"] = null
	assert_null(script.call("from_dict", bad))
	bad = good.duplicate(true)
	bad["seed"] = "01"
	assert_null(script.call("from_dict", bad), "非规范十进制")
	bad = good.duplicate(true)
	bad["seed"] = "+42"
	assert_null(script.call("from_dict", bad))
	bad = good.duplicate(true)
	bad["seed"] = " 42"
	assert_null(script.call("from_dict", bad))
	bad = good.duplicate(true)
	bad["seed"] = "9223372036854775808"  # INT64_MAX+1
	assert_null(script.call("from_dict", bad))
	bad = good.duplicate(true)
	bad["seed"] = "-9223372036854775809"  # INT64_MIN-1
	assert_null(script.call("from_dict", bad))
	# 浮点阈值 (INT64_MAX/10) 精度丢失时可能漏拦的 19 位溢出前缀
	for overflow_seed in [
		"9223372036854775810",
		"9223372036854775900",
		"-9223372036854775810",
		"-9223372036854775900",
	]:
		bad = good.duplicate(true)
		bad["seed"] = overflow_seed
		assert_null(
			script.call("from_dict", bad),
			"int64 溢出 seed 必须拒绝: %s" % overflow_seed
		)
	# 规范十进制拒绝 -0
	bad = good.duplicate(true)
	bad["seed"] = "-0"
	assert_null(script.call("from_dict", bad), "规范十进制不得接受 -0")


func test_seed_wire_is_decimal_string_with_int64_roundtrip() -> void:
	var script := _load_config_script()
	assert_not_null(script)
	if script == null:
		return
	var cases: Array = [
		0,
		1,
		-1,
		42,
		INT64_MAX,
		INT64_MIN,
		2147483648,
		-2147483648,
	]
	for p_seed in cases:
		var intent := _make_intent(&"PRACTICE", &"EAST", &"STANDARD", &"lin_yeche")
		var result: Variant = _from_intent(
			script, intent, p_seed, "seed-rt", "rv1"
		)
		assert_true(result.ok, "seed=%s 练习转换应成功" % p_seed)
		var d: Dictionary = result.config.to_dict()
		assert_eq(typeof(d["seed"]), TYPE_STRING, "wire seed 必须是规范十进制字符串")
		assert_eq(d["seed"], str(p_seed), "wire seed 规范十进制")
		var json_text: String = JSON.stringify(d)
		var parsed: Variant = JSON.parse_string(json_text)
		assert_true(parsed is Dictionary)
		assert_eq(typeof(parsed["seed"]), TYPE_STRING)
		var restored: Variant = script.call("from_dict", parsed)
		assert_not_null(restored, "int64 边界 seed=%s 必须无损还原" % p_seed)
		assert_eq(restored.seed, p_seed, "int64 round-trip 精确 seed=%s" % p_seed)


func test_practice_rejects_duplicate_character_ids_public_allows() -> void:
	var script := _load_config_script()
	assert_not_null(script)
	if script == null:
		return
	var dups: Array = [&"lin_yeche", &"qiu_jue", &"lin_yeche", &"hua_ling"]
	var practice_cfg: Variant = script.call(
		"create_validated",
		&"PRACTICE",
		&"EAST",
		&"STANDARD",
		[&"HUMAN", &"AI", &"AI", &"AI"],
		dups,
		1,
		"s",
		"rv"
	)
	assert_null(practice_cfg, "PRACTICE 必须拒绝重复 character_ids")

	var practice_dict := {
		"room_kind": "PRACTICE",
		"round_kind": "EAST",
		"game_mode": "STANDARD",
		"participants": ["HUMAN", "AI", "AI", "AI"],
		"character_ids": ["lin_yeche", "qiu_jue", "lin_yeche", "hua_ling"],
		"seed": "1",
		"session_id": "s",
		"rule_version": "rv",
	}
	assert_null(script.call("from_dict", practice_dict), "from_dict PRACTICE 拒绝重复")

	var public_cfg: Variant = script.call(
		"create_validated",
		&"PUBLIC_CASUAL",
		&"EAST",
		&"STANDARD",
		[&"HUMAN", &"AI", &"AI", &"AI"],
		dups,
		1,
		"s",
		"rv"
	)
	assert_not_null(public_cfg, "PUBLIC 仍允许重复 character_ids")
	assert_eq(public_cfg.character_ids[0], &"lin_yeche")
	assert_eq(public_cfg.character_ids[2], &"lin_yeche")


func test_to_dict_from_dict_json_roundtrip_and_rejects_illegal() -> void:
	var script := _load_config_script()
	assert_not_null(script)
	if script == null:
		return
	var intent := _make_intent(&"PRACTICE", &"HANCHAN", &"TRASH_TALK", &"hua_ling")
	var result: Variant = _from_intent(script, intent, 2026, "json-sess", "rv-json")
	assert_true(result.ok)
	var cfg: Variant = result.config
	var d: Dictionary = cfg.to_dict()
	assert_eq(typeof(d["room_kind"]), TYPE_STRING)
	assert_eq(d["room_kind"], "PRACTICE")
	assert_eq(d["round_kind"], "HANCHAN")
	assert_eq(d["game_mode"], "TRASH_TALK")
	assert_eq(d["participants"], ["HUMAN", "AI", "AI", "AI"])
	assert_eq(d["character_ids"].size(), 4)
	assert_eq(d["character_ids"][0], "hua_ling")
	assert_eq(typeof(d["seed"]), TYPE_STRING)
	assert_eq(d["seed"], "2026")
	assert_eq(d["session_id"], "json-sess")
	assert_eq(d["rule_version"], "rv-json")

	var json_text: String = JSON.stringify(d)
	var parsed: Variant = JSON.parse_string(json_text)
	assert_true(parsed is Dictionary)
	var restored: Variant = script.call("from_dict", parsed)
	assert_not_null(restored, "合法 dict 必须还原 Config")
	assert_eq(restored.room_kind, cfg.room_kind)
	assert_eq(restored.round_kind, cfg.round_kind)
	assert_eq(restored.game_mode, cfg.game_mode)
	assert_eq(restored.participants, cfg.participants)
	assert_eq(restored.character_ids, cfg.character_ids)
	assert_eq(restored.seed, cfg.seed)
	assert_eq(restored.session_id, cfg.session_id)
	assert_eq(restored.rule_version, cfg.rule_version)

	assert_null(script.call("from_dict", {}))
	assert_null(script.call("from_dict", null))
	assert_null(script.call("from_dict", {"room_kind": "PRACTICE"}))
	var bad := d.duplicate(true)
	bad["room_kind"] = "RANKED"
	assert_null(script.call("from_dict", bad))
	bad = d.duplicate(true)
	bad["participants"] = ["HUMAN", "AI"]
	assert_null(script.call("from_dict", bad))
	bad = d.duplicate(true)
	bad["character_ids"] = ["lin_yeche", "ghost", "qiu_jue", "bai_touli"]
	assert_null(script.call("from_dict", bad))
	bad = d.duplicate(true)
	bad["session_id"] = ""
	assert_null(script.call("from_dict", bad))


func test_participants_and_character_ids_copy_on_read_not_alias() -> void:
	var script := _load_config_script()
	assert_not_null(script)
	if script == null:
		return
	var parts: Array = [&"HUMAN", &"AI", &"AI", &"AI"]
	var chars: Array = [&"lin_yeche", &"qiu_jue", &"bai_touli", &"hua_ling"]
	var cfg: Variant = script.call(
		"create_validated",
		&"PRACTICE",
		&"EAST",
		&"STANDARD",
		parts,
		chars,
		42,
		"alias-sess",
		"rv1"
	)
	assert_not_null(cfg, "create_validated 应产出合法 Config")
	parts[0] = &"AI"
	chars[1] = &"ghost"
	assert_eq(cfg.participants[0], &"HUMAN", "构造输入数组不得与 Config 共享别名")
	assert_eq(cfg.character_ids[1], &"qiu_jue")

	# 直接取得可读属性后原地修改，不得影响 cfg / to_dict / launcher
	var got_parts: Array = cfg.participants
	var got_chars: Array = cfg.character_ids
	got_parts[0] = &"AI"
	got_chars[0] = &"mutated"
	assert_eq(cfg.participants[0], &"HUMAN", "copy-on-read：改取出数组不得污染 cfg")
	assert_eq(cfg.character_ids[0], &"lin_yeche")
	var d_after: Dictionary = cfg.to_dict()
	assert_eq(d_after["participants"][0], "HUMAN")
	assert_eq(d_after["character_ids"][0], "lin_yeche")

	if ResourceLoader.exists(LAUNCHER_SCRIPT):
		var launcher: Variant = (load(LAUNCHER_SCRIPT) as GDScript).new()
		var driver: Variant = launcher.launch(cfg)
		assert_not_null(driver, "篡改取出数组后 launcher 仍应接受合法 cfg")
		assert_eq(driver.seed, 42)

	var d: Dictionary = cfg.to_dict()
	d["participants"][0] = "AI"
	d["character_ids"][0] = "x"
	assert_eq(cfg.participants[0], &"HUMAN", "to_dict 输出数组不得回写 Config")
	assert_eq(cfg.character_ids[0], &"lin_yeche")

	var d2: Dictionary = {
		"room_kind": "PRACTICE",
		"round_kind": "EAST",
		"game_mode": "STANDARD",
		"participants": ["HUMAN", "AI", "AI", "AI"],
		"character_ids": ["lin_yeche", "qiu_jue", "bai_touli", "hua_ling"],
		"seed": "1",
		"session_id": "from",
		"rule_version": "rv",
	}
	var from_cfg: Variant = script.call("from_dict", d2)
	assert_not_null(from_cfg)
	d2["participants"][0] = "AI"
	d2["character_ids"][0] = "mutated"
	assert_eq(from_cfg.participants[0], &"HUMAN", "from_dict 不得与输入数组共享别名")
	assert_eq(from_cfg.character_ids[0], &"lin_yeche")
	var got2: Array = from_cfg.participants
	got2[1] = &"HUMAN"
	assert_eq(from_cfg.participants[1], &"AI", "再次 copy-on-read 保护")


func test_seed_session_id_rule_version_not_auto_generated() -> void:
	var script := _load_config_script()
	assert_not_null(script)
	if script == null:
		return
	var source: String = script.source_code
	for forbidden in ["Time.get", "randi", "randf", "OS.get_unique", "generate_uuid", "uuid"]:
		assert_false(
			source.to_lower().contains(forbidden.to_lower())
			if forbidden != "Time.get"
			else source.contains(forbidden),
			"seed/session_id/rule_version 不得自动生成：%s" % forbidden
		)


func test_config_source_boundary_no_ui_run_or_launcher_coupling() -> void:
	var script := _load_config_script()
	assert_not_null(script)
	if script == null:
		return
	var source: String = script.source_code
	for forbidden in [
		"LobbyShell",
		"RuleDrawer",
		"RunState",
		"NodeResult",
		"BattleNodeRunner",
		"PracticeSessionLauncher",
		"PlayableTable",
		"main.go",
	]:
		assert_false(source.contains(forbidden), "Config 不得越界依赖：%s" % forbidden)
	assert_true(
		source.contains("SessionIntent"),
		"Config 拥有 SessionIntent → Config 唯一转换"
	)
	if ResourceLoader.exists(LAUNCHER_SCRIPT):
		var launcher_src: String = (load(LAUNCHER_SCRIPT) as GDScript).source_code
		assert_false(
			launcher_src.contains("from_intent"),
			"转换实现必须只在 GameSessionConfig，不在 launcher"
		)
