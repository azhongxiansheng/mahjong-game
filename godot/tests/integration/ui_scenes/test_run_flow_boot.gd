extends GutTest

# Run 流程 UI 场景自动化测试 — 无 mock。
#
# 实例化真实 run_flow.tscn，挂进场景树，验证：启动落到起始包选择面板、
# 选包后真实推进到章节地图面板、RunState 被正确创建。覆盖 run_flow.gd 的
# 场景过渡接线（之前只有 RunState 逻辑层 e2e，无 UI 场景层覆盖）。

const RUN_FLOW := preload("res://ui/run/run_flow.tscn")


func before_each() -> void:
	# 清掉可能存在的真实存档，保证 RunFlow._ready 走 starter picker 而非续档。
	var ss := get_tree().root.get_node_or_null("SaveSystem")
	if ss and ss.has_method("clear_run"):
		ss.clear_run()


func test_boots_to_starter_pack_picker() -> void:
	# 流程已改为:先 CharacterPicker → 选角色后再 StarterPackPicker。
	var flow: RunFlow = RUN_FLOW.instantiate()
	add_child_autofree(flow)
	await get_tree().process_frame
	assert_not_null(flow._current_panel, "启动后应有当前面板")
	assert_true(flow._current_panel is CharacterPicker,
		"无存档时应先到角色选择面板,实际：%s"
			% flow._current_panel.get_class())


func test_choosing_pack_advances_to_chapter_map() -> void:
	var flow: RunFlow = RUN_FLOW.instantiate()
	add_child_autofree(flow)
	await get_tree().process_frame
	# 1) 角色选择面板 → 选第一个可用角色 emit signal
	var char_picker := flow._current_panel as CharacterPicker
	assert_not_null(char_picker, "应先在角色选择面板")
	if char_picker == null:
		return
	char_picker.character_chosen.emit(&"akagi")
	await get_tree().process_frame

	# 2) 推进到起始包选择面板
	var picker := flow._current_panel as StarterPackPicker
	assert_not_null(picker, "选角后应在起始包选择面板")
	if picker == null:
		return

	picker.pack_chosen.emit(&"starter_control")
	await get_tree().process_frame

	assert_not_null(flow._run_state, "选包后应创建 RunState")
	assert_true(flow._current_panel is ChapterMapView,
		"选包后应推进到章节地图，实际：%s"
			% flow._current_panel.get_class())
	if flow._run_state != null:
		assert_gt(flow._run_state.next_node_options().size(), 0,
			"章节地图应有可选节点")
