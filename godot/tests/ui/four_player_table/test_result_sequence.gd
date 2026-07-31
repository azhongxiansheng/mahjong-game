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
	var grid: VBoxContainer = null
	for child in _panel.get_children():
		if child is VBoxContainer:
			grid = child
	assert_not_null(grid, "役列表必须是单列 VBox")
	assert_eq(grid.get_child_count(), 3, "3 役 3 行")
	# 错峰入场:初始全透明(动画起点)；行是带金条的 HBox
	for row in grid.get_children():
		assert_true(row is HBoxContainer or row is Label, "役行应为 HBox/Label")
		assert_eq((row as CanvasItem).modulate.a, 0.0, "入场前透明")
		if row is HBoxContainer:
			var labels := row.get_children().filter(func(c: Node): return c is Label)
			assert_eq(labels.size(), 3, "役名 + 点状引导线 + 番数")
			assert_eq((labels[0] as Label).get_theme_font_size("font_size"), 16)
	assert_eq(_pt._result_anim_tweens.size(), 3, "每行一条动画登记")


func test_yaku_reveal_waits_700ms_per_row():
	_pt._build_yaku_rows(_panel, [
		{"name": "立直", "han": 1},
		{"name": "门前清自摸和", "han": 1},
	])
	var grid: VBoxContainer = null
	for child in _panel.get_children():
		if child is VBoxContainer:
			grid = child
	assert_not_null(grid)
	var first := grid.get_child(0) as CanvasItem
	var second := grid.get_child(1) as CanvasItem
	await wait_seconds(0.40)
	assert_eq(first.modulate.a, 0.0, "首个役在 700ms 前不得提前出现")
	await wait_seconds(0.60)
	assert_gt(first.modulate.a, 0.95, "首个役 700ms 后用 260ms 完成入场")
	assert_eq(second.modulate.a, 0.0, "第二个役必须再等 700ms")
	await wait_seconds(0.70)
	assert_gt(second.modulate.a, 0.95, "第二个役按既定节奏出现")


func test_yaku_light_and_heavy_use_260_and_280ms() -> void:
	_pt._build_yaku_rows(_panel, [
		{"name": "七番役", "han": 7},
		{"name": "八番役", "han": 8},
	])
	var grid := _panel.get_node("YakuList") as VBoxContainer
	var light := grid.get_child(0) as Control
	var heavy := grid.get_child(1) as Control
	assert_eq(light.get_meta("reference_reveal_duration_ms", -1), 260,
		"低于 8 番的轻役入场时长为 260ms")
	assert_eq(heavy.get_meta("reference_reveal_duration_ms", -1), 280,
		"8 番起的重役入场时长为 280ms")
	assert_false(bool(light.get_meta("reference_heavy", true)))
	assert_true(bool(heavy.get_meta("reference_heavy", false)))


func test_bonus_rows_share_one_reveal_phase() -> void:
	assert_true(_pt.has_method("_build_result_bonus_rows"),
		"bonus 必须有独立且可验证的单一 phase")
	if not _pt.has_method("_build_result_bonus_rows"):
		return
	var bonus = _pt.call("_build_result_bonus_rows", _panel, [
		{"name": "宝牌 ×2", "han": 2},
		{"name": "附加番", "han": 1},
	], 1.4)
	assert_eq(bonus.name, "BonusRows")
	assert_eq(bonus.get_child_count(), 2)
	assert_eq(_pt._result_anim_tweens.size(), 1,
		"多个 bonus 行必须同时出现，不能逐行新增 phase")
	for row in bonus.get_children():
		assert_eq(row.get_meta("reference_reveal_delay_ms", -1), 1400)
		assert_eq(row.get_meta("reference_reveal_duration_ms", -1), 260)


