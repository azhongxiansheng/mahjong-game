extends GutTest

# E2-02 / #232 P2-2 Red：instance_id 严格类型与范围校验。
# 尽量走当前可编译 API 得到行为 Red；不引用尚未存在的 MAX_SAFE 常量。
# 静态参数类型导致无法直调时用 Object.call 动态调用。


const _OVER_SAFE_IID: int = 9007199254740992  # 2^53，超过 JSON/JS safe int
const _MAX_SAFE_LITERAL: int = 9007199254740991


func _tile(tid: int, iid: int, red: bool = false) -> Tile:
	return Tile.new(tid, red, Tile.NO_OWNER, iid)


func _hand_iids(h: Hand) -> Array:
	var out: Array = []
	for t in h.tiles():
		out.append(t.instance_id)
	return out


func _hand_entity_order(h: Hand) -> Array:
	# 逐实体：instance_id + id + red，顺序敏感
	var out: Array = []
	for t in h.tiles():
		out.append([t.instance_id, t.id, t.is_red_dora])
	return out


func _seed_hand() -> Hand:
	var h := Hand.new()
	h.add(_tile(TileId.W1, 1))
	h.add(_tile(TileId.W2, 2))
	h.add(_tile(TileId.W3, 3, true))
	return h


# ---- take_many：类型与范围 ----

func test_take_many_rejects_string_float_bool_and_out_of_range_zero_mod() -> void:
	var bad_inputs: Array = ["1", 1.0, true, false, -2, _OVER_SAFE_IID]
	for raw in bad_inputs:
		var h := _seed_hand()
		var snap := _hand_entity_order(h)
		var result: Variant = h.take_many_by_instance_ids([raw])
		assert_null(result, "take_many 应拒绝 %s" % str(raw))
		assert_eq(_hand_entity_order(h), snap,
			"拒绝后逐实体逐顺序零修改（input=%s）" % str(raw))


func test_take_many_rejects_mixed_valid_then_bad_type_zero_mod() -> void:
	var h := _seed_hand()
	var snap := _hand_entity_order(h)
	var result: Variant = h.take_many_by_instance_ids([1, "2"])
	assert_null(result)
	assert_eq(_hand_entity_order(h), snap, "不得先扣掉合法的 1")


# ---- find / take 单张 ----

func test_find_and_take_reject_bad_types_and_range_zero_mod() -> void:
	var bad_inputs: Array = ["1", 1.0, true, false, -2, _OVER_SAFE_IID]
	for raw in bad_inputs:
		var h := _seed_hand()
		var snap := _hand_entity_order(h)
		# 静态 int 参数可能导致编译失败 → 动态 call
		var found: Variant = h.call("find_by_instance_id", raw)
		var taken: Variant = h.call("take_by_instance_id", raw)
		assert_null(found, "find 应拒绝 %s" % str(raw))
		assert_null(taken, "take 应拒绝 %s" % str(raw))
		assert_eq(_hand_entity_order(h), snap,
			"find/take 拒绝后零修改（input=%s）" % str(raw))


# ---- discard 无效范围 ----

func test_discard_rejects_out_of_range_zero_mod() -> void:
	var e := TurnEngine.new(BattleState.for_east_round(42, 0, 1, 0, 0))
	var a := _tile(TileId.W1, 10)
	var b := _tile(TileId.W2, 11)
	e.state.seats[0].hand = Hand.new()
	e.state.seats[0].hand.add(a)
	e.state.seats[0].hand.add(b)
	e.state.phase = BattlePhase.Kind.DISCARD
	var hand_snap := _hand_entity_order(e.state.seats[0].hand)
	var phase := e.state.phase
	var river_size: int = e.state.seats[0].river.size()

	assert_false(e.discard(-2))
	assert_false(e.discard(_OVER_SAFE_IID))
	assert_eq(_hand_entity_order(e.state.seats[0].hand), hand_snap)
	assert_eq(e.state.phase, phase)
	assert_eq(e.state.seats[0].river.size(), river_size)


