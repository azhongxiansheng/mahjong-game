extends GutTest

# EventNode.format_option_delta 单测:
# 把 option dict 渲染成"HP ±N · ±N 金币 · 需 N 金币"风格,无 delta 时返 ""。

func test_no_changes_returns_empty() -> void:
	assert_eq(EventNode.format_option_delta({"hp_delta": 0, "gold_delta": 0}), "")
	assert_eq(EventNode.format_option_delta({}), "")


func test_positive_hp() -> void:
	assert_eq(EventNode.format_option_delta({"hp_delta": 1}), "HP +1")
	assert_eq(EventNode.format_option_delta({"hp_delta": 5}), "HP +5")


func test_negative_hp() -> void:
	# 负号已在 %d 内自带
	assert_eq(EventNode.format_option_delta({"hp_delta": -1}), "HP -1")


func test_full_heal_sentinel_999() -> void:
	assert_eq(EventNode.format_option_delta({"hp_delta": 999}), "HP 全满")


func test_gold_gain_and_loss() -> void:
	assert_eq(EventNode.format_option_delta({"gold_delta": 30}), "+30 金币")
	assert_eq(EventNode.format_option_delta({"gold_delta": -50}), "-50 金币")


func test_require_gold_appears() -> void:
	assert_eq(EventNode.format_option_delta({"require_gold": 30}), "需 30 金币")


func test_combined_order_hp_gold_require() -> void:
	# 顺序约定:HP → gold_delta → require_gold,用 ' · ' 分隔
	var s := EventNode.format_option_delta({
		"hp_delta": 1, "gold_delta": -30, "require_gold": 30
	})
	assert_eq(s, "HP +1 · -30 金币 · 需 30 金币")


func test_zero_gold_delta_omitted() -> void:
	# gold_delta=0 不出现
	var s := EventNode.format_option_delta({"hp_delta": 2, "gold_delta": 0})
	assert_eq(s, "HP +2")
