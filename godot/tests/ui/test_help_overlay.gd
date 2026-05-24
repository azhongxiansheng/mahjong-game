extends GutTest

# HelpOverlay 单元测试 — SECTIONS 数据结构 + 实例化 + 关闭交互


func test_sections_structure() -> void:
	# 应有 3 个 sections:键盘热键 / 战斗按钮 / 日麻术语
	assert_eq(HelpOverlay.SECTIONS.size(), 3)
	for sect in HelpOverlay.SECTIONS:
		assert_true(sect is Dictionary)
		assert_true(sect.has("title"))
		assert_true(sect.has("rows"))
		assert_true(String(sect.get("title", "")).length() > 0)
		assert_true((sect.get("rows", []) as Array).size() > 0)


# 所有行都是 [key, value] 2 元素数组
func test_all_rows_are_pair_arrays() -> void:
	for sect in HelpOverlay.SECTIONS:
		for row in sect.get("rows", []):
			assert_true(row is Array, "row 应是 Array")
			assert_true((row as Array).size() >= 2, "row 至少 2 元素")
			assert_true(String((row as Array)[0]).length() > 0)
			assert_true(String((row as Array)[1]).length() > 0)


# 实例化:正常 mount + 含 title 标
func test_instance_renders_title() -> void:
	var h := HelpOverlay.new()
	add_child_autofree(h)
	await get_tree().process_frame
	# 找 Panel/title Label "快捷帮助"
	var found_title: bool = false
	var stack: Array = [h]
	while not stack.is_empty():
		var node = stack.pop_back()
		if node is Label and (node as Label).text == "快捷帮助":
			found_title = true
			break
		for child in node.get_children():
			stack.append(child)
	assert_true(found_title)


# _on_close emits signal + queue_free
func test_close_emits_signal_and_frees() -> void:
	var h := HelpOverlay.new()
	add_child(h)
	var emitted := [false]
	h.closed.connect(func(): emitted[0] = true)
	await get_tree().process_frame
	h._on_close()
	await get_tree().process_frame
	assert_true(emitted[0])
	assert_false(is_instance_valid(h))


# 至少包含一行关于 "立直" 的说明
func test_section_battle_buttons_mentions_riichi() -> void:
	var found := false
	for sect in HelpOverlay.SECTIONS:
		for row in sect.get("rows", []):
			if "立直" in String((row as Array)[0]) or "立直" in String((row as Array)[1]):
				found = true
				break
		if found:
			break
	assert_true(found, "帮助文档应包含 立直 说明")


# 包含 F3 热键
func test_keyboard_section_mentions_f3() -> void:
	var found := false
	for sect in HelpOverlay.SECTIONS:
		for row in sect.get("rows", []):
			if String((row as Array)[0]) == "F3":
				found = true
				break
	assert_true(found, "应文档化 F3 热键")
