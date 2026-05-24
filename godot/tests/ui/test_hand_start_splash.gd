extends GutTest

# HandStartSplash.format_title 格式化 + 实例化 fade 测试。


# ---- format_title 静态 helper ----

func test_format_east_1_dealer_player() -> void:
	var d: Dictionary = HandStartSplash.format_title(1, TileId.E, 0, 0)
	assert_eq(d.get("title"), "东 1 局")
	assert_eq(d.get("subtitle"), "你 是庄家")


func test_format_east_2_dealer_ai() -> void:
	var d: Dictionary = HandStartSplash.format_title(2, TileId.E, 1, 0)
	assert_eq(d.get("title"), "东 2 局")
	assert_eq(d.get("subtitle"), "AI 1 是庄家")


func test_format_with_honba() -> void:
	var d: Dictionary = HandStartSplash.format_title(3, TileId.E, 2, 2)
	assert_eq(d.get("title"), "东 3 局 · 2 本场")


func test_format_south_round() -> void:
	var d: Dictionary = HandStartSplash.format_title(5, TileId.S_WIND, 0, 0)
	# hand_number 5 在南场应显示 "南 1 局"
	assert_eq(d.get("title"), "南 1 局")


func test_format_south_round_hand_8() -> void:
	var d: Dictionary = HandStartSplash.format_title(8, TileId.S_WIND, 3, 0)
	assert_eq(d.get("title"), "南 4 局")


# ---- 实例化 / 信号 ----

func test_make_constructs_with_title_and_subtitle() -> void:
	var s := HandStartSplash.make("东 1 局", "你 是庄家")
	add_child_autofree(s)
	await get_tree().process_frame
	assert_eq(s._title_label.text, "东 1 局")
	assert_eq(s._subtitle_label.text, "你 是庄家")


# splash fade-in/out 完成后 emit finished signal,自 queue_free
func test_finished_signal_eventually_emits() -> void:
	var s := HandStartSplash.make("test", "subtitle")
	add_child(s)
	var emitted := [false]
	s.finished.connect(func(): emitted[0] = true)
	await get_tree().process_frame
	# 等够时长(0.2 fade-in + 0.7 hold + 0.4 fade-out + buffer)
	await get_tree().create_timer(1.5).timeout
	assert_true(emitted[0], "finished 应在 1.3s 后 emit")


# Subtitle 内容含庄家信息(完整 round trip:format → make)
func test_round_trip_format_to_make() -> void:
	var d: Dictionary = HandStartSplash.format_title(4, TileId.E, 0, 1)
	var s := HandStartSplash.make(String(d.title), String(d.subtitle))
	add_child_autofree(s)
	await get_tree().process_frame
	assert_eq(s._title_label.text, "东 4 局 · 1 本场")
	assert_eq(s._subtitle_label.text, "你 是庄家")