func test_result_bonus_rows_expose_total_dora_and_ability_increment() -> void:
	assert_true(_pt.has_method("_result_bonus_rows"),
		"确认结算必须从权威 WIN_DECLARED 明细生成通用 bonus 行")
	if not _pt.has_method("_result_bonus_rows"):
		return
	var rows: Array = _pt.call("_result_bonus_rows", {
		"han": 4,
		"dora_count": 3,
		"ability_extra_dora_count": 2,
	}, [{"name": "立直", "han": 1}])
	assert_eq(rows, [{"name": "宝牌（含能力额外 +2）", "han": 3}],
		"结算页必须明确展示总 Dora，且说明其中能力增量；不得混称附加番")
	var ordinary: Array = _pt.call("_result_bonus_rows", {
		"han": 3,
		"dora_count": 0,
		"ability_extra_dora_count": 0,
	}, [{"name": "立直", "han": 1}])
	assert_eq(ordinary, [{"name": "附加番", "han": 2}],
		"非 Dora 的既有 bonus 仍使用通用附加番，不猜测来源")
	var mixed: Array = _pt.call("_result_bonus_rows", {
		"han": 7,
		"dora_count": 6,
		"ability_extra_dora_count": 2,
		"ability_extra_red_dora_count": 2,
	}, [{"name": "立直", "han": 1}])
	assert_eq(mixed, [
		{"name": "宝牌（含能力额外 +2）", "han": 4},
		{"name": "赤宝牌（能力额外 +2）", "han": 2},
	], "普通能力 Dora 与能力赤 Dora 必须分行归因，总番不得重复计算")


func test_total_waits_extra_1000ms_and_enters_in_420ms() -> void:
	assert_true(_pt.has_method("_result_total_reveal_delay"))
	assert_true(_pt.has_method("_build_result_total_bar"))
	if not _pt.has_method("_result_total_reveal_delay") \
			or not _pt.has_method("_build_result_total_bar"):
		return
	var no_bonus_delay: float = _pt.call("_result_total_reveal_delay", 2, false)
	var with_bonus_delay: float = _pt.call("_result_total_reveal_delay", 2, true)
	assert_almost_eq(no_bonus_delay, 2.4, 0.001,
		"2 个役各 700ms 后，total 额外等待 1000ms")
	assert_almost_eq(with_bonus_delay, 3.1, 0.001,
		"bonus 作为单一 700ms phase 后，total 再等 1000ms")
	var total_bar = _pt.call("_build_result_total_bar",
		_panel, 9, 16000, no_bonus_delay)
	assert_eq(total_bar.get_meta("reference_reveal_delay_ms", -1), 2400)
	assert_eq(total_bar.get_meta("reference_reveal_duration_ms", -1), 420)
	assert_eq(total_bar.modulate.a, 0.0)

func test_yaku_rows_do_not_cap_phase_count():
	var many: Array = []
	for i in range(11):
		many.append({"name": "役%d" % i, "han": 1})
	_pt._build_yaku_rows(_panel, many)
	var grid: VBoxContainer = null
	for child in _panel.get_children():
		if child is VBoxContainer:
			grid = child
	assert_eq(grid.get_child_count(), 11,
		"phase_count 直接使用 yaku.length，不得截断为 8 条")
	assert_eq(_pt._result_anim_tweens.size(), 11)
	if grid.get_child_count() >= 11:
		assert_eq(grid.get_child(10).get_meta("reference_reveal_delay_ms"), 7700)

func test_four_score_rows_order_and_before_formula() -> void:
	assert_true(_pt.has_method("_build_score_delta_list"),
		"Step 2 必须使用四家分数列表")
	if not _pt.has_method("_build_score_delta_list"):
		return
	var final_scores := [23000, 29000, 24000, 24000]
	var payments := [-2000, 4000, -1000, -1000]
	var score_list = _pt.call("_build_score_delta_list",
		_panel, final_scores, payments, 2)
	assert_eq(score_list.name, "ScoreDeltaList")
	assert_eq(score_list.get_child_count(), 4)
	var ordered_seats: Array[int] = []
	for row in score_list.get_children():
		ordered_seats.append(int(row.get_meta("seat_id", -1)))
	assert_eq(ordered_seats, [2, 3, 0, 1],
		"四家必须从庄家开始按相对座位顺序排列")
	var dealer_row := score_list.get_child(0) as Control
	assert_eq((dealer_row.get_node("Before") as Label).text, "25000",
		"before 必须严格等于 final - payment")
	assert_eq((dealer_row.get_node("After") as Label).text, "25000",
		"滚分首帧的 after 从 before 开始")
	assert_eq((dealer_row.get_node("Delta") as Label).text, "0")
	var winner_row := score_list.get_child(3) as Control
	assert_eq((winner_row.get_node("Before") as Label).text, "25000")
	await wait_seconds(0.75)
	var rolling_after := int((winner_row.get_node("After") as Label).text)
	assert_gt(rolling_after, 27000,
		"1500ms cubic-out 在半程应超过线性中点")
	assert_lt(rolling_after, 29000)
	await wait_seconds(0.85)
	assert_eq((winner_row.get_node("After") as Label).text, "29000")
	assert_eq((winner_row.get_node("Delta") as Label).text, "+4000")

