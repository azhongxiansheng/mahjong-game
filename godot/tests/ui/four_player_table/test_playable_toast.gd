extends GutTest

# PlayableTable._format_toast_text / _seat_short 静态 helper 单测。
# 关键事件 → 顶部 toast 文本(立直/自摸/荣和/流局/海底/河底/开局)。

const PT := preload("res://ui/four_player_table/playable_table.gd")


func _make_event(type: StringName, actor: int = -1) -> BattleEvent:
	var ev := BattleEvent.new()
	ev.type = type
	ev.actor_seat = actor
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

func test_riichi_toast_includes_seat() -> void:
	var s := PT._format_toast_text(_make_event(&"RIICHI_DECLARED", 2))
	assert_true(s.find("立直") >= 0)
	assert_true(s.find("AI 2") >= 0)


func test_tsumo_toast_player() -> void:
	var s := PT._format_toast_text(_make_event(&"TSUMO_DECLARED", 0))
	assert_true(s.find("自摸") >= 0)
	assert_true(s.find("你") >= 0)


func test_ron_toast() -> void:
	var s := PT._format_toast_text(_make_event(&"RON_DECLARED", 1))
	assert_true(s.find("荣和") >= 0)
	assert_true(s.find("AI 1") >= 0)


func test_exhaustive_draw_toast() -> void:
	assert_eq(PT._format_toast_text(_make_event(&"EXHAUSTIVE_DRAW")), "流局")


func test_haitei_houtei_toast() -> void:
	assert_eq(PT._format_toast_text(_make_event(&"HAITEI", 0)), "海底捞月!")
	assert_eq(PT._format_toast_text(_make_event(&"HOUTEI", 0)), "河底捞鱼!")


func test_game_begin_toast() -> void:
	assert_eq(PT._format_toast_text(_make_event(&"GAME_BEGIN")), "开局")


func test_unknown_event_returns_empty() -> void:
	# 非关键事件不弹 toast (避免干扰)
	assert_eq(PT._format_toast_text(_make_event(&"TILE_DISCARDED", 0)), "")
	assert_eq(PT._format_toast_text(_make_event(&"PLAYER_ACTION", 0)), "")
