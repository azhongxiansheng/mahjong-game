class_name BattleController

# 里程碑 2 — 端到端编排器。
# 职责：
#   1. 自建 BattleState / TurnEngine / SkillRegistry / SkillScheduler / SimpleAi
#   2. 编排「摸→弃→（鸣牌窗口暂略）→下家」整局循环
#   3. 在 TurnEngine apply_xxx 调用前后向 SkillScheduler emit BattleEvent
#   4. 流局 / 自摸 / 荣胡时退出循环
# spec §13 第 2 项 — 不接 UI、不接交互、4 家全 AI。

# 里程碑 2 完成 YakuEvaluator → ScoreCalc 串接：YakuEvaluator 用 yaku/yaku_list.gd
# （含 entries / apply_exclusions / is_yakuman()），ScoreCalc 用 rules_japanese/yaku_list.gd
# （含 yaku: Array[Dict] / is_yakuman: bool / yakuman_multiplier）—— 两份语义不同；
# main 原本用同名 class_name 共存，已在 chore 中重命名为 ScoringYakuList / ScoringWinContext。
# _adapt_yaku_list() 在两份之间桥接。

const MAX_LOOP_STEPS := 2000  # 一局上限，防死循环；正常一局 < 200 步

var state: BattleState
var engine: TurnEngine
var registry: SkillRegistry
var scheduler: SkillScheduler
var ai: SimpleAi

var events: Array = []  # 事件 log（仅本地引用，便于断言）
var _settled: bool = false
var _last_event_type: StringName = &""

func _init(seed: int = 0, dealer_seat: int = 0) -> void:
	state = BattleState.for_east_round(seed, dealer_seat, 1, 0, 0)
	engine = TurnEngine.new(state)
	registry = SkillRegistry.new()
	scheduler = SkillScheduler.new(registry, state)
	ai = SimpleAi.new(seed + 1)  # AI 用不同 seed，与洗牌 seed 解耦

# ---- 主入口 ----

# 跑到流局或胡牌；返 {last_event: StringName, events: Array[BattleEvent]}
func run_to_end() -> Dictionary:
	_emit(&"GAME_BEGIN", state.dealer_seat, null, {})

	var steps := 0
	while not _settled and steps < MAX_LOOP_STEPS:
		steps += 1
		if state.phase == BattlePhase.Kind.DRAW:
			_step_draw()
		elif state.phase == BattlePhase.Kind.DISCARD:
			_step_discard()
		elif state.phase == BattlePhase.Kind.CLAIM:
			# 鸣牌窗口（里程碑 2 不实现），直接 advance
			engine.advance_to_next_seat()
		elif state.phase == BattlePhase.Kind.SETTLE:
			# 已被 _step_xxx 内部处理；保险起见强制退出
			break

	return {
		"last_event": _last_event_type,
		"events": events,
	}

# ---- 步骤 ----

func _step_draw() -> void:
	var t: Tile = engine.draw_for_current()
	if t == null:
		# 牌墙耗尽 — 流局
		_emit(&"EXHAUSTIVE_DRAW", -1, null, {})
		_settled = true
		return
	_emit(&"TILE_DRAWN", state.current_seat, _wrap_tile(t), {})
	# 自摸检测（无役不胡；本里程碑 SimpleAi 不会主动宣告，这里 BC 自动判定）
	var win := _check_tsumo(t)
	if win.is_winning:
		_settle_tsumo(t, win.wp, win.yaku_list)

func _step_discard() -> void:
	var seat: Seat = state.seats[state.current_seat]
	var to_discard: Tile = ai.decide_discard(seat)
	if to_discard == null:
		# 异常：手牌空（不应发生），强制退出
		_settled = true
		return
	var actor: int = state.current_seat
	var ok: bool = engine.discard(to_discard.id)
	if not ok:
		_settled = true
		return
	_emit(&"TILE_DISCARDED", actor, _wrap_tile(to_discard), {})

# ---- 事件 emit ----

# 把一次 emit 集中到此 helper：登记 log + 调 scheduler。
func _emit(type: StringName, actor_seat: int, ti: TileInstance, extra: Dictionary) -> SkillCtx:
	var ev := BattleEvent.make(type, actor_seat, ti, extra)
	events.append(ev)
	_last_event_type = type
	return scheduler.emit_event(ev)

