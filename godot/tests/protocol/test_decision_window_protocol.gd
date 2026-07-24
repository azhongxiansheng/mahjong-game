extends GutTest

# E2-02（#232）Red：冻结 TURN_PROMPT / CLAIM_WINDOW 私有 schema。
# ActionOffer exact={kind, payload_options}；option 走 Action 同源 payload 校验与规范化。
# 私有 hand 可空；CLAIM 每 recipient 仅自己的 allowed_actions，至少含 PASS。
# TURN_PROMPT.allowed_actions 拒 ITEM_USE；Action 命令侧仍接受 ITEM_USE。

const ROOM := "room_x"
const CMD := "550e8400-e29b-41d4-a716-446655440000"
const DECISION := "550e8400-e29b-41d4-a716-4466554400aa"
const VIEW_HASH := "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
# 对齐 Action / Wall.MAX_HAND_SEQ 与 JS safe int
const MAX_HAND_SEQ := 66229406284859
const MAX_SAFE_INT := 9007199254740991
const TILES_PER_HAND := 136

const TURN_PAYLOAD_KEYS := [
	"hand_seq", "decision_id", "seat", "hand",
	"last_drawn_tile_instance_id", "allowed_actions",
]
const CLAIM_PAYLOAD_KEYS := [
	"hand_seq", "decision_id", "discarded_by_seat",
	"discarded_tile", "allowed_actions",
]
const OFFER_KEYS := ["kind", "payload_options"]
const FORBIDDEN_CROSS_SEAT_KEYS := [
	"offers_by_seat",
	"allowed_actions_by_seat",
	"eligible_seats",
	"actions_by_seat",
	"offers",
]


## serial = iid % 136；tile = ALL[serial/4]；owner = serial%4；五牌 owner0 赤
func _canonical_tile_view_for_iid(iid: int) -> Dictionary:
	var serial: int = iid % Tile.TILES_PER_HAND
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


## iid = ALL.find(tile_id)*4 + copy_index + hand_seq*136
func _canonical_tile_view(tile_id: int, copy_index: int, hand_seq: int) -> Dictionary:
	var iid: int = TileId.ALL.find(tile_id) * 4 + copy_index + hand_seq * TILES_PER_HAND
	return _canonical_tile_view_for_iid(iid)


func _tile_view(
	instance_id: int = 10,
	tile_id: int = TileId.W5,
	is_red: bool = false,
	owner_seat: int = 0
) -> Dictionary:
	return {
		"instance_id": instance_id,
		"tile_id": tile_id,
		"is_red_dora": is_red,
		"owner_seat": owner_seat,
	}


## 跨局 instance_id 命名空间：hand_seq*136 + serial(0..135)
func _ns(hand_seq: int, serial: int) -> int:
	return hand_seq * TILES_PER_HAND + serial


func _offer(kind: String, options: Array = [{}]) -> Dictionary:
	return {
		"kind": kind,
		"payload_options": options.duplicate(true),
	}


func _discard_opt(tile_instance_id: int = 10) -> Dictionary:
	return {"tile_instance_id": tile_instance_id}


func _chi_opt(a: int = 3, b: int = 7) -> Dictionary:
	return {"companion_tile_instance_ids": [a, b]}


func _pon_opt(a: int = 3, b: int = 7) -> Dictionary:
	return {"companion_tile_instance_ids": [a, b]}


func _minkan_opt(a: int = 1, b: int = 2, c: int = 3) -> Dictionary:
	return {
		"kan_kind": "MINKAN",
		"companion_tile_instance_ids": [a, b, c],
	}


func _ankan_opt(ids: Array = [8, 4, 6, 2]) -> Dictionary:
	return {
		"kan_kind": "ANKAN",
		"tile_instance_ids": ids.duplicate(),
	}


func _added_kan_opt(meld_id: int = 2, added: int = 77) -> Dictionary:
	return {
		"kan_kind": "ADDED_KAN",
		"meld_id": meld_id,
		"added_tile_instance_id": added,
	}


func _pass_offer() -> Dictionary:
	return _offer("PASS", [{}])


func _turn_payload(
	seat: int = 0,
	hand: Array = [],
	last_drawn: int = -1,
	actions: Array = [],
	hand_seq: int = 1,
	decision_id: String = DECISION
) -> Dictionary:
	var hand_tiles: Array = hand
	if hand_tiles.is_empty() and last_drawn == -1 and actions.is_empty():
		# 最小可表达私有窗：默认一张可弃牌 + DISCARD offer；Wall canonical identity。
		var def_tv: Dictionary = _canonical_tile_view_for_iid(_ns(hand_seq, 10))
		hand_tiles = [def_tv]
		last_drawn = -1
		actions = [_offer("DISCARD", [_discard_opt(int(def_tv["instance_id"]))])]
	return {
		"hand_seq": hand_seq,
		"decision_id": decision_id,
		"seat": seat,
		"hand": hand_tiles.duplicate(true),
		"last_drawn_tile_instance_id": last_drawn,
		"allowed_actions": actions.duplicate(true),
	}


func _claim_payload(
	discarded_by_seat: int = 0,
	discarded_tile: Dictionary = {},
	actions: Array = [],
	hand_seq: int = 1,
	decision_id: String = DECISION
) -> Dictionary:
	var tile: Dictionary = discarded_tile
	if tile.is_empty():
		tile = _canonical_tile_view_for_iid(_ns(hand_seq, 50))
	var offers: Array = actions
	if offers.is_empty():
		offers = [_pass_offer()]
	return {
		"hand_seq": hand_seq,
		"decision_id": decision_id,
		"discarded_by_seat": discarded_by_seat,
		"discarded_tile": tile.duplicate(true),
		"allowed_actions": offers.duplicate(true),
	}


func _flat_event(kind: String, server_seq: int, payload: Dictionary) -> Dictionary:
	return {
		"protocol_version": 1,
		"server_seq": server_seq,
		"room_id": ROOM,
		"kind": kind,
		"payload": payload.duplicate(true),
		"view_hash": VIEW_HASH,
	}


func _exact_keys(d: Dictionary, expected: Array) -> bool:
	if d.keys().size() != expected.size():
		return false
	for k in expected:
		if not d.has(k):
			return false
	return true


func _assert_tile_view_exact(tv: Dictionary, expected: Dictionary, label: String) -> void:
	assert_true(_exact_keys(tv, [
		"instance_id", "tile_id", "is_red_dora", "owner_seat",
	]), "%s TileView exact 四键" % label)
	assert_eq(typeof(tv["instance_id"]), TYPE_INT, "%s instance_id 类型" % label)
	assert_eq(int(tv["instance_id"]), int(expected["instance_id"]), "%s instance_id" % label)
	assert_eq(typeof(tv["tile_id"]), TYPE_INT, "%s tile_id 类型" % label)
	assert_eq(int(tv["tile_id"]), int(expected["tile_id"]), "%s tile_id" % label)
	assert_eq(typeof(tv["is_red_dora"]), TYPE_BOOL, "%s is_red_dora 类型" % label)
	assert_eq(bool(tv["is_red_dora"]), bool(expected["is_red_dora"]), "%s is_red_dora" % label)
	assert_eq(typeof(tv["owner_seat"]), TYPE_INT, "%s owner_seat 类型" % label)
	assert_eq(int(tv["owner_seat"]), int(expected["owner_seat"]), "%s owner_seat" % label)


# ---- TURN_PROMPT 正例 ----

