extends GutTest

# Issue #379 Round 5 Red：协议边界（纯 schema + mode，无 FULL_GRANT，≤5s）
# authority journal 投影的 payload 端到端见 grant_chain（真实 Action 链）。
# 本文件明确边界：不冒充 authority projector 端到端；不直调 activate_single_skill。

const VIEW_HASH := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const ROOM := "room-379-r5-schema"

const FAMILY_SOURCES := [
	["GAME_BEGIN", "char_washizu_passive_v1", "character"],
	["TILE_DRAWN", "char_akagi_passive_v1", "character"],
	["WIN_DECLARED_PRE", "char_saki_passive_v1", "character"],
	["RIICHI_DECLARED", "char_momoko_passive_v1", "character"],
]


func test_skill_triggered_kind_registered() -> void:
	assert_true("SKILL_TRIGGERED" in NetworkedEvent.EVENT_KINDS,
		"#379 须将 SKILL_TRIGGERED 纳入 NetworkedEvent.EVENT_KINDS")


func test_mode_bundle_tt_accepts_std_rejects() -> void:
	var tt := ModeModuleBundle.from_config(GameSessionConfig.create_validated(
		GameSessionConfig.ROOM_PUBLIC_CASUAL, GameSessionConfig.ROUND_EAST,
		GameSessionConfig.MODE_TRASH_TALK,
		[&"HUMAN", &"HUMAN", &"HUMAN", &"HUMAN"],
		[&"hua_ling", &"lin_yeche", &"qiu_jue", &"bai_touli"],
		1, "tt", "rv-253"))
	assert_true(tt.accepts_event_kind("SKILL_TRIGGERED"),
		"TRASH_TALK 须 accept SKILL_TRIGGERED（Green：纳入 TT event 白/灰名单策略）")
	var std := ModeModuleBundle.from_config(GameSessionConfig.create_validated(
		GameSessionConfig.ROOM_PRACTICE, GameSessionConfig.ROUND_EAST,
		GameSessionConfig.MODE_STANDARD,
		[&"HUMAN", &"AI", &"AI", &"AI"],
		[&"hua_ling", &"lin_yeche", &"qiu_jue", &"bai_touli"],
		2, "std", "rv-253"))
	assert_false(std.accepts_event_kind("SKILL_TRIGGERED"),
		"STANDARD 须拒绝 SKILL_TRIGGERED（当前未在 TRASH_TALK_EVENT_KINDS → accepts=true 为 Red）")


func test_schema_make_requires_kind_and_minimal_fields() -> void:
	# 固定 schema 契约（非 authority 投影端到端）
	for row_v in FAMILY_SOURCES:
		var row: Array = row_v
		var payload := {
			"actor_seat": 0,
			"beneficiary_seat": 0,
			"skill_id": str(row[1]),
			"skill_name": "schema",
			"source_event": str(row[0]),
			"source_kind": str(row[2]),
			"hand_seq": 0,
		}
		var made: NetworkedEvent = NetworkedEvent.make(
			"SKILL_TRIGGERED", 1, ROOM, payload, VIEW_HASH)
		assert_not_null(made,
			"Green：kind 注册后 make 须接受 source_event=%s；Red：kind 缺失 → null" % str(row[0]))


func test_schema_rejects_private_fields() -> void:
	var payload := {
		"actor_seat": 0,
		"beneficiary_seat": 0,
		"skill_id": "char_washizu_passive_v1",
		"skill_name": "x",
		"source_event": "GAME_BEGIN",
		"source_kind": "character",
		"hand_seq": 0,
		"tiles": [{"instance_id": 1}],
		"wall_top": [1, 2],
		"private_hand": [3],
		"waits": [TileId.W1],
	}
	var env := {
		"protocol_version": ProtocolConstants.PROTOCOL_VERSION,
		"server_seq": 2,
		"room_id": ROOM,
		"kind": "SKILL_TRIGGERED",
		"payload": payload,
		"view_hash": VIEW_HASH,
	}
	# kind 未注册时 from_dict 亦 null；Green 后仍须拒私有字段
	assert_null(NetworkedEvent.from_dict(env), "私有字段或未注册 kind 须拒绝")


func test_schema_relic_fields_shape() -> void:
	var payload := {
		"actor_seat": 1,
		"beneficiary_seat": 1,
		"skill_id": "relic_lucky_cat_v1",
		"skill_name": "招财猫",
		"source_event": "WIN_DECLARED_PRE",
		"source_kind": "relic",
		"hand_seq": 0,
		"item_instance_id": "ii_relic_1",
		"extra_dora_delta": 1,
	}
	var made: NetworkedEvent = NetworkedEvent.make(
		"SKILL_TRIGGERED", 3, ROOM, payload, VIEW_HASH)
	assert_not_null(made, "relic 与 character 共用 kind（Green 后）")
