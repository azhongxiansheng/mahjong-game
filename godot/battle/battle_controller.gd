class_name BattleController

const RIICHI_STICK_COST: int = 1000

# 里程碑 2 — 端到端编排器。
# 职责：
#   1. 自建 BattleState / TurnEngine / SkillRegistry / SkillScheduler / SimpleAi
#   2. 编排「摸→弃→（鸣牌窗口暂略）→下家」整局循环
#   3. 在 TurnEngine apply_xxx 调用前后向 SkillScheduler emit BattleEvent
#   4. 流局 / 自摸 / 荣胡时退出循环
# spec §13 第 2 项 — 不接 UI、不接交互、4 家全 AI。

# 里程碑 2 完成 YakuEvaluator → ScoreCalc 串接：YakuEvaluator 用 yaku/yaku_list.gd
# （class_name YakuEntries，含 entries: Array[YakuEntry] / apply_exclusions / is_yakuman()），
# ScoreCalc 用 rules_japanese/yaku_list.gd（class_name YakuList，含 yaku: Array[Dict]
# / is_yakuman: bool / yakuman_multiplier）—— 两份语义不同；PR #12 已修 class_name 重名
# （旧 WinContext → 拆为 ScoreContext + WinContext，旧 YakuList → 拆为 YakuList + YakuEntries）。
# _adapt_yaku_list() 在 YakuEntries → YakuList 之间桥接。

const MAX_LOOP_STEPS := 2000  # 一局上限，防死循环；正常一局 < 200 步

var state: BattleState
var engine: TurnEngine
var registry: SkillRegistry
var scheduler: SkillScheduler
var ai: SimpleAi

var events: Array = []  # 事件 log（仅本地引用，便于断言）
var _settled: bool = false
var _last_event_type: StringName = &""

func _init(seed: int = 0, dealer_seat: int = 0, use_heuristic_ai: bool = false, round_wind: int = TileId.E) -> void:
	# round_wind: M8 半庄战支持。默认东兼容 M7；GameDriver 在南场调用时
	# 传 TileId.S_WIND 以激活场风南牌役（南、南家自风南）。
	state = BattleState.for_east_round(seed, dealer_seat, 1, 0, 0, round_wind)
	engine = TurnEngine.new(state)
	registry = SkillRegistry.new()
	scheduler = SkillScheduler.new(registry, state)
	# AI 用不同 seed，与洗牌 seed 解耦
	if use_heuristic_ai:
		ai = HeuristicAi.new(seed + 1)
	else:
		ai = SimpleAi.new(seed + 1)

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
	# M7：摸到此牌后牌墙是否空 → 海底捞月（自摸路径）
	var is_haitei: bool = (state.wall.live_wall_size() == 0)
	# 自摸检测（无役不胡；本里程碑 SimpleAi 不会主动宣告，这里 BC 自动判定）
	var win := _check_tsumo(t, is_haitei)
	if win.is_winning:
		_settle_tsumo(t, win.wp, win.yaku_list, is_haitei)

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
	# M7：discard 后 hand=13 张，AI 可决定立直（HeuristicAi.decide_riichi 走
	# RiichiValidator）。declare_riichi 成功 → state.scores[seat] -= 1000 让
	# GameDriver._apply_in_hand_skill_deltas 同步到 cumulative，避免守恒被破。
	if ai.has_method("decide_riichi"):
		var seat_after: Seat = state.seats[actor]
		if ai.decide_riichi(seat_after, state.wall.live_wall_size()):
			if engine.declare_riichi(actor):
				state.scores[actor] -= RIICHI_STICK_COST
				_emit(&"RIICHI_DECLARED", actor, null, {})
	# M7：自动 RON 检测。在每次 TILE_DISCARDED 后按 atama-hane 顺序遍历对家。
	# v1：任一对家若可胡（非振听 + 听牌 + 有役）→ 自动 apply_ron。
	# 真实玩家 UI 路径下（M8+）会替换为玩家选择窗口；当前 SimpleAi-only 阶段
	# 自动接受所有可胡机会以让 sim 看见 RON 路径。
	if not _settled:
		_try_auto_ron(to_discard, actor)

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
func _check_tsumo(drawn: Tile, is_haitei: bool = false) -> Dictionary:
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
	var game_ctx := _build_game_ctx(seat, true, is_haitei, false)
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
func _check_ron(ron_tile: Tile, winner_seat: int, is_houtei: bool = false) -> Dictionary:
	var winner: Seat = state.seats[winner_seat]
	var typed_melds: Array[Meld] = []
	for m in winner.melds:
		typed_melds.append(m)
	var wp: Dictionary = WinPattern.detect(winner.hand, typed_melds, ron_tile)
	if not wp.is_winning:
		return {"is_winning": false}
	var game_ctx := _build_game_ctx(winner, false, false, is_houtei)
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