func test_turn_prompt_exact_payload_and_empty_hand_legal() -> void:
	# 空 hand 合法；不额外假设牌数；last_drawn 必须 -1
	var empty_hand := _turn_payload(
		1,
		[],
		-1,
		[_offer("TSUMO", [{}])],
		3
	)
	assert_eq(empty_hand["hand"].size(), 0)
	var ne: NetworkedEvent = NetworkedEvent.from_dict(
		_flat_event("TURN_PROMPT", 5, empty_hand)
	)
	assert_not_null(ne, "TURN_PROMPT 空 hand 合法")
	if ne == null:
		return
	var p: Dictionary = ne.to_dict()["payload"] as Dictionary
	assert_true(_exact_keys(p, TURN_PAYLOAD_KEYS), "TURN_PROMPT payload exact 六键")
	assert_eq(typeof(p["hand_seq"]), TYPE_INT)
	assert_eq(int(p["hand_seq"]), 3)
	assert_eq(str(p["decision_id"]), DECISION)
	assert_eq(int(p["seat"]), 1)
	assert_eq(typeof(p["hand"]), TYPE_ARRAY)
	assert_eq((p["hand"] as Array).size(), 0)
	assert_eq(int(p["last_drawn_tile_instance_id"]), -1)
	assert_eq(typeof(p["allowed_actions"]), TYPE_ARRAY)
	var offers: Array = p["allowed_actions"]
	assert_eq(offers.size(), 1)
	assert_true(_exact_keys(offers[0] as Dictionary, OFFER_KEYS))
	assert_eq(str((offers[0] as Dictionary)["kind"]), "TSUMO")


func test_turn_prompt_last_drawn_in_hand_and_tile_views_exact() -> void:
	# hand_seq=7；合法手牌至多 4 张同牌；DISCARD/RIICHI/ANKAN/ADDED_KAN 均引用 hand 内 canonical 实体
	var hs := 7
	var t0 := _canonical_tile_view(TileId.W1, 0, hs)
	var t1 := _canonical_tile_view(TileId.S1, 0, hs)
	var a0 := _canonical_tile_view(TileId.W5, 0, hs)
	var a1 := _canonical_tile_view(TileId.W5, 1, hs)
	var a2 := _canonical_tile_view(TileId.W5, 2, hs)
	var a3 := _canonical_tile_view(TileId.W5, 3, hs)
	var added := _canonical_tile_view(TileId.HAKU, 0, hs)
	var t0_iid: int = int(t0["instance_id"])
	var t1_iid: int = int(t1["instance_id"])
	var a0_iid: int = int(a0["instance_id"])
	var a1_iid: int = int(a1["instance_id"])
	var a2_iid: int = int(a2["instance_id"])
	var a3_iid: int = int(a3["instance_id"])
	var added_iid: int = int(added["instance_id"])
	var payload := _turn_payload(
		2,
		[t0, t1, a0, a1, a2, a3, added],
		t1_iid,
		[
			_offer("DISCARD", [_discard_opt(t0_iid), _discard_opt(t1_iid)]),
			_offer("RIICHI", [_discard_opt(t1_iid)]),
			_offer("KAN", [
				_ankan_opt([a0_iid, a1_iid, a2_iid, a3_iid]),
				_added_kan_opt(1, added_iid),
			]),
			_offer("TSUMO", [{}]),
			_offer("DECLARE_ABORTIVE_DRAW", [{"reason": "KYUUSYU_KYUUHAI"}]),
		],
		hs
	)
	var ne: NetworkedEvent = NetworkedEvent.from_dict(_flat_event("TURN_PROMPT", 8, payload))
	assert_not_null(ne, "TURN 全合法 kind + last_drawn 在 hand 内 + offers 引用 hand")
	if ne == null:
		return
	var p: Dictionary = ne.to_dict()["payload"] as Dictionary
	assert_eq(int(p["last_drawn_tile_instance_id"]), t1_iid)
	var hand: Array = p["hand"]
	assert_eq(hand.size(), 7)
	_assert_tile_view_exact(hand[0] as Dictionary, t0, "hand[0]")
	_assert_tile_view_exact(hand[1] as Dictionary, t1, "hand[1]")
	var kinds: Array = []
	for o in p["allowed_actions"]:
		kinds.append(str((o as Dictionary)["kind"]))
	assert_eq(kinds, [
		"DISCARD", "RIICHI", "KAN", "TSUMO", "DECLARE_ABORTIVE_DRAW",
	])
	assert_false("ITEM_USE" in kinds, "TURN_PROMPT 不得 offer ITEM_USE")

	# ITEM_USE 入 allowed_actions 必须拒绝；命令侧 Action 仍接受
	var with_item := payload.duplicate(true)
	var acts: Array = (with_item["allowed_actions"] as Array).duplicate()
	acts.append(_offer("ITEM_USE", [{"item_instance_id": "inst_abc"}]))
	with_item["allowed_actions"] = acts
	assert_null(
		NetworkedEvent.from_dict(_flat_event("TURN_PROMPT", 8, with_item)),
		"TURN_PROMPT.allowed_actions 含 ITEM_USE 必须拒绝"
	)
	assert_not_null(
		Action.from_dict({
			"protocol_version": 1,
			"command_id": CMD,
			"room_id": ROOM,
			"seat": 0,
			"hand_seq": hs,
			"decision_id": DECISION,
			"kind": "ITEM_USE",
			"payload": {"item_instance_id": "inst_abc"},
			"client_seq": 1,
		}),
		"Action 命令侧仍接受 ITEM_USE"
	)


func test_turn_prompt_offer_options_normalized_deep_copy() -> void:
	# hand_seq=0；单独 canonical discard + 四张 W5 copies 0..3；ANKAN 输入乱序，期望 iid 升序
	var hs := 0
	var discard := _canonical_tile_view(TileId.W1, 0, hs)
	var a0 := _canonical_tile_view(TileId.W5, 0, hs)
	var a1 := _canonical_tile_view(TileId.W5, 1, hs)
	var a2 := _canonical_tile_view(TileId.W5, 2, hs)
	var a3 := _canonical_tile_view(TileId.W5, 3, hs)
	var discard_iid: int = int(discard["instance_id"])
	var a0_iid: int = int(a0["instance_id"])
	var a1_iid: int = int(a1["instance_id"])
	var a2_iid: int = int(a2["instance_id"])
	var a3_iid: int = int(a3["instance_id"])
	var payload := _turn_payload(
		0,
		[discard, a0, a1, a2, a3],
		-1,
		[
			_offer("DISCARD", [_discard_opt(discard_iid)]),
			_offer("KAN", [_ankan_opt([a3_iid, a1_iid, a2_iid, a0_iid])]),
		],
		hs
	)
	var ne: NetworkedEvent = NetworkedEvent.from_dict(_flat_event("TURN_PROMPT", 3, payload))
	assert_not_null(ne, "TURN option 应规范化")
	if ne == null:
		return
	var offers: Array = (ne.to_dict()["payload"] as Dictionary)["allowed_actions"]
	var kan: Dictionary = offers[1] as Dictionary
	var opts: Array = kan["payload_options"]
	assert_eq(opts.size(), 1)
	var ankan: Dictionary = opts[0] as Dictionary
	assert_true(_exact_keys(ankan, ["kan_kind", "tile_instance_ids"]))
	var ids: Array = ankan["tile_instance_ids"]
	assert_eq(ids, [a0_iid, a1_iid, a2_iid, a3_iid], "ANKAN tile_instance_ids 升序规范化")

	# 输入与输出 deep-copy
	((payload["allowed_actions"] as Array)[1] as Dictionary)["kind"] = "HACK"
	((payload["hand"] as Array)[0] as Dictionary)["instance_id"] = 999
	var out1: Dictionary = ne.to_dict()["payload"] as Dictionary
	assert_eq(str(((out1["allowed_actions"] as Array)[1] as Dictionary)["kind"]), "KAN")
	assert_eq(int(((out1["hand"] as Array)[0] as Dictionary)["instance_id"]), discard_iid)
	(out1["hand"] as Array)[0] = _tile_view(99)
	var out2: Dictionary = ne.to_dict()["payload"] as Dictionary
	assert_eq(int(((out2["hand"] as Array)[0] as Dictionary)["instance_id"]), discard_iid, "to_dict deep copy")


# ---- CLAIM_WINDOW 正例 ----