# ---- Hand.add：有效 id 去重 / INVALID 可重复 ----

func test_hand_add_rejects_duplicate_valid_instance_id() -> void:
	var h := Hand.new()
	var t1 := _tile(TileId.W1, 50)
	var t2 := _tile(TileId.W9, 50)  # 同 instance_id，不同 tile id
	# 动态 call：契约返回 bool（当前 void 会得到 null → Red）
	assert_eq(h.call("add", t1), true, "首次有效 instance_id 应成功")
	assert_eq(h.size(), 1)
	assert_eq(h.call("add", t2), false, "重复有效 instance_id 应拒绝")
	assert_eq(h.size(), 1, "拒绝后不追加")
	assert_eq(h.tile_at(0).id, TileId.W1)


func test_hand_add_allows_repeated_invalid_instance_id() -> void:
	var h := Hand.new()
	var a := Tile.new(TileId.W1)
	var b := Tile.new(TileId.W2)
	assert_eq(a.instance_id, Tile.INVALID_INSTANCE_ID)
	assert_eq(b.instance_id, Tile.INVALID_INSTANCE_ID)
	assert_eq(h.call("add", a), true, "INVALID fixture 可加入")
	assert_eq(h.call("add", b), true, "INVALID fixture 可重复加入")
	assert_eq(h.size(), 2)
	assert_eq(h.tile_at(0).instance_id, Tile.INVALID_INSTANCE_ID)
	assert_eq(h.tile_at(1).instance_id, Tile.INVALID_INSTANCE_ID)


# ---- Wall / BattleState hand_seq 范围 ----

func test_wall_new_full_set_rejects_negative_and_overflow_hand_seq() -> void:
	assert_null(Wall.new_full_set(-1), "hand_seq=-1 → null")
	# hand_seq*136+135 必须超过 9007199254740991
	# 取 floor((MAX-135)/136)+1 的安全上界字面量，保证溢出
	@warning_ignore("integer_division")
	var overflow_hand_seq: int = ((_MAX_SAFE_LITERAL - 135) / 136) + 1
	var max_iid: int = overflow_hand_seq * 136 + 135
	assert_true(max_iid > _MAX_SAFE_LITERAL,
		"fixture 保证 hand_seq*136+135 超 safe 上限")
	assert_null(Wall.new_full_set(overflow_hand_seq),
		"超限 hand_seq → null")


func test_for_east_round_rejects_negative_and_overflow_hand_seq() -> void:
	assert_null(
		BattleState.for_east_round(42, 0, 1, 0, 0, TileId.E, -1),
		"hand_seq=-1 → null")
	@warning_ignore("integer_division")
	var overflow_hand_seq: int = ((_MAX_SAFE_LITERAL - 135) / 136) + 1
	assert_true(overflow_hand_seq * 136 + 135 > _MAX_SAFE_LITERAL)
	assert_null(
		BattleState.for_east_round(42, 0, 1, 0, 0, TileId.E, overflow_hand_seq),
		"超限 hand_seq → null")


# ---- C. Hand.add 身份边界 ----

func test_hand_add_rejects_illegal_identity_minus2_and_over_max_zero_mod() -> void:
	var h := Hand.new()
	h.add(_tile(TileId.W1, 1))
	var snap := _hand_entity_order(h)
	# -2 / MAX+1 非法：false 且不追加（不能当合法 id 写入）
	assert_eq(h.call("add", _tile(TileId.W2, -2)), false, "instance_id=-2 应拒绝")
	assert_eq(h.size(), 1)
	assert_eq(_hand_entity_order(h), snap)
	assert_eq(h.call("add", _tile(TileId.W3, _OVER_SAFE_IID)), false,
		"instance_id=MAX+1 应拒绝")
	assert_eq(h.size(), 1)
	assert_eq(_hand_entity_order(h), snap)


# ---- D. Tile.from_dict 严格解析 ----

