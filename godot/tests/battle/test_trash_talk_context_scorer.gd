extends GutTest

# E5-03 / #251 round-2：真实 NetworkedEvent schema + 纯评分器。
# 禁止 mock 核心规则；禁止 schema 非法 _evt 自证；禁止客户端自报标签注入。

const RULE_VERSION := "trash_talk_rules_v1"
const ROOM := "room_x"
const HAND_SEQ := 1
const CMD := "550e8400-e29b-41d4-a716-446655440000"
const DECISION := "550e8400-e29b-41d4-a716-4466554400aa"
const VIEW_HASH := "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
const TILES_PER_HAND := 136
const AFFINITY_KEYS := ["DOMINATION", "CALM", "CUNNING", "PASSION", "MYSTIC"]
# 完整 matrix 字节 digest（含 matched_rule_ids）；由真实 scorer 产出钉死
const GOLD_MATRIX_ZERO_DIGEST := "086e2205"
const GOLD_MATRIX_TEXT_DIGEST := "ea689d48"


# ---- 出口 / 黄金 / 基础契约 ----

func test_cancelled_by_win_rejects_matrix() -> void:
	var input := _gold_text_input("CANCELLED_BY_WIN")
	var out: Dictionary = TrashTalkContextScorer.score_matrix(input)
	assert_false(bool(out.get("ok", true)))
	assert_eq((out.get("matrix", []) as Array).size(), 0)
	assert_eq(String(out.get("reason", "")), "CANCELLED_BY_WIN")


func test_full_grant_and_display_only_byte_identical_matrix() -> void:
	var full := _gold_text_input("FULL_GRANT")
	var display := _gold_text_input("DISPLAY_ONLY")
	var a: Dictionary = TrashTalkContextScorer.score_matrix(full)
	var b: Dictionary = TrashTalkContextScorer.score_matrix(display)
	assert_true(bool(a.get("ok", false)))
	assert_true(bool(b.get("ok", false)))
	assert_eq(
		TrashTalkGoldFixtures.stable_digest(a["matrix"]),
		TrashTalkGoldFixtures.stable_digest(b["matrix"])
	)


func test_gold_zero_byte_identical_via_real_scorer() -> void:
	var fixture: Dictionary = TrashTalkGoldFixtures.gold_zero()
	var out: Dictionary = TrashTalkContextScorer.score_matrix(
		_input_from_fixture(fixture, "FULL_GRANT")
	)
	assert_true(bool(out.get("ok", false)), "gold_zero 必须评分成功: %s" % str(out.get("reason", "")))
	_assert_full_matrix_byte_identical(out, fixture)


func test_gold_text_byte_identical_via_real_scorer() -> void:
	var fixture: Dictionary = TrashTalkGoldFixtures.gold_text()
	var out: Dictionary = TrashTalkContextScorer.score_matrix(
		_input_from_fixture(fixture, "DISPLAY_ONLY")
	)
	assert_true(bool(out.get("ok", false)), "gold_text 必须评分成功: %s" % str(out.get("reason", "")))
	_assert_full_matrix_byte_identical(out, fixture)
	# 完整矩阵 digest 硬编码钉死（禁止先删字段/重排后比较）
	assert_eq(
		TrashTalkGoldFixtures.stable_digest(out["matrix"]),
		GOLD_MATRIX_TEXT_DIGEST,
		"gold_text 完整 matrix digest 漂移"
	)
	var silent_rows := 0
	var spoken_rows := 0
	for row in out["matrix"]:
		if int(row["seat"]) == 1:
			spoken_rows += 1
			assert_gt(int(row["expression"]), 0)
		else:
			silent_rows += 1
			assert_eq(int(row["expression"]), 0)
	assert_eq(spoken_rows, 4)
	assert_eq(silent_rows, 12)


func test_gold_zero_full_matrix_digest_hardcoded() -> void:
	var fixture: Dictionary = TrashTalkGoldFixtures.gold_zero()
	var out: Dictionary = TrashTalkContextScorer.score_matrix(
		_input_from_fixture(fixture, "FULL_GRANT")
	)
	assert_true(bool(out.get("ok", false)))
	assert_eq(
		TrashTalkGoldFixtures.stable_digest(out["matrix"]),
		GOLD_MATRIX_ZERO_DIGEST,
		"gold_zero 完整 matrix digest 漂移"
	)
	assert_eq(
		TrashTalkGoldFixtures.stable_stringify(out["matrix"]),
		TrashTalkGoldFixtures.stable_stringify(fixture["expected"]["matrix_components"])
	)


func test_component_ranges_and_total_are_int() -> void:
	var out: Dictionary = TrashTalkContextScorer.score_matrix(_gold_text_input("FULL_GRANT"))
	assert_true(bool(out.get("ok", false)))
	assert_eq((out["matrix"] as Array).size(), 16)
	for row in out["matrix"]:
		for key in ["persona", "item_tag", "public_context", "expression", "total_score"]:
			assert_eq(typeof(row[key]), TYPE_INT, "%s 必须 TYPE_INT" % key)
			var v: int = int(row[key])
			if key == "total_score":
				assert_true(v >= 0 and v <= 4000)
			else:
				assert_true(v >= 0 and v <= 1000)
		assert_eq(
			int(row["total_score"]),
			int(row["persona"]) + int(row["item_tag"]) + int(row["public_context"]) + int(row["expression"])
		)
		var ids: Array = row["matched_rule_ids"].duplicate()
		var sorted_ids: Array = ids.duplicate()
		sorted_ids.sort()
		assert_eq(ids, sorted_ids)
	var s := TrashTalkGoldFixtures.stable_stringify(out["matrix"])
	assert_false(s.contains("f:"), "矩阵不得含浮点标记")