func test_claim_window_exact_payload_pass_required_and_optional_offers() -> void:
	var hs := 4
	# discarded W5 canonical；CHI 用可与 W5 成顺的牌；PON/MINKAN 用其余 W5 copies
	var discarded := _canonical_tile_view(TileId.W5, 0, hs)
	var chi_a := _canonical_tile_view(TileId.W4, 0, hs)
	var chi_b := _canonical_tile_view(TileId.W6, 0, hs)
	var w5_1 := _canonical_tile_view(TileId.W5, 1, hs)
	var w5_2 := _canonical_tile_view(TileId.W5, 2, hs)
	var w5_3 := _canonical_tile_view(TileId.W5, 3, hs)
	var chi_a_iid: int = int(chi_a["instance_id"])
	var chi_b_iid: int = int(chi_b["instance_id"])
	var w5_1_iid: int = int(w5_1["instance_id"])
	var w5_2_iid: int = int(w5_2["instance_id"])
	var w5_3_iid: int = int(w5_3["instance_id"])
	var payload := _claim_payload(0, discarded, [
		_pass_offer(),
		_offer("CHI", [_chi_opt(chi_b_iid, chi_a_iid)]),
		_offer("PON", [_pon_opt(w5_2_iid, w5_1_iid)]),
		_offer("KAN", [_minkan_opt(w5_3_iid, w5_1_iid, w5_2_iid)]),
		_offer("RON", [{}]),
	], hs)
	var ne: NetworkedEvent = NetworkedEvent.from_dict(_flat_event("CLAIM_WINDOW", 12, payload))
	assert_not_null(ne, "CLAIM PASS + 可选合法 offer 正例")
	if ne == null:
		return
	var p: Dictionary = ne.to_dict()["payload"] as Dictionary
	assert_true(_exact_keys(p, CLAIM_PAYLOAD_KEYS), "CLAIM_WINDOW payload exact 五键")
	assert_eq(int(p["hand_seq"]), 4)
	assert_eq(str(p["decision_id"]), DECISION)
	assert_eq(int(p["discarded_by_seat"]), 0)
	_assert_tile_view_exact(p["discarded_tile"] as Dictionary, discarded, "discarded_tile")
	for forbidden in FORBIDDEN_CROSS_SEAT_KEYS:
		assert_false(p.has(forbidden), "CLAIM 不得含跨席容器 %s" % forbidden)
	var offers: Array = p["allowed_actions"]
	assert_eq(offers.size(), 5)
	var kinds: Array = []
	for o in offers:
		var od: Dictionary = o as Dictionary
		assert_true(_exact_keys(od, OFFER_KEYS), "ActionOffer exact 两键")
		kinds.append(str(od["kind"]))
	assert_true("PASS" in kinds, "CLAIM 至少有 PASS")
	assert_eq(kinds, ["PASS", "CHI", "PON", "KAN", "RON"])
	# CHI companions 规范化 deep copy（升序）
	var chi: Dictionary = offers[1] as Dictionary
	var chi_opt: Dictionary = (chi["payload_options"] as Array)[0] as Dictionary
	assert_eq(chi_opt["companion_tile_instance_ids"], [chi_a_iid, chi_b_iid])
	# MINKAN companions 规范化（升序）
	var kan: Dictionary = offers[3] as Dictionary
	var minkan: Dictionary = (kan["payload_options"] as Array)[0] as Dictionary
	assert_eq(str(minkan["kan_kind"]), "MINKAN")
	assert_eq(minkan["companion_tile_instance_ids"], [w5_1_iid, w5_2_iid, w5_3_iid])
	# PASS 严格 [{}]
	var pass_o: Dictionary = offers[0] as Dictionary
	assert_eq((pass_o["payload_options"] as Array).size(), 1)
	assert_eq(((pass_o["payload_options"] as Array)[0] as Dictionary).keys().size(), 0)


func test_claim_window_pass_only_and_rejects_cross_seat_containers() -> void:
	var only_pass := _claim_payload(
		2,
		_canonical_tile_view(TileId.S5, 0, 0),
		[_pass_offer()],
		0
	)
	assert_not_null(
		NetworkedEvent.from_dict(_flat_event("CLAIM_WINDOW", 2, only_pass)),
		"CLAIM 仅 PASS 合法"
	)
	for forbidden in [
		"offers_by_seat", "allowed_actions_by_seat", "eligible_seats", "actions_by_seat",
	]:
		var bad := only_pass.duplicate(true)
		bad[forbidden] = {0: [_pass_offer()], 1: [_pass_offer()]}
		assert_null(
			NetworkedEvent.from_dict(_flat_event("CLAIM_WINDOW", 3, bad)),
			"CLAIM 拒绝跨席容器 %s" % forbidden
		)


# ---- ActionOffer / 窗口 kind 反例 ----

func test_turn_rejects_claim_only_kinds_and_minkan() -> void:
	# hand/DISCARD 引用均 canonical；仅 kind / MINKAN 子型为非法点
	var base_tv: Dictionary = _canonical_tile_view_for_iid(_ns(0, 10))
	var base_iid: int = int(base_tv["instance_id"])
	var base_hand := [base_tv]
	# CHI 继续 W4/W6；PON 用同一牌两个不同 canonical copies（不可复用 CHI companions）
	# TURN 在 kind 白名单处拒绝，不要求成顺/刻
	var chi_a: int = int(_canonical_tile_view(TileId.W4, 0, 0)["instance_id"])
	var chi_b: int = int(_canonical_tile_view(TileId.W6, 0, 0)["instance_id"])
	var pon_a: int = int(_canonical_tile_view(TileId.W5, 1, 0)["instance_id"])
	var pon_b: int = int(_canonical_tile_view(TileId.W5, 2, 0)["instance_id"])
	for bad_kind in ["PASS", "CHI", "PON", "RON"]:
		var opts: Array = [{}]
		if bad_kind == "CHI":
			opts = [_chi_opt(chi_a, chi_b)]
		elif bad_kind == "PON":
			opts = [_pon_opt(pon_a, pon_b)]
		var p := _turn_payload(0, base_hand, -1, [
			_offer("DISCARD", [_discard_opt(base_iid)]),
			_offer(bad_kind, opts),
		], 0)
		assert_null(
			NetworkedEvent.from_dict(_flat_event("TURN_PROMPT", 4, p)),
			"TURN 拒绝 kind=%s" % bad_kind
		)
	var minkan_ids: Array = [
		int(_canonical_tile_view(TileId.W5, 1, 0)["instance_id"]),
		int(_canonical_tile_view(TileId.W5, 2, 0)["instance_id"]),
		int(_canonical_tile_view(TileId.W5, 3, 0)["instance_id"]),
	]
	var minkan_on_turn := _turn_payload(0, base_hand, -1, [
		_offer("KAN", [_minkan_opt(minkan_ids[0], minkan_ids[1], minkan_ids[2])]),
	], 0)
	assert_null(
		NetworkedEvent.from_dict(_flat_event("TURN_PROMPT", 4, minkan_on_turn)),
		"TURN KAN 拒绝 MINKAN option"
	)