# M7：在 TILE_DISCARDED 后自动尝试 ron。按 atama-hane 顺序（discarder + 1
# 优先），首个可胡的对家直接 apply_ron。被 cancel_ron 跳过该候选试下一个
# （v1 简化：spec 严格 atama-hane 是"被取消即不再考虑"；本 v1 让其它候选
# 也有机会 fire 以让 sim 看到更多 RON 数据点）。
# is_houtei = (wall.live_wall_size() == 0) — 当前 discard 来自最后一张 live 牌。
func _try_auto_ron(discarded: Tile, discarder: int) -> void:
	var is_houtei: bool = (state.wall.live_wall_size() == 0)
	for offset in range(1, 4):
		var candidate: int = (discarder + offset) % 4
		var candidate_seat: Seat = state.seats[candidate]
		# 1) 振听 + 听牌检查（ClaimValidator 已封装）
		if not ClaimValidator.can_ron(candidate_seat.hand, candidate_seat.melds, discarded, candidate_seat.furiten):
			continue
		# 2) 有役检查（_check_ron 内部跑 YakuEvaluator + 无役拒绝）
		var ron_check: Dictionary = _check_ron(discarded, candidate, is_houtei)
		if not ron_check.is_winning:
			continue
		# 3) 试结算（apply_ron emit RON_DECLARED 给技能 cancel 机会）
		if apply_ron(candidate, discarded, discarder, is_houtei):
			return  # 已 settle

# 公共入口：荣胡（外部 driver 调用，不走 run_to_end 主循环）。
# discarder_seat: 弃牌人座（决定 ron_tile 的 owner_seat 与 score_ctx.loser_seat）。
# 返 false 表示和牌不成立（无役 / 听牌不命中 / 技能取消）。
func apply_ron(winner_seat: int, ron_tile: Tile, discarder_seat: int, is_houtei: bool = false) -> bool:
	var ron_ti := TileInstance.make(ron_tile, discarder_seat, null)
	# M7：reset 上一次 emit 留下的 cancel 标记，避免同 hand 多次 ron 尝试时
	# 旧值粘连（例：先 seat 1 的 ron 被 cancel；再 seat 2 试 ron 时 ron_cancelled[2]
	# 默认 false，但若上次 emit 不小心也触发了 seat 2 的 cancel 就会粘连）
	state.ron_cancelled[winner_seat] = false
	# 先 emit RON_DECLARED 让技能（如「中·封印」）有机会取消
	_emit(&"RON_DECLARED", winner_seat, ron_ti, {"discarder_seat": discarder_seat})
	if state.ron_cancelled[winner_seat]:
		return false
	var win := _check_ron(ron_tile, winner_seat, is_houtei)
	if not win.is_winning:
		return false
	_settle_ron(ron_tile, ron_ti, winner_seat, discarder_seat, win.wp, win.yaku_list, is_houtei)
	return true

func _settle_ron(ron_tile: Tile, ron_ti: TileInstance, winner_seat: int, discarder_seat: int, wp: Dictionary, yaku_list, is_houtei: bool = false) -> void:
	var winner: Seat = state.seats[winner_seat]

	var score_ctx := ScoreContext.new()
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

	# M7：在 ScoreCalc 之前 emit pre-score 事件（HOUTEI? + WIN_DECLARED_PRE），
	# hooks 此时可通过 ctx.add_han / mark_extra_dora / multiply_han_for_seat
	# 真正影响计分。所有 pre-score ctx 收集到 pre_ctxs 数组里以便统一应用。
	var pre_ctxs: Array = []
	if is_houtei:
		pre_ctxs.append(_emit(&"HOUTEI", winner_seat, ron_ti, {}))
	var pre_extra: Dictionary = {"discarder_seat": discarder_seat, "is_tsumo": false, "is_houtei": is_houtei}
	pre_ctxs.append(_emit(&"WIN_DECLARED_PRE", winner_seat, ron_ti, pre_extra))
	_apply_skill_han_delta(score_yaku_list, _sum_skill_han(winner_seat, pre_ctxs))
	_apply_extra_dora(score_yaku_list, winner_seat)
	# M7 B3-mini：把 multiplicative effect（任一 pre ctx）应用到番数
	_apply_han_multiplier(score_yaku_list, _composite_multiplier(winner_seat, pre_ctxs))
	# M7 B3-mini：满贯下限保底（white_mangan_floor 等消耗品）
	if _has_mangan_floor(winner_seat, pre_ctxs):
		_apply_mangan_floor(score_yaku_list)

	var result: Dictionary = ScoreCalc.calculate(wp, melds_arr, score_yaku_list, score_ctx)

	# M7：把 discarder_seat / points_won 注入 WIN_DECLARED.extra，让 post-score
	# hooks（soul_drain_hatsu / east_mirror_chambo 等用 transfer_points）能读到
	result["discarder_seat"] = discarder_seat
	result["points_won"] = int(result.get("winner_total", 0))

	engine.apply_ron(winner_seat, ron_tile)
	_emit(&"WIN_DECLARED", winner_seat, ron_ti, result)
	_settled = true

