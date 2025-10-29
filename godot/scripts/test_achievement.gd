## 成就系统 - 单元测试
## 测试 Achievement, AchievementSystem, AchievementTracker 等类

extends Node

# ============ 测试结果记录 ============
var tests_passed: int = 0
var tests_failed: int = 0
var test_results: Array = []

# ============ 测试初始化 ============

func _ready() -> void:
	"""运行所有测试"""
	print("\n" + "="*50)
	print("🧪 成就系统单元测试开始")
	print("="*50 + "\n")
	
	# 运行所有测试
	test_achievement_basic()
	test_achievement_progress()
	test_achievement_serialization()
	
	test_achievement_system_registration()
	test_achievement_system_queries()
	test_achievement_system_statistics()
	test_achievement_system_json()
	
	test_tracker_stats()
	test_tracker_win_detection()
	test_tracker_score_detection()
	
	test_performance()
	
	# 输出总结
	print_summary()


# ============ Achievement 类测试 ============

func test_achievement_basic() -> void:
	"""测试 Achievement 基础功能"""
	var achievement = Achievement.new("test_achievement", "测试成就")
	
	assert_equal(achievement.id, "test_achievement", "成就ID设置正确")
	assert_equal(achievement.name, "测试成就", "成就名称设置正确")
	assert_false(achievement.is_unlocked, "初始状态未解锁")
	assert_equal(achievement.progress, 0, "初始进度为0")
	assert_equal(achievement.max_progress, 1, "默认最大进度为1")
	
	test_passed("Achievement 基础功能")


func test_achievement_progress() -> void:
	"""测试 Achievement 进度管理"""
	var achievement = Achievement.new("progress_test", "进度测试")
	achievement.max_progress = 10
	
	# 测试进度增加
	var unlocked = achievement.update_progress(3)
	assert_false(unlocked, "进度3未解锁")
	assert_equal(achievement.progress, 3, "进度正确增加到3")
	
	# 继续增加进度
	unlocked = achievement.update_progress(5)
	assert_false(unlocked, "进度8未解锁")
	assert_equal(achievement.progress, 8, "进度正确增加到8")
	
	# 超过最大值
	unlocked = achievement.update_progress(5)
	assert_true(unlocked, "进度达到最大值时解锁")
	assert_equal(achievement.progress, 10, "进度限制在最大值")
	assert_true(achievement.is_unlocked, "成就已解锁")
	
	test_passed("Achievement 进度管理")


func test_achievement_serialization() -> void:
	"""测试 Achievement JSON 序列化"""
	var achievement = Achievement.new("serial_test", "序列化测试")
	achievement.description = "测试描述"
	achievement.category = "progress"
	achievement.rarity = "epic"
	achievement.reward_points = 500
	achievement.unlock()
	
	# 序列化
	var dict = achievement.to_dict()
	assert_equal(dict["id"], "serial_test", "JSON中ID正确")
	assert_equal(dict["name"], "序列化测试", "JSON中名称正确")
	assert_true(dict["is_unlocked"], "JSON中解锁状态正确")
	
	# 反序列化
	var new_achievement = Achievement.new("new", "新成就")
	new_achievement.from_dict(dict)
	assert_equal(new_achievement.description, "测试描述", "反序列化描述正确")
	assert_equal(new_achievement.reward_points, 500, "反序列化奖励正确")
	assert_true(new_achievement.is_unlocked, "反序列化解锁状态正确")
	
	test_passed("Achievement 序列化")


# ============ AchievementSystem 类测试 ============

func test_achievement_system_registration() -> void:
	"""测试 AchievementSystem 注册功能"""
	var system = AchievementSystem.new()
	add_child(system)
	
	# 创建测试成就
	var ach1 = Achievement.new("ach1", "成就1")
	ach1.category = "progress"
	var ach2 = Achievement.new("ach2", "成就2")
	ach2.category = "oneshot"
	
	# 注册成就
	system.register_achievement(ach1)
	system.register_achievement(ach2)
	
	assert_equal(system.get_total_count(), 2, "成就总数正确")
	assert_not_null(system.get_achievement("ach1"), "成就查询正确")
	assert_equal(system.get_achievements_by_category("progress").size(), 1, "分类查询正确")
	
	system.queue_free()
	test_passed("AchievementSystem 注册")


