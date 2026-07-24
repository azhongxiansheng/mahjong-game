extends GutTest

# E2-02（#232）Red：集中 codec 契约。
# 锁定 class_name ProtocolViewCodec @ res://protocol/protocol_view_codec.gd
# 提供 TileView / MeldView 校验与 compute_view_hash（canonical JSON + SHA-256）。

const CODEC_PATH := "res://protocol/protocol_view_codec.gd"
# preload 锁定生产路径：缺失时失败指向该路径，而非裸 Identifier parse error
const ViewCodecScript := preload("res://protocol/protocol_view_codec.gd")
const MAX_SAFE_INT := 9007199254740991


func _exact_keys(d: Dictionary, expected: Array) -> bool:
	if d.keys().size() != expected.size():
		return false
	for k in expected:
		if not d.has(k):
			return false
	return true


func _as_dict(view: Variant) -> Dictionary:
	if view == null:
		return {}
	if view is Dictionary:
		return (view as Dictionary).duplicate(true)
	if typeof(view) == TYPE_OBJECT and view.has_method("to_dict"):
		return view.to_dict()
	return {}


## Wall canonical：serial=iid%136 → tile=ALL[serial/4]、owner=serial%4、五牌 owner0 为赤
func _canonical_tile_wire_for_iid(iid: int) -> Dictionary:
	var serial: int = iid % Tile.TILES_PER_HAND
	@warning_ignore("integer_division")
	var tile_index: int = serial / 4
	var tile_id: int = TileId.ALL[tile_index]
	var owner_seat: int = serial % 4
	var is_red: bool = (
		(tile_id == TileId.W5 or tile_id == TileId.T5 or tile_id == TileId.S5)
		and owner_seat == 0
	)
	return {
		"instance_id": iid,
		"tile_id": tile_id,
		"is_red_dora": is_red,
		"owner_seat": owner_seat,
	}


## iid = TileId.ALL.find(tile_id)*4 + owner_seat + hand_seq*136
func _canonical_tile_wire(tile_id: int, owner_seat: int, hand_seq: int = 0) -> Dictionary:
	var idx: int = TileId.ALL.find(tile_id)
	var iid: int = idx * 4 + owner_seat + hand_seq * Tile.TILES_PER_HAND
	return _canonical_tile_wire_for_iid(iid)


func _canonical_tile(tile_id: int, owner_seat: int, hand_seq: int = 0) -> Tile:
	var w: Dictionary = _canonical_tile_wire(tile_id, owner_seat, hand_seq)
	return Tile.new(
		int(w["tile_id"]),
		bool(w["is_red_dora"]),
		int(w["owner_seat"]),
		int(w["instance_id"])
	)


