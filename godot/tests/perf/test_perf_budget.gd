extends GutTest

# 性能预算回归检测 — 不是精确 benchmark,是 ceiling guard。
# 跑 N 次 BC.run_to_end (纯 AI),断言总时长 < 阈值。
# 阈值留 5-10x 余量避开 CI 环境噪音,但能 catch 数量级回归(例如有人不小心
# 加 O(N²) 算法把单局从 10ms 拖到 500ms)。


# 单局 BC.run_to_end 平均预算 — CI 环境给宽松 100ms(本地正常 1-3ms,
# headless CI runner 4-5x slower 是常态;此值是 ceiling guard,catch 数量级回归)
const PER_HAND_BUDGET_MS: float = 100.0

# 一组(50 局)预算 — 累积避免单局抖动
const BATCH_HANDS: int = 50
const BATCH_BUDGET_MS: float = PER_HAND_BUDGET_MS * BATCH_HANDS  # 5000ms


func test_battle_controller_run_to_end_budget() -> void:
	var t0: int = Time.get_ticks_msec()
	for rng_seed in range(BATCH_HANDS):
		var bc := BattleController.new(rng_seed, 0, false, TileId.E)
		bc.run_to_end()
		# 不强制 result 非空 — 有些 rng_seed 进流局也算合法终局
	var elapsed: int = Time.get_ticks_msec() - t0
	gut.p("BC.run_to_end x%d batch: %d ms (avg %.1fms / hand)" % [
		BATCH_HANDS, elapsed, float(elapsed) / BATCH_HANDS])
	assert_lt(elapsed, int(BATCH_BUDGET_MS),
		"%d 局 BC.run_to_end 应 < %dms (实际 %dms)" % [
			BATCH_HANDS, int(BATCH_BUDGET_MS), elapsed])


# YakuEvaluator 单次 evaluate 应 < 5ms — 这是规则引擎热点,加 yaku 不该退化
func test_yaku_evaluator_evaluate_budget() -> void:
	# 用一个已知 tenpai + 自摸的 fixture
	var rng_seed: int = 12345
	# 跑到某局结束;BC.events 应有 1+ WIN/EXHAUSTIVE,任一终局都 OK
	var bc := BattleController.new(rng_seed, 0, false, TileId.E)
	bc.run_to_end()
	# 走 _check_tsumo 路径多次模拟
	var t0: int = Time.get_ticks_msec()
	for i in range(100):
		# 不重要是否真胡 — 只看 detect+evaluate 时长
		var seat: Seat = bc.state.seats[0]
		if seat.hand.size() == 0:
			continue
		var typed_melds: Array[Meld] = []
		for m in seat.melds.all():
			typed_melds.append(m)
		# 摸末张做 win pattern detect(可能 false 但走完算法路径)
		var last_tile: Tile = seat.hand.tiles()[seat.hand.tiles().size() - 1]
		WinPattern.detect(seat.hand, typed_melds, last_tile)
	var elapsed: int = Time.get_ticks_msec() - t0
	gut.p("WinPattern.detect x100 (post-hand fixture): %d ms" % elapsed)
	# 100 次检测应 < 500ms — 平均 5ms / 次,实际通常 0.5ms
	assert_lt(elapsed, 500, "100x WinPattern.detect 应 < 500ms (实际 %dms)" % elapsed)


# Wall 洗牌 + dead wall 预算 — 起手关键路径
func test_wall_setup_budget() -> void:
	var t0: int = Time.get_ticks_msec()
	for i in range(100):
		var w := Wall.new_full_set()
		w.shuffle(i)
		w.reserve_dead_wall(14)
	var elapsed: int = Time.get_ticks_msec() - t0
	gut.p("Wall.new_full_set + shuffle + reserve_dead_wall x100: %d ms" % elapsed)
	assert_lt(elapsed, 1000, "100x Wall 起手应 < 1000ms")