func test_claim_rejects_turn_only_kinds_and_closed_kans() -> void:
	# discarded canonical；option 字段 schema 合法，仅 kind / closed kan 为非法点
	var discarded := _canonical_tile_view_for_iid(_ns(0, 50))
	var disc_iid: int = int(discarded["instance_id"])
	for bad_kind in ["DISCARD", "RIICHI", "TSUMO", "ITEM_USE", "DECLARE_ABORTIVE_DRAW"]:
		var opt: Dictionary = {}
		match bad_kind:
			"DISCARD", "RIICHI":
				opt = _discard_opt(disc_iid)
			"ITEM_USE":
				opt = {"item_instance_id": "inst_abc"}
			"DECLARE_ABORTIVE_DRAW":
				opt = {"reason": "KYUUSYU_KYUUHAI"}
			_:
				opt = {}
		var p := _claim_payload(0, discarded, [
			_pass_offer(),
			_offer(bad_kind, [opt]),
		], 0)
		assert_null(
			NetworkedEvent.from_dict(_flat_event("CLAIM_WINDOW", 4, p)),
			"CLAIM 拒绝 kind=%s" % bad_kind
		)
	var a0 := _canonical_tile_view(TileId.W5, 0, 0)
	var a1 := _canonical_tile_view(TileId.W5, 1, 0)
	var a2 := _canonical_tile_view(TileId.W5, 2, 0)
	var a3 := _canonical_tile_view(TileId.W5, 3, 0)
	var closed_opts: Array = [
		_ankan_opt([
			int(a0["instance_id"]), int(a1["instance_id"]),
			int(a2["instance_id"]), int(a3["instance_id"]),
		]),
		_added_kan_opt(2, int(a0["instance_id"])),
	]
	for closed in closed_opts:
		var p2 := _claim_payload(0, discarded, [
			_pass_offer(),
			_offer("KAN", [closed]),
		], 0)
		assert_null(
			NetworkedEvent.from_dict(_flat_event("CLAIM_WINDOW", 4, p2)),
			"CLAIM KAN 拒绝 closed kan_kind=%s" % str(closed.get("kan_kind"))
		)


func test_action_offer_kind_unique_options_nonempty_pass_strict() -> void:
	# hand 五张 canonical：一张可弃 + 四张同牌 W5（供 ANKAN 重复 option 用例）
	var d0 := _canonical_tile_view(TileId.W1, 0, 0)
	var a0 := _canonical_tile_view(TileId.W5, 0, 0)
	var a1 := _canonical_tile_view(TileId.W5, 1, 0)
	var a2 := _canonical_tile_view(TileId.W5, 2, 0)
	var a3 := _canonical_tile_view(TileId.W5, 3, 0)
	var d0_iid: int = int(d0["instance_id"])
	var a0_iid: int = int(a0["instance_id"])
	var a1_iid: int = int(a1["instance_id"])
	var a2_iid: int = int(a2["instance_id"])
	var a3_iid: int = int(a3["instance_id"])
	var hand := [d0, a0, a1, a2, a3]
	# 重复 kind
	var dup_kind := _turn_payload(0, hand, -1, [
		_offer("DISCARD", [_discard_opt(d0_iid)]),
		_offer("DISCARD", [_discard_opt(d0_iid)]),
	], 0)
	assert_null(
		NetworkedEvent.from_dict(_flat_event("TURN_PROMPT", 1, dup_kind)),
		"同一 allowed_actions 中 kind 必须唯一"
	)
	# options 空
	var empty_opts := _turn_payload(0, hand, -1, [
		{"kind": "DISCARD", "payload_options": []},
	], 0)
	assert_null(
		NetworkedEvent.from_dict(_flat_event("TURN_PROMPT", 1, empty_opts)),
		"payload_options 必须非空"
	)
	# 规范化后重复 options（四 iid 同源 hand；乱序与升序规范化后同一 option）
	var dup_opts := _turn_payload(0, hand, -1, [
		_offer("KAN", [
			_ankan_opt([a0_iid, a1_iid, a2_iid, a3_iid]),
			_ankan_opt([a3_iid, a2_iid, a1_iid, a0_iid]),
		]),
	], 0)
	assert_null(
		NetworkedEvent.from_dict(_flat_event("TURN_PROMPT", 1, dup_opts)),
		"规范化后重复 option 拒绝"
	)
	# CHI：discarded + 可成顺 companions 均 canonical；仅规范化后重复为非法点
	var chi_disc := _canonical_tile_view(TileId.W5, 0, 0)
	var chi_a_iid: int = int(_canonical_tile_view(TileId.W4, 0, 0)["instance_id"])
	var chi_b_iid: int = int(_canonical_tile_view(TileId.W6, 0, 0)["instance_id"])
	var claim_dup_chi := _claim_payload(0, chi_disc, [
		_pass_offer(),
		_offer("CHI", [_chi_opt(chi_b_iid, chi_a_iid), _chi_opt(chi_a_iid, chi_b_iid)]),
	], 0)
	assert_null(
		NetworkedEvent.from_dict(_flat_event("CLAIM_WINDOW", 1, claim_dup_chi)),
		"CHI companions 规范化后重复拒绝"
	)
	# PASS 必须严格 [{}]
	var pass_disc := _canonical_tile_view_for_iid(_ns(0, 50))
	for bad_pass_opts in [[], [{}, {}], [{"x": 1}], [{"tile_instance_id": 1}]]:
		var bad_pass := _claim_payload(0, pass_disc, [
			{"kind": "PASS", "payload_options": bad_pass_opts},
		], 0)
		assert_null(
			NetworkedEvent.from_dict(_flat_event("CLAIM_WINDOW", 1, bad_pass)),
			"PASS payload_options 必须严格 [{}]，拒绝 %s" % str(bad_pass_opts)
		)
	# CLAIM 缺 PASS
	var no_pass := _claim_payload(0, pass_disc, [
		_offer("RON", [{}]),
	], 0)
	assert_null(
		NetworkedEvent.from_dict(_flat_event("CLAIM_WINDOW", 1, no_pass)),
		"CLAIM 至少有 PASS"
	)


func test_action_offer_options_are_action_payload_not_envelope() -> void:
	var hand_tv: Dictionary = _canonical_tile_view_for_iid(_ns(0, 10))
	var hand_iid: int = int(hand_tv["instance_id"])
	var hand := [hand_tv]
	# option 塞 envelope 字段
	var with_env := _turn_payload(0, hand, -1, [
		_offer("DISCARD", [{
			"tile_instance_id": hand_iid,
			"command_id": DECISION,
			"seat": 0,
		}]),
	], 0)
	assert_null(
		NetworkedEvent.from_dict(_flat_event("TURN_PROMPT", 1, with_env)),
		"option 不得含 Action envelope 字段"
	)
	# 旧 tile_id schema
	var old_tile := _turn_payload(0, hand, -1, [
		_offer("DISCARD", [{"tile_id": TileId.W5, "is_red_dora": false}]),
	], 0)
	assert_null(
		NetworkedEvent.from_dict(_flat_event("TURN_PROMPT", 1, old_tile)),
		"option 拒绝旧 tile_id schema"
	)
	# 错误实体：TileView 当 DISCARD option（手牌与 iid 同源 canonical，仅 option 形态非法）
	var wrong_entity := _turn_payload(0, hand, -1, [
		_offer("DISCARD", [hand_tv.duplicate(true)]),
	], 0)
	assert_null(
		NetworkedEvent.from_dict(_flat_event("TURN_PROMPT", 1, wrong_entity)),
		"DISCARD option 不得是 TileView"
	)
	# CLAIM CHI 旧 discarder 字段：discarded + companions 成顺 canonical，仅多余 discarder 键
	var chi_disc := _canonical_tile_view(TileId.W5, 0, 0)
	var chi_a_iid: int = int(_canonical_tile_view(TileId.W4, 0, 0)["instance_id"])
	var chi_b_iid: int = int(_canonical_tile_view(TileId.W6, 0, 0)["instance_id"])
	var old_chi := _claim_payload(0, chi_disc, [
		_pass_offer(),
		_offer("CHI", [{
			"discarder_seat": 0,
			"companion_tile_instance_ids": [chi_a_iid, chi_b_iid],
		}]),
	], 0)
	assert_null(
		NetworkedEvent.from_dict(_flat_event("CLAIM_WINDOW", 1, old_chi)),
		"CHI option 拒绝旧 discarder 字段"
	)


# ---- exact missing/extra/wrong types / 边界 ----

