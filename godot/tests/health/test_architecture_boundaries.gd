extends GutTest

# ARCH-00：用最小文本扫描冻结 GDScript 的显式依赖方向，不替代完整语法分析。

const FIXTURE_ROOT := "res://tests/health/fixtures/architecture_boundaries"
const MODULES := ["core", "battle", "protocol", "session", "server", "ui"]
const OWNER_ISSUES := ["#391", "#392", "#393", "#394", "#395", "#396"]

const RULES := {
	"core": [
		{"id": "core_forbidden_resource_path", "kind": "text", "matches": [
			"res://battle/", "res://session/", "res://protocol/", "res://server/", "res://ui/",
		]},
		{"id": "core_forbidden_concrete_type", "kind": "word", "matches": [
			"BattleController", "PlayableBattleController", "NetworkedBattleController",
			"IBattleController", "IAuthoritativeBattleController", "BattleState", "BattleEvent",
			"GameDriver", "Action", "NetworkedEvent", "LocalLoopbackServer",
			"PublicCasualNetworkSession", "HeadlessRoomSession", "HeadlessWorker",
			"PlayableTable", "Control", "WebSocketPeer",
		]},
	],
	"battle": [
		{"id": "battle_forbidden_resource_path", "kind": "text", "matches": [
			"res://ui/", "res://server/",
		]},
		{"id": "battle_forbidden_adapter", "kind": "word", "matches": [
			"WebSocketPeer", "LocalLoopbackServer", "HeadlessWorker", "HeadlessRoomSession",
			"ControlPlane", "ControlPlaneClient",
		]},
	],
	"protocol": [
		{"id": "protocol_forbidden_resource_path", "kind": "text", "matches": [
			"res://ui/", "res://server/",
		]},
		{"id": "protocol_forbidden_lifecycle_type", "kind": "word", "matches": [
			"Node", "Node2D", "Node3D", "Control", "CanvasItem", "CanvasLayer", "Window",
			"PackedScene", "SceneTree", "WebSocketPeer", "LocalLoopbackServer", "HeadlessWorker",
		]},
	],
	"session": [
		{"id": "session_forbidden_authority_entry", "kind": "word", "matches": [
			"TurnEngine", "ScoreCalc", "SkillScheduler",
		]},
	],
	"ui": [
		{"id": "ui_forbidden_authority_type", "kind": "word", "matches": [
			"LocalLoopbackServer",
		]},
		{"id": "ui_forbidden_authority_internal", "kind": "text", "matches": [
			"auth.get(\"_", "auth.event_journal(",
		]},
	],
}

const METADATA_MATCHES := [
	"has_meta(\"local_authority\")",
	"get_meta(\"local_authority\")",
	"set_meta(\"local_authority\"",
	"remove_meta(\"local_authority\")",
]

const CURRENT_DEBT_ALLOWLIST := [
	{
		"file": "res://battle/battle_controller.gd",
		"rule": "local_authority_metadata_seam",
		"match": "has_meta(\"local_authority\")",
		"issue": "#391",
		"count": 1,
	},
	{
		"file": "res://battle/battle_controller.gd",
		"rule": "local_authority_metadata_seam",
		"match": "get_meta(\"local_authority\")",
		"issue": "#391",
		"count": 1,
	},
	{
		"file": "res://session/practice_session_launcher.gd",
		"rule": "local_authority_metadata_seam",
		"match": "set_meta(\"local_authority\"",
		"issue": "#391",
		"count": 1,
	},
	{
		"file": "res://session/practice_session_launcher.gd",
		"rule": "local_authority_metadata_seam",
		"match": "remove_meta(\"local_authority\")",
		"issue": "#391",
		"count": 1,
	},
	{
		"file": "res://ui/four_player_table/playable_table.gd",
		"rule": "local_authority_metadata_seam",
		"match": "has_meta(\"local_authority\")",
		"issue": "#391",
		"count": 4,
	},
	{
		"file": "res://ui/four_player_table/playable_table.gd",
		"rule": "local_authority_metadata_seam",
		"match": "get_meta(\"local_authority\")",
		"issue": "#391",
		"count": 3,
	},
	{
		"file": "res://ui/four_player_table/playable_table.gd",
		"rule": "ui_forbidden_authority_internal",
		"match": "auth.get(\"_",
		"issue": "#391",
		"count": 2,
	},
	{
		"file": "res://ui/four_player_table/playable_table.gd",
		"rule": "ui_forbidden_authority_internal",
		"match": "auth.event_journal(",
		"issue": "#391",
		"count": 2,
	},
]


func test_new_forbidden_dependency_is_reported() -> void:
	var violations := _scan_roots([FIXTURE_ROOT.path_join("core")], [])
	assert_eq(violations.size(), 2, "fixture 新增 core → ui 依赖必须失败")
	if violations.size() == 2:
		assert_eq(violations[0]["match"], "res://ui/", "应报告精确匹配项")


