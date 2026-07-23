extends GutTest

# 麻将王 — M5 第 2 步：MetaProgress 跨 Run 声望单测
# E1-02：不再依赖 Autoload，显式 load().new() 实例化 legacy 脚本。

const MetaProgressScript: GDScript = preload("res://meta/meta_progress.gd")

var _instance: Node = null


func _mp() -> Node:
	return _instance


func before_each() -> void:
	_instance = MetaProgressScript.new()
	add_child_autofree(_instance)
	_instance.reset()


func after_each() -> void:
	if is_instance_valid(_instance) and _instance.has_method("reset"):
		_instance.reset()
	_instance = null


func test_meta_progress_is_explicitly_loadable():
	assert_not_null(_mp())
	assert_not_null(MetaProgressScript)


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
	assert_gt(MetaProgressScript.RENOWN_RUN_WON, MetaProgressScript.RENOWN_RUN_FAILED)


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
	assert_eq(d.get("version"), MetaProgressScript.META_VERSION)