func test_turn_prompt_rejects_missing_extra_wrong_types_and_ranges() -> void:
	var base := _turn_payload()
	assert_not_null(NetworkedEvent.from_dict(_flat_event("TURN_PROMPT", 1, base)))

	for key in TURN_PAYLOAD_KEYS:
		var missing := base.duplicate(true)
		missing.erase(key)
		assert_null(
			NetworkedEvent.from_dict(_flat_event("TURN_PROMPT", 1, missing)),
			"TURN 缺 %s 拒绝" % key
		)

	var extra := base.duplicate(true)
	extra["window_id"] = "w1"
	assert_null(
		NetworkedEvent.from_dict(_flat_event("TURN_PROMPT", 1, extra)),
		"TURN 多余键拒绝"
	)

	var bad_seat := base.duplicate(true)
	bad_seat["seat"] = 4
	assert_null(NetworkedEvent.from_dict(_flat_event("TURN_PROMPT", 1, bad_seat)), "seat>3")
	bad_seat["seat"] = -1
	assert_null(NetworkedEvent.from_dict(_flat_event("TURN_PROMPT", 1, bad_seat)), "seat<0")
	bad_seat["seat"] = 1.0
	assert_null(NetworkedEvent.from_dict(_flat_event("TURN_PROMPT", 1, bad_seat)), "seat float")

	var bad_hs := base.duplicate(true)
	bad_hs["hand_seq"] = -1
	assert_null(NetworkedEvent.from_dict(_flat_event("TURN_PROMPT", 1, bad_hs)), "hand_seq=-1")
	bad_hs["hand_seq"] = MAX_HAND_SEQ + 1
	assert_null(
		NetworkedEvent.from_dict(_flat_event("TURN_PROMPT", 1, bad_hs)),
		"hand_seq=MAX_HAND_SEQ+1"
	)
	bad_hs["hand_seq"] = 1.5
	assert_null(NetworkedEvent.from_dict(_flat_event("TURN_PROMPT", 1, bad_hs)), "hand_seq float")
	var max_hs_iid: int = _ns(MAX_HAND_SEQ, 10)
	var max_hs_tv: Dictionary = _canonical_tile_view_for_iid(max_hs_iid)
	assert_not_null(NetworkedEvent.from_dict(_flat_event(
		"TURN_PROMPT", 1, _turn_payload(0, [max_hs_tv], -1, [
			_offer("DISCARD", [_discard_opt(int(max_hs_tv["instance_id"]))]),
		], MAX_HAND_SEQ)
	)), "hand_seq=MAX_HAND_SEQ 合法且 instance_id 落在该局命名空间")

	for bad_dec in [
		"", "not-a-uuid", "550e8400e29b41d4a716446655440000", 123,
		"550e8400-e29b-11d4-a716-4466554400aa", # version≠4
		"550e8400-e29b-41d4-7716-4466554400aa", # variant 7xxx
		"550e8400-e29b-41d4-c716-4466554400aa", # variant cxxx
	]:
		var bd := base.duplicate(true)
		bd["decision_id"] = bad_dec
		assert_null(
			NetworkedEvent.from_dict(_flat_event("TURN_PROMPT", 1, bd)),
			"非法 decision_id: %s" % str(bad_dec)
		)
	var upper := base.duplicate(true)
	upper["decision_id"] = "550E8400-E29B-41D4-A716-4466554400AA"
	assert_null(
		NetworkedEvent.from_dict(_flat_event("TURN_PROMPT", 1, upper)),
		"大写 UUID 必须拒绝"
	)
	# 正例：lowercase v4+variant 仍合法
	assert_not_null(
		NetworkedEvent.from_dict(_flat_event("TURN_PROMPT", 1, base)),
		"lowercase v4 decision_id 正例"
	)

	# 重复 instance_id：两 view 均为同一 canonical 的 duplicate，仅 iid 重复为非法点
	var dup_tv: Dictionary = _canonical_tile_view_for_iid(_ns(0, 10))
	var dup_iid: int = int(dup_tv["instance_id"])
	var dup_other: Dictionary = _canonical_tile_view_for_iid(_ns(0, 11))
	assert_not_null(NetworkedEvent.from_dict(_flat_event(
		"TURN_PROMPT", 1, _turn_payload(0, [dup_tv, dup_other], -1, [
			_offer("DISCARD", [_discard_opt(dup_iid)]),
		], 0)
	)), "paired baseline: 两张不同 canonical hand 合法")
	var dup_hand := _turn_payload(0, [
		dup_tv.duplicate(true),
		dup_tv.duplicate(true),
	], -1, [_offer("DISCARD", [_discard_opt(dup_iid)])], 0)
	assert_null(
		NetworkedEvent.from_dict(_flat_event("TURN_PROMPT", 1, dup_hand)),
		"hand 不得重复 instance_id"
	)

	# last_drawn 成员约束：hand/DISCARD 同源 canonical，仅 last_drawn 非法
	var ld_tv: Dictionary = _canonical_tile_view_for_iid(_ns(0, 10))
	var ld_iid: int = int(ld_tv["instance_id"])
	var ld_not_in_hand: int = int(_canonical_tile_view_for_iid(_ns(0, 11))["instance_id"])
	assert_not_null(NetworkedEvent.from_dict(_flat_event(
		"TURN_PROMPT", 1, _turn_payload(0, [ld_tv], ld_iid, [
			_offer("DISCARD", [_discard_opt(ld_iid)]),
		], 0)
	)), "paired baseline: last_drawn 在 hand 内合法")
	var not_member := _turn_payload(0, [ld_tv], ld_not_in_hand, [
		_offer("DISCARD", [_discard_opt(ld_iid)]),
	], 0)
	assert_null(
		NetworkedEvent.from_dict(_flat_event("TURN_PROMPT", 1, not_member)),
		"last_drawn>=0 必须是 hand 中 instance_id"
	)
	var last_neg := _turn_payload(0, [ld_tv], -2, [
		_offer("DISCARD", [_discard_opt(ld_iid)]),
	], 0)
	assert_null(
		NetworkedEvent.from_dict(_flat_event("TURN_PROMPT", 1, last_neg)),
		"last_drawn<-1 拒绝"
	)
	# hand_seq=0 命名空间仅 [0,135]；TileView 按 MAX_SAFE iid canonical，仅命名空间越界
	var max_safe_tv: Dictionary = _canonical_tile_view_for_iid(MAX_SAFE_INT)
	var max_safe_iid: int = int(max_safe_tv["instance_id"])
	assert_null(NetworkedEvent.from_dict(_flat_event(
		"TURN_PROMPT", 1, _turn_payload(0, [max_safe_tv], max_safe_iid, [
			_offer("DISCARD", [_discard_opt(max_safe_iid)]),
		], 0)
	)), "hand_seq=0 时 MAX_SAFE instance_id 超出命名空间拒绝")
	var over_safe := _turn_payload(0, [ld_tv], MAX_SAFE_INT + 1, [
		_offer("DISCARD", [_discard_opt(ld_iid)]),
	], 0)
	assert_null(
		NetworkedEvent.from_dict(_flat_event("TURN_PROMPT", 1, over_safe)),
		"last_drawn=MAX_SAFE+1 拒绝"
	)

	# 坏 TileView：除缺 owner_seat / iid float 外其余字段为整数基准 canonical
	var tv_base: Dictionary = _canonical_tile_view_for_iid(_ns(0, 1))
	var tv_base_iid: int = int(tv_base["instance_id"])
	assert_not_null(NetworkedEvent.from_dict(_flat_event(
		"TURN_PROMPT", 1, _turn_payload(0, [tv_base], -1, [
			_offer("DISCARD", [_discard_opt(tv_base_iid)]),
		], 0)
	)), "paired baseline: 完整 canonical TileView 合法")
	var missing_owner: Dictionary = tv_base.duplicate(true)
	missing_owner.erase("owner_seat")
	var bad_tv := _turn_payload(0, [missing_owner], -1, [
		_offer("DISCARD", [_discard_opt(tv_base_iid)]),
	], 0)
	assert_null(
		NetworkedEvent.from_dict(_flat_event("TURN_PROMPT", 1, bad_tv)),
		"hand TileView 缺 owner_seat"
	)
	# float iid：不引用实体的 TSUMO offer，只让 TileView.instance_id float 非法
	# （DISCARD 仍引用整数 iid 会额外触发「引用不在 hand」）
	assert_not_null(NetworkedEvent.from_dict(_flat_event(
		"TURN_PROMPT", 1, _turn_payload(0, [tv_base], -1, [
			_offer("TSUMO", [{}]),
		], 0)
	)), "paired baseline: canonical hand + TSUMO 合法")
	var float_view: Dictionary = tv_base.duplicate(true)
	float_view["instance_id"] = float(tv_base_iid) + 0.5
	var float_tv := _turn_payload(0, [float_view], -1, [
		_offer("TSUMO", [{}]),
	], 0)
	assert_null(
		NetworkedEvent.from_dict(_flat_event("TURN_PROMPT", 1, float_tv)),
		"hand TileView.instance_id float 拒绝"
	)

	# offer 结构：hand/引用 canonical，仅 offer 缺键或多余键
	var offer_tv: Dictionary = _canonical_tile_view_for_iid(_ns(0, 10))
	var offer_iid: int = int(offer_tv["instance_id"])
	assert_not_null(NetworkedEvent.from_dict(_flat_event(
		"TURN_PROMPT", 1, _turn_payload(0, [offer_tv], -1, [
			_offer("DISCARD", [_discard_opt(offer_iid)]),
		], 0)
	)), "paired baseline: 合法 DISCARD offer")
	var bad_offer := _turn_payload(0, [offer_tv], -1, [
		{"kind": "DISCARD"},
	], 0)
	assert_null(
		NetworkedEvent.from_dict(_flat_event("TURN_PROMPT", 1, bad_offer)),
		"offer 缺 payload_options"
	)
	var offer_extra := _turn_payload(0, [offer_tv], -1, [
		{"kind": "DISCARD", "payload_options": [_discard_opt(offer_iid)], "extra": 1},
	], 0)
	assert_null(
		NetworkedEvent.from_dict(_flat_event("TURN_PROMPT", 1, offer_extra)),
		"offer 多余键拒绝"
	)


