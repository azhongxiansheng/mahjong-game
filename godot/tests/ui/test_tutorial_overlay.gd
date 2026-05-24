extends GutTest

# TutorialOverlay + SettingsManager.tutorial_seen — 新手引导持久化逻辑。


func _sm() -> Node:
	return get_tree().root.get_node("/root/SettingsManager")


# ---- SettingsManager.tutorial_seen ----

func test_tutorial_seen_defaults_false_or_loaded() -> void:
	# 首次启动 / 文件不存在时默认 false;测试环境可能已有 settings.json
	# 至少确认字段存在
	var sm = _sm()
	assert_true(sm.tutorial_seen is bool, "tutorial_seen 应是 bool")


func test_set_tutorial_seen() -> void:
	var sm = _sm()
	var saved: bool = sm.tutorial_seen
	sm.set_tutorial_seen(true)
	assert_true(sm.tutorial_seen, "set_tutorial_seen(true) 应生效")
	sm.set_tutorial_seen(false)
	assert_false(sm.tutorial_seen)
	# restore
	sm.set_tutorial_seen(saved)


func test_tutorial_seen_emits_settings_changed() -> void:
	var sm = _sm()
	var saved: bool = sm.tutorial_seen
	watch_signals(sm)
	sm.set_tutorial_seen(true)
	assert_signal_emitted(sm, "settings_changed")
	sm.set_tutorial_seen(saved)


# ---- TutorialOverlay 多页导航 ----

func test_overlay_starts_at_page_zero() -> void:
	var t := TutorialOverlay.new()
	add_child_autofree(t)
	await get_tree().process_frame
	assert_eq(t._current_page, 0, "首次显示在第 0 页")


func test_overlay_next_advances_page() -> void:
	var t := TutorialOverlay.new()
	add_child_autofree(t)
	await get_tree().process_frame
	t._on_next()
	assert_eq(t._current_page, 1)


func test_overlay_prev_clamps_at_zero() -> void:
	var t := TutorialOverlay.new()
	add_child_autofree(t)
	await get_tree().process_frame
	t._on_prev()  # 已在 0,不应回退
	assert_eq(t._current_page, 0)


func test_overlay_last_page_text_is_start_game() -> void:
	var t := TutorialOverlay.new()
	add_child_autofree(t)
	await get_tree().process_frame
	# 跳到最后一页
	for i in range(TutorialOverlay.PAGES.size() - 1):
		t._on_next()
	assert_eq(t._current_page, TutorialOverlay.PAGES.size() - 1)
	# 此时 next_btn.text 应改成 "开始游戏 ✓"
	assert_eq(t._next_btn.text, "开始游戏 ✓")


# 跳过按钮立刻 finish + 标 seen=true
func test_skip_marks_tutorial_seen() -> void:
	var sm = _sm()
	var saved: bool = sm.tutorial_seen
	sm.set_tutorial_seen(false)
	var t := TutorialOverlay.new()
	add_child_autofree(t)
	await get_tree().process_frame
	t._on_skip()
	await get_tree().process_frame
	assert_true(sm.tutorial_seen, "Skip 应标 seen=true")
	# restore
	sm.set_tutorial_seen(saved)


# 读完最后页 → 下一页按钮 = 完成 → seen=true
func test_finish_last_page_marks_seen() -> void:
	var sm = _sm()
	var saved: bool = sm.tutorial_seen
	sm.set_tutorial_seen(false)
	var t := TutorialOverlay.new()
	add_child_autofree(t)
	await get_tree().process_frame
	for i in range(TutorialOverlay.PAGES.size() - 1):
		t._on_next()
	# 此时在最后页,再点 next = 完成
	t._on_next()
	await get_tree().process_frame
	assert_true(sm.tutorial_seen)
	sm.set_tutorial_seen(saved)


# PAGES 字典所有项都应有 title + body
func test_pages_structure() -> void:
	for p in TutorialOverlay.PAGES:
		assert_true(p is Dictionary)
		assert_true(p.has("title"))
		assert_true(p.has("body"))
		assert_true(String(p.get("title", "")).length() > 0)
		assert_true(String(p.get("body", "")).length() > 0)
