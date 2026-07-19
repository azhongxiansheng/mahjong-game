extends GutTest

# T4 结算编排(spec 2026-06-11 G4)— 役逐条入场 / 分数滚动 / 点击跳过。

const PT_SCENE := preload("res://ui/four_player_table/playable_table.gd")

var _pt: PlayableTable
var _panel: Panel

func before_each() -> void:
	_pt = PT_SCENE.new()
	add_child_autofree(_pt)
	_panel = Panel.new()
	_pt.add_child(_panel)
	_pt._result_anim_tweens.clear()

func test_yaku_rows_built_and_staggered():
	_pt._build_yaku_rows(_panel, [
		{"name": "立直", "han": 1},
		{"name": "门前清自摸和", "han": 1},
		{"name": "平和", "han": 1},
	])
	var grid: GridContainer = null
	for child in _panel.get_children():
		if child is GridContainer:
			grid = child
	assert_not_null(grid, "役列表用 Grid 容器")
	assert_eq(grid.get_child_count(), 3, "3 役 3 行")
	# 错峰入场:初始全透明(动画起点)；行是带金条的 HBox
	for row in grid.get_children():
		assert_true(row is HBoxContainer or row is Label, "役行应为 HBox/Label")
		assert_eq((row as CanvasItem).modulate.a, 0.0, "入场前透明")
	assert_eq(_pt._result_anim_tweens.size(), 3, "每行一条动画登记")

func test_yaku_rows_overflow_aggregated():
	var many: Array = []
	for i in range(11):
		many.append({"name": "役%d" % i, "han": 1})
	_pt._build_yaku_rows(_panel, many)
	var grid: GridContainer = null
	for child in _panel.get_children():
		if child is GridContainer:
			grid = child
	assert_eq(grid.get_child_count(), 9, "8 条上限 + 1 条聚合「…等 N 役」")

func test_rolling_score_starts_at_zero():
	_pt._build_rolling_score(_panel, 8000, true)
	var lbl: Label = _panel.get_node_or_null("RollingScore")
	assert_not_null(lbl)
	assert_eq(lbl.text, "0 点", "从 0 开始滚")
	assert_eq(_pt._result_anim_tweens.size(), 1)

func test_skip_jumps_to_final_state():
	_pt._build_yaku_rows(_panel, [{"name": "立直", "han": 1}])
	_pt._build_rolling_score(_panel, 12000, false)
	var consumed: bool = _pt._skip_result_animations()
	assert_true(consumed, "动画在播时点击被消费(不关面板)")
	var lbl: Label = _panel.get_node_or_null("RollingScore")
	assert_eq(lbl.text, "12000 点", "跳到终值")
	for child in _panel.get_children():
		if child is GridContainer:
			for row in child.get_children():
				assert_eq((row as CanvasItem).modulate.a, 1.0, "役行跳到不透明")
	# 第二次点击:无动画 → 返 false(调用方关面板)
	assert_false(_pt._skip_result_animations())


func test_yaku_banner_builds_labels_then_frees():
	# 横幅应创建 YakuBanner 节点、写役名、结束后自毁
	var yaku: Array = [
		{"name": "立直", "han": 1},
		{"name": "一发", "han": 1},
	]
	_pt._play_yaku_banner(yaku)
	await get_tree().process_frame
	var banner := _pt.get_node_or_null("YakuBanner")
	assert_not_null(banner, "应有 YakuBanner 临时节点")
	var lbl_count := 0
	for c in banner.get_children():
		if c is Label:
			lbl_count += 1
			assert_true((c as Label).text.find("立直") >= 0
				or (c as Label).text.find("一发") >= 0)
	assert_eq(lbl_count, 2)
	# hold ~0.55 + fade 0.2
	await wait_seconds(1.2)
	assert_null(_pt.get_node_or_null("YakuBanner"), "横幅结束后应销毁")

func test_rolling_score_color_by_player_benefit():
	_pt._build_rolling_score(_panel, 8000, true)
	var up: Label = _panel.get_node_or_null("RollingScore")
	assert_eq(up.get_theme_color("font_color"), Color(0.94, 0.84, 0.42), "玩家受益金色")
	up.name = "Old"
	_pt._build_rolling_score(_panel, 8000, false)
	var down: Label = _panel.get_node_or_null("RollingScore")
	assert_eq(down.get_theme_color("font_color"), Color(0.93, 0.42, 0.42), "玩家放铳红色")
