class_name UnitTests

# 单元测试框架
# 用于测试所有核心系统的正确性

# 测试统计
var tests_run: int = 0
var tests_passed: int = 0
var tests_failed: int = 0
var failed_tests: Array = []

# ==================== 主测试入口 ====================

func run_all_tests() -> void:
	"""运行所有单元测试"""
	var separator = "="
	for i in range(60):
		separator += "="
	
	print("\n" + separator)
	print("【开始运行单元测试】")
	print(separator + "\n")
	
	# 重置统计
	tests_run = 0
	tests_passed = 0
	tests_failed = 0
	failed_tests.clear()
	
	# 运行所有测试
	test_card_data()
	test_card_hand()
	test_mahjong_deck()
	test_form_validator()
	test_object_pool()
	test_logger()
	test_config_manager()
	test_database_manager()
	
	# 打印总结
	_print_test_summary()

# ==================== CardData 测试 ====================

func test_card_data() -> void:
	"""测试 CardData 类"""
	print("\n【测试 CardData】")
	
	# 测试 1: 创建卡牌
	var card = CardData.new(0, 5)
	_assert_equal("创建卡牌", card.suit, 0)
	_assert_equal("创建卡牌", card.num, 5)
	
	# 测试 2: 卡牌名称
	var name = card.get_card_name()
	_assert_not_empty("卡牌名称", name)
	
	print("✓ CardData 测试完成")

# ==================== CardHand 测试 ====================

func test_card_hand() -> void:
	"""测试 CardHand 类"""
	print("\n【测试 CardHand】")
	
	var hand = CardHand.new()
	
	# 测试 1: 添加卡牌
	hand.add_card(CardData.new(0, 1))
	_assert_equal("添加卡牌数量", hand.get_card_count(), 1)
	
	# 测试 2: 添加多张卡牌
	hand.add_card(CardData.new(0, 2))
	hand.add_card(CardData.new(1, 3))
	_assert_equal("添加多张卡牌", hand.get_card_count(), 3)
	
	# 测试 3: 清空手牌
	hand.clear()
	_assert_equal("清空手牌", hand.get_card_count(), 0)
	
	print("✓ CardHand 测试完成")

# ==================== MahjongDeck 测试 ====================

func test_mahjong_deck() -> void:
	"""测试 MahjongDeck 类"""
	print("\n【测试 MahjongDeck】")
	
	var deck = MahjongDeck.new()
	
	# 测试 1: 甲板大小
	_assert_equal("甲板大小", deck.cards.size(), 108)
	
	# 测试 2: 抽卡
	var card = deck.draw_card()
	_assert_not_null("抽卡成功", card)
	_assert_equal("抽卡后甲板大小", deck.cards.size(), 107)
	
	# 测试 3: 洗牌
	deck.shuffle()
	_assert_equal("洗牌后甲板大小", deck.cards.size(), 107)
	
	print("✓ MahjongDeck 测试完成")

# ==================== FormValidator 测试 ====================

func test_form_validator() -> void:
	"""测试 FormValidator 类"""
	print("\n【测试 FormValidator】")
	
	# 测试 1: 用户名验证
	_assert_true("有效用户名", FormValidator.is_valid_username("player123"))
	_assert_false("无效用户名-太短", FormValidator.is_valid_username("ab"))
	_assert_false("无效用户名-特殊字符", FormValidator.is_valid_username("player@"))
	
	# 测试 2: 密码验证
	_assert_true("有效密码", FormValidator.is_valid_password("Password123"))
	_assert_false("无效密码-太短", FormValidator.is_valid_password("Pass1"))
	_assert_false("无效密码-无大写", FormValidator.is_valid_password("password123"))
	
	# 测试 3: 邮箱验证
	_assert_true("有效邮箱", FormValidator.is_valid_email("test@example.com"))
	_assert_false("无效邮箱-无@", FormValidator.is_valid_email("testexample.com"))
	_assert_false("无效邮箱-无点号", FormValidator.is_valid_email("test@example"))
	
	print("✓ FormValidator 测试完成")

# ==================== ObjectPool 测试 ====================

func test_object_pool() -> void:
	"""测试 ObjectPool 类"""
	print("\n【测试 ObjectPool】")
	
	var pool = ObjectPool.new()
	
	# 测试 1: 获取按钮
	var button = pool.get_button("Test")
	_assert_not_null("获取按钮", button)
	_assert_equal("按钮文本", button.text, "Test")
	
	# 测试 2: 归还按钮
	pool.return_button(button)
	_assert_greater("按钮池非空", pool.get_button_pool_size(), 0)
	
	# 测试 3: 获取标签
	var label = pool.get_label("Label")
	_assert_not_null("获取标签", label)
	_assert_equal("标签文本", label.text, "Label")
	
	print("✓ ObjectPool 测试完成")

# ==================== Logger 测试 ====================

func test_logger() -> void:
	"""测试 GameLogger 类"""
	print("\n【测试 GameLogger】")
	
	# 测试 1: 日志输出
	var initial_size = GameLogger.get_buffer_size()
	GameLogger.info("测试信息", "TEST")
	_assert_greater("日志缓冲区增长", GameLogger.get_buffer_size(), initial_size)
	
	# 测试 2: 日志级别
	GameLogger.set_log_level(GameLogger.LogLevel.ERROR)
	var size_before = GameLogger.get_buffer_size()
	GameLogger.debug("调试信息", "TEST")
	_assert_equal("调试信息被过滤", GameLogger.get_buffer_size(), size_before)
	
	# 重置日志级别
	GameLogger.set_log_level(GameLogger.LogLevel.DEBUG)
	
	print("✓ GameLogger 测试完成")