func test_pool_item_order_is_lexicographic() -> void:
	var input := _gold_text_input("FULL_GRANT")
	input["pool_item_ids"] = [
		"wall_peek_v1", "relic_lucky_cat_v1", "double_payout_v1", "iron_shield_v1",
	]
	var out: Dictionary = TrashTalkContextScorer.score_matrix(input)
	assert_true(bool(out.get("ok", false)))
	var seen: Array = []
	for row in out["matrix"]:
		if int(row["seat"]) == 0:
			seen.append(String(row["item_id"]))
	var expected := seen.duplicate()
	expected.sort()
	assert_eq(seen, expected)


func test_silent_seat_full_row_expression_zero() -> void:
	var input := _base_input("FULL_GRANT")
	input["public_events"] = [_ne_action_applied(90, "RIICHI", 2)]
	var out: Dictionary = TrashTalkContextScorer.score_matrix(input)
	assert_true(bool(out.get("ok", false)))
	assert_eq((out["matrix"] as Array).size(), 16)
	for row in out["matrix"]:
		assert_eq(int(row["expression"]), 0)
		assert_eq(int(row["total_score"]), 0)


func test_client_forged_tags_and_hidden_fields_do_not_affect_matrix() -> void:
	var clean_in := _gold_text_input("FULL_GRANT")
	var clean: Dictionary = TrashTalkContextScorer.score_matrix(clean_in)
	assert_true(bool(clean.get("ok", false)))

	var dirty := clean_in.duplicate(true)
	dirty["public_context_tags_active"] = ["CTX_MELD_SEEN", "CTX_DORA_REVEALED", "CTX_SEAT_LEADING"]
	dirty["client_context"] = {"claimed_score": 99999}
	dirty["seats_private"] = [{"hand": ["1m"]}, {}, {}, {}]
	dirty["wall"] = {"remaining": 1}
	# public_initial 保持合法白名单（额外隐藏字段不得混入 initial）
	var polluted: Dictionary = TrashTalkContextScorer.score_matrix(dirty)
	assert_true(bool(polluted.get("ok", false)))
	assert_eq(
		TrashTalkGoldFixtures.stable_digest(clean["matrix"]),
		TrashTalkGoldFixtures.stable_digest(polluted["matrix"]),
		"伪造标签/隐藏字段不得改变矩阵"
	)
	var tags: Array = polluted.get("public_context_tags_active", [])
	assert_true(tags.has("CTX_RIICHI_OPEN"))
	assert_false(tags.has("CTX_MELD_SEEN"), "客户端 forged MELD 不得注入: %s" % str(tags))

	# public_initial 夹带未知键 → 整窗拒绝
	var dirty_ini := clean_in.duplicate(true)
	dirty_ini["public_initial"] = {
		"hand_seq": HAND_SEQ,
		"dealer_seat": 0,
		"scores": [25000, 25000, 25000, 25000],
		"hand": ["secret"],
	}
	var rej: Dictionary = TrashTalkContextScorer.score_matrix(dirty_ini)
	assert_false(bool(rej.get("ok", true)))
	assert_eq(String(rej.get("reason", "")), "PUBLIC_INITIAL_UNKNOWN_KEY")
	assert_eq((rej.get("matrix", []) as Array).size(), 0)


func test_public_initial_hand_seq_required_and_bound() -> void:
	var base := _base_input("FULL_GRANT")
	# 缺失 hand_seq
	var missing := base.duplicate(true)
	missing["public_initial"] = {
		"dealer_seat": 0,
		"scores": [25000, 25000, 25000, 25000],
	}
	var o1: Dictionary = TrashTalkContextScorer.score_matrix(missing)
	assert_false(bool(o1.get("ok", true)))
	assert_eq(String(o1.get("reason", "")), "PUBLIC_INITIAL_MISSING_FIELD")
	assert_eq((o1.get("matrix", []) as Array).size(), 0)

	# 跨手
	var cross := base.duplicate(true)
	cross["public_initial"] = {
		"hand_seq": HAND_SEQ + 3,
		"dealer_seat": 0,
		"scores": [25000, 25000, 25000, 25000],
	}
	var o2: Dictionary = TrashTalkContextScorer.score_matrix(cross)
	assert_false(bool(o2.get("ok", true)))
	assert_eq(String(o2.get("reason", "")), "PUBLIC_INITIAL_HAND_SEQ_MISMATCH")

	# 非法 dealer
	var bad_dealer := base.duplicate(true)
	bad_dealer["public_initial"] = {
		"hand_seq": HAND_SEQ,
		"dealer_seat": 9,
		"scores": [25000, 25000, 25000, 25000],
	}
	var o3: Dictionary = TrashTalkContextScorer.score_matrix(bad_dealer)
	assert_false(bool(o3.get("ok", true)))
	assert_eq(String(o3.get("reason", "")), "INVALID_DEALER_SEAT")

	# 非法 scores 长度
	var bad_scores := base.duplicate(true)
	bad_scores["public_initial"] = {
		"hand_seq": HAND_SEQ,
		"dealer_seat": 0,
		"scores": [25000, 25000],
	}
	var o4: Dictionary = TrashTalkContextScorer.score_matrix(bad_scores)
	assert_false(bool(o4.get("ok", true)))
	assert_eq(String(o4.get("reason", "")), "INVALID_SCORES")

	# adapter 非法 initial 稳定失败（不默认值吞掉）
	var ad: Dictionary = TrashTalkPublicContextAdapter.derive_seat_public_context_tags({
		"room_id": ROOM,
		"hand_seq": HAND_SEQ,
		"closing_boundary_server_seq": 100,
		"context_boundary_server_seq": 100,
		"public_initial": {"dealer_seat": 0, "scores": [1, 2, 3, 4]},
		"public_events": [],
	})
	assert_false(bool(ad.get("ok", true)))
	assert_eq(String(ad.get("reason", "")), "PUBLIC_INITIAL_MISSING_FIELD")


