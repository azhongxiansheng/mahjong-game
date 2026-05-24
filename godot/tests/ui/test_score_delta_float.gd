extends GutTest

# SeatPanel set_score 触发的 "+N / -N" 飘字测试。

const SEAT_PANEL := preload("res://ui/four_player_table/seat_panel.tscn")


func _make_panel() -> SeatPanel:
	var p: SeatPanel = SEAT_PANEL.instantiate()
	add_child_autofree(p)
	return p


# 首次 bind(prev=0)不应飘字
func test_first_score_set_no_delta() -> void:
	var sp := _make_panel()
	await get_tree().process_frame
	var before: int = sp._label_score.get_parent().get_child_count()
	sp.set_score(25000)
	# 父容器 child count 不应增(脉冲在 label 自己上,delta float 来源是父容器)
	var after: int = sp._label_score.get_parent().get_child_count()
	assert_eq(after, before, "首次 bind 不应飘字 (prev=0 跳过)")


# 二次 set 分数上涨 → 父容器新增一个 Label
func test_score_up_spawns_positive_delta() -> void:
	var sp := _make_panel()
	await get_tree().process_frame
	sp.set_score(25000)  # 首次
	var before: int = sp._label_score.get_parent().get_child_count()
	sp.set_score(30200)  # +5200
	var after: int = sp._label_score.get_parent().get_child_count()
	assert_eq(after, before + 1, "上涨应飘 +5200 Label")
	# 找到新加的 Label
	var float_lbl: Label = null
	for c in sp._label_score.get_parent().get_children():
		if c is Label and (c as Label).text == "+5200":
			float_lbl = c
			break
	assert_not_null(float_lbl, "应有 text '+5200' 的 Label")


# 分数下跌 → 红色 "-N"
func test_score_down_spawns_negative_delta() -> void:
	var sp := _make_panel()
	await get_tree().process_frame
	sp.set_score(25000)
	sp.set_score(23500)  # -1500
	var float_lbl: Label = null
	for c in sp._label_score.get_parent().get_children():
		if c is Label and (c as Label).text == "-1500":
			float_lbl = c
			break
	assert_not_null(float_lbl, "下跌应飘 '-1500' Label")


# 同值再 set 不飘
func test_same_score_no_delta() -> void:
	var sp := _make_panel()
	await get_tree().process_frame
	sp.set_score(25000)
	var before: int = sp._label_score.get_parent().get_child_count()
	sp.set_score(25000)
	var after: int = sp._label_score.get_parent().get_child_count()
	assert_eq(after, before, "同值不应飘字")


# 多次涨分应叠加生成多个 Label,各自独立 tween 不互踩
func test_multiple_deltas_stack() -> void:
	var sp := _make_panel()
	await get_tree().process_frame
	sp.set_score(25000)
	sp.set_score(28000)  # +3000
	sp.set_score(31000)  # +3000
	sp.set_score(35000)  # +4000
	var float_count: int = 0
	for c in sp._label_score.get_parent().get_children():
		if c is Label and ((c as Label).text == "+3000" or (c as Label).text == "+4000"):
			float_count += 1
	assert_eq(float_count, 3, "3 次涨分应各自飘字")