func _from_dict_dyn(v: Variant) -> Variant:
	# 动态调用静态 from_dict，避免非 Dictionary 在类型签名上 parse 失败
	return (load("res://core/tile/tile.gd") as GDScript).call("from_dict", v)


func test_from_dict_rejects_non_dictionary() -> void:
	assert_null(_from_dict_dyn(null))
	assert_null(_from_dict_dyn("not_dict"))
	assert_null(_from_dict_dyn(1))
	assert_null(_from_dict_dyn([]))


func test_from_dict_rejects_missing_or_extra_keys() -> void:
	assert_null(Tile.from_dict({
		"id": TileId.W1,
		"is_red_dora": false,
		"owner_seat": -1,
	}), "缺 instance_id")
	assert_null(Tile.from_dict({
		"id": TileId.W1,
		"is_red_dora": false,
		"owner_seat": -1,
		"instance_id": 1,
		"extra": 0,
	}), "多 key")
	assert_null(Tile.from_dict({}), "空 dict")


func test_from_dict_rejects_silent_coercion_string_float_bool() -> void:
	# 不得 int()/bool() 静默强转
	var base := {
		"id": TileId.W5,
		"is_red_dora": true,
		"owner_seat": 0,
		"instance_id": 10,
	}
	var bad_id := base.duplicate()
	bad_id["id"] = "4"
	assert_null(Tile.from_dict(bad_id), "id=String 拒绝")
	var bad_id_f := base.duplicate()
	bad_id_f["id"] = 4.0
	assert_null(Tile.from_dict(bad_id_f), "id=float 拒绝")
	var bad_red := base.duplicate()
	bad_red["is_red_dora"] = 1
	assert_null(Tile.from_dict(bad_red), "is_red_dora=int 拒绝")
	var bad_red_s := base.duplicate()
	bad_red_s["is_red_dora"] = "true"
	assert_null(Tile.from_dict(bad_red_s), "is_red_dora=String 拒绝")
	var bad_owner := base.duplicate()
	bad_owner["owner_seat"] = "0"
	assert_null(Tile.from_dict(bad_owner), "owner_seat=String 拒绝")
	var bad_owner_f := base.duplicate()
	bad_owner_f["owner_seat"] = 0.0
	assert_null(Tile.from_dict(bad_owner_f), "owner_seat=float 拒绝")
	var bad_iid := base.duplicate()
	bad_iid["instance_id"] = "10"
	assert_null(Tile.from_dict(bad_iid), "instance_id=String 拒绝")
	var bad_iid_f := base.duplicate()
	bad_iid_f["instance_id"] = 10.0
	assert_null(Tile.from_dict(bad_iid_f), "instance_id=float 拒绝")
	var bad_iid_b := base.duplicate()
	bad_iid_b["instance_id"] = true
	assert_null(Tile.from_dict(bad_iid_b), "instance_id=bool 拒绝")


func test_from_dict_rejects_illegal_tile_id_red_owner_instance() -> void:
	assert_null(Tile.from_dict({
		"id": 99,
		"is_red_dora": false,
		"owner_seat": -1,
		"instance_id": Tile.INVALID_INSTANCE_ID,
	}), "非法 tile id")
	assert_null(Tile.from_dict({
		"id": TileId.W1,
		"is_red_dora": true,
		"owner_seat": -1,
		"instance_id": Tile.INVALID_INSTANCE_ID,
	}), "非五赤 is_red_dora=true")
	assert_null(Tile.from_dict({
		"id": TileId.W5,
		"is_red_dora": true,
		"owner_seat": 4,
		"instance_id": 1,
	}), "owner_seat=4 越界")
	assert_null(Tile.from_dict({
		"id": TileId.W5,
		"is_red_dora": true,
		"owner_seat": -2,
		"instance_id": 1,
	}), "owner_seat=-2 越界")
	assert_null(Tile.from_dict({
		"id": TileId.W5,
		"is_red_dora": true,
		"owner_seat": 0,
		"instance_id": -2,
	}), "instance_id=-2")
	assert_null(Tile.from_dict({
		"id": TileId.W5,
		"is_red_dora": true,
		"owner_seat": 0,
		"instance_id": _OVER_SAFE_IID,
	}), "instance_id 超 safe")


