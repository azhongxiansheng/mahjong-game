extends GutTest

# PlayableTable._format_toast_text / _seat_short 静态 helper 单测。
# 关键事件 → 顶部 toast 文本；特殊胡牌役改走确认后的参考横幅。

const PT := preload("res://ui/four_player_table/playable_table.gd")


func _make_event(type: StringName, actor: int = -1, extra: Dictionary = {}) -> BattleEvent:
	var ev := BattleEvent.new()
	ev.type = type
	ev.actor_seat = actor
	ev.extra = extra
	return ev


# ---- _seat_short ----

func test_seat_short_player_is_you() -> void:
	assert_eq(PT._seat_short(0), "你")


func test_seat_short_ai_uses_index() -> void:
	assert_eq(PT._seat_short(1), "AI 1")
	assert_eq(PT._seat_short(3), "AI 3")


func test_seat_short_unknown_fallback() -> void:
	assert_eq(PT._seat_short(-1), "?")
	assert_eq(PT._seat_short(99), "?")


# ---- _format_toast_text ----

# T1(spec 2026-06-11 G1)起,立直/自摸/荣和由 CallAnnounce 大字演出承担,
# toast 通道返空,避免同一信息双通道重复闪。
func test_riichi_tsumo_ron_no_longer_use_toast() -> void:
	assert_eq(PT._format_toast_text(_make_event(&"RIICHI_DECLARED", 2)), "",
		"立直走 CallAnnounce,不再 toast")
	assert_eq(PT._format_toast_text(_make_event(&"TSUMO_DECLARED", 0)), "")
	assert_eq(PT._format_toast_text(_make_event(&"RON_DECLARED", 1)), "")


func test_exhaustive_draw_toast() -> void:
	assert_eq(PT._format_toast_text(_make_event(&"EXHAUSTIVE_DRAW")), "流局")


func test_haitei_houtei_wait_for_confirmed_moment_band() -> void:
	assert_eq(PT._format_toast_text(_make_event(&"HAITEI", 0)), "")
	assert_eq(PT._format_toast_text(_make_event(&"HOUTEI", 0)), "")


func test_game_begin_toast() -> void:
	assert_eq(PT._format_toast_text(_make_event(&"GAME_BEGIN")), "开局")


func test_playable_table_does_not_embed_specific_character_ids() -> void:
	var source := FileAccess.get_file_as_string(
		"res://ui/four_player_table/playable_table.gd")
	assert_false(source.contains("qiu_jue"), "牌桌不应认识具体 character_id")
	assert_false(source.contains("char_kaiji_passive_v1"), "牌桌不应认识具体 ability_id")
	assert_false(source.contains("lin_yeche"), "新增角色不得回到牌桌硬编码")
	assert_false(source.contains("char_akagi_passive_v1"), "新增能力不得回到牌桌硬编码")
	assert_false(source.contains("bai_touli"), "白透璃不得回到牌桌硬编码")
	assert_false(source.contains("char_washizu_passive_v1"), "白透璃能力不得回到牌桌硬编码")


func test_profile_feedback_reaches_real_toast_handler() -> void:
	var table = PT.new()
	add_child_autofree(table)
	table.bind_character_ids([&"qiu_jue", &"lin_yeche", &"bai_touli", &"hua_ling"])
	table._handle_event_toast(_make_event(&"SKILL_TRIGGERED", 0, {
		"skill_id": &"char_kaiji_passive_v1",
		"skill_name": "裘绝·绝崖翻盘",
	}))
	assert_not_null(table._toast_label)
	assert_eq(table._toast_label.text, "🔥 裘绝 · 绝崖翻盘　+2 番（点数 < 15000）")


func test_lin_yeche_profile_feedback_reaches_real_toast_handler() -> void:
	var table = PT.new()
	add_child_autofree(table)
	table.bind_character_ids([&"lin_yeche", &"qiu_jue", &"bai_touli", &"hua_ling"])
	table._handle_event_toast(_make_event(&"SKILL_TRIGGERED", 0, {
		"skill_id": &"char_akagi_passive_v1",
		"skill_name": "林夜彻·脊读鬼神",
	}))
	assert_not_null(table._toast_label)
	assert_eq(table._toast_label.text, "👁 林夜彻 · 脊读鬼神　透视下家手牌")


func test_bai_touli_profile_reaches_real_toast_and_reveal_strip_label() -> void:
	var table = PT.new()
	add_child_autofree(table)
	table.bind_character_ids([&"bai_touli", &"qiu_jue", &"lin_yeche", &"hua_ling"])
	table._handle_event_toast(_make_event(&"SKILL_TRIGGERED", 0, {
		"skill_id": &"char_washizu_passive_v1",
		"skill_name": "白透璃·万透镜华",
	}))
	assert_not_null(table._toast_label)
	assert_eq(table._toast_label.text, "🔮 白透璃 · 万透镜华　看破三家各两张手牌")
	for panel in table._table.seat_panels:
		assert_eq(panel.viewer_reveal_label(), "镜华")


func test_unknown_event_returns_empty() -> void:
	# 非关键事件不弹 toast (避免干扰)
	assert_eq(PT._format_toast_text(_make_event(&"TILE_DISCARDED", 0)), "")
	assert_eq(PT._format_toast_text(_make_event(&"PLAYER_ACTION", 0)), "")