func test_battle_state_snapshot_is_valid_public_initial() -> void:
	var st: BattleState = BattleState.for_east_round(7, 1, 1, 0, 0, TileId.E, HAND_SEQ)
	assert_not_null(st)
	st.scores = [30000, 20000, 25000, 25000] as Array[int]
	var snap: Dictionary = TrashTalkPublicContextAdapter.public_snapshot_from_battle_state(st)
	assert_eq(int(snap.get("hand_seq", -1)), HAND_SEQ)
	var v: Dictionary = TrashTalkPublicContextAdapter.validate_public_initial(snap, HAND_SEQ)
	assert_true(bool(v.get("ok", false)), str(v.get("reason", "")))
	var input := _base_input("FULL_GRANT")
	input["public_initial"] = snap
	input["public_events"] = [_ne_action_applied(90, "RIICHI", 2)]
	input["utterances_by_seat"] = {
		"0": [], "1": [_utt("u1", "燃烧翻盘", "zh", 10)], "2": [], "3": [],
	}
	var out: Dictionary = TrashTalkContextScorer.score_matrix(input)
	assert_true(bool(out.get("ok", false)), str(out.get("reason", "")))
	# seat1 最高分 → LEADING；dealer seat1
	assert_true(out["public_context_tags_active"].has("CTX_SEAT_LEADING")
		or out["public_context_tags_active"].has("CTX_IS_DEALER"))


# ---- 真实 NetworkedEvent 边界 ----

func test_claim_pass_and_minkan_in_context_after_closing() -> void:
	var closing := 100
	var context := 110
	var events: Array = [
		_ne_action_applied(90, "RIICHI", 2),
		_ne_claim_window(101),
		_ne_action_applied(105, "PASS", 0),
		_ne_action_applied(106, "PASS", 1),
		_ne_action_applied(107, "PASS", 3),
		_ne_action_applied(111, "DISCARD", 0), # > context：排除
	]
	for e in events:
		assert_not_null(NetworkedEvent.from_dict(e), "fixture 必须 from_dict 成功: %s" % str(e.get("kind")))

	var input := _base_input("FULL_GRANT")
	input["closing_boundary_server_seq"] = closing
	input["context_boundary_server_seq"] = context
	input["public_events"] = events
	input["utterances_by_seat"] = {
		"0": [],
		"1": [_utt("u1", "燃烧翻盘必胜", "zh", 95)],
		"2": [],
		"3": [],
	}
	var out: Dictionary = TrashTalkContextScorer.score_matrix(input)
	assert_true(bool(out.get("ok", false)), str(out.get("reason", "")))
	var tags: Array = out.get("public_context_tags_active", [])
	assert_true(tags.has("CTX_RIICHI_OPEN"))
	assert_false(tags.has("CTX_MELD_SEEN"), "全 PASS 无鸣牌: %s" % str(tags))

	# 非和牌 MINKAN 在 context 内
	var meld_events: Array = [
		_ne_action_applied(90, "RIICHI", 2),
		_ne_claim_window(101),
		_ne_action_applied(105, "KAN", 0, _resolved_kan("MINKAN", 0)),
	]
	assert_not_null(NetworkedEvent.from_dict(meld_events[2]))
	var input2 := input.duplicate(true)
	input2["public_events"] = meld_events
	var out2: Dictionary = TrashTalkContextScorer.score_matrix(input2)
	assert_true(bool(out2.get("ok", false)), str(out2.get("reason", "")))
	assert_true(out2["public_context_tags_active"].has("CTX_MELD_SEEN"))


