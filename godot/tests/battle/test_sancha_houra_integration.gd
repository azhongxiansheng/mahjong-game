extends GutTest

# 日麻 §3.2 三家和了(sancha houra)接入 BattleController 验证。
# 修复前:BC._try_auto_ron 用 atama-hane 首胡即收,3 人同时荣胡时只第一个胜。
# 修复后:在主循环前先扫候选数 _count_ron_candidates,≥3 → ABORTIVE_DRAW。


# Helper:把 14 张 tanyao 牌(去掉 1 张作为待胡牌)塞 hand,得到 13 张听 W5 牌
func _build_w5_tanki_hand(extra_set_a: int, extra_set_b: int, extra_set_c: int) -> Hand:
	# 4 套顺子 + W5(tanki 等 W5 配对)。extra_set_* 让 3 个 seat 牌型有别。
	var h := Hand.new()
	# 共用底:W234 T234 S234
	for tid in [TileId.W2, TileId.W3, TileId.W4,
				TileId.T2, TileId.T3, TileId.T4,
				TileId.S2, TileId.S3, TileId.S4]:
		h.add(Tile.new(tid))
	# 第 4 套(seat 独立)
	h.add(Tile.new(extra_set_a))
	h.add(Tile.new(extra_set_b))
	h.add(Tile.new(extra_set_c))
	# 待胡 tanki
	h.add(Tile.new(TileId.W5))
	return h


# Helper:构造 3 家全听 W5 的 BC
func _setup_three_w5_tenpai() -> BattleController:
	var bc := BattleController.new(42, 0, false, TileId.E)
	# discarder 是 seat 0(current_seat 默认 0)
	bc.state.current_seat = 0
	# seat 1: + S5 S6 S7(都 2-8 → tanyao 役)
	bc.state.seats[1].hand = _build_w5_tanki_hand(TileId.S5, TileId.S6, TileId.S7)
	# seat 2: + S6 S7 S8
	bc.state.seats[2].hand = _build_w5_tanki_hand(TileId.S6, TileId.S7, TileId.S8)
	# seat 3: T5 T6 T7
	bc.state.seats[3].hand = _build_w5_tanki_hand(TileId.T5, TileId.T6, TileId.T7)
	return bc


# ---- _count_ron_candidates ----

func test_count_zero_candidates_when_no_tenpai() -> void:
	var bc := BattleController.new(42, 0, false, TileId.E)
	# 4 家手都空,谁都不能胡
	for s in bc.state.seats:
		s.hand._tiles.clear()
	var n: int = bc._count_ron_candidates(Tile.new(TileId.W5), 0, false)
	assert_eq(n, 0, "无候选应返 0")


func test_count_three_candidates_for_w5_discard() -> void:
	var bc := _setup_three_w5_tenpai()
	var n: int = bc._count_ron_candidates(Tile.new(TileId.W5), 0, false)
	assert_eq(n, 3, "3 家全听 W5 + tanyao 应返 3")


# ---- _try_auto_ron sancha houra ----

func test_try_auto_ron_emits_abortive_when_three_candidates() -> void:
	var bc := _setup_three_w5_tenpai()
	bc._try_auto_ron(Tile.new(TileId.W5), 0)
	assert_true(bc._settled, "三家和了应 _settled=true")
	var last_event: BattleEvent = bc.events[bc.events.size() - 1]
	assert_eq(last_event.type, &"ABORTIVE_DRAW", "应 emit ABORTIVE_DRAW")
	assert_eq(String(last_event.extra.get("reason", "")), "sancha_houra",
		"reason 应是 sancha_houra")


# 仅 2 家可胡 → 不应 abortive,走正常 atama-hane(首个胜)
func test_try_auto_ron_no_abortive_when_two_candidates() -> void:
	var bc := _setup_three_w5_tenpai()
	# 把 seat 3 手清空,只留 seat 1 + 2
	bc.state.seats[3].hand._tiles.clear()
	bc._try_auto_ron(Tile.new(TileId.W5), 0)
	# 不应是 sancha houra(可能是其它结果:首胡 settle 或 noop)
	for ev in bc.events:
		assert_ne(String(ev.extra.get("reason", "")), "sancha_houra",
			"2 家可胡不应是 sancha_houra")


# 0 家可胡 → 完全无事件
func test_try_auto_ron_noop_when_no_candidates() -> void:
	var bc := BattleController.new(42, 0, false, TileId.E)
	for s in bc.state.seats:
		s.hand._tiles.clear()
	bc.state.current_seat = 0
	bc._try_auto_ron(Tile.new(TileId.W5), 0)
	assert_false(bc._settled, "无候选应保持非 settle")
	# 不应有 ABORTIVE_DRAW
	for ev in bc.events:
		assert_ne(ev.type, &"ABORTIVE_DRAW",
			"无候选不应 emit ABORTIVE_DRAW")
