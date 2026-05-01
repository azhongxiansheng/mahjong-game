extends GutTest

# 麻将王 — M5 第 2 步：MetaProgress 跨 Run 声望单测

func _mp() -> Node:
	return get_tree().root.get_node_or_null("MetaProgress")

func before_each() -> void:
	var mp := _mp()
	if mp:
		mp.reset()

func after_each() -> void:
	var mp := _mp()
	if mp:
		mp.reset()

func test_meta_progress_is_autoload():
	assert_not_null(_mp())

func test_initial_zero():
	var mp := _mp()
	assert_eq(mp.renown, 0)
	assert_eq(mp.runs_completed, 0)
	assert_eq(mp.runs_won, 0)

func test_add_renown_won():
	var mp := _mp()
	var amount: int = mp.add_renown_for_run(true)
	assert_eq(amount, mp.RENOWN_RUN_WON)
	assert_eq(mp.renown, mp.RENOWN_RUN_WON)
	assert_eq(mp.runs_completed, 1)
	assert_eq(mp.runs_won, 1)

func test_add_renown_failed():
	var mp := _mp()
	var amount: int = mp.add_renown_for_run(false)
	assert_eq(amount, mp.RENOWN_RUN_FAILED)
	assert_eq(mp.renown, mp.RENOWN_RUN_FAILED)
	assert_eq(mp.runs_completed, 1)
	assert_eq(mp.runs_won, 0)

func test_renown_won_higher_than_failed():
	# v1 占位数值：通关 +50 / 失败 +5
	assert_gt(MetaProgress.RENOWN_RUN_WON, MetaProgress.RENOWN_RUN_FAILED)

func test_multiple_runs_accumulate():
	var mp := _mp()
	mp.add_renown_for_run(true)   # +50
	mp.add_renown_for_run(false)  # +5
	mp.add_renown_for_run(false)  # +5
	assert_eq(mp.renown, mp.RENOWN_RUN_WON + mp.RENOWN_RUN_FAILED * 2)
	assert_eq(mp.runs_completed, 3)
	assert_eq(mp.runs_won, 1)

func test_reset_clears_state_and_file():
	var mp := _mp()
	mp.add_renown_for_run(true)
	mp.reset()
	assert_eq(mp.renown, 0)
	assert_eq(mp.runs_completed, 0)
	assert_eq(mp.runs_won, 0)

func test_save_load_roundtrip():
	# add_renown_for_run 内部会 save_meta；模拟 reload 应保留状态
	var mp := _mp()
	mp.add_renown_for_run(true)
	mp.add_renown_for_run(true)
	var saved_renown: int = mp.renown
	var saved_completed: int = mp.runs_completed
	# 直接调 _load_meta 重置 in-memory state（先把数值改了，再 load 看是否还原）
	mp.renown = 9999
	mp.runs_completed = 9999
	mp._load_meta()
	assert_eq(mp.renown, saved_renown)
	assert_eq(mp.runs_completed, saved_completed)

func test_to_dict_includes_version():
	var mp := _mp()
	var d: Dictionary = mp.to_dict()
	assert_eq(d.get("version"), MetaProgress.META_VERSION)