func test_skip_jumps_to_final_state():
	_pt._build_yaku_rows(_panel, [{"name": "立直", "han": 1}])
	var consumed: bool = _pt._skip_result_animations()
	assert_true(consumed, "动画在播时点击被消费(不关面板)")
	for child in _panel.get_children():
		if child is VBoxContainer:
			for row in child.get_children():
				assert_eq((row as CanvasItem).modulate.a, 1.0, "役行跳到不透明")
	# 第二次点击:无动画 → 返 false(调用方关面板)
	assert_false(_pt._skip_result_animations())


func test_original_result_shell_keeps_final_hand_visible() -> void:
	assert_true(_pt.has_method("_create_result_modal_shell"),
		"结算必须有可测的生产 modal shell")
	if not _pt.has_method("_create_result_modal_shell"):
		return
	var shell: Dictionary = _pt._create_result_modal_shell()
	var bg := shell["backdrop"] as ColorRect
	var panel := shell["panel"] as Panel
	assert_eq(bg.color, Color("00000055"), "低透明背幕保留最终牌面可读性")
	assert_eq(panel.position, TableLayout.RESULT_PANEL_RECT.position,
		"结算层位于桌心偏上且避开手牌/操作带")
	assert_eq(panel.size, Vector2(900, 650))
	var style := panel.get_theme_stylebox("panel") as StyleBoxFlat
	assert_eq(style.bg_color, Color("111217f5"))
	assert_eq(style.border_color, Color("8f7047"))
	assert_eq(style.border_width_left, 1)
	assert_eq(style.corner_radius_top_left, 12)
	assert_eq(style.content_margin_left, 36.0)
	assert_eq(style.content_margin_top, 28.0)
	assert_eq(style.content_margin_right, 36.0)
	assert_eq(style.content_margin_bottom, 24.0)
	var felt := panel.get_node_or_null("FeltGradient") as ColorRect
	assert_not_null(felt, "FeltGradient 节点与结算层结构必须保留")
	if felt != null:
		assert_true(felt.visible, "黑曜薄漆材质层不得以隐藏规避旧绿毡")
		assert_true(felt.material is ShaderMaterial)
		var material := felt.material as ShaderMaterial
		var lacquer_top_value: Variant = material.get_shader_parameter("lacquer_top")
		var lacquer_bottom_value: Variant = material.get_shader_parameter("lacquer_bottom")
		var inner_line_value: Variant = material.get_shader_parameter("inner_line")
		assert_true(lacquer_top_value is Color, "FeltGradient 必须暴露黑曜薄漆顶色")
		assert_true(lacquer_bottom_value is Color, "FeltGradient 必须暴露黑曜薄漆底色")
		assert_true(inner_line_value is Color, "FeltGradient 必须保留克制内暗线")
		if not lacquer_top_value is Color or not lacquer_bottom_value is Color \
				or not inner_line_value is Color:
			return
		var lacquer_top := lacquer_top_value as Color
		var lacquer_bottom := lacquer_bottom_value as Color
		var inner_line := inner_line_value as Color
		assert_lt(lacquer_top.get_luminance(), 0.12)
		assert_lt(lacquer_bottom.get_luminance(), 0.08)
		assert_lt(inner_line.get_luminance(), lacquer_bottom.get_luminance())


func test_result_overlay_escape_does_not_open_settings_or_close_result() -> void:
	var shell: Dictionary = _pt._create_result_modal_shell()
	var overlay := shell["overlay"] as Control
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	get_viewport().push_input(escape)
	await get_tree().process_frame
	assert_true(is_instance_valid(overlay))
	assert_null(get_tree().root.get_node_or_null("_settings_overlay_root"),
		"局结算期间 Esc 不得在其上打开设置层")