func _settle_tsumo(drawn: Tile, wp: Dictionary, yaku_list, is_haitei: bool = false) -> void:
	var seat: Seat = state.seats[state.current_seat]
	var ti := _wrap_tile(drawn)
	_emit(&"TSUMO_DECLARED", state.current_seat, ti, {})

	var score_ctx := ScoreContext.new()
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

	# M7：HAITEI? + WIN_DECLARED_PRE，accumulate hook 影响（han_deltas / dora /
	# multiplier）。pre_ctxs 持所有 pre-score ctx 引用。
	var pre_ctxs: Array = []
	if is_haitei:
		pre_ctxs.append(_emit(&"HAITEI", state.current_seat, ti, {}))
	var pre_extra: Dictionary = {"is_tsumo": true, "is_haitei": is_haitei}
	pre_ctxs.append(_emit(&"WIN_DECLARED_PRE", state.current_seat, ti, pre_extra))
	_apply_skill_han_delta(score_yaku_list, _sum_skill_han(state.current_seat, pre_ctxs))
	_apply_extra_dora(score_yaku_list, state.current_seat)
	_apply_han_multiplier(score_yaku_list, _composite_multiplier(state.current_seat, pre_ctxs))
	if _has_mangan_floor(state.current_seat, pre_ctxs):
		_apply_mangan_floor(score_yaku_list)

	var result: Dictionary = ScoreCalc.calculate(wp, melds_arr, score_yaku_list, score_ctx)

	# M7：tsumo 无 discarder_seat（自摸无放铳人），仅设 points_won
	result["points_won"] = int(result.get("winner_total", 0))

	engine.apply_tsumo(state.current_seat, drawn)
	_emit(&"WIN_DECLARED", state.current_seat, ti, result)
	_settled = true

# 把 YakuEntries（YakuEvaluator 出口）转成 YakuList（ScoreCalc 入口）。
func _adapt_yaku_list(eval_list: YakuEntries) -> YakuList:
	var sc := YakuList.new()
	sc.is_yakuman = eval_list.is_yakuman()
	sc.yakuman_multiplier = eval_list.yakuman_total_multiplier()
	sc.dora_count = state.dora_indicators.visible.size()
	# YakuEntry.yaku_id 是 int (YakuId 常量)，但 YakuList.is_pinfu / is_chiitoi
	# 走 has_yaku(&"pinfu") / has_yaku(&"chiitoitsu") StringName 比较。
	# 这里把 PINFU / CHIITOITSU 转 StringName 让 FuCalculator 特殊符识别正确（M4
	# BattleNodeRunner 跑大量随机牌局触发了这个 M2 留下的类型不匹配 bug）。
	for entry in eval_list.entries:
		sc.yaku.append({"id": _yaku_id_to_string_name(entry.yaku_id), "han": entry.han})
	return sc

# M7：把 pre-score hook 累积的 han 增量注入到 ScoreCalc 输入的 yaku_list。
# 调用方负责把多个 ctx（HAITEI/HOUTEI + WIN_DECLARED_PRE）的 han_deltas
# 求和后传 delta 进来。delta = 0 不注入，避免污染 yaku_list；
# delta != 0 追加 &"skill_bonus" entry 由 ScoreCalc 累加。
static func _apply_skill_han_delta(yaku_list: YakuList, delta: int) -> void:
	if delta == 0:
		return
	yaku_list.add_yaku(&"skill_bonus", delta)