func test_claim_window_rejects_missing_extra_wrong_types_and_tileview() -> void:
	var base := _claim_payload()
	assert_not_null(NetworkedEvent.from_dict(_flat_event("CLAIM_WINDOW", 1, base)))

	for key in CLAIM_PAYLOAD_KEYS:
		var missing := base.duplicate(true)
		missing.erase(key)
		assert_null(
			NetworkedEvent.from_dict(_flat_event("CLAIM_WINDOW", 1, missing)),
			"CLAIM 缺 %s 拒绝" % key
		)

	var extra := base.duplicate(true)
	extra["discarder_seat"] = 1
	assert_null(
		NetworkedEvent.from_dict(_flat_event("CLAIM_WINDOW", 1, extra)),
		"CLAIM 旧 discarder_seat 键拒绝"
	)
	extra = base.duplicate(true)
	extra["tile_id"] = TileId.W5
	assert_null(
		NetworkedEvent.from_dict(_flat_event("CLAIM_WINDOW", 1, extra)),
		"CLAIM 旧 tile_id 顶层键拒绝"
	)

	var bad_seat := base.duplicate(true)
	bad_seat["discarded_by_seat"] = 4
	assert_null(
		NetworkedEvent.from_dict(_flat_event("CLAIM_WINDOW", 1, bad_seat)),
		"discarded_by_seat 必须 0..3"
	)
	bad_seat["discarded_by_seat"] = "0"
	assert_null(
		NetworkedEvent.from_dict(_flat_event("CLAIM_WINDOW", 1, bad_seat)),
		"discarded_by_seat 不得 str 强转"
	)

	# discarded_tile 仅翻转 is_red_dora；其余字段保持 base 内 canonical identity
	var disc_canon: Dictionary = (base["discarded_tile"] as Dictionary).duplicate(true)
	var disc_canon_iid: int = int(disc_canon["instance_id"])
	var bad_red: Dictionary = disc_canon.duplicate(true)
	bad_red["is_red_dora"] = not bool(bad_red["is_red_dora"])
	var bad_tile := base.duplicate(true)
	bad_tile["discarded_tile"] = bad_red
	assert_null(
		NetworkedEvent.from_dict(_flat_event("CLAIM_WINDOW", 1, bad_tile)),
		"discarded_tile 非法 is_red_dora 拒绝"
	)
	# 缺键负例：不伪造其余 identity 字段
	bad_tile["discarded_tile"] = {"tile_id": TileId.W5}
	assert_null(
		NetworkedEvent.from_dict(_flat_event("CLAIM_WINDOW", 1, bad_tile)),
		"discarded_tile 非 exact TileView 拒绝"
	)

	# float iid：其余字段为整数基准 disc_canon 的 canonical 值
	var float_disc: Dictionary = disc_canon.duplicate(true)
	float_disc["instance_id"] = float(disc_canon_iid) + 0.5
	var float_iid := base.duplicate(true)
	float_iid["discarded_tile"] = float_disc
	assert_null(
		NetworkedEvent.from_dict(_flat_event("CLAIM_WINDOW", 1, float_iid)),
		"discarded_tile.instance_id float 拒绝"
	)

	# 输入 deep-copy（hand_seq=0 命名空间；canonical W5 discarded + 其余 W5 copies 做 PON）
	var deep_disc := _canonical_tile_view(TileId.W5, 0, 0)
	var deep_w5_1 := _canonical_tile_view(TileId.W5, 1, 0)
	var deep_w5_2 := _canonical_tile_view(TileId.W5, 2, 0)
	var deep_disc_iid: int = int(deep_disc["instance_id"])
	var deep_w5_1_iid: int = int(deep_w5_1["instance_id"])
	var deep_w5_2_iid: int = int(deep_w5_2["instance_id"])
	var src := _claim_payload(1, deep_disc, [
		_pass_offer(),
		_offer("PON", [_pon_opt(deep_w5_1_iid, deep_w5_2_iid)]),
	], 0)
	var ne: NetworkedEvent = NetworkedEvent.from_dict(_flat_event("CLAIM_WINDOW", 9, src))
	assert_not_null(ne)
	if ne == null:
		return
	src["discarded_by_seat"] = 3
	(src["discarded_tile"] as Dictionary)["instance_id"] = 0
	((src["allowed_actions"] as Array)[1] as Dictionary)["kind"] = "HACK"
	var out1: Dictionary = ne.to_dict()["payload"] as Dictionary
	assert_eq(int(out1["discarded_by_seat"]), 1)
	assert_eq(int((out1["discarded_tile"] as Dictionary)["instance_id"]), deep_disc_iid)
	assert_eq(str(((out1["allowed_actions"] as Array)[1] as Dictionary)["kind"]), "PON")
	# PON companions 规范化输出
	var pon_opt: Dictionary = (
		((out1["allowed_actions"] as Array)[1] as Dictionary)["payload_options"] as Array
	)[0]
	assert_eq(pon_opt["companion_tile_instance_ids"], [deep_w5_1_iid, deep_w5_2_iid])
	out1["discarded_by_seat"] = 0
	var out2: Dictionary = ne.to_dict()["payload"] as Dictionary
	assert_eq(int(out2["discarded_by_seat"]), 1, "to_dict deep copy")

# ---- #232 跨局命名空间 + TURN offer 手牌引用反例（生产缺口 Red）----

