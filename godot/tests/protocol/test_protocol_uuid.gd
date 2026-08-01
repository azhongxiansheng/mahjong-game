extends GutTest

## E2-02 Red：唯一共享 UUID validator
## 冻结路径 res://protocol/protocol_uuid.gd / class_name ProtocolUuid
## static is_canonical_v4(value: Variant) -> bool
## 合法仅 lowercase RFC 4122 v4 + variant 8/9/a/b；DTO 源码锁调用共享 API。

const UUID_PATH := "res://protocol/protocol_uuid.gd"
const ACTION_PATH := "res://protocol/action.gd"
const CR_PATH := "res://protocol/command_result.gd"
# ARCH-03 #393：command_id 校验随 payload codec 拆分迁移到领域 codec 文件
const NE_TABLE_CODEC_PATH := "res://protocol/table_flow_payload_codec.gd"
const NE_REWARD_CODEC_PATH := "res://protocol/reward_item_payload_codec.gd"

const VALID_V4 := "550e8400-e29b-41d4-a716-446655440000"
const VALID_V4_B := "550e8400-e29b-41d4-b716-4466554400aa"
const VALID_V4_8 := "550e8400-e29b-41d4-8716-446655440000"
const VALID_V4_9 := "550e8400-e29b-41d4-9716-446655440000"


func _source_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


## 缺文件/缺方法时返回 null（调用方 assert 类型为 bool，防 reject 伪绿）
func _call_is_canonical_v4(value: Variant) -> Variant:
	if not ResourceLoader.exists(UUID_PATH):
		return null
	var script: GDScript = load(UUID_PATH) as GDScript
	if script == null:
		return null
	if not script.has_method("is_canonical_v4"):
		return null
	return script.call("is_canonical_v4", value)


func _assert_canonical(value: Variant, expect: bool, label: String) -> void:
	var ret: Variant = _call_is_canonical_v4(value)
	assert_eq(typeof(ret), TYPE_BOOL, "%s: is_canonical_v4 必须返回 bool（当前 typeof=%d）" % [label, typeof(ret)])
	if typeof(ret) != TYPE_BOOL:
		return
	assert_eq(bool(ret), expect, label)


func test_protocol_uuid_path_and_class_contract() -> void:
	assert_true(
		ResourceLoader.exists(UUID_PATH),
		"生产 ProtocolUuid 路径冻结: %s" % UUID_PATH
	)
	if not ResourceLoader.exists(UUID_PATH):
		return

	var src: String = _source_text(UUID_PATH)
	assert_false(src.is_empty(), "ProtocolUuid 源码可读")
	assert_true(src.contains("class_name ProtocolUuid"), "必须 class_name ProtocolUuid")
	assert_true(
		src.contains("static func is_canonical_v4"),
		"必须 static func is_canonical_v4"
	)

	var script: GDScript = load(UUID_PATH) as GDScript
	assert_not_null(script)
	if script == null:
		return
	var found := false
	for m in script.get_script_method_list():
		if str(m.get("name", "")) != "is_canonical_v4":
			continue
		found = true
		var args: Array = m.get("args", [])
		assert_eq(args.size(), 1, "is_canonical_v4 恰 1 参 value: Variant")
		if args.size() == 1:
			var a0: Dictionary = args[0]
			# Godot 反射：Variant 参数 type == TYPE_NIL
			assert_eq(int(a0.get("type", -1)), TYPE_NIL,
				"is_canonical_v4(value: Variant) 反射 type 须 TYPE_NIL")
		break
	assert_true(found, "get_script_method_list 必须含 is_canonical_v4")


func test_is_canonical_v4_accepts_lowercase_rfc4122_v4_variants() -> void:
	assert_true(ResourceLoader.exists(UUID_PATH), "生产 ProtocolUuid 必须存在: %s" % UUID_PATH)
	if not ResourceLoader.exists(UUID_PATH):
		return
	for ok in [VALID_V4, VALID_V4_B, VALID_V4_8, VALID_V4_9]:
		_assert_canonical(ok, true, "合法 lowercase v4+variant 必须 true: %s" % ok)


func test_is_canonical_v4_rejects_case_shape_type_version_variant() -> void:
	assert_true(ResourceLoader.exists(UUID_PATH), "生产 ProtocolUuid 必须存在: %s" % UUID_PATH)
	if not ResourceLoader.exists(UUID_PATH):
		return

	# uppercase / mixed
	_assert_canonical("550E8400-E29B-41D4-A716-446655440000", false, "全大写拒绝")
	_assert_canonical("550e8400-E29b-41d4-a716-446655440000", false, "混大小写拒绝")

	# 错误形状
	for bad in [
		"",
		"not-a-uuid",
		"550e8400e29b41d4a716446655440000",
		"550e8400-e29b-41d4-a716",
		"550e8400-e29b-41d4-a716-4466554400000",
		"550e8400-e29b-41d4-a716-44665544000",
		"gggggggg-e29b-41d4-a716-446655440000",
		"{550e8400-e29b-41d4-a716-446655440000}",
		"550e8400-e29b-41d4-a716-446655440000 ",
	]:
		_assert_canonical(bad, false, "错误形状拒绝: %s" % bad)

	# 非 String
	for non_str in [null, 0, 1.0, true, [], {}]:
		_assert_canonical(non_str, false, "非 String 拒绝 typeof=%d" % typeof(non_str))

	# version 非 4（third group 1xxx 等）
	_assert_canonical("550e8400-e29b-11d4-a716-446655440000", false, "version=1 拒绝")
	_assert_canonical("550e8400-e29b-51d4-a716-446655440000", false, "version=5 拒绝")

	# variant 非 RFC（fourth group 7xxx / cxxx；仅 8/9/a/b）
	_assert_canonical("550e8400-e29b-41d4-7716-446655440000", false, "variant 7xxx 拒绝")
	_assert_canonical("550e8400-e29b-41d4-c716-446655440000", false, "variant cxxx 拒绝")
	_assert_canonical("550e8400-e29b-41d4-0716-446655440000", false, "variant 0xxx 拒绝")


func test_action_command_result_networked_event_use_shared_protocol_uuid() -> void:
	# 防三份漂移：DTO 必须调用 ProtocolUuid.is_canonical_v4，不得自带 _UUID_RE / 本地 _is_uuid
	assert_true(ResourceLoader.exists(UUID_PATH), "生产 ProtocolUuid 必须存在: %s" % UUID_PATH)
	if not ResourceLoader.exists(UUID_PATH):
		return

	for path in [ACTION_PATH, CR_PATH, NE_TABLE_CODEC_PATH, NE_REWARD_CODEC_PATH]:
		assert_true(FileAccess.file_exists(path), "DTO 源码存在: %s" % path)
		var src: String = _source_text(path)
		assert_false(src.is_empty(), "DTO 源码可读: %s" % path)
		assert_true(
			src.contains("ProtocolUuid.is_canonical_v4"),
			"%s 必须调用 ProtocolUuid.is_canonical_v4" % path
		)
		assert_false(
			src.contains("_UUID_RE"),
			"%s 不得自带 _UUID_RE" % path
		)
		assert_false(
			src.contains("func _is_uuid"),
			"%s 不得自带本地 _is_uuid validator" % path
		)
