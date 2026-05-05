extends GutTest

# 麻将王 — M12 Path C 第 1 步：Action 协议数据类型测试。

# ---- 构造 helpers ----

func test_discard_helper():
	var a := Action.discard(0, TileId.W5)
	assert_eq(a.kind, Action.Kind.DISCARD)
	assert_eq(a.seat, 0)
	assert_eq(int(a.payload["tile_id"]), TileId.W5)

func test_riichi_helper():
	var a := Action.riichi(2, TileId.S3)
	assert_eq(a.kind, Action.Kind.RIICHI)
	assert_eq(a.seat, 2)
	assert_eq(int(a.payload["tile_id"]), TileId.S3)

func test_chi_helper():
	var a := Action.chi(1, [TileId.W2, TileId.W3, TileId.W4])
	assert_eq(a.kind, Action.Kind.CHI)
	assert_eq(a.seat, 1)
	assert_eq(a.payload["tiles"].size(), 3)

func test_pon_helper():
	var a := Action.pon(3, TileId.HAKU)
	assert_eq(a.kind, Action.Kind.PON)
	assert_eq(a.seat, 3)

func test_kan_helper_default_minkan():
	var a := Action.kan(0, TileId.W5)
	assert_eq(a.kind, Action.Kind.KAN)
	assert_eq(a.payload["kind"], "minkan")

func test_kan_helper_ankan():
	var a := Action.kan(0, TileId.W5, "ankan")
	assert_eq(a.payload["kind"], "ankan")

func test_ron_helper_records_discarder():
	var a := Action.ron(2, TileId.S5, 1)
	assert_eq(a.kind, Action.Kind.RON)
	assert_eq(a.seat, 2)
	assert_eq(int(a.payload["discarder_seat"]), 1)

func test_tsumo_helper_no_payload():
	var a := Action.tsumo(0)
	assert_eq(a.kind, Action.Kind.TSUMO)
	assert_eq(a.payload.size(), 0)

func test_pass_claim_helper():
	var a := Action.pass_claim(1)
	assert_eq(a.kind, Action.Kind.PASS_CLAIM)
	assert_eq(a.seat, 1)

# ---- 序列化 ----

func test_to_from_dict_roundtrip_discard():
	var a := Action.discard(0, TileId.W5, 42)
	var d: Dictionary = a.to_dict()
	var a2: Action = Action.from_dict(d)
	assert_eq(a2.kind, a.kind)
	assert_eq(a2.seat, a.seat)
	assert_eq(a2.client_seq, a.client_seq)
	assert_eq(int(a2.payload["tile_id"]), TileId.W5)

func test_to_from_dict_roundtrip_chi():
	var a := Action.chi(1, [TileId.W2, TileId.W3, TileId.W4])
	var d: Dictionary = a.to_dict()
	var a2: Action = Action.from_dict(d)
	assert_eq(a2.payload["tiles"], [TileId.W2, TileId.W3, TileId.W4])

func test_from_dict_empty_returns_null():
	assert_null(Action.from_dict({}))

func test_payload_isolation():
	# to_dict 复制 payload 防别名共享
	var a := Action.discard(0, TileId.W5)
	var d: Dictionary = a.to_dict()
	d["payload"]["tile_id"] = 999
	# 原 action 不受 dict 修改影响
	assert_eq(int(a.payload["tile_id"]), TileId.W5)

# ---- describe ----

func test_describe_includes_kind_name():
	var s: String = Action.discard(0, TileId.W5).describe()
	assert_true(s.contains("DISCARD"), "describe 含 kind name")
	assert_true(s.contains("seat=0"), "describe 含 seat")