func test_turn_prompt_rejects_instance_ids_outside_hand_seq_namespace() -> void:
	# hand_seq=1 合法域 [136,271]；iid=10 属 hand_seq=0。
	# TileView 按越界 iid 本身 canonical，仅 namespace 与 hand_seq 不匹配。
	var oor_tv: Dictionary = _canonical_tile_view_for_iid(10)
	var oor_iid: int = int(oor_tv["instance_id"])
	var oor := _turn_payload(0, [oor_tv], -1, [
		_offer("DISCARD", [_discard_opt(oor_iid)]),
	], 1)
	assert_null(
		NetworkedEvent.from_dict(_flat_event("TURN_PROMPT", 1, oor)),
		"TURN hand instance_id 超出 hand_seq 命名空间必须拒绝"
	)
	# 上界+1：view 按越界 iid canonical
	var over_iid: int = _ns(1, 136)
	var over_tv: Dictionary = _canonical_tile_view_for_iid(over_iid)
	var over := _turn_payload(0, [over_tv], -1, [
		_offer("DISCARD", [_discard_opt(over_iid)]),
	], 1)
	assert_null(
		NetworkedEvent.from_dict(_flat_event("TURN_PROMPT", 1, over)),
		"TURN hand instance_id=hand_seq*136+136 必须拒绝"
	)
	# 正例：边界 serial 0 与 135（canonical view + 同源 discard iid）
	var ns_lo: Dictionary = _canonical_tile_view_for_iid(_ns(1, 0))
	assert_not_null(NetworkedEvent.from_dict(_flat_event(
		"TURN_PROMPT", 1, _turn_payload(0, [ns_lo], -1, [
			_offer("DISCARD", [_discard_opt(int(ns_lo["instance_id"]))]),
		], 1)
	)), "serial=0 合法")
	var ns_hi: Dictionary = _canonical_tile_view_for_iid(_ns(1, 135))
	assert_not_null(NetworkedEvent.from_dict(_flat_event(
		"TURN_PROMPT", 1, _turn_payload(0, [ns_hi], -1, [
			_offer("DISCARD", [_discard_opt(int(ns_hi["instance_id"]))]),
		], 1)
	)), "serial=135 合法")


func test_claim_window_rejects_discarded_tile_outside_hand_seq_namespace() -> void:
	# view 按越界 iid=10 canonical；仅 hand_seq=2 命名空间不匹配
	var bad := _claim_payload(
		0, _canonical_tile_view_for_iid(10), [_pass_offer()], 2
	)
	assert_null(
		NetworkedEvent.from_dict(_flat_event("CLAIM_WINDOW", 1, bad)),
		"CLAIM discarded_tile 超出 hand_seq=2 命名空间 [272,407] 必须拒绝"
	)
	assert_not_null(NetworkedEvent.from_dict(_flat_event(
		"CLAIM_WINDOW", 1, _claim_payload(
			0, _canonical_tile_view_for_iid(_ns(2, 10)), [_pass_offer()], 2
		)
	)), "CLAIM discarded_tile 在命名空间内合法")


## CLAIM companions 须落在 hand_seq 命名空间（本窗无 hand/recipient 字段；
## 仅校验 companion_tile_instance_ids 与 discarded_tile 的跨局域，不引入新 wire 键）。
func test_claim_window_rejects_companion_ids_outside_hand_seq_namespace() -> void:
	var hs := 2
	# 合法域 [272,407]
	var lo: int = _ns(hs, 0)
	var hi: int = _ns(hs, 135)
	# 共享 discarded W5 copy0（canonical）；CHI 用 W4/W6，PON/MINKAN 用其余 W5
	var discarded: Dictionary = _canonical_tile_view(TileId.W5, 0, hs)
	var chi_a_iid: int = int(_canonical_tile_view(TileId.W4, 0, hs)["instance_id"])
	var chi_b_iid: int = int(_canonical_tile_view(TileId.W6, 0, hs)["instance_id"])
	var pon_a_iid: int = int(_canonical_tile_view(TileId.W5, 1, hs)["instance_id"])
	var pon_b_iid: int = int(_canonical_tile_view(TileId.W5, 2, hs)["instance_id"])
	var minkan_c_iid: int = int(_canonical_tile_view(TileId.W5, 3, hs)["instance_id"])
	# 按替换位分别构造前/后 hand_seq 中相同 tile_id+copy 的 canonical iid，只让 namespace 越界
	var chi_a_prev: int = int(_canonical_tile_view(TileId.W4, 0, hs - 1)["instance_id"])
	var chi_b_next: int = int(_canonical_tile_view(TileId.W6, 0, hs + 1)["instance_id"])
	var pon_a_prev: int = int(_canonical_tile_view(TileId.W5, 1, hs - 1)["instance_id"])
	var pon_b_next: int = int(_canonical_tile_view(TileId.W5, 2, hs + 1)["instance_id"])
	var minkan_c_prev: int = int(_canonical_tile_view(TileId.W5, 3, hs - 1)["instance_id"])

	# paired baseline：全合法 companions 可 from_dict
	assert_not_null(NetworkedEvent.from_dict(_flat_event(
		"CLAIM_WINDOW", 1, _claim_payload(0, discarded, [
			_pass_offer(),
			_offer("CHI", [_chi_opt(chi_a_iid, chi_b_iid)]),
			_offer("PON", [_pon_opt(pon_a_iid, pon_b_iid)]),
			_offer("KAN", [_minkan_opt(pon_a_iid, pon_b_iid, minkan_c_iid)]),
		], hs)
	)), "paired baseline: CHI/PON/MINKAN 全合法 companions")

	# ---- 逐类反例：替换位保持原牌型/copy，仅 companion iid 跨 hand_seq 命名空间 ----
	# CHI：第一 companion 仍为 W4 copy0，落在前一 hand_seq
	assert_null(NetworkedEvent.from_dict(_flat_event(
		"CLAIM_WINDOW", 1, _claim_payload(0, discarded, [
			_pass_offer(),
			_offer("CHI", [_chi_opt(chi_a_prev, chi_b_iid)]),
		], hs)
	)), "CHI companion[0] 超出 hand_seq 命名空间必须拒绝")
	# CHI：第二 companion 仍为 W6 copy0，落在后一 hand_seq
	assert_null(NetworkedEvent.from_dict(_flat_event(
		"CLAIM_WINDOW", 1, _claim_payload(0, discarded, [
			_pass_offer(),
			_offer("CHI", [_chi_opt(chi_a_iid, chi_b_next)]),
		], hs)
	)), "CHI companion[1] 超出 hand_seq 命名空间必须拒绝")

	# PON：替换位仍为对应 W5 copy
	assert_null(NetworkedEvent.from_dict(_flat_event(
		"CLAIM_WINDOW", 1, _claim_payload(0, discarded, [
			_pass_offer(),
			_offer("PON", [_pon_opt(pon_a_prev, pon_b_iid)]),
		], hs)
	)), "PON companion[0] 超出 hand_seq 命名空间必须拒绝")
	assert_null(NetworkedEvent.from_dict(_flat_event(
		"CLAIM_WINDOW", 1, _claim_payload(0, discarded, [
			_pass_offer(),
			_offer("PON", [_pon_opt(pon_a_iid, pon_b_next)]),
		], hs)
	)), "PON companion[1] 超出 hand_seq 命名空间必须拒绝")

	# MINKAN：三 companion 分位覆盖，替换位仍为对应 W5 copy
	assert_null(NetworkedEvent.from_dict(_flat_event(
		"CLAIM_WINDOW", 1, _claim_payload(0, discarded, [
			_pass_offer(),
			_offer("KAN", [_minkan_opt(pon_a_prev, pon_b_iid, minkan_c_iid)]),
		], hs)
	)), "MINKAN companion[0] 超出 hand_seq 命名空间必须拒绝")
	assert_null(NetworkedEvent.from_dict(_flat_event(
		"CLAIM_WINDOW", 1, _claim_payload(0, discarded, [
			_pass_offer(),
			_offer("KAN", [_minkan_opt(pon_a_iid, pon_b_next, minkan_c_iid)]),
		], hs)
	)), "MINKAN companion[1] 超出 hand_seq 命名空间必须拒绝")
	assert_null(NetworkedEvent.from_dict(_flat_event(
		"CLAIM_WINDOW", 1, _claim_payload(0, discarded, [
			_pass_offer(),
			_offer("KAN", [_minkan_opt(pon_a_iid, pon_b_iid, minkan_c_prev)]),
		], hs)
	)), "MINKAN companion[2] 超出 hand_seq 命名空间必须拒绝")

	# ---- 正例：companions 全在命名空间（含边界 serial 0/135）----
	# 下界：W2 discarded + W1(serial0)/W3 做 CHI（合法顺子，验 serial0）
	var chi_disc := _canonical_tile_view(TileId.W2, 0, hs)
	var chi_w1 := _canonical_tile_view_for_iid(lo)
	var chi_w3 := _canonical_tile_view(TileId.W3, 0, hs)
	var chi_w1_iid: int = int(chi_w1["instance_id"])
	var chi_w3_iid: int = int(chi_w3["instance_id"])
	assert_not_null(NetworkedEvent.from_dict(_flat_event(
		"CLAIM_WINDOW", 1, _claim_payload(0, chi_disc, [
			_pass_offer(),
			_offer("CHI", [_chi_opt(chi_w1_iid, chi_w3_iid)]),
		], hs)
	)), "CLAIM CHI companions 含 serial0 下界合法")

	# 上界：CHUN discarded + 其余 CHUN copies（含 serial135）做 PON/MINKAN
	var chun0 := _canonical_tile_view(TileId.CHUN, 0, hs)
	var chun1 := _canonical_tile_view(TileId.CHUN, 1, hs)
	var chun2 := _canonical_tile_view(TileId.CHUN, 2, hs)
	var chun3 := _canonical_tile_view_for_iid(hi)
	var chun1_iid: int = int(chun1["instance_id"])
	var chun2_iid: int = int(chun2["instance_id"])
	var chun3_iid: int = int(chun3["instance_id"])
	assert_not_null(NetworkedEvent.from_dict(_flat_event(
		"CLAIM_WINDOW", 1, _claim_payload(0, chun0, [
			_pass_offer(),
			_offer("PON", [_pon_opt(chun1_iid, chun2_iid)]),
			_offer("KAN", [_minkan_opt(chun1_iid, chun2_iid, chun3_iid)]),
		], hs)
	)), "CLAIM PON/MINKAN companions 含 serial135 上界合法")

	# ---- PASS / RON 不受 companions 命名空间规则影响（无 companion 字段）----
	var pass_disc: Dictionary = _canonical_tile_view_for_iid(_ns(hs, 50))
	assert_not_null(NetworkedEvent.from_dict(_flat_event(
		"CLAIM_WINDOW", 1, _claim_payload(0, pass_disc, [_pass_offer()], hs)
	)), "仅 PASS 合法（无 companion）")
	assert_not_null(NetworkedEvent.from_dict(_flat_event(
		"CLAIM_WINDOW", 1, _claim_payload(0, pass_disc, [
			_pass_offer(),
			_offer("RON", [{}]),
		], hs)
	)), "PASS+RON 合法（无 companion）")


