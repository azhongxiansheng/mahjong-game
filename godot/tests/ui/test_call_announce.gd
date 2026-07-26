extends GutTest

# 原创结界舞台宣告层：只约束安全区、可读性与生命周期。


func test_kind_style_covers_supported_table_events() -> void:
	for kind in [&"chi", &"pon", &"minkan", &"ankan", &"added_kan",
			&"riichi", &"tsumo", &"ron", &"chankan"]:
		assert_true(CallAnnounce.KIND_STYLE.has(kind), "缺 kind: %s" % kind)
		var style: Array = CallAnnounce.KIND_STYLE[kind]
		assert_eq(style.size(), 3)
		assert_true(style[0] is String and (style[0] as String).length() > 0)
		assert_true(style[1] is Color)
		assert_true(int(style[2]) >= 40 and int(style[2]) <= 56,
			"字号须在窄带/短印记的可读范围内")
	for unsupported_kind in [&"yakuman", &"kyuusyu", &"ryuukyoku"]:
		assert_false(CallAnnounce.KIND_STYLE.has(unsupported_kind))


func test_four_seat_marks_use_distinct_directions_and_safe_anchors() -> void:
	var dirs := {}
	for seat_id in range(4):
		assert_true(CallAnnounce.SEAT_LAYOUT.has(seat_id))
		var anchor: Vector2 = CallAnnounce.SEAT_LAYOUT[seat_id][0]
		var direction: Vector2 = CallAnnounce.SEAT_LAYOUT[seat_id][1]
		dirs[direction] = true
		var mark := Rect2(anchor - CallAnnounce.CALL_MARK_SIZE / 2.0,
			CallAnnounce.CALL_MARK_SIZE)
		for public_zone in TableLayout.crowded_state_rects():
			assert_false(mark.intersects(public_zone, false))
		assert_false(mark.intersects(TableLayout.ACTION_BAR_RECT, false))
		assert_false(mark.intersects(TableLayout.HAND_SAFE_RECT, false))
	assert_eq(dirs.size(), 4, "四席滑入方向应各不相同")


func test_motion_contract_stays_presentational() -> void:
	assert_eq(CallAnnounce.CALL_SLIDE_DIST, 24.0)
	assert_eq(CallAnnounce.CALL_SLIDE_TIME, 0.5)
	assert_eq(CallAnnounce.WIN_SLIDE_DIST, 32.0)
	assert_eq(CallAnnounce.WIN_SLIDE_TIME, 0.65)
	assert_eq(CallAnnounce.CALL_LIFETIME, 1.38)
	assert_eq(CallAnnounce.WIN_LIFETIME, 3.0)
	assert_lt(CallAnnounce.CALL_SLIDE_TIME, CallAnnounce.CALL_LIFETIME)
	assert_lt(CallAnnounce.WIN_SLIDE_TIME, CallAnnounce.WIN_LIFETIME)


func test_copy_and_fonts_cover_all_announce_characters() -> void:
	var expected := {
		&"chi": ["吃", Color("2eb872"), 46],
		&"pon": ["碰", Color("2e8fd9"), 46],
		&"minkan": ["杠", Color("e8731f"), 46],
		&"riichi": ["听", Color("e8c45a"), 46],
		&"tsumo": ["自摸", Color("e63a28"), 52],
		&"ron": ["荣和", Color("e63a28"), 52],
		&"chankan": ["抢杠", Color("ef8528"), 52],
	}
	for kind in expected:
		assert_eq(CallAnnounce.KIND_STYLE[kind], expected[kind])
	assert_true(CallAnnounce.RIICHI_FONT.has_char(ord("听")))
	for character in "吃碰杠自摸荣和抢":
		assert_true(CallAnnounce.CALL_FONT.has_char(ord(character)),
			"Liu Jian Mao Cao 子集缺字: %s" % character)


func test_play_unknown_kind_returns_null() -> void:
	var parent := Control.new()
	add_child_autofree(parent)
	assert_null(CallAnnounce.play(parent, &"nonsense", 0))
	assert_null(CallAnnounce.play(null, &"pon", 0))


func test_regular_call_creates_non_blocking_overlay_and_self_frees() -> void:
	var parent := Control.new()
	add_child_autofree(parent)
	var call := CallAnnounce.play(parent, &"pon", 1)
	assert_not_null(call)
	assert_eq(call.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	var main := call.get_node_or_null("MainText") as Label
	assert_not_null(main)
	if main != null:
		assert_eq(main.label_settings.font_color, Color.WHITE)
		assert_eq(main.label_settings.outline_color, Color("2e8fd9"))
		assert_eq(main.label_settings.font_size, 46)
	assert_not_null(call.get_node_or_null("Halo"))
	await wait_seconds(1.8)
	assert_false(is_instance_valid(call), "普通鸣牌结束应自毁")


func test_regular_and_win_avatars_stay_compact_and_horizontal() -> void:
	var parent := Control.new()
	add_child_autofree(parent)
	var texture := PlaceholderTexture2D.new()
	texture.size = Vector2(64, 80)
	for spec in [[&"chi", 0, 6.0, false], [&"ron", 2, 10.0, true]]:
		var call := CallAnnounce.play(parent,
			StringName(spec[0]), int(spec[1]), texture)
		await get_tree().process_frame
		var avatar := call.get_node_or_null("Avatar") as TextureRect
		var main := call.get_node_or_null("MainText") as Label
		assert_not_null(avatar)
		assert_not_null(main)
		if avatar != null and main != null:
			assert_eq(avatar.size, Vector2(48, 48))
			assert_almost_eq(main.position.x - (avatar.position.x + avatar.size.x),
				float(spec[2]), 0.01)
		assert_eq(call.get_meta("layout_direction"), "row")
		assert_eq(bool(call.get_meta("is_win_announce")), bool(spec[3]))


func test_effect_colors_halo_and_ring_sizes_match_impact_levels() -> void:
	assert_eq(CallAnnounce.CALL_EFFECT_STYLE[&"pon"], {
		"halo": Color("78befabf"), "shock": Color("aad7ffe6")})
	assert_eq(CallAnnounce.WIN_EFFECT_STYLE[&"ron"], {
		"halo": Color("f06e5ad1"), "shock": Color("ffc882f2")})
	assert_eq(CallAnnounce.CALL_HALO_KEYFRAMES,
		[[0.0, 0.0, 32.0, 0.5], [0.35, 1.0, 24.0, 1.4],
			[1.0, 0.55, 22.0, 1.1]])
	var parent := Control.new()
	add_child_autofree(parent)
	var regular := CallAnnounce.play(parent, &"pon", 1)
	var win := CallAnnounce.play(parent, &"ron", 1)
	assert_eq(regular._ring_end_diameter, CallAnnounce.CALL_MARK_SIZE.x)
	assert_lte(win._ring_end_diameter, CallAnnounce.WIN_SAFE_RECT.size.y,
		"和牌冲击环不得溢出高冲击窄带")


func test_cubic_bezier_solver_is_stable() -> void:
	assert_almost_eq(CallAnnounce.sample_cubic_bezier(
		0.5, 0.16, 1.0, 0.3, 1.0), 0.9717791, 0.00001)
	assert_almost_eq(CallAnnounce.sample_cubic_bezier(
		0.5, 0.2, 0.7, 0.3, 1.0), 0.9099721, 0.00001)