# 把 Tile 包成 TileInstance 以喂事件 payload。
# Tile 当前没有 owner_seat 字段（main 合并冲突里 commit 2b87929 的字段被丢掉，是 main 旧债，
# 不在里程碑 2 修复范围）。本里程碑 owner_seat 默认 -1；路径 C/D 涉及 owner 归属时由
# BattleController 在专用 fixture 入口（_register_skill_for_tile）显式塞 TileInstance 到映射表。
func _wrap_tile(t: Tile) -> TileInstance:
	if t == null:
		return null
	return TileInstance.make(t, -1, null)

# ---- 胡牌结算 ----
#
# 调用顺序（spec §6.1 + §12.1）：
#   WaitCalculator 隐式（WinPattern.detect 内部即跑分解）
#   → WinPattern.detect → YakuEvaluator.evaluate（apply_exclusions 内置）
#   → 无役校验 → ScoreCalc.calculate → emit WIN_DECLARED

# 把 14 张手（含刚摸到的 drawn）拆成 13 张暗牌 + 和牌张，然后跑 WinPattern + YakuEvaluator。
# 返 {is_winning: bool, wp?: Dict, yaku_list?: YakuList, hand_13?: Hand, melds?: Array}
func _check_tsumo(drawn: Tile) -> Dictionary:
	var seat: Seat = state.seats[state.current_seat]
	var hand_13 := _hand_minus_first(seat.hand, drawn.id)
	if hand_13 == null:
		return {"is_winning": false}
	# Seat.melds 是 untyped Array，转成 Array[Meld] 喂规则引擎
	var typed_melds: Array[Meld] = []
	for m in seat.melds:
		typed_melds.append(m)
	var wp: Dictionary = WinPattern.detect(hand_13, typed_melds, drawn)
	if not wp.is_winning:
		return {"is_winning": false}
	var game_ctx := _build_game_ctx(seat, true)
	var yaku_wc := WinContext.new(hand_13, typed_melds, drawn, wp, game_ctx)
	var yaku_list = YakuEvaluator.evaluate(yaku_wc)
	# 无役不能胡（dora 不构成役）；yaku/yaku_list.gd 的 is_yakuman 是函数
	var has_yaku: bool = yaku_list.is_yakuman() or yaku_list.size() > 0
	if not has_yaku:
		return {"is_winning": false}
	return {
		"is_winning": true,
		"wp": wp,
		"yaku_list": yaku_list,
		"hand_13": hand_13,
		"melds": typed_melds,
	}

# 检查 winner_seat 用 ron_tile 荣胡是否合法。
# winner.hand 是 13 张听牌期手（不含 ron_tile）；ron_tile 由对家弃牌补上。
func _check_ron(ron_tile: Tile, winner_seat: int) -> Dictionary:
	var winner: Seat = state.seats[winner_seat]
	var typed_melds: Array[Meld] = []
	for m in winner.melds:
		typed_melds.append(m)
	var wp: Dictionary = WinPattern.detect(winner.hand, typed_melds, ron_tile)
	if not wp.is_winning:
		return {"is_winning": false}
	var game_ctx := _build_game_ctx(winner, false)
	var yaku_wc := WinContext.new(winner.hand, typed_melds, ron_tile, wp, game_ctx)
	var yaku_list = YakuEvaluator.evaluate(yaku_wc)
	var has_yaku: bool = yaku_list.is_yakuman() or yaku_list.size() > 0
	if not has_yaku:
		return {"is_winning": false}
	return {
		"is_winning": true,
		"wp": wp,
		"yaku_list": yaku_list,
		"melds": typed_melds,
	}

# 公共入口：荣胡（外部 driver 调用，不走 run_to_end 主循环）。
# discarder_seat: 弃牌人座（决定 ron_tile 的 owner_seat 与 score_ctx.loser_seat）。
# 返 false 表示和牌不成立（无役 / 听牌不命中 / 技能取消）。
func apply_ron(winner_seat: int, ron_tile: Tile, discarder_seat: int) -> bool:
	var ron_ti := TileInstance.make(ron_tile, discarder_seat, null)
	# 先 emit RON_DECLARED 让技能（如「中·封印」）有机会取消
	_emit(&"RON_DECLARED", winner_seat, ron_ti, {"discarder_seat": discarder_seat})
	if state.ron_cancelled[winner_seat]:
		return false
	var win := _check_ron(ron_tile, winner_seat)
	if not win.is_winning:
		return false
	_settle_ron(ron_tile, ron_ti, winner_seat, discarder_seat, win.wp, win.yaku_list)
	return true