func test_post_closing_normal_discard_riichi_ankan_added_kan_excluded() -> void:
	var closing := 100
	var context := 120
	var base_events: Array = [
		_ne_action_applied(90, "DISCARD", 1),
	]
	var a_in := _base_input("FULL_GRANT")
	a_in["closing_boundary_server_seq"] = closing
	a_in["context_boundary_server_seq"] = context
	a_in["public_events"] = base_events
	a_in["utterances_by_seat"] = {
		"0": [], "1": [_utt("u1", "燃烧翻盘必胜", "zh", 95)], "2": [], "3": [],
	}
	var a: Dictionary = TrashTalkContextScorer.score_matrix(a_in)

	var polluted_events: Array = base_events.duplicate(true)
	polluted_events.append(_ne_action_applied(105, "DISCARD", 2))
	polluted_events.append(_ne_action_applied(106, "RIICHI", 3))
	polluted_events.append(_ne_action_applied(107, "KAN", 1, _resolved_kan("ANKAN", 1)))
	polluted_events.append(_ne_action_applied(108, "KAN", 2, _resolved_kan("ADDED_KAN", 2)))
	for e in polluted_events:
		assert_not_null(NetworkedEvent.from_dict(e), "必须可构造: %s" % e.get("kind"))
	var b_in := a_in.duplicate(true)
	b_in["public_events"] = polluted_events
	var b: Dictionary = TrashTalkContextScorer.score_matrix(b_in)
	assert_eq(
		TrashTalkGoldFixtures.stable_digest(a["matrix"]),
		TrashTalkGoldFixtures.stable_digest(b["matrix"]),
		"closing 后普通 DISCARD/RIICHI/ANKAN/ADDED_KAN 不得影响矩阵"
	)
	assert_false(b["public_context_tags_active"].has("CTX_RIICHI_OPEN"),
		"closing 后 RIICHI 不得入上下文")
	assert_false(b["public_context_tags_active"].has("CTX_MELD_SEEN"),
		"closing 后 ANKAN/ADDED_KAN 不得入上下文")


func test_minkan_after_closing_enters_context_ankan_does_not() -> void:
	var closing := 100
	var context := 110
	var minkan := _ne_action_applied(105, "KAN", 0, _resolved_kan("MINKAN", 0))
	var ankan := _ne_action_applied(105, "KAN", 0, _resolved_kan("ANKAN", 0))
	assert_not_null(NetworkedEvent.from_dict(minkan))
	assert_not_null(NetworkedEvent.from_dict(ankan))

	var tags_m := TrashTalkPublicContextAdapter.derive_public_context_tags({
		"room_id": ROOM,
		"hand_seq": HAND_SEQ,
		"closing_boundary_server_seq": closing,
		"context_boundary_server_seq": context,
		"public_events": [minkan],
		"public_initial": _public_initial(HAND_SEQ, 0, [25000, 25000, 25000, 25000]),
	})
	var tags_a := TrashTalkPublicContextAdapter.derive_public_context_tags({
		"room_id": ROOM,
		"hand_seq": HAND_SEQ,
		"closing_boundary_server_seq": closing,
		"context_boundary_server_seq": context,
		"public_events": [ankan],
		"public_initial": _public_initial(HAND_SEQ, 0, [25000, 25000, 25000, 25000]),
	})
	assert_true(tags_m.has("CTX_MELD_SEEN"), "MINKAN 可在 closing 后入 context")
	assert_false(tags_a.has("CTX_MELD_SEEN"), "ANKAN 在 closing 后不得入")


func test_events_after_context_boundary_excluded() -> void:
	var tags := TrashTalkPublicContextAdapter.derive_public_context_tags({
		"room_id": ROOM,
		"hand_seq": HAND_SEQ,
		"closing_boundary_server_seq": 100,
		"context_boundary_server_seq": 110,
		"public_events": [
			_ne_action_applied(111, "RIICHI", 1),
			_ne_action_applied(112, "PON", 2),
			_ne_claim_window(113),
		],
		"public_initial": _public_initial(HAND_SEQ, 0, [25000, 25000, 25000, 25000]),
	})
	assert_false(tags.has("CTX_RIICHI_OPEN"))
	assert_false(tags.has("CTX_MELD_SEEN"))


func test_invalid_networked_event_and_cross_hand_room_excluded() -> void:
	var good := _ne_action_applied(90, "RIICHI", 1)
	assert_not_null(NetworkedEvent.from_dict(good))
	var bad_payload := good.duplicate(true)
	bad_payload["payload"] = {"seat": 1} # 非法 schema
	assert_null(NetworkedEvent.from_dict(bad_payload), "非法 payload 必须 from_dict 失败")

	# 仅改 hand_seq 不改 tile namespace → from_dict 拒绝（实体命名空间契约）
	var broken_hand := good.duplicate(true)
	broken_hand["payload"] = (good["payload"] as Dictionary).duplicate(true)
	broken_hand["payload"]["hand_seq"] = HAND_SEQ + 9
	assert_null(NetworkedEvent.from_dict(broken_hand), "hand_seq 与 tile namespace 不一致必须拒绝")

	# schema 合法的跨手 RIICHI（tile 落在 other_hs 命名空间）
	var other_hs := HAND_SEQ + 9
	var cross_hand := _env("ACTION_APPLIED", 90, {
		"causation_command_id": CMD,
		"hand_seq": other_hs,
		"decision_id": DECISION,
		"seat": 1,
		"action_kind": "RIICHI",
		"resolved_payload": {
			"tile": _canonical_tile_view(TileId.W5, 1, other_hs),
			"discard_source": "DRAWN",
		},
	})
	assert_not_null(NetworkedEvent.from_dict(cross_hand), "合法跨手事件应可构造")

	var cross_room := good.duplicate(true)
	cross_room["room_id"] = "other_room"
	assert_not_null(NetworkedEvent.from_dict(cross_room))

	var tags := TrashTalkPublicContextAdapter.derive_public_context_tags({
		"room_id": ROOM,
		"hand_seq": HAND_SEQ,
		"closing_boundary_server_seq": 100,
		"context_boundary_server_seq": 100,
		"public_events": [bad_payload, broken_hand, cross_hand, cross_room],
		"public_initial": _public_initial(HAND_SEQ, 0, [25000, 25000, 25000, 25000]),
	})
	assert_false(tags.has("CTX_RIICHI_OPEN"), "非法/跨手/跨房不得注入: %s" % str(tags))

	# 仅 good 事件才注入
	var tags2 := TrashTalkPublicContextAdapter.derive_public_context_tags({
		"room_id": ROOM,
		"hand_seq": HAND_SEQ,
		"closing_boundary_server_seq": 100,
		"context_boundary_server_seq": 100,
		"public_events": [bad_payload, good],
		"public_initial": _public_initial(HAND_SEQ, 0, [25000, 25000, 25000, 25000]),
	})
	assert_true(tags2.has("CTX_RIICHI_OPEN"))


