extends GutTest
## TileInstance internal DTO 契约冻结（非公开 TileView）。
## exact keys 六个；skill 绝不序列化。

const EXPECTED_KEYS: Array[String] = [
	"tile_id",
	"is_red_dora",
	"tile_owner_seat",
	"tile_instance_id",
	"owner_seat",
	"holder_seat",
]


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _valid_dict(
	tile_id: int = TileId.W5,
	is_red_dora: bool = true,
	tile_owner_seat: int = 2,
	tile_instance_id: int = 987654321,
	owner_seat: int = 3,
	holder_seat: int = 1
) -> Dictionary:
	return {
		"tile_id": tile_id,
		"is_red_dora": is_red_dora,
		"tile_owner_seat": tile_owner_seat,
		"tile_instance_id": tile_instance_id,
		"owner_seat": owner_seat,
		"holder_seat": holder_seat,
	}


func _assert_exact_six_keys(d: Dictionary, label: String) -> void:
	assert_eq(d.size(), 6, "%s: dict 必须恰好 6 键" % label)
	for k in EXPECTED_KEYS:
		assert_true(d.has(k), "%s: 缺少键 %s" % [label, k])
	for k in d.keys():
		assert_true(k in EXPECTED_KEYS, "%s: 多余键 %s" % [label, str(k)])


func _assert_from_dict_rejects(input: Variant, label: String) -> void:
	var result = TileInstance.from_dict(input)
	assert_null(result, label)


func _make_positive_ti(skill: SkillResource = null) -> TileInstance:
	var tile := Tile.new(TileId.W5, true, 2, 987654321)
	var ti: TileInstance = TileInstance.make(tile, 3, skill)
	ti.holder_seat = 1
	return ti


func _assert_typeof_int(v: Variant, label: String) -> void:
	assert_eq(typeof(v), TYPE_INT, label)


func _assert_typeof_bool(v: Variant, label: String) -> void:
	assert_eq(typeof(v), TYPE_BOOL, label)


# ---------------------------------------------------------------------------
# 正例：to_dict exact 六键 + 类型
# ---------------------------------------------------------------------------

func test_to_dict_exact_six_keys_and_types() -> void:
	var skill := SkillResource.new()
	skill.id = "test_skill"
	var ti := _make_positive_ti(skill)
	var d: Dictionary = ti.to_dict()

	_assert_exact_six_keys(d, "to_dict_positive")
	assert_false(d.has("skill"), "to_dict 绝不序列化 skill")

	_assert_typeof_int(d["tile_id"], "tile_id 类型 int")
	_assert_typeof_bool(d["is_red_dora"], "is_red_dora 类型 bool")
	_assert_typeof_int(d["tile_owner_seat"], "tile_owner_seat 类型 int")
	_assert_typeof_int(d["tile_instance_id"], "tile_instance_id 类型 int")
	_assert_typeof_int(d["owner_seat"], "owner_seat 类型 int")
	_assert_typeof_int(d["holder_seat"], "holder_seat 类型 int")

	assert_eq(d["tile_id"], TileId.W5, "tile_id 值")
	assert_eq(d["is_red_dora"], true, "is_red_dora 值")
	assert_eq(d["tile_owner_seat"], 2, "tile_owner_seat 值")
	assert_eq(d["tile_instance_id"], 987654321, "tile_instance_id 值")
	assert_eq(d["owner_seat"], 3, "owner_seat 值")
	assert_eq(d["holder_seat"], 1, "holder_seat 值")