## 故意伪造 / 类型负例用；正例请走 _canonical_tile_wire*
func _tile_wire(
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


func _meld_wire(
	kind: String = "PON",
	meld_id: int = 0,
	from_seat: int = 2,
	called: int = 30,
	added: int = -1,
	tiles: Array = []
) -> Dictionary:
	var tile_list: Array = tiles
	if tile_list.is_empty():
		if kind == "CHI":
			# W2/W3/W4 各合法 canonical copy；called 为 W4 且 owner=from_seat
			var t_w2 := _canonical_tile_wire(TileId.W2, 0)
			var t_w3 := _canonical_tile_wire(TileId.W3, 0)
			var t_called := _canonical_tile_wire(TileId.W4, from_seat)
			called = int(t_called["instance_id"])
			tile_list = [t_w2, t_w3, t_called]
		elif kind == "ANKAN":
			called = -1
			from_seat = -1
			# 同牌种四 canonical copy（owner 0..3）
			tile_list = [
				_canonical_tile_wire(TileId.W5, 0),
				_canonical_tile_wire(TileId.W5, 1),
				_canonical_tile_wire(TileId.W5, 2),
				_canonical_tile_wire(TileId.W5, 3),
			]
		elif kind == "ADDED_KAN":
			# 同牌四 copy；called=from 成员、added=另一成员
			var added_owner: int = 3 if from_seat != 3 else 1
			var t_called := _canonical_tile_wire(TileId.HAKU, from_seat)
			var t_added := _canonical_tile_wire(TileId.HAKU, added_owner)
			called = int(t_called["instance_id"])
			added = int(t_added["instance_id"])
			tile_list = []
			for o in range(4):
				if o == from_seat or o == added_owner:
					continue
				tile_list.append(_canonical_tile_wire(TileId.HAKU, o))
			tile_list.append(t_called)
			tile_list.append(t_added)
		elif kind == "MINKAN":
			# 同牌四 copy；called=from 成员
			var t_called := _canonical_tile_wire(TileId.W5, from_seat)
			called = int(t_called["instance_id"])
			tile_list = []
			for o in range(4):
				if o == from_seat:
					continue
				tile_list.append(_canonical_tile_wire(TileId.W5, o))
			tile_list.append(t_called)
		else:
			# PON：同牌三 copy（不含某一 owner）；called=from 成员
			var t_called := _canonical_tile_wire(TileId.HAKU, from_seat)
			called = int(t_called["instance_id"])
			tile_list = []
			var picked := 0
			for o in range(4):
				if o == from_seat:
					continue
				tile_list.append(_canonical_tile_wire(TileId.HAKU, o))
				picked += 1
				if picked == 2:
					break
			tile_list.append(t_called)
	return {
		"meld_id": meld_id,
		"kind": kind,
		"from_seat": from_seat,
		"called_tile_instance_id": called,
		"added_tile_instance_id": added,
		"tiles": tile_list,
	}


func _is_lowercase_hex64(s: String) -> bool:
	if s.length() != 64:
		return false
	if s != s.to_lower():
		return false
	var re := RegEx.new()
	re.compile("^[0-9a-f]{64}$")
	return re.search(s) != null


func test_codec_production_path_and_class_name_locked() -> void:
	assert_eq(CODEC_PATH, "res://protocol/protocol_view_codec.gd")
	assert_true(ResourceLoader.exists(CODEC_PATH), "缺失生产契约: %s" % CODEC_PATH)
	var script: GDScript = ViewCodecScript as GDScript
	assert_not_null(script)
	assert_eq(script.get_global_name(), "ProtocolViewCodec", "class_name 必须锁定")
	var method_names: Array = []
	for method in script.get_script_method_list():
		method_names.append(str(method.get("name", "")))
	for public_method in [
		"tile_view_from_tile", "meld_view_from_meld", "tile_view_from_dict",
		"meld_view_from_dict", "compute_view_hash",
	]:
		assert_has(method_names, public_method, "缺少生产静态 API: %s" % public_method)


# ---- TileView ----

func test_tile_view_exact_four_keys_and_roundtrip() -> void:
	# 赤五仅 owner0 合法
	var wire := _canonical_tile_wire(TileId.W5, 0)
	var tv: Variant = ViewCodecScript.tile_view_from_dict(wire)
	assert_not_null(tv, "合法 TileView 应构造")
	if tv == null:
		return
	var out: Dictionary = _as_dict(tv)
	assert_true(_exact_keys(out, [
		"instance_id", "tile_id", "is_red_dora", "owner_seat",
	]), "TileView exact 四键")
	assert_eq(typeof(out["instance_id"]), TYPE_INT)
	assert_eq(int(out["instance_id"]), int(wire["instance_id"]))
	assert_eq(typeof(out["tile_id"]), TYPE_INT)
	assert_eq(int(out["tile_id"]), TileId.W5)
	assert_true(TileId.ALL.has(int(out["tile_id"])), "tile_id 必须合法牌种")
	assert_eq(typeof(out["is_red_dora"]), TYPE_BOOL)
	assert_eq(bool(out["is_red_dora"]), true)
	assert_eq(typeof(out["owner_seat"]), TYPE_INT)
	assert_eq(int(out["owner_seat"]), 0)


func test_tile_view_is_red_dora_only_for_w5_t5_s5() -> void:
	# 正例：赤宝仅 W5 / T5 / S5 且 owner0
	for tid in [TileId.W5, TileId.T5, TileId.S5]:
		var ok: Variant = ViewCodecScript.tile_view_from_dict(_canonical_tile_wire(tid, 0))
		assert_not_null(ok, "is_red_dora=true 合法 tile_id=%s" % tid)
		if ok != null:
			assert_eq(bool(_as_dict(ok)["is_red_dora"]), true)
			assert_eq(int(_as_dict(ok)["tile_id"]), tid)
			assert_eq(int(_as_dict(ok)["owner_seat"]), 0)

	# 反例：非 5 数牌（故意伪造 is_red）
	for tid in [TileId.W1, TileId.W4, TileId.W6, TileId.T4, TileId.S9]:
		assert_null(
			ViewCodecScript.tile_view_from_dict(_tile_wire(2, tid, true, 0)),
			"is_red_dora=true 非5数牌拒绝 tile_id=%s" % tid
		)
	# 反例：字牌
	for tid in [TileId.E, TileId.HAKU, TileId.CHUN]:
		assert_null(
			ViewCodecScript.tile_view_from_dict(_tile_wire(3, tid, true, 0)),
			"is_red_dora=true 字牌拒绝 tile_id=%s" % tid
		)
	# is_red_dora=false 对任意合法牌种仍可（canonical）
	assert_not_null(
		ViewCodecScript.tile_view_from_dict(_canonical_tile_wire(TileId.W1, 0)),
		"is_red_dora=false 非5合法"
	)
	assert_not_null(
		ViewCodecScript.tile_view_from_dict(_canonical_tile_wire(TileId.HAKU, 0)),
		"is_red_dora=false 字牌合法"
	)


func test_tile_view_rejects_hidden_and_null_input() -> void:
	assert_null(ViewCodecScript.tile_view_from_dict(null), "null 不得构造 TileView")
	assert_null(
		ViewCodecScript.tile_view_from_dict({
			"instance_id": 1,
			"tile_id": TileId.W5,
			"is_red_dora": false,
			"owner_seat": 0,
			"hidden": true,
		}),
		"显式 hidden flag 必须拒绝（无背面 TileView）"
	)
	assert_null(
		ViewCodecScript.tile_view_from_dict({
			"instance_id": 1,
			"tile_id": TileId.W5,
			"is_red_dora": false,
			"owner_seat": 0,
			"is_hidden": true,
		}),
		"is_hidden=true 必须拒绝"
	)


func test_tile_view_rejects_invalid_types_ranges_extra_missing() -> void:
	assert_null(ViewCodecScript.tile_view_from_dict({
		"tile_id": TileId.W5, "is_red_dora": false, "owner_seat": 0,
	}), "缺 instance_id")
	assert_null(ViewCodecScript.tile_view_from_dict({
		"instance_id": 1, "is_red_dora": false, "owner_seat": 0,
	}), "缺 tile_id")
	assert_null(ViewCodecScript.tile_view_from_dict({
		"instance_id": 1, "tile_id": TileId.W5, "owner_seat": 0,
	}), "缺 is_red_dora")
	assert_null(ViewCodecScript.tile_view_from_dict({
		"instance_id": 1, "tile_id": TileId.W5, "is_red_dora": false,
	}), "缺 owner_seat")
	assert_null(ViewCodecScript.tile_view_from_dict({
		"instance_id": 1, "tile_id": TileId.W5, "is_red_dora": false,
		"owner_seat": 0, "extra": 1,
	}), "多余键拒绝")

	assert_null(ViewCodecScript.tile_view_from_dict({
		"instance_id": -1, "tile_id": TileId.W5, "is_red_dora": false, "owner_seat": 0,
	}), "instance_id 负数")
	assert_not_null(
		ViewCodecScript.tile_view_from_dict(_canonical_tile_wire_for_iid(MAX_SAFE_INT)),
		"instance_id=MAX_SAFE 合法"
	)
	assert_null(ViewCodecScript.tile_view_from_dict({
		"instance_id": MAX_SAFE_INT + 1, "tile_id": TileId.W5, "is_red_dora": false, "owner_seat": 0,
	}), "instance_id=MAX_SAFE+1 拒绝")
	assert_null(ViewCodecScript.tile_view_from_dict({
		"instance_id": 1.0, "tile_id": TileId.W5, "is_red_dora": false, "owner_seat": 0,
	}), "instance_id float")
	assert_null(ViewCodecScript.tile_view_from_dict({
		"instance_id": "1", "tile_id": TileId.W5, "is_red_dora": false, "owner_seat": 0,
	}), "instance_id string")
	assert_null(ViewCodecScript.tile_view_from_dict({
		"instance_id": 1, "tile_id": 99, "is_red_dora": false, "owner_seat": 0,
	}), "非法 tile_id 非 TileId 范围")
	assert_null(ViewCodecScript.tile_view_from_dict({
		"instance_id": 1, "tile_id": -1, "is_red_dora": false, "owner_seat": 0,
	}), "tile_id 负数")
	assert_false(TileId.ALL.has(99))
	assert_true(TileId.ALL.has(TileId.CHUN))

	assert_null(ViewCodecScript.tile_view_from_dict({
		"instance_id": 1, "tile_id": TileId.W5, "is_red_dora": 1, "owner_seat": 0,
	}), "is_red_dora 非 bool")
	assert_null(ViewCodecScript.tile_view_from_dict({
		"instance_id": 1, "tile_id": TileId.W5, "is_red_dora": false, "owner_seat": 4,
	}), "owner_seat > 3")
	assert_null(ViewCodecScript.tile_view_from_dict({
		"instance_id": 1, "tile_id": TileId.W5, "is_red_dora": false, "owner_seat": -2,
	}), "owner_seat < -1")
	# canonical public TileView owner 必须 0..3；-1 不再合法
	assert_null(
		ViewCodecScript.tile_view_from_dict(_tile_wire(1, TileId.E, false, -1)),
		"owner_seat=-1 拒绝（canonical owner 必须 0..3）"
	)


func test_tile_view_deep_copy() -> void:
	var wire := _canonical_tile_wire(TileId.S5, 2)
	var expected_iid: int = int(wire["instance_id"])
	var tv: Variant = ViewCodecScript.tile_view_from_dict(wire)
	assert_not_null(tv)
	if tv == null:
		return
	wire["instance_id"] = 999
	var out1: Dictionary = _as_dict(tv)
	assert_eq(int(out1["instance_id"]), expected_iid)
	out1["instance_id"] = 111
	var out2: Dictionary = _as_dict(tv)
	assert_eq(int(out2["instance_id"]), expected_iid, "to_dict / 返回值 deep copy")


# ---- MeldView ----

func test_meld_view_exact_six_keys() -> void:
	for kind in ["CHI", "PON", "MINKAN", "ANKAN", "ADDED_KAN"]:
		var wire := _meld_wire(kind)
		var mv: Variant = ViewCodecScript.meld_view_from_dict(wire)
		assert_not_null(mv, "合法 MeldView kind=%s" % kind)
		if mv == null:
			continue
		var out: Dictionary = _as_dict(mv)
		assert_true(_exact_keys(out, [
			"meld_id", "kind", "from_seat", "called_tile_instance_id",
			"added_tile_instance_id", "tiles",
		]), "MeldView exact 六键 kind=%s" % kind)
		assert_eq(typeof(out["meld_id"]), TYPE_INT)
		assert_eq(typeof(out["kind"]), TYPE_STRING)
		assert_eq(str(out["kind"]), kind)
		assert_eq(typeof(out["tiles"]), TYPE_ARRAY)
		var tiles: Array = out["tiles"] as Array
		if kind in ["CHI", "PON"]:
			assert_eq(tiles.size(), 3, "%s 必须 3 张" % kind)
		else:
			assert_eq(tiles.size(), 4, "%s 必须 4 张" % kind)


func test_meld_view_full_cross_validation_by_kind() -> void:
	# ---- CHI：3 张、同花色连续；from 0..3、called 成员、added=-1 ----
	var chi_ok: Variant = ViewCodecScript.meld_view_from_dict(_meld_wire("CHI"))
	assert_not_null(chi_ok, "CHI 合法")
	if chi_ok != null:
		var chi_out: Dictionary = _as_dict(chi_ok)
		assert_eq(int(chi_out["added_tile_instance_id"]), -1)
		assert_true(int(chi_out["from_seat"]) >= 0 and int(chi_out["from_seat"]) <= 3)
		assert_true(int(chi_out["called_tile_instance_id"]) >= 0)

	assert_null(ViewCodecScript.meld_view_from_dict({
		"meld_id": 0, "kind": "CHI", "from_seat": 2,
		"called_tile_instance_id": 12, "added_tile_instance_id": -1,
		"tiles": [
			_tile_wire(10, TileId.W2, false, 0),
			_tile_wire(11, TileId.W3, false, 0),
			_tile_wire(12, TileId.W4, false, 2),
			_tile_wire(13, TileId.W5, false, 0),
		],
	}), "CHI 不得 4 张")
	assert_null(ViewCodecScript.meld_view_from_dict({
		"meld_id": 0, "kind": "CHI", "from_seat": 2,
		"called_tile_instance_id": 12, "added_tile_instance_id": -1,
		"tiles": [
			_tile_wire(10, TileId.W2, false, 0),
			_tile_wire(11, TileId.W3, false, 0),
			_tile_wire(12, TileId.T4, false, 2), # 跨花色
		],
	}), "CHI 必须同花色")
	assert_null(ViewCodecScript.meld_view_from_dict({
		"meld_id": 0, "kind": "CHI", "from_seat": 2,
		"called_tile_instance_id": 12, "added_tile_instance_id": -1,
		"tiles": [
			_tile_wire(10, TileId.W2, false, 0),
			_tile_wire(11, TileId.W3, false, 0),
			_tile_wire(12, TileId.W5, false, 2), # 不连续
		],
	}), "CHI 必须连续")
	assert_null(ViewCodecScript.meld_view_from_dict({
		"meld_id": 0, "kind": "CHI", "from_seat": 4,
		"called_tile_instance_id": 12, "added_tile_instance_id": -1,
		"tiles": [
			_tile_wire(10, TileId.W2, false, 0),
			_tile_wire(11, TileId.W3, false, 0),
			_tile_wire(12, TileId.W4, false, 2),
		],
	}), "CHI from_seat 必须 0..3")
	assert_null(ViewCodecScript.meld_view_from_dict({
		"meld_id": 0, "kind": "CHI", "from_seat": 2,
		"called_tile_instance_id": 999, "added_tile_instance_id": -1,
		"tiles": [
			_tile_wire(10, TileId.W2, false, 0),
			_tile_wire(11, TileId.W3, false, 0),
			_tile_wire(12, TileId.W4, false, 2),
		],
	}), "CHI called 必须是 tiles 成员")
	assert_null(ViewCodecScript.meld_view_from_dict({
		"meld_id": 0, "kind": "CHI", "from_seat": 2,
		"called_tile_instance_id": 12, "added_tile_instance_id": 40,
		"tiles": [
			_tile_wire(10, TileId.W2, false, 0),
			_tile_wire(11, TileId.W3, false, 0),
			_tile_wire(12, TileId.W4, false, 2),
		],
	}), "CHI added 必须 -1")

	# ---- PON：3 张 tile_id 全同 ----
	assert_not_null(ViewCodecScript.meld_view_from_dict(_meld_wire("PON")), "PON 合法")
	assert_null(ViewCodecScript.meld_view_from_dict({
		"meld_id": 0, "kind": "PON", "from_seat": 2,
		"called_tile_instance_id": 3, "added_tile_instance_id": -1,
		"tiles": [
			_tile_wire(1, TileId.HAKU, false, 0),
			_tile_wire(2, TileId.HAKU, false, 0),
			_tile_wire(3, TileId.HAKU, false, 2),
			_tile_wire(4, TileId.HAKU, false, 0),
		],
	}), "PON 不得 4 张")
	assert_null(ViewCodecScript.meld_view_from_dict({
		"meld_id": 0, "kind": "PON", "from_seat": 2,
		"called_tile_instance_id": 3, "added_tile_instance_id": -1,
		"tiles": [
			_tile_wire(1, TileId.HAKU, false, 0),
			_tile_wire(2, TileId.HATSU, false, 0),
			_tile_wire(3, TileId.HAKU, false, 2),
		],
	}), "PON tile_id 必须全同")
	assert_null(ViewCodecScript.meld_view_from_dict({
		"meld_id": 0, "kind": "PON", "from_seat": -1,
		"called_tile_instance_id": 3, "added_tile_instance_id": -1,
		"tiles": [
			_tile_wire(1, TileId.HAKU, false, 0),
			_tile_wire(2, TileId.HAKU, false, 0),
			_tile_wire(3, TileId.HAKU, false, 2),
		],
	}), "PON from_seat 必须 0..3")
	assert_null(ViewCodecScript.meld_view_from_dict({
		"meld_id": 0, "kind": "PON", "from_seat": 2,
		"called_tile_instance_id": 999, "added_tile_instance_id": -1,
		"tiles": [
			_tile_wire(1, TileId.HAKU, false, 0),
			_tile_wire(2, TileId.HAKU, false, 0),
			_tile_wire(3, TileId.HAKU, false, 2),
		],
	}), "PON called 必须是 tiles 成员")
	assert_null(ViewCodecScript.meld_view_from_dict({
		"meld_id": 0, "kind": "PON", "from_seat": 2,
		"called_tile_instance_id": 3, "added_tile_instance_id": 9,
		"tiles": [
			_tile_wire(1, TileId.HAKU, false, 0),
			_tile_wire(2, TileId.HAKU, false, 0),
			_tile_wire(3, TileId.HAKU, false, 2),
		],
	}), "PON added 必须 -1")

	# ---- MINKAN：4 张 tile_id 全同；from 0..3、called 成员、added=-1 ----
	assert_not_null(ViewCodecScript.meld_view_from_dict(_meld_wire("MINKAN")), "MINKAN 合法")
	assert_null(ViewCodecScript.meld_view_from_dict({
		"meld_id": 0, "kind": "MINKAN", "from_seat": 2,
		"called_tile_instance_id": 53, "added_tile_instance_id": -1,
		"tiles": [
			_tile_wire(50, TileId.W5, false, 0),
			_tile_wire(51, TileId.W5, false, 0),
			_tile_wire(52, TileId.W5, false, 0),
		],
	}), "MINKAN 必须 4 张")
	assert_null(ViewCodecScript.meld_view_from_dict({
		"meld_id": 0, "kind": "MINKAN", "from_seat": 2,
		"called_tile_instance_id": 53, "added_tile_instance_id": -1,
		"tiles": [
			_tile_wire(50, TileId.W5, false, 0),
			_tile_wire(51, TileId.W5, false, 0),
			_tile_wire(52, TileId.W6, false, 0),
			_tile_wire(53, TileId.W5, false, 2),
		],
	}), "MINKAN tile_id 必须全同")
	assert_null(ViewCodecScript.meld_view_from_dict({
		"meld_id": 0, "kind": "MINKAN", "from_seat": 2,
		"called_tile_instance_id": 53, "added_tile_instance_id": 50,
		"tiles": [
			_tile_wire(50, TileId.W5, false, 0),
			_tile_wire(51, TileId.W5, false, 0),
			_tile_wire(52, TileId.W5, false, 0),
			_tile_wire(53, TileId.W5, false, 2),
		],
	}), "MINKAN added 必须 -1")

	# ---- ANKAN：4 张全同；from/called/added 全 -1 ----
	assert_not_null(ViewCodecScript.meld_view_from_dict(_meld_wire("ANKAN")), "ANKAN 合法")
	var ankan_out: Dictionary = _as_dict(ViewCodecScript.meld_view_from_dict(_meld_wire("ANKAN")))
	if not ankan_out.is_empty():
		assert_eq(int(ankan_out["from_seat"]), -1)
		assert_eq(int(ankan_out["called_tile_instance_id"]), -1)
		assert_eq(int(ankan_out["added_tile_instance_id"]), -1)
	assert_null(ViewCodecScript.meld_view_from_dict({
		"meld_id": 0, "kind": "ANKAN", "from_seat": 0,
		"called_tile_instance_id": -1, "added_tile_instance_id": -1,
		"tiles": [
			_tile_wire(20, TileId.W5, false, 0),
			_tile_wire(21, TileId.W5, false, 0),
			_tile_wire(22, TileId.W5, false, 0),
			_tile_wire(23, TileId.W5, false, 0),
		],
	}), "ANKAN from 必须 -1")
	assert_null(ViewCodecScript.meld_view_from_dict({
		"meld_id": 0, "kind": "ANKAN", "from_seat": -1,
		"called_tile_instance_id": 20, "added_tile_instance_id": -1,
		"tiles": [
			_tile_wire(20, TileId.W5, false, 0),
			_tile_wire(21, TileId.W5, false, 0),
			_tile_wire(22, TileId.W5, false, 0),
			_tile_wire(23, TileId.W5, false, 0),
		],
	}), "ANKAN called 必须 -1")
	assert_null(ViewCodecScript.meld_view_from_dict({
		"meld_id": 0, "kind": "ANKAN", "from_seat": -1,
		"called_tile_instance_id": -1, "added_tile_instance_id": 23,
		"tiles": [
			_tile_wire(20, TileId.W5, false, 0),
			_tile_wire(21, TileId.W5, false, 0),
			_tile_wire(22, TileId.W5, false, 0),
			_tile_wire(23, TileId.W5, false, 0),
		],
	}), "ANKAN added 必须 -1")
	assert_null(ViewCodecScript.meld_view_from_dict({
		"meld_id": 0, "kind": "ANKAN", "from_seat": -1,
		"called_tile_instance_id": -1, "added_tile_instance_id": -1,
		"tiles": [
			_tile_wire(20, TileId.W5, false, 0),
			_tile_wire(21, TileId.W5, false, 0),
			_tile_wire(22, TileId.W6, false, 0),
			_tile_wire(23, TileId.W5, false, 0),
		],
	}), "ANKAN tile_id 必须全同")

	# ---- ADDED_KAN：4 张全同；from 0..3；called 与 added 均为不同成员 ----
	assert_not_null(ViewCodecScript.meld_view_from_dict(_meld_wire("ADDED_KAN")), "ADDED_KAN 合法")
	assert_null(ViewCodecScript.meld_view_from_dict({
		"meld_id": 0, "kind": "ADDED_KAN", "from_seat": 2,
		"called_tile_instance_id": 30, "added_tile_instance_id": -1,
		"tiles": [
			_tile_wire(30, TileId.HAKU, false, 2),
			_tile_wire(31, TileId.HAKU, false, 0),
			_tile_wire(32, TileId.HAKU, false, 0),
			_tile_wire(40, TileId.HAKU, false, 0),
		],
	}), "ADDED_KAN 必须 added>=0")
	assert_null(ViewCodecScript.meld_view_from_dict({
		"meld_id": 0, "kind": "ADDED_KAN", "from_seat": 2,
		"called_tile_instance_id": 30, "added_tile_instance_id": 999,
		"tiles": [
			_tile_wire(30, TileId.HAKU, false, 2),
			_tile_wire(31, TileId.HAKU, false, 0),
			_tile_wire(32, TileId.HAKU, false, 0),
			_tile_wire(40, TileId.HAKU, false, 0),
		],
	}), "ADDED_KAN added 必须在 tiles")
	assert_null(ViewCodecScript.meld_view_from_dict({
		"meld_id": 0, "kind": "ADDED_KAN", "from_seat": 2,
		"called_tile_instance_id": 30, "added_tile_instance_id": 30,
		"tiles": [
			_tile_wire(30, TileId.HAKU, false, 2),
			_tile_wire(31, TileId.HAKU, false, 0),
			_tile_wire(32, TileId.HAKU, false, 0),
			_tile_wire(40, TileId.HAKU, false, 0),
		],
	}), "ADDED_KAN called 与 added 必须不同成员")
	assert_null(ViewCodecScript.meld_view_from_dict({
		"meld_id": 0, "kind": "ADDED_KAN", "from_seat": -1,
		"called_tile_instance_id": 30, "added_tile_instance_id": 40,
		"tiles": [
			_tile_wire(30, TileId.HAKU, false, 2),
			_tile_wire(31, TileId.HAKU, false, 0),
			_tile_wire(32, TileId.HAKU, false, 0),
			_tile_wire(40, TileId.HAKU, false, 0),
		],
	}), "ADDED_KAN from_seat 必须 0..3")
	assert_null(ViewCodecScript.meld_view_from_dict({
		"meld_id": 0, "kind": "ADDED_KAN", "from_seat": 2,
		"called_tile_instance_id": 30, "added_tile_instance_id": 40,
		"tiles": [
			_tile_wire(30, TileId.HAKU, false, 2),
			_tile_wire(31, TileId.HAKU, false, 0),
			_tile_wire(32, TileId.HATSU, false, 0),
			_tile_wire(40, TileId.HAKU, false, 0),
		],
	}), "ADDED_KAN tile_id 必须全同（保留原 meld）")


func test_meld_view_tiles_preserve_input_order() -> void:
	# 合法 PON 同牌三副本乱序 owner3/1/2 → 输出原样保留（禁止按 iid 升序）
	var t3 := _canonical_tile_wire(TileId.HAKU, 3)
	var t1 := _canonical_tile_wire(TileId.HAKU, 1)
	var t2 := _canonical_tile_wire(TileId.HAKU, 2) # called
	var iid3: int = int(t3["instance_id"])
	var iid1: int = int(t1["instance_id"])
	var iid2: int = int(t2["instance_id"])
	var wire := {
		"meld_id": 1,
		"kind": "PON",
		"from_seat": 2,
		"called_tile_instance_id": iid2,
		"added_tile_instance_id": -1,
		"tiles": [t3, t1, t2],
	}
	var mv: Variant = ViewCodecScript.meld_view_from_dict(wire)
	assert_not_null(mv, "非升序 iid 的合法 PON 应可解析")
	if mv == null:
		return
	var out: Dictionary = _as_dict(mv)
	assert_eq(int(out["called_tile_instance_id"]), iid2)
	assert_eq(int(out["added_tile_instance_id"]), -1)
	var tiles: Array = out["tiles"] as Array
	assert_eq(tiles.size(), 3)
	assert_eq(int((tiles[0] as Dictionary)["instance_id"]), iid3)
	assert_eq(int((tiles[0] as Dictionary)["tile_id"]), TileId.HAKU)
	assert_eq(int((tiles[0] as Dictionary)["owner_seat"]), 3)
	assert_eq(int((tiles[1] as Dictionary)["instance_id"]), iid1)
	assert_eq(int((tiles[1] as Dictionary)["tile_id"]), TileId.HAKU)
	assert_eq(int((tiles[1] as Dictionary)["owner_seat"]), 1)
	assert_eq(int((tiles[2] as Dictionary)["instance_id"]), iid2)
	assert_eq(int((tiles[2] as Dictionary)["tile_id"]), TileId.HAKU)
	assert_eq(int((tiles[2] as Dictionary)["owner_seat"]), 2)
	# instance_id unique 且输入非升序
	assert_true(iid3 > iid1 or iid1 > iid2 or iid3 > iid2)
	assert_ne(iid3, iid1)
	assert_ne(iid1, iid2)
	assert_ne(iid3, iid2)


func test_chi_rejects_non_domain_tile_order_even_when_values_form_a_sequence() -> void:
	for tile_ids in [
		[TileId.W4, TileId.W2, TileId.W3],
		[TileId.W3, TileId.W2, TileId.W4],
	]:
		var wire := _meld_wire("CHI", 1, 2, 30, -1, [
			_tile_wire(30, tile_ids[0], false, 2),
			_tile_wire(31, tile_ids[1], false, 0),
			_tile_wire(32, tile_ids[2], false, 0),
		])
		assert_null(
			ViewCodecScript.meld_view_from_dict(wire),
			"CHI 只接受花色内连续升序，输入=%s" % str(tile_ids)
		)


func test_meld_view_rejects_duplicate_tile_instance_ids_and_bad_kind() -> void:
	assert_null(ViewCodecScript.meld_view_from_dict({
		"meld_id": 0,
		"kind": "PON",
		"from_seat": 1,
		"called_tile_instance_id": 1,
		"added_tile_instance_id": -1,
		"tiles": [
			_tile_wire(1, TileId.HAKU, false, 1),
			_tile_wire(1, TileId.HAKU, false, 0),
			_tile_wire(2, TileId.HAKU, false, 0),
		],
	}), "tiles instance_id 必须唯一")

	assert_null(ViewCodecScript.meld_view_from_dict({
		"meld_id": 0,
		"kind": "KAKAN",
		"from_seat": 1,
		"called_tile_instance_id": 1,
		"added_tile_instance_id": -1,
		"tiles": [
			_tile_wire(1, TileId.HAKU, false, 1),
			_tile_wire(2, TileId.HAKU, false, 0),
			_tile_wire(3, TileId.HAKU, false, 0),
		],
	}), "牌组 kind 仅 CHI/PON/MINKAN/ANKAN/ADDED_KAN")

	assert_null(ViewCodecScript.meld_view_from_dict({
		"meld_id": 0,
		"kind": "PON",
		"from_seat": 1,
		"called_tile_instance_id": 1,
		"added_tile_instance_id": -1,
		"tiles": [],
	}), "tiles 不得为空")

	assert_null(ViewCodecScript.meld_view_from_dict({
		"meld_id": -1,
		"kind": "PON",
		"from_seat": 1,
		"called_tile_instance_id": 1,
		"added_tile_instance_id": -1,
		"tiles": [
			_tile_wire(1, TileId.HAKU, false, 1),
			_tile_wire(2, TileId.HAKU, false, 0),
			_tile_wire(3, TileId.HAKU, false, 0),
		],
	}), "meld_id 负数拒绝")
	assert_not_null(
		ViewCodecScript.meld_view_from_dict(_meld_wire("PON", MAX_SAFE_INT, 1)),
		"meld_id=MAX_SAFE 合法"
	)
	assert_null(ViewCodecScript.meld_view_from_dict({
		"meld_id": MAX_SAFE_INT + 1,
		"kind": "PON",
		"from_seat": 1,
		"called_tile_instance_id": 1,
		"added_tile_instance_id": -1,
		"tiles": [
			_tile_wire(1, TileId.HAKU, false, 1),
			_tile_wire(2, TileId.HAKU, false, 0),
			_tile_wire(3, TileId.HAKU, false, 0),
		],
	}), "meld_id=MAX_SAFE+1 拒绝")

	var extra := _meld_wire("PON")
	extra["extra"] = true
	assert_null(ViewCodecScript.meld_view_from_dict(extra), "MeldView 多余键拒绝")

	var missing := _meld_wire("PON")
	missing.erase("meld_id")
	assert_null(ViewCodecScript.meld_view_from_dict(missing), "缺 meld_id 拒绝")


func test_meld_view_deep_copy() -> void:
	var wire := _meld_wire("PON")
	var mv: Variant = ViewCodecScript.meld_view_from_dict(wire)
	assert_not_null(mv)
	if mv == null:
		return
	(wire["tiles"] as Array)[0]["instance_id"] = 999
	var out: Dictionary = _as_dict(mv)
	var tiles: Array = out["tiles"]
	assert_ne(int((tiles[0] as Dictionary).get("instance_id", -1)), 999,
		"from_dict 后改输入 tiles 不得污染")
	if tiles[0] is Dictionary:
		(tiles[0] as Dictionary)["instance_id"] = 888
	var out2: Dictionary = _as_dict(mv)
	assert_ne(int((out2["tiles"][0] as Dictionary).get("instance_id", -1)), 888,
		"to_dict deep copy")


# ---- compute_view_hash ----

func test_compute_view_hash_canonical_order_independent_dict_keys() -> void:
	var v1 := {"b": 1, "a": {"y": 2, "x": 3}, "c": true}
	var v2 := {"c": true, "a": {"x": 3, "y": 2}, "b": 1}
	var h1: String = str(ViewCodecScript.compute_view_hash(v1))
	var h2: String = str(ViewCodecScript.compute_view_hash(v2))
	assert_eq(h1, h2, "同语义不同 Dictionary 插入顺序必须同 hash")
	assert_true(_is_lowercase_hex64(h1), "view_hash 必须 64 位小写 hex")
	assert_eq(h1.length(), 64)


func test_compute_view_hash_preserves_array_order() -> void:
	var a := {"items": [1, 2, 3]}
	var b := {"items": [3, 2, 1]}
	var ha: String = str(ViewCodecScript.compute_view_hash(a))
	var hb: String = str(ViewCodecScript.compute_view_hash(b))
	assert_ne(ha, hb, "数组顺序必须影响 hash")
	assert_true(_is_lowercase_hex64(ha))
	assert_true(_is_lowercase_hex64(hb))


func test_compute_view_hash_stable_for_public_view_shape() -> void:
	var public_view := {
		"hand_seq": 3,
		"seats": [
			{"seat": 0, "tile": _tile_wire(1, TileId.W1, false, 0)},
			{"seat": 1, "tile": _tile_wire(2, TileId.W2, false, 1)},
		],
	}
	var h: String = str(ViewCodecScript.compute_view_hash(public_view))
	assert_true(_is_lowercase_hex64(h))
	# 再次计算相同
	assert_eq(str(ViewCodecScript.compute_view_hash(public_view.duplicate(true))), h)


# ---- P2：领域工厂 tile_view_from_tile / meld_view_from_meld ----

func _codec_has_method(method_name: String) -> bool:
	var script: GDScript = ViewCodecScript as GDScript
	if script == null:
		return false
	for m in script.get_script_method_list():
		if str(m.get("name", "")) == method_name:
			return true
	return false


func _codec_call(method_name: String, arg: Variant) -> Variant:
	var script: GDScript = ViewCodecScript as GDScript
	return script.call(method_name, arg)


func test_domain_factory_api_names_locked() -> void:
	assert_true(
		_codec_has_method("tile_view_from_tile"),
		"锁 API 名：tile_view_from_tile(tile: Tile)->Variant"
	)
	assert_true(
		_codec_has_method("meld_view_from_meld"),
		"锁 API 名：meld_view_from_meld(meld: Meld)->Variant"
	)


func test_tile_view_from_tile_valid_red_owner_and_canonical() -> void:
	assert_true(_codec_has_method("tile_view_from_tile"), "缺少 tile_view_from_tile")
	if not _codec_has_method("tile_view_from_tile"):
		return
	# 赤五必须 owner0
	var tile: Tile = _canonical_tile(TileId.W5, 0)
	var tv: Variant = _codec_call("tile_view_from_tile", tile)
	assert_not_null(tv, "合法 Tile 应产出 TileView")
	if tv == null:
		return
	# 同一 exact 四键 canonical validator
	var revalidated: Variant = ViewCodecScript.tile_view_from_dict(tv)
	assert_not_null(revalidated, "输出必须通过 tile_view_from_dict exact 四键校验")
	var out: Dictionary = _as_dict(revalidated)
	assert_true(_exact_keys(out, [
		"instance_id", "tile_id", "is_red_dora", "owner_seat",
	]))
	assert_eq(int(out["instance_id"]), tile.instance_id)
	assert_eq(int(out["tile_id"]), TileId.W5)
	assert_eq(bool(out["is_red_dora"]), true)
	assert_eq(int(out["owner_seat"]), 0)


func test_tile_view_from_tile_rejects_invalid_null_wrong_object() -> void:
	assert_true(_codec_has_method("tile_view_from_tile"), "缺少 tile_view_from_tile")
	if not _codec_has_method("tile_view_from_tile"):
		return
	assert_null(_codec_call("tile_view_from_tile", null), "null → null")
	assert_null(
		_codec_call("tile_view_from_tile", Tile.new(TileId.W1, false, 0, Tile.INVALID_INSTANCE_ID)),
		"INVALID instance_id → null"
	)
	assert_null(
		_codec_call("tile_view_from_tile", RefCounted.new()),
		"wrong Object → null"
	)
	# 非 Tile 领域对象
	var called := Tile.new(TileId.HAKU, false, 1, 10)
	var a := Tile.new(TileId.HAKU, false, 0, 11)
	var b := Tile.new(TileId.HAKU, false, 0, 12)
	var meld := Meld.make_pon([a, called, b], 1, 5, called)
	assert_null(_codec_call("tile_view_from_tile", meld), "Meld 不得当作 Tile")


func test_tile_view_from_tile_domain_mutation_does_not_pollute() -> void:
	assert_true(_codec_has_method("tile_view_from_tile"), "缺少 tile_view_from_tile")
	if not _codec_has_method("tile_view_from_tile"):
		return
	var tile: Tile = _canonical_tile(TileId.S5, 1)
	var expected_iid: int = tile.instance_id
	var tv: Variant = _codec_call("tile_view_from_tile", tile)
	assert_not_null(tv)
	if tv == null:
		return
	tile.owner_seat = 3
	tile.is_red_dora = true
	tile.id = TileId.W1
	var out: Dictionary = _as_dict(tv)
	assert_eq(int(out["owner_seat"]), 1, "改 domain owner 不得污染已返回 DTO")
	assert_eq(bool(out["is_red_dora"]), false, "改 domain red 不得污染")
	assert_eq(int(out["tile_id"]), TileId.S5, "改 domain id 不得污染")
	assert_eq(int(out["instance_id"]), expected_iid)


func test_meld_view_from_meld_pon_preserves_domain_tile_order() -> void:
	assert_true(_codec_has_method("meld_view_from_meld"), "缺少 meld_view_from_meld")
	if not _codec_has_method("meld_view_from_meld"):
		return
	# 领域 m.tiles 顺序 [owner3, owner2(called), owner1] 必须原样保留（禁止按 iid 升序）
	var called: Tile = _canonical_tile(TileId.HAKU, 2)
	var a: Tile = _canonical_tile(TileId.HAKU, 3)
	var b: Tile = _canonical_tile(TileId.HAKU, 1)
	var m := Meld.make_pon([a, called, b], 2, 7, called)
	var mv: Variant = _codec_call("meld_view_from_meld", m)
	assert_not_null(mv, "合法 PON 应产出 MeldView")
	if mv == null:
		return
	var revalidated: Variant = ViewCodecScript.meld_view_from_dict(mv)
	assert_not_null(revalidated, "输出必须通过 meld_view_from_dict exact 六键校验")
	var out: Dictionary = _as_dict(revalidated)
	assert_true(_exact_keys(out, [
		"meld_id", "kind", "from_seat", "called_tile_instance_id",
		"added_tile_instance_id", "tiles",
	]))
	assert_eq(int(out["meld_id"]), 7)
	assert_eq(str(out["kind"]), "PON")
	assert_eq(int(out["from_seat"]), 2)
	assert_eq(int(out["called_tile_instance_id"]), called.instance_id)
	assert_eq(int(out["added_tile_instance_id"]), -1)
	var tiles: Array = out["tiles"] as Array
	assert_eq(tiles.size(), 3)
	assert_eq(int((tiles[0] as Dictionary)["instance_id"]), a.instance_id)
	assert_eq(int((tiles[1] as Dictionary)["instance_id"]), called.instance_id)
	assert_eq(int((tiles[2] as Dictionary)["instance_id"]), b.instance_id)


func test_meld_view_from_meld_added_kan_from_pon_promote() -> void:
	assert_true(_codec_has_method("meld_view_from_meld"), "缺少 meld_view_from_meld")
	if not _codec_has_method("meld_view_from_meld"):
		return
	# 赤五必须 owner0；PON/杠用同牌不同 owner；from=0 使 called 可为赤
	var called: Tile = _canonical_tile(TileId.W5, 0)
	var a: Tile = _canonical_tile(TileId.W5, 1)
	var b: Tile = _canonical_tile(TileId.W5, 2)
	var m := Meld.make_pon([a, called, b], 0, 9, called)
	var fourth: Tile = _canonical_tile(TileId.W5, 3)
	assert_true(m.promote_to_added_kan(fourth), "PON→ADDED_KAN promote 必须成功")
	assert_eq(m.kind, Meld.Kind.ADDED_KAN)
	assert_eq(m.meld_id, 9)
	assert_eq(m.called_tile_instance_id, called.instance_id)
	assert_eq(m.added_tile_instance_id, fourth.instance_id)

	var mv: Variant = _codec_call("meld_view_from_meld", m)
	assert_not_null(mv, "ADDED_KAN domain 应产出 MeldView")
	if mv == null:
		return
	var revalidated: Variant = ViewCodecScript.meld_view_from_dict(mv)
	assert_not_null(revalidated, "ADDED_KAN 输出必须过 exact 六键校验")
	var out: Dictionary = _as_dict(revalidated)
	assert_eq(int(out["meld_id"]), 9, "promote 后保留 meld_id")
	assert_eq(str(out["kind"]), "ADDED_KAN")
	assert_eq(int(out["from_seat"]), 0)
	assert_eq(int(out["called_tile_instance_id"]), called.instance_id, "保留 called")
	assert_eq(int(out["added_tile_instance_id"]), fourth.instance_id, "写入 added")
	var tiles: Array = out["tiles"] as Array
	assert_eq(tiles.size(), 4)
	# 赤五 called 保留
	var saw_red := false
	for t in tiles:
		var td: Dictionary = t
		if int(td["instance_id"]) == called.instance_id:
			assert_eq(bool(td["is_red_dora"]), true)
			assert_eq(int(td["tile_id"]), TileId.W5)
			assert_eq(int(td["owner_seat"]), 0)
			saw_red = true
	assert_true(saw_red, "赤五 called tile 必须出现在 tiles")
	# 领域顺序：make_pon([a,called,b]) + promote(fourth)
	assert_eq(int((tiles[0] as Dictionary)["instance_id"]), a.instance_id)
	assert_eq(int((tiles[1] as Dictionary)["instance_id"]), called.instance_id)
	assert_eq(int((tiles[2] as Dictionary)["instance_id"]), b.instance_id)
	assert_eq(int((tiles[3] as Dictionary)["instance_id"]), fourth.instance_id)


func test_meld_view_from_meld_rejects_invalid_null_wrong_object() -> void:
	assert_true(_codec_has_method("meld_view_from_meld"), "缺少 meld_view_from_meld")
	if not _codec_has_method("meld_view_from_meld"):
		return
	assert_null(_codec_call("meld_view_from_meld", null), "null → null")
	assert_null(_codec_call("meld_view_from_meld", RefCounted.new()), "wrong Object → null")
	assert_null(
		_codec_call("meld_view_from_meld", Tile.new(TileId.W1, false, 0, 1)),
		"Tile 不得当作 Meld"
	)
	# INVALID meld_id
	var called := Tile.new(TileId.HAKU, false, 2, 20)
	var a := Tile.new(TileId.HAKU, false, 0, 21)
	var b := Tile.new(TileId.HAKU, false, 0, 22)
	var bad_id := Meld.make_pon([a, called, b], 2, Tile.INVALID_INSTANCE_ID, called)
	assert_null(_codec_call("meld_view_from_meld", bad_id), "INVALID meld_id → null")
	# tiles 内 INVALID instance_id
	var bad_tile := Tile.new(TileId.HAKU, false, 0, Tile.INVALID_INSTANCE_ID)
	var ok_called := Tile.new(TileId.HAKU, false, 1, 30)
	var ok_b := Tile.new(TileId.HAKU, false, 0, 31)
	var bad_tiles := Meld.make_pon([bad_tile, ok_called, ok_b], 1, 4, ok_called)
	assert_null(
		_codec_call("meld_view_from_meld", bad_tiles),
		"tiles 含 INVALID instance_id → null"
	)


func test_meld_view_from_meld_domain_mutation_does_not_pollute() -> void:
	assert_true(_codec_has_method("meld_view_from_meld"), "缺少 meld_view_from_meld")
	if not _codec_has_method("meld_view_from_meld"):
		return
	var called: Tile = _canonical_tile(TileId.HAKU, 2)
	var a: Tile = _canonical_tile(TileId.HAKU, 0)
	var b: Tile = _canonical_tile(TileId.HAKU, 1)
	var m := Meld.make_pon([a, called, b], 2, 6, called)
	var mv: Variant = _codec_call("meld_view_from_meld", m)
	assert_not_null(mv)
	if mv == null:
		return
	var snap: Dictionary = _as_dict(mv).duplicate(true)
	# 后续可变 domain 数组/字段
	m.tiles.append(_canonical_tile(TileId.HAKU, 3))
	m.from_seat = 0
	m.kind = Meld.Kind.CHI
	var out: Dictionary = _as_dict(mv)
	assert_eq(str(out["kind"]), "PON", "改 domain kind 不得污染")
	assert_eq(int(out["from_seat"]), 2, "改 domain from_seat 不得污染")
	assert_eq((out["tiles"] as Array).size(), 3, "改 domain tiles 不得污染")
	assert_eq(int(out["meld_id"]), int(snap["meld_id"]))
	assert_eq(int(out["called_tile_instance_id"]), called.instance_id)


# ---- P2：compute_view_hash 严格 domain ----

func test_compute_view_hash_domain_rejects_float_oob_int_nonstring_key_object() -> void:
	# float（含 1.0 / 0.0）→ 空串
	assert_eq(str(ViewCodecScript.compute_view_hash(1.0)), "", "float 1.0 → \"\"")
	assert_eq(str(ViewCodecScript.compute_view_hash(0.0)), "", "float 0.0 → \"\"")
	assert_eq(str(ViewCodecScript.compute_view_hash(-1.5)), "", "float 负 → \"\"")
	assert_eq(
		str(ViewCodecScript.compute_view_hash({"a": 1.0})), "",
		"dict 内 float → \"\""
	)
	assert_eq(
		str(ViewCodecScript.compute_view_hash([1.0])), "",
		"array 内 float → \"\""
	)

	# 越界 int
	assert_eq(
		str(ViewCodecScript.compute_view_hash(MAX_SAFE_INT + 1)), "",
		"int > MAX_SAFE → \"\""
	)
	assert_eq(
		str(ViewCodecScript.compute_view_hash(-(MAX_SAFE_INT + 1))), "",
		"int < -MAX_SAFE → \"\""
	)
	assert_eq(
		str(ViewCodecScript.compute_view_hash({"n": MAX_SAFE_INT + 1})), "",
		"dict 内越界 int → \"\""
	)

	# 非 String 字典键
	assert_eq(str(ViewCodecScript.compute_view_hash({1: "a"})), "", "int key → \"\"")
	assert_eq(str(ViewCodecScript.compute_view_hash({true: 1})), "", "bool key → \"\"")

	# Object
	assert_eq(
		str(ViewCodecScript.compute_view_hash(RefCounted.new())), "",
		"Object → \"\""
	)
	assert_eq(
		str(ViewCodecScript.compute_view_hash({"o": RefCounted.new()})), "",
		"dict 内 Object → \"\""
	)


func test_compute_view_hash_safe_int_boundaries_and_allowed_scalars() -> void:
	# safe 负/正边界可 hash 且 64 小写 hex
	var h_max: String = str(ViewCodecScript.compute_view_hash(MAX_SAFE_INT))
	var h_min: String = str(ViewCodecScript.compute_view_hash(-MAX_SAFE_INT))
	assert_true(_is_lowercase_hex64(h_max), "MAX_SAFE 可 hash")
	assert_true(_is_lowercase_hex64(h_min), "-MAX_SAFE 可 hash")
	assert_ne(h_max, h_min)

	assert_true(_is_lowercase_hex64(str(ViewCodecScript.compute_view_hash(null))))
	assert_true(_is_lowercase_hex64(str(ViewCodecScript.compute_view_hash(true))))
	assert_true(_is_lowercase_hex64(str(ViewCodecScript.compute_view_hash(false))))
	assert_true(_is_lowercase_hex64(str(ViewCodecScript.compute_view_hash(0))))
	assert_true(_is_lowercase_hex64(str(ViewCodecScript.compute_view_hash("x"))))
	assert_true(_is_lowercase_hex64(str(ViewCodecScript.compute_view_hash([1, 2]))))
	assert_true(_is_lowercase_hex64(str(ViewCodecScript.compute_view_hash({"k": 1}))))


func test_compute_view_hash_known_vector_canonical_a1() -> void:
	# 跨语言固定向量：canonical JSON UTF-8 字节 {"a":1}
	const KNOWN_SHA256 := "015abd7f5cc57a2dd94b7590f04ad8084273905ee33ec5cebeae62276a97f862"
	# 再用 Godot 标准 SHA-256 独立校验 fixture 本身，避免手抄输入漂移。
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update('{"a":1}'.to_utf8_buffer())
	var expected: String = ctx.finish().hex_encode()
	assert_eq(expected, KNOWN_SHA256, "fixture 必须等于冻结的跨端 known vector")
	var actual: String = str(ViewCodecScript.compute_view_hash({"a": 1}))
	assert_eq(actual, KNOWN_SHA256, "canonical {\"a\":1} SHA-256 必须匹配冻结向量")
	assert_true(_is_lowercase_hex64(actual))


# ---- P1 Red：真实 Wall canonical identity（instance_id 绑定 tile_id/red/owner）----

func test_tile_view_from_dict_rejects_forged_canonical_identity_against_real_wall() -> void:
	# 真实 Wall：hand_seq=0 与 7，各 draw 136 张真实 Tile；不硬编码 serial。
	var wall0: Wall = Wall.new_full_set(0)
	var wall7: Wall = Wall.new_full_set(7)
	assert_not_null(wall0, "Wall.new_full_set(0) 非 null")
	assert_not_null(wall7, "Wall.new_full_set(7) 非 null")
	if wall0 == null or wall7 == null:
		return

	var tiles0: Array = []
	var tiles7: Array = []
	for _i in range(Tile.TILES_PER_HAND):
		var t0: Tile = wall0.draw()
		var t7: Tile = wall7.draw()
		assert_not_null(t0, "hand_seq0 第 %s 张真实 Tile" % _i)
		assert_not_null(t7, "hand_seq7 第 %s 张真实 Tile" % _i)
		assert_true(t0 is Tile)
		assert_true(t7 is Tile)
		tiles0.append(t0)
		tiles7.append(t7)
	assert_eq(tiles0.size(), Tile.TILES_PER_HAND, "hand_seq0 共 136 张")
	assert_eq(tiles7.size(), Tile.TILES_PER_HAND, "hand_seq7 共 136 张")

	var views0: Array = []
	var views7: Array = []
	var iid_delta: int = 7 * Tile.TILES_PER_HAND
	for serial in range(Tile.TILES_PER_HAND):
		var tv0: Variant = ViewCodecScript.tile_view_from_tile(tiles0[serial])
		assert_not_null(tv0, "hand_seq0 serial=%s tile_view_from_tile" % serial)
		var rv0: Variant = ViewCodecScript.tile_view_from_dict(tv0)
		assert_not_null(rv0, "hand_seq0 serial=%s tile_view_from_dict 合法" % serial)
		var d0: Dictionary = _as_dict(rv0)
		assert_true(_exact_keys(d0, [
			"instance_id", "tile_id", "is_red_dora", "owner_seat",
		]), "hand_seq0 exact 四键 serial=%s" % serial)
		views0.append(d0)

		var tv7: Variant = ViewCodecScript.tile_view_from_tile(tiles7[serial])
		assert_not_null(tv7, "hand_seq7 serial=%s tile_view_from_tile" % serial)
		var rv7: Variant = ViewCodecScript.tile_view_from_dict(tv7)
		assert_not_null(rv7, "hand_seq7 serial=%s tile_view_from_dict 合法" % serial)
		var d7: Dictionary = _as_dict(rv7)
		assert_true(_exact_keys(d7, [
			"instance_id", "tile_id", "is_red_dora", "owner_seat",
		]), "hand_seq7 exact 四键 serial=%s" % serial)
		views7.append(d7)

		# 同 draw serial：iid 差 7*TILES_PER_HAND，身份字段一致
		assert_eq(
			int(d7["instance_id"]) - int(d0["instance_id"]), iid_delta,
			"同 serial instance_id 差 7*TILES_PER_HAND serial=%s" % serial
		)
		assert_eq(int(d7["tile_id"]), int(d0["tile_id"]), "同 serial tile_id serial=%s" % serial)
		assert_eq(
			bool(d7["is_red_dora"]), bool(d0["is_red_dora"]),
			"同 serial is_red_dora serial=%s" % serial
		)
		assert_eq(
			int(d7["owner_seat"]), int(d0["owner_seat"]),
			"同 serial owner_seat serial=%s" % serial
		)

	assert_eq(views0.size(), 136, "hand_seq0 合法 view 共 136")
	assert_eq(views7.size(), 136, "hand_seq7 合法 view 共 136")

	# 单一目标：真实 tile_id==W5 && is_red_dora==false，优先 owner_seat=1
	var target: Dictionary = {}
	var preferred: Dictionary = {}
	for d in views0:
		if int(d["tile_id"]) != TileId.W5:
			continue
		if bool(d["is_red_dora"]):
			continue
		if target.is_empty():
			target = d
		if int(d["owner_seat"]) == 1:
			preferred = d
			break
	if not preferred.is_empty():
		target = preferred
	assert_false(target.is_empty(), "真实牌山必须存在非赤 W5 view")
	assert_eq(int(target["tile_id"]), TileId.W5)
	assert_eq(bool(target["is_red_dora"]), false)
	var fixed_iid: int = int(target["instance_id"])
	var fixed_owner: int = int(target["owner_seat"])

	# 三份 deep duplicate 伪造，instance_id 不变 → 当前 codec 错误接受 → Red
	var forge_tile_id: Dictionary = target.duplicate(true)
	forge_tile_id["tile_id"] = TileId.W6
	assert_eq(int(forge_tile_id["instance_id"]), fixed_iid, "伪造 tile_id 保持 instance_id")
	assert_ne(int(forge_tile_id["tile_id"]), TileId.W5)
	assert_true(TileId.ALL.has(int(forge_tile_id["tile_id"])))
	assert_null(
		ViewCodecScript.tile_view_from_dict(forge_tile_id),
		"canonical：同 instance_id 改 tile_id 必须拒绝（当前错误接受）"
	)

	var forge_red: Dictionary = target.duplicate(true)
	forge_red["is_red_dora"] = true
	assert_eq(int(forge_red["instance_id"]), fixed_iid, "伪造 is_red_dora 保持 instance_id")
	assert_eq(int(forge_red["tile_id"]), TileId.W5)
	assert_eq(bool(forge_red["is_red_dora"]), true)
	assert_null(
		ViewCodecScript.tile_view_from_dict(forge_red),
		"canonical：同 instance_id 改 is_red_dora 必须拒绝（当前错误接受）"
	)

	var other_owner: int = (fixed_owner + 1) % 4
	if other_owner == fixed_owner:
		other_owner = (fixed_owner + 2) % 4
	var forge_owner: Dictionary = target.duplicate(true)
	forge_owner["owner_seat"] = other_owner
	assert_eq(int(forge_owner["instance_id"]), fixed_iid, "伪造 owner_seat 保持 instance_id")
	assert_ne(int(forge_owner["owner_seat"]), fixed_owner)
	assert_true(int(forge_owner["owner_seat"]) >= 0 and int(forge_owner["owner_seat"]) <= 3)
	assert_null(
		ViewCodecScript.tile_view_from_dict(forge_owner),
		"canonical：同 instance_id 改 owner_seat 必须拒绝（当前错误接受）"
	)