func test_adapter_ron_tsumo_deal_in_dealer_seat_tags() -> void:
	var ron := _ne_action_applied(50, "RON", 1) # seat1 荣和
	assert_not_null(NetworkedEvent.from_dict(ron))
	var rp: Dictionary = ron["payload"]["resolved_payload"]
	assert_true(rp.has("from_seat"))
	var loser: int = int(rp["from_seat"])

	var seat_tags: Dictionary = TrashTalkPublicContextAdapter.derive_seat_public_context_tags({
		"room_id": ROOM,
		"hand_seq": HAND_SEQ,
		"closing_boundary_server_seq": 100,
		"context_boundary_server_seq": 100,
		"public_events": [ron],
		"public_initial": _public_initial(HAND_SEQ, 2, [10000, 40000, 20000, 30000]),
	})
	assert_true(bool(seat_tags.get("ok", false)), str(seat_tags.get("reason", "")))
	assert_eq(int(seat_tags.get("dealer_seat", -1)), 2)
	assert_true((seat_tags["2"] as Array).has("CTX_IS_DEALER"))
	assert_true((seat_tags["1"] as Array).has("CTX_RON_WINNER"))
	assert_true((seat_tags[str(loser)] as Array).has("CTX_DEAL_IN_LOSER"))
	assert_true((seat_tags["1"] as Array).has("CTX_SEAT_LEADING"))
	assert_true((seat_tags["0"] as Array).has("CTX_SEAT_TRAILING"))

	var tsumo := _ne_action_applied(51, "TSUMO", 3)
	assert_not_null(NetworkedEvent.from_dict(tsumo))
	var st2: Dictionary = TrashTalkPublicContextAdapter.derive_seat_public_context_tags({
		"room_id": ROOM,
		"hand_seq": HAND_SEQ,
		"closing_boundary_server_seq": 100,
		"context_boundary_server_seq": 100,
		"public_events": [tsumo],
		"public_initial": _public_initial(HAND_SEQ, 0, [25000, 25000, 25000, 25000]),
	})
	assert_true(bool(st2.get("ok", false)), str(st2.get("reason", "")))
	assert_true((st2["3"] as Array).has("CTX_TSUMO_WINNER"))
	assert_false((st2["3"] as Array).has("CTX_RON_WINNER"))

	# scorer 对 CANCELLED 仍无矩阵
	var cancel_in := _gold_text_input("CANCELLED_BY_WIN")
	cancel_in["public_events"] = [ron]
	var cancel_out: Dictionary = TrashTalkContextScorer.score_matrix(cancel_in)
	assert_eq(String(cancel_out.get("reason", "")), "CANCELLED_BY_WIN")
	assert_eq((cancel_out.get("matrix", []) as Array).size(), 0)


func test_adapter_battle_state_whitelist_only() -> void:
	var st: BattleState = BattleState.for_east_round(7, 1, 1, 0, 0, TileId.E, HAND_SEQ)
	assert_not_null(st)
	st.scores = [30000, 20000, 25000, 25000] as Array[int]
	var snap: Dictionary = TrashTalkPublicContextAdapter.public_snapshot_from_battle_state(st)
	assert_eq(int(snap.get("dealer_seat", -1)), 1)
	assert_eq(snap.get("scores", []), [30000, 20000, 25000, 25000])
	assert_false(snap.has("seats"))
	assert_false(snap.has("wall"))
	assert_false(snap.has("hand"))


func test_utterance_after_closing_ignored_not_context_relaxed() -> void:
	var input := _base_input("FULL_GRANT")
	input["closing_boundary_server_seq"] = 100
	input["context_boundary_server_seq"] = 110
	input["public_events"] = []
	input["utterances_by_seat"] = {
		"0": [],
		"1": [_utt("late", "燃烧起来！这局我必胜翻盘！", "zh", 105)],
		"2": [],
		"3": [],
	}
	var out: Dictionary = TrashTalkContextScorer.score_matrix(input)
	assert_true(bool(out.get("ok", false)))
	for row in _rows_for_seat(out, 1):
		assert_eq(int(row["expression"]), 0)
		assert_eq(int(row["persona"]), 0)


func test_missing_ptt_end_rejects_window() -> void:
	var input := _base_input("FULL_GRANT")
	input["utterances_by_seat"] = {
		"0": [],
		"1": [{"utterance_id": "u1", "text": "燃烧", "language": "zh"}],
		"2": [],
		"3": [],
	}
	var out: Dictionary = TrashTalkContextScorer.score_matrix(input)
	assert_false(bool(out.get("ok", true)))
	assert_eq(String(out.get("reason", "")), "MISSING_PTT_END_SERVER_SEQ")
	assert_eq((out.get("matrix", []) as Array).size(), 0)