func test_each_dependency_rule_reports_concrete_violation() -> void:
	var violations := _scan_roots([FIXTURE_ROOT.path_join("rules")], [])
	var found_rules: Array[String] = []
	for violation in violations:
		found_rules.append(String(violation["rule"]))
	for expected_rule in [
		"battle_forbidden_adapter",
		"protocol_forbidden_lifecycle_type",
		"session_forbidden_authority_entry",
		"ui_forbidden_authority_type",
		"ui_forbidden_authority_internal",
		"local_authority_metadata_seam",
	]:
		assert_true(found_rules.has(expected_rule), "fixture 应命中规则：%s" % expected_rule)


func test_concrete_type_words_ignore_string_copy_but_keep_real_dependencies() -> void:
	var violations := _scan_roots([FIXTURE_ROOT.path_join("string_literals")], [])
	var rule_counts := {}
	for violation in violations:
		var rule := String(violation["rule"])
		rule_counts[rule] = int(rule_counts.get(rule, 0)) + 1
	assert_eq(violations.size(), 4, "只应命中真实类型、资源路径、metadata 与 auth 私有读取")
	assert_eq(rule_counts.get("core_forbidden_concrete_type", 0), 1)
	assert_eq(rule_counts.get("core_forbidden_resource_path", 0), 1)
	assert_eq(rule_counts.get("ui_forbidden_authority_type", 0), 0)
	assert_eq(rule_counts.get("ui_forbidden_authority_internal", 0), 1)
	assert_eq(rule_counts.get("local_authority_metadata_seam", 0), 1)


func test_allowlist_requires_exact_file_rule_and_match() -> void:
	var exact_allowlist := [{
		"file": FIXTURE_ROOT.path_join("core/new_violation.gd"),
		"rule": "core_forbidden_resource_path",
		"match": "res://ui/",
		"issue": "#391",
		"count": 1,
	}]
	assert_eq(
		_scan_roots([FIXTURE_ROOT.path_join("core")], exact_allowlist).size(),
		1,
		"同文件新增相同匹配也必须超过 count=1 的精确豁免",
	)
	var exact_count_allowlist: Array = exact_allowlist.duplicate(true)
	exact_count_allowlist[0]["count"] = 2
	assert_eq(_scan_roots([FIXTURE_ROOT.path_join("core")], exact_count_allowlist), [])
	var final_acceptance_owner: Array = exact_count_allowlist.duplicate(true)
	final_acceptance_owner[0]["issue"] = "#397"
	assert_gt(
		_scan_roots([FIXTURE_ROOT.path_join("core")], final_acceptance_owner).size(),
		0,
		"最终验收 #397 不能作为待实现债务 owner",
	)

	var wrong_match: Array = exact_allowlist.duplicate(true)
	wrong_match[0]["match"] = "res://server/"
	assert_gt(_scan_roots([FIXTURE_ROOT.path_join("core")], wrong_match).size(), 0)

	var wrong_file: Array = exact_allowlist.duplicate(true)
	wrong_file[0]["file"] = FIXTURE_ROOT.path_join("core/other.gd")
	assert_gt(_scan_roots([FIXTURE_ROOT.path_join("core")], wrong_file).size(), 0)


func test_comments_do_not_create_violations() -> void:
	assert_eq(_scan_roots([FIXTURE_ROOT.path_join("comments")], []), [])


func test_test_and_plugin_directories_are_excluded() -> void:
	assert_eq(_scan_roots([FIXTURE_ROOT.path_join("exclusions")], []), [])


func test_zero_allowlist_lists_every_current_debt_with_owner_issue() -> void:
	var violations := _scan_roots(_production_roots(), [])
	var expected_total := 0
	for entry in CURRENT_DEBT_ALLOWLIST:
		expected_total += int(entry["count"])
		assert_true(entry["issue"] in OWNER_ISSUES, "每项债务必须归属后续 ARCH Issue")
	assert_eq(violations.size(), expected_total, "零豁免扫描必须列全当前债务")


func test_current_production_debt_is_frozen_by_exact_allowlist() -> void:
	assert_eq(_scan_roots(_production_roots(), CURRENT_DEBT_ALLOWLIST), [])


func _production_roots() -> Array[String]:
	return [
		"res://core",
		"res://battle",
		"res://protocol",
		"res://session",
		"res://server",
		"res://ui",
	]


func _scan_roots(roots: Array, allowlist: Array) -> Array[Dictionary]:
	var violations: Array[Dictionary] = []
	for root_value in roots:
		var root := String(root_value)
		var files: Array[String] = []
		_collect_gd_files(root, root, files)
		files.sort()
		for file_path in files:
			_scan_file(root, file_path, violations)
	violations.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _violation_key(a) < _violation_key(b)
	)
	return _apply_allowlist(violations, allowlist)


