extends GutTest

# T1 宣告演出(spec 2026-06-11 G1)— CallAnnounce 生命周期与配置测试。

func test_kind_style_covers_all_9_kinds():
	for kind in [&"chi", &"pon", &"minkan", &"ankan", &"added_kan",
			&"riichi", &"tsumo", &"ron", &"yakuman"]:
		assert_true(CallAnnounce.KIND_STYLE.has(kind), "缺 kind: %s" % kind)
		var style: Array = CallAnnounce.KIND_STYLE[kind]
		assert_eq(style.size(), 3, "%s 应有 [文案, 描边色, 字号]" % kind)
		assert_true(style[0] is String and (style[0] as String).length() > 0)
		assert_true(style[1] is Color)
		assert_true(int(style[2]) >= 72, "%s 字号应 ≥72(spec AC-G1-a)" % kind)

func test_seat_layout_covers_4_seats_with_distinct_directions():
	var dirs := {}
	for s in range(4):
		assert_true(CallAnnounce.SEAT_LAYOUT.has(s))
		var dir: Vector2 = CallAnnounce.SEAT_LAYOUT[s][1]
		dirs[dir] = true
	assert_eq(dirs.size(), 4, "四座位滑入方向应各不相同")

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
	assert_eq(main.label_settings.outline_color, Color("3c8cbe"), "碰 = 蓝描边")
	assert_not_null(ca.get_node_or_null("Halo0"), "应有光晕层")
	# 生命周期:LIFETIME(1.25s)+ 余量后自毁
	await wait_seconds(1.8)
	assert_false(is_instance_valid(ca), "演出结束应自毁(无孤儿)")

func test_play_with_avatar_adds_texture_rect():
	var parent := Control.new()
	add_child_autofree(parent)
	var tex := PlaceholderTexture2D.new()
	tex.size = Vector2(64, 80)
	var ca := CallAnnounce.play(parent, &"ron", 2, tex)
	assert_not_null(ca)
	var found := false
	for child in ca.get_children():
		if child is TextureRect and (child as TextureRect).texture == tex:
			found = true
	assert_true(found, "传 avatar 时应有立绘节点")