func test_invalid_language_and_utterance_conflict_reject() -> void:
	var bad_lang := _base_input("FULL_GRANT")
	bad_lang["language"] = "fr"
	bad_lang["utterances_by_seat"] = {
		"0": [], "1": [_utt("u1", "燃烧", "fr", 10)], "2": [], "3": [],
	}
	var o1: Dictionary = TrashTalkContextScorer.score_matrix(bad_lang)
	assert_false(bool(o1.get("ok", true)))

	var conflict := _base_input("FULL_GRANT")
	conflict["utterances_by_seat"] = {
		"0": [],
		"1": [
			_utt("same", "燃烧", "zh", 10),
			{"utterance_id": "same", "text": "翻盘", "language": "zh", "ptt_end_server_seq": 11},
		],
		"2": [],
		"3": [],
	}
	var o2: Dictionary = TrashTalkContextScorer.score_matrix(conflict)
	assert_false(bool(o2.get("ok", true)))
	assert_eq(String(o2.get("reason", "")), "UTTERANCE_CONFLICT")


func test_unknown_character_item_duplicate_pool_reject() -> void:
	var bad_char := _base_input("FULL_GRANT")
	bad_char["character_ids"] = ["lin_yeche", "no_such_char", "bai_touli", "hua_ling"]
	assert_false(bool(TrashTalkContextScorer.score_matrix(bad_char).get("ok", true)))

	var bad_item := _base_input("FULL_GRANT")
	bad_item["pool_item_ids"] = ["double_payout_v1", "iron_shield_v1", "wall_peek_v1", "no_item"]
	assert_false(bool(TrashTalkContextScorer.score_matrix(bad_item).get("ok", true)))

	var dup := _base_input("FULL_GRANT")
	dup["pool_item_ids"] = ["double_payout_v1", "double_payout_v1", "iron_shield_v1", "wall_peek_v1"]
	assert_false(bool(TrashTalkContextScorer.score_matrix(dup).get("ok", true)))


func test_zh_en_ja_scoring() -> void:
	var zh := _score_one_seat(1, "qiu_jue", "zh", "燃烧起来！这局我必胜翻盘！")
	assert_true(bool(zh.get("ok", false)))
	assert_gt(int(_rows_for_seat(zh, 1)[0]["persona"]), 0)
	var en := _score_one_seat(1, "qiu_jue", "en", "Time to BURN and comeback!")
	assert_true(bool(en.get("ok", false)))
	assert_gt(int(_rows_for_seat(en, 1)[0]["persona"]), 0)
	var ja := _score_one_seat(1, "qiu_jue", "ja", "燃えろ！逆転だ！")
	assert_true(bool(ja.get("ok", false)))
	assert_gt(int(_rows_for_seat(ja, 1)[0]["persona"]), 0)


func test_rule_once_per_seat_window() -> void:
	var input := _base_input("FULL_GRANT")
	input["public_events"] = [_ne_action_applied(90, "RIICHI", 2)]
	input["utterances_by_seat"] = {
		"0": [],
		"1": [
			_utt("u1", "燃烧翻盘必胜", "zh", 10),
			_utt("u2", "燃烧翻盘必胜燃烧翻盘", "zh", 11),
		],
		"2": [],
		"3": [],
	}
	var out: Dictionary = TrashTalkContextScorer.score_matrix(input)
	assert_true(bool(out.get("ok", false)))
	var ids: Array = out["matched_rule_ids_by_seat"]["1"]
	var seen := {}
	for rid in ids:
		assert_false(seen.has(rid), "rule 每 seat 最多一次: %s" % rid)
		seen[rid] = true
	assert_eq(int(_rows_for_seat(out, 1)[0]["persona"]), 220)


func test_repeat_execution_byte_identical() -> void:
	var input := _gold_text_input("FULL_GRANT")
	var a: Dictionary = TrashTalkContextScorer.score_matrix(input)
	var b: Dictionary = TrashTalkContextScorer.score_matrix(input)
	assert_eq(
		TrashTalkGoldFixtures.stable_digest(a),
		TrashTalkGoldFixtures.stable_digest(b)
	)


func test_momentum_affinity_enum_stable() -> void:
	assert_eq(Character.affinity_keys(), [
		&"DOMINATION", &"CALM", &"CUNNING", &"PASSION", &"MYSTIC",
	])
	assert_eq(TrashTalkRuleCatalog.AFFINITY_KEYS, AFFINITY_KEYS)
	var c: Character = CharacterPool.find(&"qiu_jue")
	assert_eq(String(c.affinity_primary), "PASSION")
	assert_eq(String(c.affinity_secondary), "DOMINATION")


# --- helpers: 真实 NetworkedEvent fixture ---

func _ns(serial: int, hand_seq: int = HAND_SEQ) -> int:
	return hand_seq * TILES_PER_HAND + serial


func _canonical_tile_view_for_iid(iid: int) -> Dictionary:
	var serial: int = iid % TILES_PER_HAND
	@warning_ignore("integer_division")
	var tile_index: int = serial / 4
	var tile_id: int = TileId.ALL[tile_index]
	var owner_seat: int = serial % 4
	var is_red: bool = (
		owner_seat == 0
		and (tile_id == TileId.W5 or tile_id == TileId.T5 or tile_id == TileId.S5)
	)
	return {
		"instance_id": iid,
		"tile_id": tile_id,
		"is_red_dora": is_red,
		"owner_seat": owner_seat,
	}