func test_from_dict_accepts_valid_and_roundtrip() -> void:
	var ok := Tile.from_dict({
		"id": TileId.W5,
		"is_red_dora": true,
		"owner_seat": 2,
		"instance_id": 42,
	})
	assert_not_null(ok)
	assert_eq(ok.id, TileId.W5)
	assert_true(ok.is_red_dora)
	assert_eq(ok.owner_seat, 2)
	assert_eq(ok.instance_id, 42)
	# INVALID_INSTANCE_ID 合法 fixture
	var inv := Tile.from_dict({
		"id": TileId.W1,
		"is_red_dora": false,
		"owner_seat": -1,
		"instance_id": Tile.INVALID_INSTANCE_ID,
	})
	assert_not_null(inv)
	assert_eq(inv.instance_id, Tile.INVALID_INSTANCE_ID)
	# roundtrip
	var t := Tile.new(TileId.T5, true, 3, 99)
	var restored: Tile = Tile.from_dict(t.to_dict())
	assert_not_null(restored)
	assert_eq(restored.instance_id, 99)
	assert_eq(restored.id, TileId.T5)
	assert_true(restored.is_red_dora)
	assert_eq(restored.owner_seat, 3)


# ---- A. TurnEngine 实体 identity 参数 fail-closed（动态 call）----

func _bad_identity_values() -> Array:
	return ["1", 1.0, true, false, -1, -2, _OVER_SAFE_IID]


func _snap_engine_core(e: TurnEngine) -> Dictionary:
	return {
		"phase": e.state.phase,
		"current": e.state.current_seat,
		"hands": [
			_hand_entity_order(e.state.seats[0].hand),
			_hand_entity_order(e.state.seats[1].hand),
			_hand_entity_order(e.state.seats[2].hand),
			_hand_entity_order(e.state.seats[3].hand),
		],
		"rivers": [
			e.state.seats[0].river.size(),
			e.state.seats[1].river.size(),
			e.state.seats[2].river.size(),
			e.state.seats[3].river.size(),
		],
		"meld_counts": [
			e.state.seats[0].melds.size(),
			e.state.seats[1].melds.size(),
			e.state.seats[2].melds.size(),
			e.state.seats[3].melds.size(),
		],
		"points": e.state.seats[0].points,
		"riichi_sticks": e.state.riichi_sticks,
		"riichi0": e.state.seats[0].riichi.declared,
	}


func _assert_engine_unmodified(e: TurnEngine, snap: Dictionary, label: String) -> void:
	var now := _snap_engine_core(e)
	assert_eq(now["phase"], snap["phase"], "%s phase" % label)
	assert_eq(now["current"], snap["current"], "%s current" % label)
	assert_eq(now["hands"], snap["hands"], "%s hands" % label)
	assert_eq(now["rivers"], snap["rivers"], "%s rivers" % label)
	assert_eq(now["meld_counts"], snap["meld_counts"], "%s melds" % label)
	assert_eq(now["points"], snap["points"], "%s points" % label)
	assert_eq(now["riichi_sticks"], snap["riichi_sticks"], "%s sticks" % label)
	assert_eq(now["riichi0"], snap["riichi0"], "%s riichi" % label)


func test_discard_rejects_bad_identity_types_explicit_false_zero_mod() -> void:
	var e := TurnEngine.new(BattleState.for_east_round(42, 0, 1, 0, 0))
	e.state.seats[0].hand = Hand.new()
	e.state.seats[0].hand.add(_tile(TileId.W1, 10))
	e.state.seats[0].hand.add(_tile(TileId.W2, 11))
	e.state.phase = BattlePhase.Kind.DISCARD
	for raw in _bad_identity_values():
		var snap := _snap_engine_core(e)
		var ret: Variant = e.call("discard", raw)
		assert_eq(ret, false, "discard 应返回 false（input=%s），不能靠类型错误" % str(raw))
		_assert_engine_unmodified(e, snap, "discard/%s" % str(raw))