func test_turn_prompt_offers_must_reference_current_hand_entities() -> void:
	var hs := 1
	var hand_tv: Dictionary = _canonical_tile_view_for_iid(_ns(hs, 10))
	var in_hand: int = int(hand_tv["instance_id"])
	var out_hand := _ns(hs, 11)
	var hand := [hand_tv]

	# DISCARD 引用不在 hand 的实体
	assert_null(NetworkedEvent.from_dict(_flat_event(
		"TURN_PROMPT", 2, _turn_payload(0, hand, -1, [
			_offer("DISCARD", [_discard_opt(out_hand)]),
		], hs)
	)), "DISCARD tile_instance_id 不在 hand 必须拒绝")

	# RIICHI 同
	assert_null(NetworkedEvent.from_dict(_flat_event(
		"TURN_PROMPT", 2, _turn_payload(0, hand, -1, [
			_offer("DISCARD", [_discard_opt(in_hand)]),
			_offer("RIICHI", [_discard_opt(out_hand)]),
		], hs)
	)), "RIICHI tile_instance_id 不在 hand 必须拒绝")

	# ANKAN：三张 hand 与引用均为同一牌 canonical copies；第四 copy 只缺席于 hand
	# 额外 DISCARD 实体也 canonical，不伪造 TileView
	var a0_miss := _canonical_tile_view(TileId.W5, 0, hs)
	var a1_miss := _canonical_tile_view(TileId.W5, 1, hs)
	var a2_miss := _canonical_tile_view(TileId.W5, 2, hs)
	var a3_miss := _canonical_tile_view(TileId.W5, 3, hs)
	var a0_miss_iid: int = int(a0_miss["instance_id"])
	var a1_miss_iid: int = int(a1_miss["instance_id"])
	var a2_miss_iid: int = int(a2_miss["instance_id"])
	var a3_miss_iid: int = int(a3_miss["instance_id"])
	var three_in := [a0_miss, a1_miss, a2_miss, hand_tv]
	assert_not_null(NetworkedEvent.from_dict(_flat_event(
		"TURN_PROMPT", 2, _turn_payload(0, [a0_miss, a1_miss, a2_miss, a3_miss], -1, [
			_offer("DISCARD", [_discard_opt(a0_miss_iid)]),
			_offer("KAN", [_ankan_opt([a0_miss_iid, a1_miss_iid, a2_miss_iid, a3_miss_iid])]),
		], hs)
	)), "paired baseline: ANKAN 四张全在 hand 合法")
	assert_null(NetworkedEvent.from_dict(_flat_event(
		"TURN_PROMPT", 2, _turn_payload(0, three_in, -1, [
			_offer("DISCARD", [_discard_opt(in_hand)]),
			_offer("KAN", [_ankan_opt([a0_miss_iid, a1_miss_iid, a2_miss_iid, a3_miss_iid])]),
		], hs)
	)), "ANKAN 缺第四张在 hand 必须拒绝")

	# ADDED_KAN：added 实体必须在 hand（meld_id→同席 PON 超出 TURN 现有 schema，不伪造字段）
	assert_null(NetworkedEvent.from_dict(_flat_event(
		"TURN_PROMPT", 2, _turn_payload(0, hand, -1, [
			_offer("DISCARD", [_discard_opt(in_hand)]),
			_offer("KAN", [_added_kan_opt(0, out_hand)]),
		], hs)
	)), "ADDED_KAN added_tile_instance_id 不在 hand 必须拒绝")

	# 正例：ANKAN 四张全在 hand（同一牌四个 canonical copies）
	var a0 := _canonical_tile_view(TileId.W5, 0, hs)
	var a1 := _canonical_tile_view(TileId.W5, 1, hs)
	var a2 := _canonical_tile_view(TileId.W5, 2, hs)
	var a3 := _canonical_tile_view(TileId.W5, 3, hs)
	var a0_iid: int = int(a0["instance_id"])
	var a1_iid: int = int(a1["instance_id"])
	var a2_iid: int = int(a2["instance_id"])
	var a3_iid: int = int(a3["instance_id"])
	var four := [a0, a1, a2, a3]
	assert_not_null(NetworkedEvent.from_dict(_flat_event(
		"TURN_PROMPT", 2, _turn_payload(0, four, -1, [
			_offer("DISCARD", [_discard_opt(a0_iid)]),
			_offer("KAN", [_ankan_opt([a0_iid, a1_iid, a2_iid, a3_iid])]),
		], hs)
	)), "ANKAN 四实体在 hand 且互异合法")
	# 正例：ADDED_KAN added 在 hand（引用 canonical hand iid）
	assert_not_null(NetworkedEvent.from_dict(_flat_event(
		"TURN_PROMPT", 2, _turn_payload(0, hand, -1, [
			_offer("DISCARD", [_discard_opt(in_hand)]),
			_offer("KAN", [_added_kan_opt(0, in_hand)]),
		], hs)
	)), "ADDED_KAN added 在 hand 合法（meld_id 仅 schema 可表达范围）")
