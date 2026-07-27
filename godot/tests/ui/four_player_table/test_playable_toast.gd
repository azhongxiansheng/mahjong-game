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
	assert_false(source.contains("hua_ling"), "华岭澄不得回到牌桌硬编码")
	assert_false(source.contains("char_saki_passive_v1"), "华岭澄能力不得回到牌桌硬编码")
	assert_false(source.contains("ying_li"), "状态胶囊仍须由 profile 驱动")
	assert_false(source.contains("char_momoko_passive_v1"), "牌桌不得识别影立静 ability_id")
	assert_false(source.contains("bao_luo"), "宝络绯不得回到牌桌硬编码")
	assert_false(source.contains("char_kuro_passive_v1"), "宝络绯能力不得回到牌桌硬编码")
	assert_false(source.contains("lian_yao"), "连曜真状态不得回到牌桌硬编码")
	assert_false(source.contains("char_teru_passive_v1"), "连曜真能力不得回到牌桌硬编码")


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


func test_hua_ling_profile_feedback_reaches_real_toast_handler() -> void:
	var table = PT.new()
	add_child_autofree(table)
	table.bind_character_ids([&"hua_ling", &"qiu_jue", &"bai_touli", &"lin_yeche"])
	table._handle_event_toast(_make_event(&"SKILL_TRIGGERED", 0, {
		"skill_id": &"char_saki_passive_v1",
		"skill_name": "华岭澄·宝华绽放",
	}))
	assert_not_null(table._toast_label)
	if table._toast_label == null:
		return
	assert_eq(table._toast_label.text, "✦ 华岭澄 · 宝华绽放　+2 Dora")
	assert_eq(table._toast_label.get_theme_color("font_color"), Color("7fe0c3"))


func test_ying_li_real_primed_state_reaches_top_safe_status_capsule() -> void:
	var bc := PlayableBattleController.new(343)
	assert_true(BossAbilityFactory.inject(
		bc.registry, &"char_momoko_passive_v1", 2))
	bc.call("_emit", &"RIICHI_DECLARED", 2, null, {})

	var table = PT.new()
	add_child_autofree(table)
	table.set("_reward_local_seat", 2)
	table.bind_character_ids([&"qiu_jue", &"bai_touli", &"ying_li", &"hua_ling"])
	table.set("_bc", bc)
	table.call("_sync_character_status")
	var capsule := table.get_node_or_null("CharacterStatusBadge") as Control
	assert_not_null(capsule)
	if capsule == null:
		return
	assert_true(capsule.visible)
	assert_eq(String(capsule.call("status_text")), "消影一发 · 潜伏中")
	var rect := capsule.get_rect()
	assert_gte(rect.position.y, 0.0)
	assert_lte(rect.end.y, TableLayout.TOP_BAR_H,
		"状态胶囊不得下探到牌桌")
	assert_lte(rect.end.x, TableLayout.TABLE_W - 196.0,
		"状态胶囊不得覆盖规则/设置按钮")

	bc.call("_emit", &"WIN_DECLARED_PRE", 2, null, {})
	table.call("_sync_character_status")
	assert_false(capsule.visible, "能力消费后胶囊必须消失")


func test_bao_luo_profile_feedback_reaches_existing_top_safe_toast() -> void:
	var table = PT.new()
	add_child_autofree(table)
	table.bind_character_ids([&"bao_luo", &"qiu_jue", &"bai_touli", &"hua_ling"])
	table._handle_event_toast(_make_event(&"SKILL_TRIGGERED", 0, {
		"skill_id": &"char_kuro_passive_v1",
		"skill_name": "宝络绯·赤线缠宝",
		"extra_red_dora_delta": 2,
	}))
	assert_not_null(table._toast_label)
	if table._toast_label == null:
		return
	assert_eq(table._toast_label.text, "♦ 宝络绯 · 赤线缠宝　+2 赤 Dora")
	assert_eq(table._toast_label.get_theme_color("font_color"), Color("ff5b6e"))
	assert_eq(table._toast_label.position, Vector2(420, 12),
		"必须复用既有顶部安全区，不改变牌桌布局")


func test_lian_yao_real_streak_reaches_top_safe_dynamic_status_capsule() -> void:
	var bc := PlayableBattleController.new(349)
	assert_true(BossAbilityFactory.inject(
		bc.registry, &"char_teru_passive_v1", 1))
	bc.call("_emit", &"WIN_DECLARED_PRE", 1, null, {})
	bc.call("_emit", &"WIN_DECLARED_PRE", 1, null, {})

	var table = PT.new()
	add_child_autofree(table)
	table.set("_reward_local_seat", 1)
	table.bind_character_ids([&"qiu_jue", &"lian_yao", &"bai_touli", &"hua_ling"])
	table.set("_bc", bc)
	table.call("_sync_character_status")
	var capsule := table.get_node_or_null("CharacterStatusBadge") as Control
	assert_not_null(capsule)
	if capsule == null:
		return
	assert_true(capsule.visible)
	assert_eq(String(capsule.call("status_text")), "叠曜 2 层 · 本次 +2 番")
	var rect := capsule.get_rect()
	assert_gte(rect.position.y, 0.0)
	assert_lte(rect.end.y, TableLayout.TOP_BAR_H)
	assert_lte(rect.end.x, TableLayout.TABLE_W - 196.0)

	bc.call("_emit", &"EXHAUSTIVE_DRAW", -1, null, {})
	table.call("_sync_character_status")
	assert_false(capsule.visible, "流局重置后状态胶囊必须立即消失")


func test_unknown_event_returns_empty() -> void:
	# 非关键事件不弹 toast (避免干扰)
	assert_eq(PT._format_toast_text(_make_event(&"TILE_DISCARDED", 0)), "")
	assert_eq(PT._format_toast_text(_make_event(&"PLAYER_ACTION", 0)), "")