# ==================== ConfigManager 测试 ====================

func test_config_manager() -> void:
	"""测试 ConfigManager 类"""
	print("\n【测试 ConfigManager】")
	
	var config = ConfigManager.new()
	
	# 测试 1: 获取配置
	_assert_equal("获取配置", config.get("max_players"), 4)
	_assert_equal("获取不存在的配置", config.get("non_existent", 99), 99)
	
	# 测试 2: 设置配置
	config.set("test_key", "test_value")
	_assert_equal("设置配置", config.get("test_key"), "test_value")
	
	# 测试 3: 检查配置
	_assert_true("配置存在", config.has("max_players"))
	_assert_false("配置不存在", config.has("fake_key"))
	
	# 测试 4: 配置验证
	_assert_true("配置有效", config.validate_config())
	
	print("✓ ConfigManager 测试完成")

# ==================== DatabaseManager 测试 ====================

func test_database_manager() -> void:
	"""测试 DatabaseManager 类"""
	print("\n【测试 DatabaseManager】")
	
	var db = DatabaseManager.new()
	
	# 测试 1: 用户注册
	var success = db.register_user("testuser", "test@example.com", "TestPass123")
	_assert_true("用户注册", success)
	
	# 测试 2: 注册重复用户
	var duplicate = db.register_user("testuser", "test2@example.com", "TestPass123")
	_assert_false("注册重复用户", duplicate)
	
	# 测试 3: 用户登录
	var user = db.login_user("testuser", "TestPass123")
	_assert_not_null("正确密码登录", user)
	
	# 测试 4: 错误密码登录
	var wrong_pass = db.login_user("testuser", "WrongPass123")
	_assert_null("错误密码登录", wrong_pass)
	
	print("✓ DatabaseManager 测试完成")

# ==================== 测试工具方法 ====================

func _assert_equal(test_name: String, actual, expected) -> void:
	"""断言相等"""
	tests_run += 1
	if actual == expected:
		tests_passed += 1
		print("  ✓ %s" % test_name)
	else:
		tests_failed += 1
		failed_tests.append("%s (期望: %s, 实际: %s)" % [test_name, str(expected), str(actual)])
		print("  ✗ %s - 期望: %s, 实际: %s" % [test_name, str(expected), str(actual)])

func _assert_true(test_name: String, condition: bool) -> void:
	"""断言为真"""
	tests_run += 1
	if condition:
		tests_passed += 1
		print("  ✓ %s" % test_name)
	else:
		tests_failed += 1
		failed_tests.append(test_name)
		print("  ✗ %s" % test_name)

func _assert_false(test_name: String, condition: bool) -> void:
	"""断言为假"""
	tests_run += 1
	if not condition:
		tests_passed += 1
		print("  ✓ %s" % test_name)
	else:
		tests_failed += 1
		failed_tests.append(test_name)
		print("  ✗ %s" % test_name)

func _assert_not_null(test_name: String, value) -> void:
	"""断言非空"""
	tests_run += 1
	if value != null:
		tests_passed += 1
		print("  ✓ %s" % test_name)
	else:
		tests_failed += 1
		failed_tests.append(test_name)
		print("  ✗ %s - 值为null" % test_name)

func _assert_null(test_name: String, value) -> void:
	"""断言为空"""
	tests_run += 1
	if value == null:
		tests_passed += 1
		print("  ✓ %s" % test_name)
	else:
		tests_failed += 1
		failed_tests.append(test_name)
		print("  ✗ %s - 值不为null" % test_name)

func _assert_not_empty(test_name: String, value: String) -> void:
	"""断言非空字符串"""
	tests_run += 1
	if value != "":
		tests_passed += 1
		print("  ✓ %s" % test_name)
	else:
		tests_failed += 1
		failed_tests.append(test_name)
		print("  ✗ %s - 字符串为空" % test_name)

func _assert_greater(test_name: String, actual, expected) -> void:
	"""断言大于"""
	tests_run += 1
	if actual > expected:
		tests_passed += 1
		print("  ✓ %s" % test_name)
	else:
		tests_failed += 1
		failed_tests.append("%s (%s > %s)" % [test_name, str(actual), str(expected)])
		print("  ✗ %s - %s 未大于 %s" % [test_name, str(actual), str(expected)])

# ==================== 测试总结 ====================

func _print_test_summary() -> void:
	"""打印测试总结"""
	var separator = "="
	for i in range(60):
		separator += "="
	
	print("\n" + separator)
	print("【测试总结】")
	print(separator)
	print("总测试数: %d" % tests_run)
	print("通过: %d ✓" % tests_passed)
	print("失败: %d ✗" % tests_failed)
	
	if tests_failed > 0:
		print("\n失败的测试:")
		for failed in failed_tests:
			print("  - %s" % failed)
	
	var pass_rate = (float(tests_passed) / float(tests_run) * 100.0) if tests_run > 0 else 0
	print("\n通过率: %.1f%%" % pass_rate)
	print(separator + "\n")

func get_test_results() -> Dictionary:
	"""获取测试结果"""
	return {
		"total": tests_run,
		"passed": tests_passed,
		"failed": tests_failed,
		"pass_rate": (float(tests_passed) / float(tests_run) * 100.0) if tests_run > 0 else 0
	}