func _collect_gd_files(root: String, dir_path: String, out: Array[String]) -> void:
	if dir_path != root and dir_path.get_file() in ["tests", "addons"]:
		return
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	while true:
		var entry_name := dir.get_next()
		if entry_name.is_empty():
			break
		if entry_name.begins_with("."):
			continue
		var full_path := dir_path.path_join(entry_name)
		if dir.current_is_dir():
			_collect_gd_files(root, full_path, out)
		elif entry_name.ends_with(".gd"):
			out.append(full_path)
	dir.list_dir_end()


func _scan_file(root: String, file_path: String, out: Array[Dictionary]) -> void:
	var module := _module_for_file(root, file_path)
	if module.is_empty():
		return
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		out.append(_violation(file_path, 0, "scanner_unreadable_file", file_path))
		return
	var line_number := 0
	while not file.eof_reached():
		line_number += 1
		var source_line := _strip_comment(file.get_line())
		if source_line.strip_edges().is_empty():
			continue
		var word_source_line := _mask_strings(source_line)
		for rule in RULES.get(module, []):
			for match_value in rule["matches"]:
				var match_text := String(match_value)
				var matched := (
					source_line.contains(match_text)
					if rule["kind"] == "text"
					else _contains_word(word_source_line, match_text)
				)
				if matched:
					out.append(_violation(file_path, line_number, rule["id"], match_text))
		for match_value in METADATA_MATCHES:
			var match_text := String(match_value)
			if source_line.contains(match_text):
				out.append(_violation(
					file_path, line_number, "local_authority_metadata_seam", match_text
				))
	file.close()


func _module_for_file(root: String, file_path: String) -> String:
	var root_name := root.trim_suffix("/").get_file()
	if root_name in MODULES:
		return root_name
	var relative := file_path.trim_prefix(root.trim_suffix("/") + "/")
	var first_segment := relative.get_slice("/", 0)
	return first_segment if first_segment in MODULES else ""


func _strip_comment(line: String) -> String:
	var quote := ""
	var escaped := false
	for index in range(line.length()):
		var character := line.substr(index, 1)
		if not quote.is_empty():
			if escaped:
				escaped = false
			elif character == "\\":
				escaped = true
			elif character == quote:
				quote = ""
		elif character == "\"" or character == "'":
			quote = character
		elif character == "#":
			return line.substr(0, index)
	return line


func _mask_strings(line: String) -> String:
	var masked := ""
	var quote := ""
	var escaped := false
	for index in range(line.length()):
		var character := line.substr(index, 1)
		if quote.is_empty():
			if character == "\"" or character == "'":
				quote = character
				masked += " "
			else:
				masked += character
		else:
			masked += " "
			if escaped:
				escaped = false
			elif character == "\\":
				escaped = true
			elif character == quote:
				quote = ""
	return masked


func _contains_word(line: String, word: String) -> bool:
	var regex := RegEx.new()
	var error := regex.compile("(^|[^A-Za-z0-9_])%s([^A-Za-z0-9_]|$)" % word)
	return error == OK and regex.search(line) != null


func _violation(file_path: String, line: int, rule: String, match_text: String) -> Dictionary:
	return {"file": file_path, "line": line, "rule": rule, "match": match_text}


func _violation_key(violation: Dictionary) -> String:
	return "%s|%06d|%s|%s" % [
		violation["file"], violation["line"], violation["rule"], violation["match"],
	]


func _allowlist_key(entry: Dictionary) -> String:
	return "%s|%s|%s" % [entry.get("file", ""), entry.get("rule", ""), entry.get("match", "")]


func _apply_allowlist(violations: Array[Dictionary], allowlist: Array) -> Array[Dictionary]:
	var remaining := violations.duplicate(true)
	for raw_entry in allowlist:
		var entry := raw_entry as Dictionary
		var key := _allowlist_key(entry)
		var expected_count := int(entry.get("count", 0))
		var issue := String(entry.get("issue", ""))
		if (
			key.contains("*")
			or key.contains("?")
			or not String(entry.get("file", "")).ends_with(".gd")
			or expected_count <= 0
			or issue not in OWNER_ISSUES
		):
			remaining.append(_violation(
				String(entry.get("file", "")), 0, "invalid_allowlist_entry", key
			))
			continue
		var matching_indexes: Array[int] = []
		for index in range(remaining.size()):
			if _allowlist_key(remaining[index]) == key:
				matching_indexes.append(index)
		for offset in range(mini(expected_count, matching_indexes.size()) - 1, -1, -1):
			remaining.remove_at(matching_indexes[offset])
		if matching_indexes.size() < expected_count:
			remaining.append(_violation(
				String(entry.get("file", "")), 0, "stale_allowlist_entry", key
			))
	remaining.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _violation_key(a) < _violation_key(b)
	)
	return remaining