func _settle_ron(ron_tile: Tile, ron_ti: TileInstance, winner_seat: int, discarder_seat: int, wp: Dictionary, yaku_list) -> void:
	var winner: Seat = state.seats[winner_seat]

	var score_ctx := ScoringWinContext.new()
	score_ctx.is_tsumo = false
	score_ctx.winning_tile = ron_tile
	score_ctx.round_wind = state.round_wind
	score_ctx.seat_wind = winner.seat_wind
	score_ctx.dealer_seat = state.dealer_seat
	score_ctx.winner_seat = winner_seat
	score_ctx.loser_seat = discarder_seat
	score_ctx.honba = state.honba
	score_ctx.riichi_sticks = state.riichi_sticks

	var melds_arr: Array = []
	for m in winner.melds:
		melds_arr.append(m)
	var score_yaku_list := _adapt_yaku_list(yaku_list)
	var result: Dictionary = ScoreCalc.calculate(wp, melds_arr, score_yaku_list, score_ctx)

	engine.apply_ron(winner_seat, ron_tile)
	_emit(&"WIN_DECLARED", winner_seat, ron_ti, result)
	_settled = true

func _settle_tsumo(drawn: Tile, wp: Dictionary, yaku_list) -> void:
	var seat: Seat = state.seats[state.current_seat]
	var ti := _wrap_tile(drawn)
	_emit(&"TSUMO_DECLARED", state.current_seat, ti, {})

	var score_ctx := ScoringWinContext.new()
	score_ctx.is_tsumo = true
	score_ctx.winning_tile = drawn
	score_ctx.round_wind = state.round_wind
	score_ctx.seat_wind = seat.seat_wind
	score_ctx.dealer_seat = state.dealer_seat
	score_ctx.winner_seat = state.current_seat
	score_ctx.honba = state.honba
	score_ctx.riichi_sticks = state.riichi_sticks

	var melds_arr: Array = []
	for m in seat.melds:
		melds_arr.append(m)

	var score_yaku_list := _adapt_yaku_list(yaku_list)
	var result: Dictionary = ScoreCalc.calculate(wp, melds_arr, score_yaku_list, score_ctx)

	engine.apply_tsumo(state.current_seat, drawn)
	_emit(&"WIN_DECLARED", state.current_seat, ti, result)
	_settled = true

# 把 yaku/YakuList（YakuEvaluator 出口）转成 ScoringYakuList（ScoreCalc 入口）。
func _adapt_yaku_list(eval_list) -> ScoringYakuList:
	var sc := ScoringYakuList.new()
	sc.is_yakuman = eval_list.is_yakuman()
	sc.yakuman_multiplier = eval_list.yakuman_total_multiplier()
	sc.dora_count = state.dora_indicators.visible.size()
	# YakuEntry.yaku_id 是 int，ScoringYakuList.add_yaku 入参是 StringName，
	# 直接 append dict 绕过类型门（ScoreCalc 只读 entry.han 累加）
	for entry in eval_list.entries:
		sc.yaku.append({"id": entry.yaku_id, "han": entry.han})
	return sc

# ---- 私有 helper ----

# 从 hand 拷一份并移除第一个 id == tile_id 的牌；返新 Hand；找不到返 null。
func _hand_minus_first(hand: Hand, tile_id: int) -> Hand:
	var copy := Hand.new()
	var skipped := false
	for t in hand._tiles:
		if not skipped and t.id == tile_id:
			skipped = true
			continue
		copy.add(t)
	if not skipped:
		return null
	return copy

# 用当前 BattleState + seat 构造 yaku/GameContext。
func _build_game_ctx(seat: Seat, is_tsumo: bool) -> GameContext:
	var ctx := GameContext.new()
	ctx.bakaze = state.round_wind
	ctx.jikaze = seat.seat_wind
	ctx.is_tsumo = is_tsumo
	ctx.is_riichi = seat.riichi.declared
	ctx.is_double_riichi = seat.riichi.double_riichi
	ctx.is_ippatsu = seat.riichi.ippatsu_window
	ctx.dora_count = state.dora_indicators.visible.size()
	return ctx
