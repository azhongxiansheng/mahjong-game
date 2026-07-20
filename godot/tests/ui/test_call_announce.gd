extends GutTest

# T1 宣告演出(spec 2026-06-11 G1)— CallAnnounce 生命周期与配置测试。

func test_kind_style_covers_all_kinds():
	for kind in [&"chi", &"pon", &"minkan", &"ankan", &"added_kan",
			&"riichi", &"tsumo", &"ron", &"chankan"]:
		assert_true(CallAnnounce.KIND_STYLE.has(kind), "缺 kind: %s" % kind)
		var style: Array = CallAnnounce.KIND_STYLE[kind]
		assert_eq(style.size(), 3, "%s 应有 [文案, 描边色, 字号]" % kind)
		assert_true(style[0] is String and (style[0] as String).length() > 0)
		assert_true(style[1] is Color)
		assert_true(int(style[2]) >= 72, "%s 字号应 ≥72(spec AC-G1-a)" % kind)
	for non_reference_kind in [&"yakuman", &"kyuusyu", &"ryuukyoku"]:
		assert_false(CallAnnounce.KIND_STYLE.has(non_reference_kind),
			"公开 bundle 未把 %s 交给 CallAnnounce" % non_reference_kind)


func test_seat_layout_covers_4_seats_with_distinct_directions():
	var dirs := {}
	for s in range(4):
		assert_true(CallAnnounce.SEAT_LAYOUT.has(s))
		var dir: Vector2 = CallAnnounce.SEAT_LAYOUT[s][1]
		dirs[dir] = true
	assert_eq(dirs.size(), 4, "四座位滑入方向应各不相同")


func test_reference_1600x900_anchor_and_motion_contract():
	var expected := {
		0: Vector2(800, 650),
		1: Vector2(1120, 396),
		2: Vector2(800, 200),
		3: Vector2(480, 396),
	}
	for seat_id in range(4):
		assert_eq(CallAnnounce.SEAT_LAYOUT[seat_id][0], expected[seat_id],
			"宣告锚点必须直接对齐参考站 1600×900 构图")
	assert_eq(CallAnnounce.CALL_SLIDE_DIST, 24.0)
	assert_eq(CallAnnounce.CALL_SLIDE_TIME, 0.5)
	assert_eq(CallAnnounce.WIN_SLIDE_DIST, 32.0)
	assert_eq(CallAnnounce.WIN_SLIDE_TIME, 0.65)
	assert_eq(CallAnnounce.CALL_HALO_TIME, 1.1)
	assert_eq(CallAnnounce.WIN_HALO_TIME, 1.4)
	assert_eq(CallAnnounce.CALL_SHOCK_TIME, 0.75)
	assert_eq(CallAnnounce.WIN_SHOCK_TIME, 1.0)


func test_reference_call_style_contract():
	var expected := {
		&"chi": ["吃", Color("2eb872"), 96],
		&"pon": ["碰", Color("2e8fd9"), 96],
		&"minkan": ["杠", Color("e8731f"), 96],
		&"riichi": ["听", Color("e8c45a"), 96],
		&"tsumo": ["自摸", Color("e63a28"), 108],
		&"ron": ["荣和", Color("e63a28"), 108],
		&"chankan": ["抢杠", Color("ef8528"), 108],
	}
	for kind in expected:
		assert_eq(CallAnnounce.KIND_STYLE[kind], expected[kind],
			"宣告字、颜色、字号不得自行改写")
	assert_true(CallAnnounce.RIICHI_FONT.has_char(ord("听")),
		"Ma Shan Zheng 子集必须包含参考立直文案“听”")
	for character in "吃碰杠自摸荣和抢":
		assert_true(CallAnnounce.CALL_FONT.has_char(ord(character)),
			"Liu Jian Mao Cao 子集缺字: %s" % character)

func test_play_unknown_kind_returns_null():
	var parent := Control.new()
	add_child_autofree(parent)
	assert_null(CallAnnounce.play(parent, &"nonsense", 0))
	assert_null(CallAnnounce.play(null, &"pon", 0))

func test_play_creates_overlay_and_self_frees():
	var parent := Control.new()
	add_child_autofree(parent)
	var ca := CallAnnounce.play(parent, &"pon", 1)
	assert_not_null(ca)
	assert_true(ca.get_parent() == parent)
	assert_eq(ca.mouse_filter, Control.MOUSE_FILTER_IGNORE, "演出层不阻塞点击")
	# 主字存在且用白字 + kind 配色描边
	var main: Label = ca.get_node_or_null("MainText")
	assert_not_null(main, "应有 MainText 主字层")
	assert_eq(main.label_settings.font_color, Color.WHITE)
	assert_eq(main.label_settings.outline_color, Color("2e8fd9"), "碰 = 参考蓝描边")
	assert_eq(main.label_settings.outline_size, 9, "普通宣告固定 9px 描边")
	assert_not_null(ca.get_node_or_null("Halo"), "CSS ::before 等价为单层光晕")
	assert_null(ca.get_node_or_null("Halo0"), "不得保留自创三层 halo")
	# 本地鸣牌状态由参考调度 900ms + 480ms 后清除。
	await wait_seconds(1.8)
	assert_false(is_instance_valid(ca), "演出结束应自毁(无孤儿)")