func test_declare_riichi_and_discard_rejects_bad_identity_explicit_false() -> void:
	var e := TurnEngine.new(BattleState.for_east_round(42, 0, 1, 0, 0))
	# 14 张听型（与 entity_actions 一致）：弃 900 后听
	var tiles: Array = [
		_tile(TileId.W2, 901), _tile(TileId.W4, 902),
		_tile(TileId.T2, 903), _tile(TileId.T3, 904), _tile(TileId.T4, 905),
		_tile(TileId.T5, 906), _tile(TileId.T6, 907), _tile(TileId.T7, 908),
		_tile(TileId.S2, 909), _tile(TileId.S3, 910), _tile(TileId.S4, 911),
		_tile(TileId.S5, 912), _tile(TileId.S5, 913),
		_tile(TileId.W3, 900),
	]
	e.state.seats[0].hand = Hand.new()
	for t in tiles:
		e.state.seats[0].hand.add(t)
	e.state.phase = BattlePhase.Kind.DISCARD
	for raw in _bad_identity_values():
		var snap := _snap_engine_core(e)
		var ret: Variant = e.call("declare_riichi_and_discard", 0, raw)
		assert_eq(ret, false, "declare_riichi_and_discard 应 false（iid=%s）" % str(raw))
		_assert_engine_unmodified(e, snap, "riichi_discard/%s" % str(raw))


func test_claim_actions_reject_bad_claimed_and_companion_identities() -> void:
	var e := TurnEngine.new(BattleState.for_east_round(42, 0, 1, 0, 0))
	e.state.seats[0].hand = Hand.new()
	e.state.seats[0].hand.add(_tile(TileId.W3, 500))
	e.state.phase = BattlePhase.Kind.DISCARD
	assert_true(e.discard(500))
	e.state.seats[1].hand = Hand.new()
	e.state.seats[1].hand.add(_tile(TileId.W2, 501))
	e.state.seats[1].hand.add(_tile(TileId.W4, 502))
	e.state.seats[2].hand = Hand.new()
	e.state.seats[2].hand.add(_tile(TileId.W3, 601))
	e.state.seats[2].hand.add(_tile(TileId.W3, 602))
	e.state.seats[2].hand.add(_tile(TileId.W3, 603))
	e.state.seats[2].hand.add(_tile(TileId.W3, 604))
	e.state.seats[2].hand.add(_tile(TileId.W3, 605))
	for raw in _bad_identity_values():
		var snap := _snap_engine_core(e)
		assert_eq(e.call("apply_chi", 1, raw, [501, 502]), false,
			"apply_chi claimed=%s" % str(raw))
		assert_eq(e.call("apply_chi", 1, 500, [raw, 502]), false,
			"apply_chi companion0=%s" % str(raw))
		assert_eq(e.call("apply_pon", 2, raw, [601, 602]), false,
			"apply_pon claimed=%s" % str(raw))
		assert_eq(e.call("apply_pon", 2, 500, [raw, 602]), false,
			"apply_pon companion=%s" % str(raw))
		assert_eq(e.call("apply_minkan", 2, raw, [601, 602, 603]), false,
			"apply_minkan claimed=%s" % str(raw))
		assert_eq(e.call("apply_minkan", 2, 500, [601, 602, raw]), false,
			"apply_minkan companion=%s" % str(raw))
		assert_eq(e.call("apply_ron", 2, raw), false, "apply_ron claimed=%s" % str(raw))
		_assert_engine_unmodified(e, snap, "claim_bad_id/%s" % str(raw))