func test_result_detail_tabs_show_yaku_fu_formula_and_payment() -> void:
	assert_true(_pt.has_method("_build_result_detail_tabs"))
	if not _pt.has_method("_build_result_detail_tabs"):
		return
	var tabs: TabContainer = _pt.call("_build_result_detail_tabs", _panel, {
		"han": 3,
		"fu": 40,
		"base_points": 1280,
		"is_tsumo": false,
		"winner_seat": 1,
		"discarder_seat": 2,
		"payout": {2: 5200},
		"winner_total": 5200,
		"yaku_names": [{"name": "立直", "han": 1}],
		"fu_breakdown": {
			"raw_fu": 38,
			"rounded_fu": 40,
			"items": [
				{"key": "base", "label": "副底", "fu": 20},
				{"key": "menzen_ron", "label": "门清荣和", "fu": 10},
			],
		},
	})
	assert_eq(tabs.name, "ResultDetailTabs")
	assert_eq(tabs.get_tab_title(0), "役种")
	assert_eq(tabs.get_tab_title(1), "番符明细")
	var copy := ""
	for label in tabs.find_children("*", "Label", true, false):
		copy += " " + (label as Label).text
	for required in ["立直", "40符 3番", "副底", "38符", "40 × 2^(3+2)", "5200点"]:
		assert_true(copy.contains(required), "结算双页签缺少：%s" % required)