func test_play_with_avatar_adds_texture_rect():
	var parent := Control.new()
	add_child_autofree(parent)
	var tex := PlaceholderTexture2D.new()
	tex.size = Vector2(64, 80)
	var ca := CallAnnounce.play(parent, &"ron", 2, tex)
	assert_not_null(ca)
	var avatar := ca.get_node_or_null("Avatar") as TextureRect
	assert_not_null(avatar)
	assert_eq(avatar.size, Vector2(220, 220), "和牌宣告头像固定 220×220")
	var main := ca.get_node("MainText") as Label
	assert_almost_eq(main.position.y - (avatar.position.y + avatar.size.y), 8.0, 0.01,
		"win-announce 必须头像在上、文字在下、gap 8px")
	assert_eq(ca.get_meta("layout_direction"), "column")
	assert_null(ca.get_node_or_null("AvatarFrame"), "参考头像没有自创金框")
	await wait_seconds(1.8)
	assert_true(is_instance_valid(ca), "和牌常规结束局面约显示 3000ms，不能复用 1380ms")


func test_regular_call_avatar_is_200_square():
	var parent := Control.new()
	add_child_autofree(parent)
	var tex := PlaceholderTexture2D.new()
	tex.size = Vector2(64, 80)
	var ca := CallAnnounce.play(parent, &"chi", 0, tex)
	assert_not_null(ca)
	var avatar := ca.get_node_or_null("Avatar") as TextureRect
	var main := ca.get_node_or_null("MainText") as Label
	assert_not_null(avatar)
	assert_not_null(main)
	assert_eq(avatar.size, Vector2(200, 200), "普通鸣牌宣告头像固定 200×200")
	assert_almost_eq(main.position.x - (avatar.position.x + avatar.size.x), 4.0, 0.01,
		"call-announce 横排仅 margin-right 4px")
	assert_eq(ca.get_meta("layout_direction"), "row")


func test_reference_halo_shock_colors_and_keyframes() -> void:
	assert_eq(CallAnnounce.CALL_EFFECT_STYLE[&"pon"], {
		"halo": Color("78befabf"), "shock": Color("aad7ffe6")})
	assert_eq(CallAnnounce.WIN_EFFECT_STYLE[&"ron"], {
		"halo": Color("f06e5ad1"), "shock": Color("ffc882f2")})
	assert_eq(CallAnnounce.WIN_EFFECT_STYLE[&"chankan"], {
		"halo": Color("ffaa5ad9"), "shock": Color("ffd78cf2")})
	assert_eq(CallAnnounce.CALL_HALO_KEYFRAMES,
		[[0.0, 0.0, 32.0, 0.5], [0.35, 1.0, 24.0, 1.4],
			[1.0, 0.55, 22.0, 1.1]])
	assert_eq(CallAnnounce.WIN_HALO_KEYFRAMES,
		[[0.0, 0.0, 48.0, 0.4], [0.35, 1.0, 36.0, 1.5],
			[1.0, 0.6, 34.0, 1.1]])
	assert_eq(CallAnnounce.CALL_SHOCK_KEYFRAMES,
		[[0.0, 0.0, 8.0, 40.0], [0.2, 1.0, 0.0, 0.0],
			[1.0, 0.0, 1.0, 460.0]])
	assert_eq(CallAnnounce.WIN_SHOCK_KEYFRAMES,
		[[0.0, 0.0, 10.0, 60.0], [0.2, 1.0, 0.0, 0.0],
			[1.0, 0.0, 1.0, 640.0]])


func test_reference_cubic_bezier_is_not_expo_approximation() -> void:
	assert_almost_eq(CallAnnounce.sample_cubic_bezier(0.5, 0.16, 1.0, 0.3, 1.0),
		0.9717791, 0.00001, "slide 精确 cubic-bezier(.16,1,.3,1)")
	assert_almost_eq(CallAnnounce.sample_cubic_bezier(0.5, 0.2, 0.7, 0.3, 1.0),
		0.9099721, 0.00001, "shock 精确 cubic-bezier(.2,.7,.3,1)")