func test_achievement_system_queries() -> void:
	"""测试 AchievementSystem 查询功能"""
	var system = AchievementSystem.new()
	add_child(system)
	
	# 创建和注册成就
	for i in range(5):
		var ach = Achievement.new("ach_%d" % i, "成就%d" % i)
		ach.category = "progress" if i % 2 == 0 else "oneshot"
		system.register_achievement(ach)
	
	# 解锁部分成就
	system.unlock_achievement("ach_0")
	system.unlock_achievement("ach_1")
	
	assert_equal(system.get_unlocked_count(), 2, "已解锁计数正确")
	assert_equal(system.get_locked_achievements().size(), 3, "未解锁计数正确")
	assert_true(system.get_completion_percent() > 0.0, "完成度计算正确")
	
	system.queue_free()
	test_passed("AchievementSystem 查询")


func test_achievement_system_statistics() -> void:
	"""测试 AchievementSystem 统计功能"""
	var system = AchievementSystem.new()
	add_child(system)
	
	# 创建成就并设置奖励
	for i in range(3):
		var ach = Achievement.new("reward_%d" % i, "奖励成就%d" % i)
		ach.reward_points = (i + 1) * 100
		system.register_achievement(ach)
	
	# 解锁部分成就
	system.unlock_achievement("reward_0")  # 100 点
	system.unlock_achievement("reward_1")  # 200 点
	
	var stats = system.get_statistics()
	assert_equal(stats["total_achievements"], 3, "统计总数正确")
	assert_equal(stats["unlocked_count"], 2, "统计已解锁数正确")
	assert_equal(stats["total_points"], 300, "统计总点数正确")
	
	system.queue_free()
	test_passed("AchievementSystem 统计")


func test_achievement_system_json() -> void:
	"""测试 AchievementSystem JSON 导入导出"""
	var system1 = AchievementSystem.new()
	add_child(system1)
	
	# 创建和设置成就
	var ach = Achievement.new("json_test", "JSON测试")
	system1.register_achievement(ach)
	system1.unlock_achievement("json_test")
	
	# 导出
	var json_str = system1.export_to_json()
	assert_true(json_str.length() > 0, "导出JSON非空")
	
	# 新系统导入
	var system2 = AchievementSystem.new()
	add_child(system2)
	system2.register_achievement(Achievement.new("json_test", "JSON测试"))
	
	var success = system2.import_from_json(json_str)
	assert_true(success, "导入JSON成功")
	assert_true(system2.get_achievement("json_test").is_unlocked, "导入后成就状态正确")
	
	system1.queue_free()
	system2.queue_free()
	test_passed("AchievementSystem JSON")


# ============ AchievementTracker 类测试 ============

func test_tracker_stats() -> void:
	"""测试 AchievementTracker 统计功能"""
	var tracker = AchievementTracker.new()
	add_child(tracker)
	
	# 模拟游戏完成
	tracker.on_game_completed({
		"is_victory": true,
		"score": 5000,
		"play_time": 300
	})
	
	var stats = tracker.get_stats()
	assert_equal(stats["total_wins"], 1, "胜利计数正确")
	assert_equal(stats["total_games"], 1, "游戏计数正确")
	assert_equal(stats["highest_score"], 5000, "最高分记录正确")
	assert_equal(stats["current_streak"], 1, "连胜计数正确")
	
	tracker.queue_free()
	test_passed("AchievementTracker 统计")


func test_tracker_win_detection() -> void:
	"""测试 AchievementTracker 胜利检测"""
	var system = AchievementSystem.new()
	add_child(system)
	var tracker = AchievementTracker.new()
	add_child(tracker)
	
	# 创建并注册成就
	for i in range(1, 4):
		var ach = Achievement.new("win_streak_%d" % i, "连胜%d" % i)
		system.register_achievement(ach)
	
	tracker.set_achievement_system(system)
	
	# 模拟连胜
	for i in range(5):
		tracker.on_game_completed({"is_victory": true, "score": 1000, "play_time": 60})
	
	# 检查连胜成就
	assert_true(system.get_achievement("win_streak_3").is_unlocked, "3连胜成就解锁")
	assert_equal(tracker.total_wins, 5, "胜利总数正确")
	assert_equal(tracker.current_win_streak, 5, "当前连胜正确")
	
	system.queue_free()
	tracker.queue_free()
	test_passed("AchievementTracker 胜利检测")