func test_result_winner_portrait_uses_real_texture_and_named_placeholder() -> void:
	assert_true(_pt.has_method("_build_result_winner_portrait"))
	if not _pt.has_method("_build_result_winner_portrait"):
		return
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	var portrait: Control = _pt.call("_build_result_winner_portrait", _panel, texture, "林夜澈")
	await get_tree().process_frame
	assert_eq(portrait.name, "WinnerPortraitStage")
	var art := portrait.get_node_or_null("WinnerPortrait") as TextureRect
	assert_not_null(art)
	assert_eq(art.texture, texture)
	assert_eq(art.stretch_mode, TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
	assert_eq(art.size, Vector2(208, 330), "立绘必须缩放到舞台范围，不能按原图尺寸溢出或被裁成空白")
	assert_eq((portrait.get_node("WinnerName") as Label).text, "林夜澈")


func test_result_portrait_resolves_character_art_to_transparent_cutout() -> void:
	var character: Character = CharacterPool.all()[0]
	var source := load(character.portrait_path) as Texture2D
	var resolved: Texture2D = _pt.call("_result_cutout_texture", source)
	assert_not_null(resolved)
	assert_eq(resolved.resource_path,
		"res://assets/ui/lobby_stage/resident_lin_yeche_cutout.png")
	var second: Character = CharacterPool.all()[1]
	var second_resolved: Texture2D = _pt.call("_result_cutout_texture",
		load(second.portrait_path) as Texture2D)
	assert_eq(second_resolved.resource_path,
		"res://assets/roguelike/characters/char_qiu_jue_cutout.png")


func test_table_rules_entry_opens_yaku_codex_page() -> void:
	assert_true(_pt.has_method("_open_yaku_codex"))
	if not _pt.has_method("_open_yaku_codex"):
		return
	_pt.call("_open_yaku_codex")
	await get_tree().process_frame
	var overlay := get_tree().root.get_node_or_null("_yaku_codex_overlay_root")
	assert_not_null(overlay)
	if overlay != null:
		assert_eq(overlay.call("get_current_page"), &"yaku")
		overlay.queue_free()


func test_result_hand_tiles_keep_readable_modal_size() -> void:
	var tile := _pt._make_overlay_tile(TileId.W1, false)
	add_child_autofree(tile)
	assert_eq(tile.custom_minimum_size, Vector2(34, 45), "modal win hand 固定 34×45")


func test_win_result_reuses_flat_meld_with_34x45_tiles() -> void:
	var bc := PlayableBattleController.new(20260720)
	var called := Tile.new(TileId.W3, false, Tile.NO_OWNER, 3001)
	assert_true(bc.state.seats[0].melds.add_existing(Meld.make_chi([
		Tile.new(TileId.W2, false, Tile.NO_OWNER, 3000),
		called,
		Tile.new(TileId.W4, false, Tile.NO_OWNER, 3002),
	], 3, 0, called)))
	bc.state.seats[0].hand = Hand.new()
	for id in [
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.S6, TileId.S7, TileId.W5, TileId.W5,
	]:
		bc.state.seats[0].hand.add(Tile.new(id))
	_pt._bc = bc
	var strip := _pt._render_winning_hand_strip(_panel, 0, TileId.W1, false, 0)
	var flat_melds := strip.get_node_or_null("FlatMelds")
	assert_not_null(flat_melds,
		"mP win modal 必须复用 Fl(flat:true)，不能全部竖直 append")
	if flat_melds == null:
		return
	var slots := flat_melds.find_children("*", "Control", true, false).filter(
		func(node: Node) -> bool:
			return bool(node.get_meta("flat_meld_tile", false)))
	assert_eq(slots.size(), 3)
	assert_eq(slots.map(func(slot: Control):
		return bool(slot.get_meta("horizontal"))), [true, false, false])
	assert_eq(slots[0].get_meta("visual_size"), Vector2(45, 34),
		"win modal 横牌使用 34×45 override 后的 45×34 bbox")
	var called_face := slots[0].get_node_or_null("Face") as Control
	assert_not_null(called_face)
	if called_face != null:
		assert_eq(called_face.custom_minimum_size, Vector2(34, 45),
			"win flat meld 仍在 .modal__win-hand 34×45 scope 内")
		assert_eq(called_face.rotation_degrees, -90.0)


func test_win_result_waits_for_continue_before_score_roll() -> void:
	var bc := PlayableBattleController.new(20260720)
	var win_tile := TileSkillAnchor.make(Tile.new(TileId.W1), 0)
	var win := BattleEvent.make(&"WIN_DECLARED", 0, win_tile, {
		"han": 3,
		"fu": 40,
		"winner_total": 8000,
		"discarder_seat": -1,
		"payout": {1: 2000, 2: 2000, 3: 4000},
		"yaku_names": [{"name": "立直", "han": 1}],
	})
	bc.events = [win]
	_pt._bc = bc
	var announce_overlapped_mount := {"value": false}
	_pt.child_entered_tree.connect(func(child: Node) -> void:
		if child.name != "ResultOverlay":
			return
		for existing in _pt.get_children():
			if existing is CallAnnounce and not existing.is_queued_for_deletion():
				announce_overlapped_mount["value"] = true)
	# 生产 polling loop 在下一 process_frame 才消费刚确认的 WIN_DECLARED。
	get_tree().process_frame.connect(func() -> void:
		CallAnnounce.play(_pt, &"tsumo", 0), CONNECT_ONE_SHOT)
	_pt._show_hand_result_overlay({"last_event": "TSUMO_DECLARED"})
	await wait_seconds(2.75)
	assert_null(_pt.get_node_or_null("ResultOverlay"),
		"确认 WIN_DECLARED 后 3000ms 前不得挂载 result modal")
	assert_true(_pt.get_children().any(func(child: Node) -> bool:
		return child is CallAnnounce), "门控期间应仍在播放 win announce")
	await wait_seconds(0.40)
	var overlay := _pt.get_node_or_null("ResultOverlay") as Control
	assert_not_null(overlay, "3000ms 门控完成后必须挂载 result modal")
	assert_false(bool(announce_overlapped_mount["value"]),
		"modal 挂载瞬间不得与下一帧才创建的 win announce 重叠")
	var panel := overlay.get_node("ResultModal") as Panel
	assert_null(panel.get_node_or_null("ScoreDeltaList"),
		"Step 1 只能显示番种，不得提前启动 1500ms 滚分")
	assert_null(panel.get_node_or_null("RollingScore"),
		"Step 2 不得退回胜者单数字")
	var buttons := panel.find_children("*", "Button", true, false)
	assert_eq(buttons.size(), 1, "Step 1 仅保留显式继续按钮")
	var button := buttons[0] as Button
	assert_eq(button.text, "继续 →")
	button.pressed.emit()
	await get_tree().process_frame
	var score_list := panel.get_node_or_null("ScoreDeltaList") as VBoxContainer
	assert_not_null(score_list,
		"点击继续时才挂载四家 1500ms 滚分列表")
	assert_eq(score_list.get_child_count(), 4)
	assert_null(panel.get_node_or_null("RollingScore"))
	assert_false((panel.get_node("ResultDetailTabs") as Control).visible)
	assert_eq(button.text, "确定")
	var winner_row := score_list.get_node("ScoreDeltaSeat0") as Control
	assert_eq((winner_row.get_node("Before") as Label).text, "25000")
	_pt._skip_result_animations()
	assert_eq((winner_row.get_node("After") as Label).text, "33000")
	assert_eq((winner_row.get_node("Delta") as Label).text, "+8000")
	var payer_row := score_list.get_node("ScoreDeltaSeat1") as Control
	assert_eq((payer_row.get_node("After") as Label).text, "23000")
	assert_eq((payer_row.get_node("Delta") as Label).text, "-2000")
	button.pressed.emit()
	await get_tree().process_frame
	assert_true(not is_instance_valid(overlay) or overlay.is_queued_for_deletion())