func _canonical_tile_view(tile_id: int, copy_index: int, hand_seq: int = HAND_SEQ) -> Dictionary:
	var idx: int = TileId.ALL.find(tile_id)
	var iid: int = idx * 4 + copy_index + hand_seq * TILES_PER_HAND
	return _canonical_tile_view_for_iid(iid)


func _meld_view(kind: String, from_seat: int, called_serial: int = 50) -> Dictionary:
	var tiles: Array = []
	var added: int = -1
	var fs: int = from_seat
	var called_id: int = -1
	@warning_ignore("integer_division")
	var type_index: int = (called_serial % TILES_PER_HAND) / 4
	if type_index < 0 or type_index >= TileId.ALL.size():
		type_index = 0
	var type_tid: int = TileId.ALL[type_index]
	if kind == "ANKAN":
		fs = -1
		called_id = -1
		for o in range(4):
			tiles.append(_canonical_tile_view(type_tid, o))
	elif kind == "CHI":
		var called_tid: int = TileId.W4
		var a_tid: int = TileId.W2
		var b_tid: int = TileId.W3
		if (
			not TileId.is_honor(type_tid)
			and TileId.number(type_tid) >= 3
			and TileId.number(type_tid) <= 9
		):
			called_tid = type_tid
			a_tid = type_tid - 2
			b_tid = type_tid - 1
		var t_a := _canonical_tile_view(a_tid, 0)
		var t_b := _canonical_tile_view(b_tid, 0)
		var t_called := _canonical_tile_view(called_tid, fs)
		called_id = int(t_called["instance_id"])
		tiles = [t_a, t_b, t_called]
	elif kind == "MINKAN" or kind == "ADDED_KAN":
		var t_called := _canonical_tile_view(type_tid, fs)
		called_id = int(t_called["instance_id"])
		if kind == "ADDED_KAN":
			var added_owner: int = 3 if fs != 3 else 1
			var t_added := _canonical_tile_view(type_tid, added_owner)
			added = int(t_added["instance_id"])
			for o in range(4):
				if o == fs or o == added_owner:
					continue
				tiles.append(_canonical_tile_view(type_tid, o))
			tiles.append(t_called)
			tiles.append(t_added)
		else:
			for o in range(4):
				if o == fs:
					continue
				tiles.append(_canonical_tile_view(type_tid, o))
			tiles.append(t_called)
	else:
		var t_called2 := _canonical_tile_view(type_tid, fs)
		called_id = int(t_called2["instance_id"])
		var picked := 0
		for o in range(4):
			if o == fs:
				continue
			tiles.append(_canonical_tile_view(type_tid, o))
			picked += 1
			if picked == 2:
				break
		tiles.append(t_called2)
	return {
		"meld_id": 0,
		"kind": kind,
		"from_seat": fs,
		"called_tile_instance_id": called_id,
		"added_tile_instance_id": added,
		"tiles": tiles,
	}


func _resolved_for(action_kind: String, seat: int) -> Dictionary:
	match action_kind:
		"DISCARD", "RIICHI":
			return {
				"tile": _canonical_tile_view(TileId.W5, seat % 4, HAND_SEQ),
				"discard_source": "DRAWN",
			}
		"CHI":
			return {"meld": _meld_view("CHI", (seat + 1) % 4, 50)}
		"PON":
			return {"meld": _meld_view("PON", (seat + 1) % 4, 51)}
		"KAN":
			return {"meld": _meld_view("MINKAN", (seat + 1) % 4, 52)}
		"RON":
			return {
				"winning_tile": _canonical_tile_view(TileId.W5, 0, HAND_SEQ),
				"from_seat": (seat + 1) % 4,
			}
		"TSUMO":
			return {
				"winning_tile": _canonical_tile_view(TileId.W5, seat % 4, HAND_SEQ),
			}
		"PASS":
			return {}
		"DECLARE_ABORTIVE_DRAW":
			return {"reason": "KYUUSYU_KYUUHAI"}
		_:
			return {}


func _resolved_kan(meld_kind: String, actor_seat: int) -> Dictionary:
	var from_seat: int = -1 if meld_kind == "ANKAN" else (actor_seat + 1) % 4
	return {"meld": _meld_view(meld_kind, from_seat, 52)}


func _env(kind: String, seq: int, payload: Dictionary) -> Dictionary:
	return {
		"protocol_version": 1,
		"server_seq": seq,
		"room_id": ROOM,
		"kind": kind,
		"payload": payload.duplicate(true),
		"view_hash": VIEW_HASH,
	}


func _ne_action_applied(
	seq: int,
	action_kind: String,
	seat: int = 0,
	resolved: Dictionary = {}
) -> Dictionary:
	var rp: Dictionary = resolved
	if rp.is_empty():
		rp = _resolved_for(action_kind, seat)
	return _env("ACTION_APPLIED", seq, {
		"causation_command_id": CMD,
		"hand_seq": HAND_SEQ,
		"decision_id": DECISION,
		"seat": seat,
		"action_kind": action_kind,
		"resolved_payload": rp.duplicate(true),
	})


func _ne_claim_window(seq: int) -> Dictionary:
	return _env("CLAIM_WINDOW", seq, {
		"hand_seq": HAND_SEQ,
		"decision_id": DECISION,
		"discarded_by_seat": 2,
		"discarded_tile": _canonical_tile_view(TileId.W5, 2, HAND_SEQ),
		"allowed_actions": [
			{"kind": "PASS", "payload_options": [{}]},
		],
	})