func test_from_dict_roundtrip_preserves_identity_and_nulls_skill() -> void:
	var skill := SkillResource.new()
	skill.id = "test_skill"
	var ti := _make_positive_ti(skill)
	assert_ne(ti.skill, null, "构造时 skill 非 null（前置）")

	var d: Dictionary = ti.to_dict()
	var restored: TileInstance = TileInstance.from_dict(d)

	assert_not_null(restored, "roundtrip from_dict 成功")
	if restored == null:
		return
	assert_eq(restored.tile.id, TileId.W5, "roundtrip tile.id")
	assert_eq(restored.tile.is_red_dora, true, "roundtrip tile.is_red_dora")
	assert_eq(restored.tile.owner_seat, 2, "roundtrip tile.owner_seat")
	assert_eq(restored.tile.instance_id, 987654321, "roundtrip tile.instance_id")
	assert_eq(restored.owner_seat, 3, "roundtrip TI owner_seat")
	assert_eq(restored.holder_seat, 1, "roundtrip TI holder_seat")
	assert_eq(restored.skill, null, "roundtrip skill 必须为 null（不序列化）")


func test_to_dict_output_mutation_does_not_pollute_object() -> void:
	var ti := _make_positive_ti()
	var d: Dictionary = ti.to_dict()
	d["tile_id"] = TileId.W1
	d["is_red_dora"] = false
	d["tile_owner_seat"] = 0
	d["tile_instance_id"] = 0
	d["owner_seat"] = -1
	d["holder_seat"] = -1

	assert_eq(ti.tile.id, TileId.W5, "改 dict 不污染 tile.id")
	assert_eq(ti.tile.is_red_dora, true, "改 dict 不污染 is_red_dora")
	assert_eq(ti.tile.owner_seat, 2, "改 dict 不污染 tile.owner_seat")
	assert_eq(ti.tile.instance_id, 987654321, "改 dict 不污染 instance_id")
	assert_eq(ti.owner_seat, 3, "改 dict 不污染 owner_seat")
	assert_eq(ti.holder_seat, 1, "改 dict 不污染 holder_seat")


func test_from_dict_copy_on_read_source_mutation_safe() -> void:
	var src := _valid_dict()
	var restored: TileInstance = TileInstance.from_dict(src)
	assert_not_null(restored, "copy-on-read: from_dict 成功")
	if restored == null:
		return

	src["tile_id"] = TileId.W9
	src["is_red_dora"] = false
	src["tile_owner_seat"] = 0
	src["tile_instance_id"] = 1
	src["owner_seat"] = 0
	src["holder_seat"] = 0

	assert_eq(restored.tile.id, TileId.W5, "篡改原 dict 不改 tile.id")
	assert_eq(restored.tile.is_red_dora, true, "篡改原 dict 不改 is_red_dora")
	assert_eq(restored.tile.owner_seat, 2, "篡改原 dict 不改 tile.owner_seat")
	assert_eq(restored.tile.instance_id, 987654321, "篡改原 dict 不改 instance_id")
	assert_eq(restored.owner_seat, 3, "篡改原 dict 不改 owner_seat")
	assert_eq(restored.holder_seat, 1, "篡改原 dict 不改 holder_seat")


# ---------------------------------------------------------------------------
# instance_id 合法边界正例：-1、0、MAX
# ---------------------------------------------------------------------------

func test_instance_id_boundary_negative_one() -> void:
	var d := _valid_dict(TileId.W5, false, -1, -1, -1, -1)
	var ti: TileInstance = TileInstance.from_dict(d)
	assert_not_null(ti, "instance_id=-1 合法")
	if ti == null:
		return
	assert_eq(ti.tile.instance_id, -1, "instance_id=-1 保留")


func test_instance_id_boundary_zero() -> void:
	var d := _valid_dict(TileId.W1, false, 0, 0, 0, 0)
	var ti: TileInstance = TileInstance.from_dict(d)
	assert_not_null(ti, "instance_id=0 合法")
	if ti == null:
		return
	assert_eq(ti.tile.instance_id, 0, "instance_id=0 保留")


func test_instance_id_boundary_max_safe() -> void:
	var d := _valid_dict(
		TileId.S1, false, 1, Tile.MAX_SAFE_INSTANCE_ID, 1, 2
	)
	var ti: TileInstance = TileInstance.from_dict(d)
	assert_not_null(ti, "instance_id=MAX 合法")
	if ti == null:
		return
	assert_eq(ti.tile.instance_id, Tile.MAX_SAFE_INSTANCE_ID, "instance_id=MAX 保留")