func test_tracker_score_detection() -> void:
	"""测试 AchievementTracker 分数检测"""
	var system = AchievementSystem.new()
	add_child(system)
	var tracker = AchievementTracker.new()
	add_child(tracker)
	
	# 创建并注册成就
	var ach = Achievement.new("score_10000", "高分成就")
	system.register_achievement(ach)
	tracker.set_achievement_system(system)
	
	# 模拟高分
	tracker.on_game_completed({"is_victory": true, "score": 10000, "play_time": 60})
	
	# 检查分数成就
	assert_true(system.get_achievement("score_10000").is_unlocked, "高分成就解锁")
	assert_equal(tracker.highest_score, 10000, "最高分记录正确")
	
	system.queue_free()
	tracker.queue_free()
	test_passed("AchievementTracker 分数检测")


# ============ 性能测试 ============

func test_performance() -> void:
	"""性能基准测试"""
	var system = AchievementSystem.new()
	add_child(system)
	
	# 创建大量成就
	var start_time = Time.get_ticks_msec()
	for i in range(1000):
		var ach = Achievement.new("perf_ach_%d" % i, "性能测试成就%d" % i)
		system.register_achievement(ach)
	var registration_time = Time.get_ticks_msec() - start_time
	
	# 测试查询性能
	start_time = Time.get_ticks_msec()
	for i in range(1000):
		system.get_achievement("perf_ach_%d" % i)
	var query_time = Time.get_ticks_msec() - start_time
	
	# 测试统计性能
	start_time = Time.get_ticks_msec()
	system.get_statistics()
	var stats_time = Time.get_ticks_msec() - start_time
	
	print("\n📊 性能基准 (1000个成就):")
	print("  注册时间: %dms" % registration_time)
	print("  查询时间: %dms" % query_time)
	print("  统计时间: %dms" % stats_time)
	
	assert_less_than(registration_time, 100, "注册性能达标")
	assert_less_than(query_time, 50, "查询性能达标")
	assert_less_than(stats_time, 50, "统计性能达标")
	
	system.queue_free()
	test_passed("性能基准测试")


# ============ 测试辅助函数 ============

func assert_equal(actual, expected, message: String) -> void:
	"""断言相等"""
	if actual == expected:
		test_passed(message)
	else:
		test_failed("%s (期望: %s, 实际: %s)" % [message, expected, actual])


func assert_true(condition: bool, message: String) -> void:
	"""断言真"""
	if condition:
		test_passed(message)
	else:
		test_failed("%s (条件为假)" % message)


func assert_false(condition: bool, message: String) -> void:
	"""断言假"""
	if not condition:
		test_passed(message)
	else:
		test_failed("%s (条件为真)" % message)


func assert_not_null(value, message: String) -> void:
	"""断言非空"""
	if value != null:
		test_passed(message)
	else:
		test_failed("%s (值为空)" % message)


func assert_less_than(actual, expected, message: String) -> void:
	"""断言小于"""
	if actual < expected:
		test_passed(message)
	else:
		test_failed("%s (期望<%s, 实际:%s)" % [message, expected, actual])


func test_passed(message: String) -> void:
	"""测试通过"""
	tests_passed += 1
	test_results.append("[✅] " + message)


func test_failed(message: String) -> void:
	"""测试失败"""
	tests_failed += 1
	test_results.append("[❌] " + message)


func print_summary() -> void:
	"""打印测试总结"""
	print("\n" + "="*50)
	print("📋 测试结果总结")
	print("="*50)
	
	for result in test_results:
		print(result)
	
	print("\n" + "="*50)
	print("📊 测试统计")
	print("="*50)
	print("✅ 通过: %d" % tests_passed)
	print("❌ 失败: %d" % tests_failed)
	print("📈 通过率: %.1f%%" % (float(tests_passed) / (tests_passed + tests_failed) * 100))
	print("="*50 + "\n")
	
	if tests_failed == 0:
		print("🎉 所有测试通过!")
	else:
		print("⚠️  有 %d 个测试失败" % tests_failed)