func _utt(uid: String, text: String, lang: String, ptt: int) -> Dictionary:
	return {
		"utterance_id": uid,
		"text": text,
		"language": lang,
		"ptt_end_server_seq": ptt,
	}


func _public_initial(hand_seq: int = HAND_SEQ, dealer: int = 0, scores: Array = []) -> Dictionary:
	var sc: Array = scores
	if sc.is_empty():
		sc = [25000, 25000, 25000, 25000]
	return {
		"hand_seq": hand_seq,
		"dealer_seat": dealer,
		"scores": sc.duplicate(),
	}


func _base_input(window_exit: String) -> Dictionary:
	return {
		"rule_version": RULE_VERSION,
		"window_id": "hand_1_window_0",
		"hand_seq": HAND_SEQ,
		"room_id": ROOM,
		"window_exit": window_exit,
		"closing_boundary_server_seq": 100,
		"context_boundary_server_seq": 100,
		"language": "zh",
		"character_ids": ["lin_yeche", "qiu_jue", "bai_touli", "hua_ling"],
		"pool_item_ids": ["double_payout_v1", "iron_shield_v1", "wall_peek_v1", "dora_charm_v1"],
		"utterances_by_seat": {"0": [], "1": [], "2": [], "3": []},
		"public_events": [],
		"public_initial": _public_initial(HAND_SEQ),
	}


func _gold_text_input(window_exit: String) -> Dictionary:
	return _input_from_fixture(TrashTalkGoldFixtures.gold_text(), window_exit)


func _input_from_fixture(fixture: Dictionary, window_exit: String) -> Dictionary:
	var texts: Dictionary = fixture.get("texts_by_seat", {})
	var lang := String(fixture.get("language", "zh"))
	var hand_seq: int = int(fixture.get("hand_seq", HAND_SEQ))
	var utts := {}
	for seat in range(4):
		var t := String(texts.get(str(seat), ""))
		if t.is_empty():
			utts[str(seat)] = []
		else:
			utts[str(seat)] = [_utt("utt_%d" % seat, t, lang, 50)]
	# 黄金有文本期望 CTX_RIICHI_OPEN：用真实 RIICHI 事件派生，禁止喂 public_context_tags_active
	var events: Array = []
	var expect_tags: Array = fixture.get("public_context_tags_active", [])
	if expect_tags.has("CTX_RIICHI_OPEN"):
		var riichi := _ne_action_applied(40, "RIICHI", 2)
		# hand_seq 对齐 fixture
		riichi["payload"]["hand_seq"] = hand_seq
		# 修正 tile namespace
		var tile := _canonical_tile_view(TileId.W5, 2, hand_seq)
		riichi["payload"]["resolved_payload"] = {
			"tile": tile,
			"discard_source": "DRAWN",
		}
		assert_not_null(NetworkedEvent.from_dict(riichi), "gold RIICHI fixture 必须合法")
		events.append(riichi)
	return {
		"rule_version": String(fixture.get("rule_version", RULE_VERSION)),
		"window_id": String(fixture.get("window_id", "")),
		"hand_seq": hand_seq,
		"room_id": ROOM,
		"window_exit": window_exit,
		"closing_boundary_server_seq": 100,
		"context_boundary_server_seq": 100,
		"language": lang,
		"character_ids": fixture.get("character_ids", []).duplicate(),
		"pool_item_ids": fixture.get("pool_item_ids", []).duplicate(),
		"utterances_by_seat": utts,
		"public_events": events,
		"public_initial": _public_initial(hand_seq),
	}


## 完整矩阵 + matched_rule_ids_by_seat 字节级全等（禁止挑字段/先排序）
func _assert_full_matrix_byte_identical(out: Dictionary, fixture: Dictionary) -> void:
	var expected: Dictionary = fixture.get("expected", {})
	var exp_matrix: Array = expected.get("matrix_components", [])
	var got_matrix: Array = out.get("matrix", [])
	assert_eq(
		TrashTalkGoldFixtures.stable_stringify(got_matrix),
		TrashTalkGoldFixtures.stable_stringify(exp_matrix),
		"完整 matrix 必须 stable_stringify 字节全等"
	)
	assert_eq(
		TrashTalkGoldFixtures.stable_stringify(out.get("matched_rule_ids_by_seat", {})),
		TrashTalkGoldFixtures.stable_stringify(expected.get("matched_rule_ids_by_seat", {})),
		"matched_rule_ids_by_seat 必须 stable_stringify 字节全等"
	)


func _score_one_seat(seat: int, character_id: String, language: String, text: String) -> Dictionary:
	var input := _base_input("FULL_GRANT")
	var chars := ["lin_yeche", "qiu_jue", "bai_touli", "hua_ling"]
	chars[seat] = character_id
	input["character_ids"] = chars
	input["language"] = language
	input["public_events"] = []
	var utts := {"0": [], "1": [], "2": [], "3": []}
	utts[str(seat)] = [_utt("u1", text, language, 10)]
	input["utterances_by_seat"] = utts
	return TrashTalkContextScorer.score_matrix(input)


func _rows_for_seat(out: Dictionary, seat: int) -> Array:
	var rows: Array = []
	for row in out.get("matrix", []):
		if int(row["seat"]) == seat:
			rows.append(row)
	return rows