# ---------------------------------------------------------------------------
# from_dict 结构级拒绝：null / 非 Dictionary / 空 / 缺 key / 多 key
# ---------------------------------------------------------------------------

func test_from_dict_rejects_null() -> void:
	_assert_from_dict_rejects(null, "reject:null")


func test_from_dict_rejects_non_dictionary() -> void:
	var cases: Array = [
		["reject:non_dict:int", 42],
		["reject:non_dict:string", "not_a_dict"],
		["reject:non_dict:array", []],
		["reject:non_dict:bool", true],
		["reject:non_dict:float", 1.5],
	]
	for c in cases:
		_assert_from_dict_rejects(c[1], c[0])


func test_from_dict_rejects_empty_dict() -> void:
	_assert_from_dict_rejects({}, "reject:empty_dict")


func test_from_dict_rejects_missing_each_key() -> void:
	for missing in EXPECTED_KEYS:
		var d := _valid_dict()
		d.erase(missing)
		_assert_from_dict_rejects(d, "reject:missing_key:%s" % missing)


func test_from_dict_rejects_extra_key() -> void:
	var extras: Array = [
		["reject:extra_key:skill", "skill", null],
		["reject:extra_key:foo", "foo", 1],
		["reject:extra_key:tile", "tile", {}],
	]
	for c in extras:
		var d := _valid_dict()
		d[c[1]] = c[2]
		_assert_from_dict_rejects(d, c[0])


# ---------------------------------------------------------------------------
# 每字段错误类型：bool/float/String 不得被 int/bool 强转
# ---------------------------------------------------------------------------

func test_from_dict_rejects_wrong_type_tile_id() -> void:
	var cases: Array = [
		["reject:type:tile_id:bool", true],
		["reject:type:tile_id:float", 1.0],
		["reject:type:tile_id:string", "W5"],
	]
	for c in cases:
		var d := _valid_dict()
		d["tile_id"] = c[1]
		_assert_from_dict_rejects(d, c[0])


func test_from_dict_rejects_wrong_type_is_red_dora() -> void:
	var cases: Array = [
		["reject:type:is_red_dora:int", 1],
		["reject:type:is_red_dora:float", 1.0],
		["reject:type:is_red_dora:string", "true"],
	]
	for c in cases:
		var d := _valid_dict()
		d["is_red_dora"] = c[1]
		_assert_from_dict_rejects(d, c[0])


func test_from_dict_rejects_wrong_type_tile_owner_seat() -> void:
	var cases: Array = [
		["reject:type:tile_owner_seat:bool", true],
		["reject:type:tile_owner_seat:float", 2.0],
		["reject:type:tile_owner_seat:string", "2"],
	]
	for c in cases:
		var d := _valid_dict()
		d["tile_owner_seat"] = c[1]
		_assert_from_dict_rejects(d, c[0])


func test_from_dict_rejects_wrong_type_tile_instance_id() -> void:
	var cases: Array = [
		["reject:type:tile_instance_id:bool", false],
		["reject:type:tile_instance_id:float", 0.0],
		["reject:type:tile_instance_id:string", "0"],
	]
	for c in cases:
		var d := _valid_dict()
		d["tile_instance_id"] = c[1]
		_assert_from_dict_rejects(d, c[0])


func test_from_dict_rejects_wrong_type_owner_seat() -> void:
	var cases: Array = [
		["reject:type:owner_seat:bool", false],
		["reject:type:owner_seat:float", 3.0],
		["reject:type:owner_seat:string", "3"],
	]
	for c in cases:
		var d := _valid_dict()
		d["owner_seat"] = c[1]
		_assert_from_dict_rejects(d, c[0])