# M7 B2：把 BattleState.extra_dora_count[winner] + extra_red_dora_count[winner]
# 加到 yaku_list.dora_count（hooks 通过 ctx.mark_extra_dora_for_seat /
# ctx.mark_red_dora_for_seat 累积）。
func _apply_extra_dora(yaku_list: YakuList, winner_seat: int) -> void:
	yaku_list.dora_count += int(state.extra_dora_count[winner_seat])
	yaku_list.dora_count += int(state.extra_red_dora_count[winner_seat])

# M7 B3-mini：把 ctx.han_multipliers[winner] 应用到 yaku_list。
# 用合成"&\"skill_multiplier\""yaku entry 表达：(factor - 1) * total_han 番。
# 例如 factor=2.0、当前 total_han=5 → 加 +5 番（合 10 番）。
# factor <= 1.0 不操作（避免 ScoreFormula 钳制 < 0 番时混乱）。
static func _apply_han_multiplier(yaku_list: YakuList, factor: float) -> void:
	if factor <= 1.0:
		return
	var current_total: int = yaku_list.total_han()
	var added: int = int(current_total * (factor - 1.0))
	if added != 0:
		yaku_list.add_yaku(&"skill_multiplier", added)

# 累加多个 ctx 中 winner_seat 的 han_deltas（用于 HAITEI/HOUTEI + WIN_DECLARED_PRE）
static func _sum_skill_han(winner_seat: int, ctxs: Array) -> int:
	var total: int = 0
	for c in ctxs:
		if c == null:
			continue
		total += int(c.han_deltas.get(winner_seat, 0))
	return total

# 多个 ctx 的 han_multipliers 累乘（×2 + ×1.5 = ×3 复合）
static func _composite_multiplier(winner_seat: int, ctxs: Array) -> float:
	var product: float = 1.0
	for c in ctxs:
		if c == null:
			continue
		product *= float(c.han_multipliers.get(winner_seat, 1.0))
	return product

# M7 B3-mini：ensure_mangan — winner 在任一 ctx 标了 mangan_floor 时，
# 若当前 total_han < 5（满贯阈值）补差到 5（合成 &"skill_mangan_floor" yaku）。
const MANGAN_HAN_THRESHOLD: int = 5

static func _has_mangan_floor(winner_seat: int, ctxs: Array) -> bool:
	for c in ctxs:
		if c == null:
			continue
		if bool(c.mangan_floor_seats.get(winner_seat, false)):
			return true
	return false

static func _apply_mangan_floor(yaku_list: YakuList) -> void:
	var current: int = yaku_list.total_han()
	if current >= MANGAN_HAN_THRESHOLD:
		return  # 已满贯，无需补差
	yaku_list.add_yaku(&"skill_mangan_floor", MANGAN_HAN_THRESHOLD - current)

# 兼容性 wrapper：从单个 ctx 取 han_deltas[winner_seat] 调 _apply_skill_han_delta。
# 现存测试 / 后续 PR 还会调用，保留。
static func _apply_skill_han(yaku_list: YakuList, ctx: SkillCtx, winner_seat: int) -> void:
	if ctx == null:
		return
	var delta: int = int(ctx.han_deltas.get(winner_seat, 0))
	_apply_skill_han_delta(yaku_list, delta)

# YakuId int → StringName 映射。仅覆盖 YakuList.has_yaku 实际查询的 id；
# 其它 id 用 str(int) 占位（不影响 ScoreCalc 累加 han 的正确性）。
static func _yaku_id_to_string_name(yaku_id: int) -> StringName:
	match yaku_id:
		YakuId.PINFU: return &"pinfu"
		YakuId.CHIITOITSU: return &"chiitoitsu"
	return StringName(str(yaku_id))

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
# is_haitei / is_houtei 由 _check_tsumo / _check_ron 根据牌墙状态传入；
# 之前一直是 false，导致海底捞月 / 河底捞鱼役在真战斗永不被检测。
func _build_game_ctx(seat: Seat, is_tsumo: bool, is_haitei: bool = false, is_houtei: bool = false) -> GameContext:
	var ctx := GameContext.new()
	ctx.bakaze = state.round_wind
	ctx.jikaze = seat.seat_wind
	ctx.is_tsumo = is_tsumo
	ctx.is_riichi = seat.riichi.declared
	ctx.is_double_riichi = seat.riichi.double_riichi
	ctx.is_ippatsu = seat.riichi.ippatsu_window
	ctx.is_haitei = is_haitei
	ctx.is_houtei = is_houtei
	ctx.dora_count = state.dora_indicators.visible.size()
	return ctx