func test_ankan_and_tsumo_and_added_kan_reject_bad_identities() -> void:
	# ankan / tsumo 场景
	var e := TurnEngine.new(BattleState.for_east_round(42, 0, 1, 0, 0))
	e.state.seats[0].hand = Hand.new()
	for iid in [801, 802, 803, 804]:
		e.state.seats[0].hand.add(_tile(TileId.W5, iid))
	e.state.seats[0].hand.add(_tile(TileId.T1, 805))
	e.state.phase = BattlePhase.Kind.DISCARD
	e.state.seats[0].last_drawn_instance_id = 804
	for raw in _bad_identity_values():
		var snap := _snap_engine_core(e)
		assert_eq(e.call("apply_ankan", 0, [801, 802, 803, raw]), false,
			"ankan elem=%s" % str(raw))
		assert_eq(e.call("apply_tsumo", 0, raw), false, "tsumo last=%s" % str(raw))
		_assert_engine_unmodified(e, snap, "ankan_tsumo/%s" % str(raw))

	# added_kan：先建 pon
	var e2 := TurnEngine.new(BattleState.for_east_round(42, 0, 1, 0, 0))
	e2.state.seats[0].hand = Hand.new()
	e2.state.seats[0].hand.add(_tile(TileId.W5, 900))
	e2.state.phase = BattlePhase.Kind.DISCARD
	assert_true(e2.discard(900))
	e2.state.seats[1].hand = Hand.new()
	e2.state.seats[1].hand.add(_tile(TileId.W5, 901))
	e2.state.seats[1].hand.add(_tile(TileId.W5, 902))
	assert_true(e2.apply_pon(1, 900, [901, 902]))
	var mid: int = e2.state.seats[1].melds.all()[0].meld_id
	e2.state.seats[1].hand.add(_tile(TileId.W5, 903))
	e2.state.phase = BattlePhase.Kind.DISCARD
	for raw in _bad_identity_values():
		var snap2 := _snap_engine_core(e2)
		assert_eq(e2.call("apply_added_kan", 1, mid, raw), false,
			"added_kan added=%s" % str(raw))
		# meld_id 非法类别
		assert_eq(e2.call("apply_added_kan", 1, raw, 903), false,
			"added_kan meld_id=%s" % str(raw))
		_assert_engine_unmodified(e2, snap2, "added_kan/%s" % str(raw))


# ---- B. TurnEngine seat 参数索引前校验 + self-ron ----

func _bad_seat_values() -> Array:
	return [-1, 4, "0", 1.0, true, false]


func test_pon_minkan_reject_invalid_claimant_seat_zero_mod() -> void:
	var e := TurnEngine.new(BattleState.for_east_round(42, 0, 1, 0, 0))
	e.state.seats[0].hand = Hand.new()
	e.state.seats[0].hand.add(_tile(TileId.W5, 700))
	e.state.phase = BattlePhase.Kind.DISCARD
	assert_true(e.discard(700))
	e.state.seats[2].hand = Hand.new()
	e.state.seats[2].hand.add(_tile(TileId.W5, 701))
	e.state.seats[2].hand.add(_tile(TileId.W5, 702))
	e.state.seats[2].hand.add(_tile(TileId.W5, 703))
	for seat_raw in _bad_seat_values():
		var snap := _snap_engine_core(e)
		assert_eq(e.call("apply_pon", seat_raw, 700, [701, 702]), false,
			"pon seat=%s" % str(seat_raw))
		assert_eq(e.call("apply_minkan", seat_raw, 700, [701, 702, 703]), false,
			"minkan seat=%s" % str(seat_raw))
		_assert_engine_unmodified(e, snap, "pon_minkan_seat/%s" % str(seat_raw))