func test_from_dict_rejects_wrong_type_holder_seat() -> void:
	var cases: Array = [
		["reject:type:holder_seat:bool", true],
		["reject:type:holder_seat:float", 1.0],
		["reject:type:holder_seat:string", "1"],
	]
	for c in cases:
		var d := _valid_dict()
		d["holder_seat"] = c[1]
		_assert_from_dict_rejects(d, c[0])


# ---------------------------------------------------------------------------
# 值域：tile_id ∈ TileId.ALL；red 仅 W5/T5/S5；seats -1..3；instance_id
# ---------------------------------------------------------------------------

func test_from_dict_rejects_tile_id_not_in_all() -> void:
	var bad_ids: Array = [
		["reject:tile_id:negative", -1],
		["reject:tile_id:out_of_range_high", 99999],
		["reject:tile_id:not_in_all", 100],
	]
	for c in bad_ids:
		var d := _valid_dict()
		d["tile_id"] = c[1]
		d["is_red_dora"] = false
		_assert_from_dict_rejects(d, c[0])


func test_from_dict_rejects_red_true_on_non_five() -> void:
	# red true 只允许 W5/T5/S5
	var non_fives: Array = [
		["reject:red_on:W1", TileId.W1],
		["reject:red_on:T1", TileId.T1],
		["reject:red_on:S1", TileId.S1],
		["reject:red_on:W9", TileId.W9],
	]
	for c in non_fives:
		var d := _valid_dict(c[1], true, 0, 0, 0, 0)
		_assert_from_dict_rejects(d, c[0])


func test_from_dict_accepts_red_true_on_w5_t5_s5() -> void:
	var fives: Array = [
		["accept:red:W5", TileId.W5],
		["accept:red:T5", TileId.T5],
		["accept:red:S5", TileId.S5],
	]
	for c in fives:
		var d := _valid_dict(c[1], true, 0, 0, 0, 0)
		var ti: TileInstance = TileInstance.from_dict(d)
		assert_not_null(ti, c[0])
		if ti == null:
			continue
		assert_eq(ti.tile.is_red_dora, true, "%s is_red_dora" % c[0])
		assert_eq(ti.tile.id, c[1], "%s tile_id" % c[0])


func test_from_dict_rejects_seat_out_of_range() -> void:
	var seat_fields: Array[String] = ["tile_owner_seat", "owner_seat", "holder_seat"]
	var bad_values: Array = [
		["lt_neg1", -2],
		["gt_3", 4],
		["huge", 99],
	]
	for field in seat_fields:
		for bv in bad_values:
			var d := _valid_dict(TileId.W1, false, 0, 0, 0, 0)
			d[field] = bv[1]
			_assert_from_dict_rejects(
				d, "reject:seat:%s:%s" % [field, bv[0]]
			)


func test_from_dict_accepts_seat_boundary_neg1_to_3() -> void:
	for seat in [-1, 0, 1, 2, 3]:
		var d := _valid_dict(TileId.W1, false, seat, 0, seat, seat)
		var ti: TileInstance = TileInstance.from_dict(d)
		assert_not_null(ti, "accept:seat:%d" % seat)
		if ti == null:
			continue
		assert_eq(ti.tile.owner_seat, seat, "tile.owner_seat=%d" % seat)
		assert_eq(ti.owner_seat, seat, "owner_seat=%d" % seat)
		assert_eq(ti.holder_seat, seat, "holder_seat=%d" % seat)


func test_from_dict_rejects_instance_id_below_neg1() -> void:
	var d := _valid_dict(TileId.W1, false, 0, -2, 0, 0)
	_assert_from_dict_rejects(d, "reject:instance_id:lt_neg1")


func test_from_dict_rejects_instance_id_above_max() -> void:
	var d := _valid_dict(
		TileId.W1, false, 0, Tile.MAX_SAFE_INSTANCE_ID + 1, 0, 0
	)
	_assert_from_dict_rejects(d, "reject:instance_id:gt_max")