func test_ron_rejects_self_and_out_of_range_seat_zero_mod() -> void:
	var e := TurnEngine.new(BattleState.for_east_round(42, 0, 1, 0, 0))
	e.state.seats[0].hand = Hand.new()
	e.state.seats[0].hand.add(_tile(TileId.W5, 1000))
	e.state.phase = BattlePhase.Kind.DISCARD
	assert_true(e.discard(1000))
	# 标准听 W5 嵌张
	var ids := [
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.W4, TileId.W6,
		TileId.S5, TileId.S5,
	]
	e.state.seats[2].hand = Hand.new()
	for i in range(ids.size()):
		e.state.seats[2].hand.add(_tile(ids[i], 2000 + i))
	# self-ron：claimant == discarder (current_seat=0)
	var snap := _snap_engine_core(e)
	assert_eq(e.call("apply_ron", 0, 1000), false, "self-ron 必须拒绝")
	_assert_engine_unmodified(e, snap, "self_ron")
	for seat_raw in [-1, 4, "2", true]:
		var snap2 := _snap_engine_core(e)
		assert_eq(e.call("apply_ron", seat_raw, 1000), false,
			"ron seat=%s" % str(seat_raw))
		_assert_engine_unmodified(e, snap2, "ron_seat/%s" % str(seat_raw))


func test_tsumo_rejects_out_of_range_seat_zero_mod() -> void:
	var e := TurnEngine.new(BattleState.for_east_round(42, 0, 1, 0, 0))
	var win_iid: int = 1500
	var ids := [
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.W4, TileId.W6,
		TileId.S5, TileId.S5,
	]
	e.state.seats[0].hand = Hand.new()
	for i in range(ids.size()):
		e.state.seats[0].hand.add(_tile(ids[i], 1400 + i))
	e.state.seats[0].hand.add(_tile(TileId.W5, win_iid))
	e.state.phase = BattlePhase.Kind.DISCARD
	e.state.seats[0].last_drawn_instance_id = win_iid
	for seat_raw in [-1, 4, "0", false]:
		var snap := _snap_engine_core(e)
		assert_eq(e.call("apply_tsumo", seat_raw, win_iid), false,
			"tsumo seat=%s" % str(seat_raw))
		_assert_engine_unmodified(e, snap, "tsumo_seat/%s" % str(seat_raw))


func test_seat_table_driven_all_entity_seat_entries() -> void:
	# 表驱动：declare_riichi / declare_riichi_and_discard / chi / ankan / added_kan
	var e := TurnEngine.new(BattleState.for_east_round(42, 0, 1, 0, 0))
	e.state.seats[0].hand = Hand.new()
	e.state.seats[0].hand.add(_tile(TileId.W3, 500))
	e.state.phase = BattlePhase.Kind.DISCARD
	assert_true(e.discard(500))
	e.state.seats[1].hand = Hand.new()
	e.state.seats[1].hand.add(_tile(TileId.W2, 501))
	e.state.seats[1].hand.add(_tile(TileId.W4, 502))
	# 另备 DISCARD 态引擎做 ankan / riichi / added_kan
	var e_d := TurnEngine.new(BattleState.for_east_round(42, 0, 1, 0, 0))
	e_d.state.seats[0].hand = Hand.new()
	for iid in [801, 802, 803, 804]:
		e_d.state.seats[0].hand.add(_tile(TileId.W5, iid))
	e_d.state.phase = BattlePhase.Kind.DISCARD
	# 仅覆盖真实存在的实体入口；declare_riichi 无独立 seat API（走 declare_riichi_and_discard）
	var cases: Array = [
		["declare_riichi_and_discard", e_d, [-1, 801]],
		["apply_chi", e, [-1, 500, [501, 502]]],
		["apply_ankan", e_d, [-1, [801, 802, 803, 804]]],
	]
	for seat_raw in _bad_seat_values():
		for c in cases:
			var method: String = c[0]
			var eng: TurnEngine = c[1]
			var args: Array = c[2].duplicate()
			args[0] = seat_raw
			var snap := _snap_engine_core(eng)
			var ret: Variant = eng.callv(method, args)
			assert_eq(ret, false, "%s seat=%s 应 false" % [method, str(seat_raw)])
			_assert_engine_unmodified(eng, snap, "%s/%s" % [method, str(seat_raw)])
