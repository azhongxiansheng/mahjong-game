class_name GameDriver

# 麻将王 — 里程碑 3 第 1 步：东风战跨局驱动器（plan-3 D1/D6）
#
# 职责：
#   - 持东风战层状态：hand_index / honba / riichi_sticks / cumulative_scores / dealer_seat
#   - 每局开始：用 seed + hand_index 实例化 BattleController，注入当前累计分
#   - 每局结束：经 HandSettlement 统一落账（#375；与 Worker 共用语义）
#   - advance_or_finish: 决定连庄/流转/整场结束（spec §3.2 + §10）
#
# 不在本类范围：
#   - 听牌检测（流局优先用 battle 真实 WaitCalculator；可覆盖 tenpai_array）
#   - UI 渲染（→ 第 2-4 步）
#   - 鸣牌窗口（M2 留给后续 plan）

const STARTING_SCORE: int = 25000
const NUM_HANDS_EAST_ROUND: int = 4  # 历史默认；M8 改为 total_hands 实例字段
const RIICHI_STICK_VALUE: int = 1000

var seed: int = 0
# hand_index: 线性递增（0..total_hands-1）。半庄战不在 E4→S1 处重置；
# round_wind 由 _compute_current_round_wind() 函数式计算（不同于
# 重置 hand_index 的方案 — 让连庄计数不被风圈切换干扰）
var hand_index: int = 0
# E2-02：独立于 hand_index 的局序号分配器（连庄也推进；洗牌 seed = seed+allocated）
var next_hand_seq: int = 0
var honba: int = 0
var riichi_sticks: int = 0
var dealer_seat: int = 0
var cumulative_scores: Array[int] = []
var battle: IAuthoritativeBattleController = null  # E2-02：本地权威路径
var finished: bool = false
# M7 平衡：是否用 HeuristicAi（默认 false 保持向后兼容）
var use_heuristic_ai: bool = false
# M10 Path A：HeuristicAi 启用 ShantenCalculator-aware 弃牌（仅 use_heuristic_ai 时有效）
var use_shanten_ai: bool = false
# M8 半庄战参数化：
# - total_hands=4, hands_per_round=4 → 东风战（M7 默认）
# - total_hands=8, hands_per_round=4 → 半庄战（前 4 局东、后 4 局南）
var total_hands: int = NUM_HANDS_EAST_ROUND
var hands_per_round: int = NUM_HANDS_EAST_ROUND
# E2-04：构造期注入的模式模块包（可空兼容旧路径；生产启动器必填）
var mode_modules: ModeModuleBundle = null
# M7 / #375：start_hand 时冻结起始分与棒，供 HandSettlement 算 in-hand 调整
var _pre_hand_state_scores: Array[int] = [0, 0, 0, 0]
var _pre_hand_riichi_sticks: int = 0
var _pre_hand_honba: int = 0
var _pre_hand_frozen: bool = false
# #375：已提交 hand 规范结果（幂等/冲突）
var _settlement_tracker: Dictionary = HandSettlement.empty_tracker()
# 流局路径：apply_result 仅分析，advance_or_finish 带 tenpai 后提交
var _pending_draw_events: Array = []
var _pending_draw_state_scores: Array = []
var _pending_draw_state_sticks: int = 0
var _pending_draw_hand_seq: int = -1
var _pending_draw_kind: String = ""


func _init(p_seed: int = 0, p_total_hands: int = NUM_HANDS_EAST_ROUND, p_hands_per_round: int = NUM_HANDS_EAST_ROUND) -> void:
	seed = p_seed
	total_hands = p_total_hands
	hands_per_round = p_hands_per_round
	cumulative_scores = [STARTING_SCORE, STARTING_SCORE, STARTING_SCORE, STARTING_SCORE]

# M8: 当前局对应的场风。东风战恒东；半庄战 hand_index>=4 切到南。
# 调用方需保证 hand_index < total_hands 时调用（连庄超出 total_hands 例外，
# 见 advance_or_finish 终局判定）。
func _compute_current_round_wind() -> int:
	if hand_index < hands_per_round:
		return TileId.E
	return TileId.S_WIND

# 自定义 BC 工厂；玩家可玩路径用它注入 PlayableBattleController。
# 默认 = BattleController（v1 AI vs AI 行为）。
# 签名：(seed, dealer_seat, use_heuristic_ai, round_wind, hand_seq) -> IAuthoritativeBattleController
var bc_factory: Callable = Callable()

# 创建当前 hand 的 BattleController；把累计分 + honba + riichi_sticks 注入
# 到 battle.state，便于 ScoreFormula 在结算时引用本场起点。
# E2-02：hand_seq 独立于 hand_index；仅 candidate 有效后才写入 battle / 推进 counter。
func start_hand() -> IAuthoritativeBattleController:
	if battle != null or finished:
		return null
	if next_hand_seq < 0 or next_hand_seq > Wall.MAX_HAND_SEQ:
		return null
	var allocated: int = next_hand_seq
	var round_wind: int = _compute_current_round_wind()
	var shuffle_seed: int = seed + allocated
	var candidate: IAuthoritativeBattleController = null
	if bc_factory.is_valid():
		candidate = bc_factory.call(shuffle_seed, dealer_seat, use_heuristic_ai, round_wind, allocated)
	else:
		candidate = BattleController.new(shuffle_seed, dealer_seat, use_heuristic_ai, round_wind, allocated)
	if candidate == null or candidate.state == null:
		return null
	for i in range(4):
		candidate.state.scores[i] = cumulative_scores[i]
		if i < candidate.state.seats.size() and candidate.state.seats[i] is Seat:
			(candidate.state.seats[i] as Seat).points = cumulative_scores[i]
	candidate.state.honba = honba
	candidate.state.riichi_sticks = riichi_sticks
	# 拍照供 HandSettlement 算 skill 转分 / 立直棒增量
	for i in range(4):
		_pre_hand_state_scores[i] = candidate.state.scores[i]
	_pre_hand_riichi_sticks = riichi_sticks
	_pre_hand_honba = honba
	_pre_hand_frozen = true
	_settlement_tracker = HandSettlement.empty_tracker()
	_clear_pending_draw()
	# M8.5：注入 strategic context 给 HeuristicAi（终局策略：领先时不立直）
	if use_heuristic_ai and candidate.ai is HeuristicAi:
		var hai := candidate.ai as HeuristicAi
		hai.set_strategic_context(cumulative_scores, hand_index, total_hands)
		# M10 Path A：可选启用 shanten-aware 弃牌
		if use_shanten_ai:
			hai.use_shanten_aware_discard = true
	battle = candidate
	next_hand_seq = allocated + 1
	return battle

# 解析 events，经 HandSettlement 统一落账到 cumulative_scores。
# 流局：若尚未提供 tenpai，暂存 pending，在 advance_or_finish 带 tenpai 后提交。
#
# 返：
#   - 胡牌：{kind: "tsumo"|"ron", winner_seat, payout, han, fu, winner_total, settlement}
#   - 流し：{kind: "nagashi_mangan", winner_seat, payout, settlement}
#   - 流局：{kind: "exhaustive_draw"|"abortive_draw", ...}
func apply_result(events: Array) -> Dictionary:
	_clear_pending_draw()
	var start_scores: Array = _resolve_start_scores()
	var start_honba: int = _pre_hand_honba if _pre_hand_frozen else honba
	var start_sticks: int = _pre_hand_riichi_sticks if _pre_hand_frozen else riichi_sticks

	var state: BattleState = battle.state if battle != null else null
	var owns_temp_state := false
	if state == null:
		# 单元测试路径：仅 events + 累计分，构造最小 state
		state = BattleState.new()
		state.scores = [
			int(start_scores[0]), int(start_scores[1]),
			int(start_scores[2]), int(start_scores[3]),
		]
		state.dealer_seat = dealer_seat
		state.honba = honba
		state.riichi_sticks = riichi_sticks
		state.hand_seq = maxi(0, next_hand_seq - 1)
		for i in range(4):
			state.seats.append(Seat.new(i, TileId.E, int(start_scores[i])))
		owns_temp_state = true

	# 本 hand 已提交：幂等返回 canonical，禁止从已落账 state 二次 build/payout
	var hand_seq_now: int = int(state.hand_seq)
	var stored: Dictionary = HandSettlement.committed_result(_settlement_tracker)
	if not stored.is_empty() and int(stored.get("hand_seq", -1)) == hand_seq_now:
		riichi_sticks = int(stored.get("riichi_sticks", riichi_sticks))
		return _driver_view_from_settlement(stored, events)

	# 先解析 outcome，流局延迟提交以接受 tenpai 覆盖
	var probe: Dictionary = HandSettlement.build(
		events, start_scores, state, [], start_honba, start_sticks
	)
	if probe.is_empty() or str(probe.get("outcome", "")) == HandSettlement.OUTCOME_EXHAUSTIVE:
		_pending_draw_events = events.duplicate()
		_pending_draw_state_scores = []
		for s in state.scores:
			_pending_draw_state_scores.append(int(s))
		_pending_draw_state_sticks = int(state.riichi_sticks)
		_pending_draw_hand_seq = int(state.hand_seq)
		_pending_draw_kind = "exhaustive_draw"
		if battle != null:
			riichi_sticks = battle.state.riichi_sticks
		return {"kind": "exhaustive_draw", "settlement_pending": true}

	# WIN / NAGASHI / ABORTIVE：立即提交
	var commit_state: BattleState = null if owns_temp_state else state
	if not HandSettlement.commit(
		probe, cumulative_scores, _settlement_tracker, commit_state,
		start_scores, _enforce_settlement_conservation()
	):
		return {}
	# 返回 tracker 中的 canonical（与 ledger 一致）
	var canon: Dictionary = HandSettlement.committed_result(_settlement_tracker)
	if canon.is_empty():
		canon = probe
	riichi_sticks = int(canon.get("riichi_sticks", 0))
	return _driver_view_from_settlement(canon, events)


func _enforce_settlement_conservation() -> bool:
	# null mode_modules：兼容旧路径，按 STANDARD 严格守恒（不静默当 TRASH_TALK）
	if mode_modules == null:
		return true
	if mode_modules.is_trash_talk():
		return false
	return true


func _resolve_start_scores() -> Array:
	if _pre_hand_frozen:
		var out: Array = []
		for i in range(4):
			out.append(int(_pre_hand_state_scores[i]))
		return out
	var out2: Array = []
	for s in cumulative_scores:
		out2.append(int(s))
	return out2


func _driver_view_from_settlement(settlement: Dictionary, events: Array) -> Dictionary:
	var outcome: String = str(settlement.get("outcome", ""))
	var kind: String = HandSettlement.outcome_to_driver_kind(outcome)
	var view := {
		"kind": kind,
		"settlement": settlement.duplicate(true),
		"renchan": bool(settlement.get("renchan", false)),
	}
	var winners: Array = settlement.get("winner_seats", [])
	if not winners.is_empty():
		view["winner_seat"] = int(winners[0])
	match outcome:
		HandSettlement.OUTCOME_RON, HandSettlement.OUTCOME_TSUMO:
			var win_extra: Dictionary = {}
			for i in range(events.size() - 1, -1, -1):
				var ev: BattleEvent = events[i] as BattleEvent
				if ev != null and ev.type == &"WIN_DECLARED":
					win_extra = ev.extra if typeof(ev.extra) == TYPE_DICTIONARY else {}
					break
			view["payout"] = win_extra.get("payout", {})
			view["han"] = int(win_extra.get("han", 0))
			view["fu"] = int(win_extra.get("fu", 0))
			view["winner_total"] = int(win_extra.get("winner_total", 0))
		HandSettlement.OUTCOME_NAGASHI:
			var w: int = int(winners[0]) if not winners.is_empty() else -1
			view["payout"] = NagashiMangan.payout(w, int(settlement.get("dealer_seat", dealer_seat)))
		HandSettlement.OUTCOME_ABORTIVE:
			for i in range(events.size() - 1, -1, -1):
				var ev2: BattleEvent = events[i] as BattleEvent
				if ev2 != null and ev2.type == &"ABORTIVE_DRAW":
					view["reason"] = String(ev2.extra.get("reason", ""))
					break
	return view


# 决定连庄 / 流转 / 整场结束。
#
# result 来自 apply_result()，可携带 tenpai_array（流局路径下必需，
# 4-bool 数组表示每 seat 是否听牌）。
#
# - 庄家自摸 / 庄家荣胡 / 流局且庄家听牌 → 连庄：dealer 不变，hand_index 不变，honba+=1
# - 闲家胡 / 流局且庄家不听 → 流转：hand_index+=1，dealer 顺时针旋转，honba=0
# - hand_index 达到 NUM_HANDS_EAST_ROUND 且未连庄 → 整场结束（finished=true）
#
# 流局：在此用 HandSettlement 提交 noten（#375 与 Worker 同语义）
#
# 返 {finished, renchan, kind}
func advance_or_finish(result: Dictionary) -> Dictionary:
	var kind: String = result.get("kind", "exhaustive_draw")
	var renchan := false

	if kind == "exhaustive_draw" and _pending_draw_kind == "exhaustive_draw":
		var tenpai_array: Array = result.get("tenpai_array", [])
		var state: BattleState = null
		if battle != null:
			state = battle.state
		else:
			state = BattleState.new()
			state.scores = [
				int(_pending_draw_state_scores[0]) if _pending_draw_state_scores.size() == 4 else int(cumulative_scores[0]),
				int(_pending_draw_state_scores[1]) if _pending_draw_state_scores.size() == 4 else int(cumulative_scores[1]),
				int(_pending_draw_state_scores[2]) if _pending_draw_state_scores.size() == 4 else int(cumulative_scores[2]),
				int(_pending_draw_state_scores[3]) if _pending_draw_state_scores.size() == 4 else int(cumulative_scores[3]),
			]
			state.dealer_seat = dealer_seat
			state.honba = honba
			state.riichi_sticks = _pending_draw_state_sticks if _pending_draw_state_sticks >= 0 else riichi_sticks
			state.hand_seq = _pending_draw_hand_seq if _pending_draw_hand_seq >= 0 else maxi(0, next_hand_seq - 1)
			for i in range(4):
				state.seats.append(Seat.new(i, TileId.E, int(state.scores[i])))
		# 若有真实 battle，优先用 state 听牌；测试可覆盖 tenpai_array
		if tenpai_array.size() != 4 and battle != null:
			tenpai_array = HandSettlement.detect_tenpai_array(state)

		var start_scores: Array = _resolve_start_scores()
		# 确保 state.scores 为 pending 快照（未应用 noten）
		if _pending_draw_state_scores.size() == 4:
			for i in range(4):
				state.scores[i] = int(_pending_draw_state_scores[i])
			state.riichi_sticks = _pending_draw_state_sticks
			state.hand_seq = _pending_draw_hand_seq

		var events: Array = _pending_draw_events
		if events.is_empty():
			events = [BattleEvent.make(&"EXHAUSTIVE_DRAW", -1)]
		var start_honba: int = _pre_hand_honba if _pre_hand_frozen else honba
		var start_sticks: int = _pre_hand_riichi_sticks if _pre_hand_frozen else riichi_sticks

		var settlement: Dictionary = HandSettlement.build(
			events, start_scores, state, tenpai_array, start_honba, start_sticks
		)
		if settlement.is_empty():
			# 非法/不完整：fail-closed，不推进 hand / 不清 battle
			return {
				"finished": finished,
				"renchan": false,
				"kind": kind,
				"error": "SETTLEMENT_BUILD_FAILED",
			}
		if not HandSettlement.commit(
			settlement, cumulative_scores, _settlement_tracker,
			state if battle != null else null,
			start_scores, _enforce_settlement_conservation()
		):
			return {
				"finished": finished,
				"renchan": false,
				"kind": kind,
				"error": "SETTLEMENT_COMMIT_FAILED",
			}
		var canon_draw: Dictionary = HandSettlement.committed_result(_settlement_tracker)
		if not canon_draw.is_empty():
			settlement = canon_draw
		riichi_sticks = int(settlement.get("riichi_sticks", riichi_sticks))
		renchan = bool(settlement.get("renchan", false))
		result["settlement"] = settlement
		_clear_pending_draw()
	else:
		match kind:
			"tsumo", "ron", "nagashi_mangan":
				if result.has("settlement"):
					renchan = bool(result["settlement"].get("renchan", false))
				else:
					renchan = (int(result.get("winner_seat", -1)) == dealer_seat)
			"abortive_draw":
				if result.has("settlement"):
					renchan = bool(result["settlement"].get("renchan", true))
				else:
					renchan = true
			"exhaustive_draw":
				var tenpai2: Array = result.get("tenpai_array", [false, false, false, false])
				renchan = ExhaustiveDraw.is_dealer_renchan(dealer_seat, tenpai2)
				var deltas2: Dictionary = ExhaustiveDraw.noten_payout(tenpai2)
				for s2 in deltas2:
					cumulative_scores[s2] += int(deltas2[s2])
			_:
				renchan = bool(result.get("renchan", false))

	if renchan:
		honba += 1
	else:
		honba = 0
		hand_index += 1
		dealer_seat = (dealer_seat + 1) % 4

	if not renchan and hand_index >= total_hands:
		finished = true

	battle = null
	_clear_pending_draw()
	# 本局已落账进 cumulative：清空 tracker，避免无 start_hand 时 hand_seq 复用导致误幂等
	_settlement_tracker = HandSettlement.empty_tracker()
	_pre_hand_frozen = false

	return {
		"finished": finished,
		"renchan": renchan,
		"kind": kind,
	}


func _clear_pending_draw() -> void:
	_pending_draw_events = []
	_pending_draw_state_scores = []
	_pending_draw_state_sticks = 0
	_pending_draw_hand_seq = -1
	_pending_draw_kind = ""


# 调用方在玩家声明立直时调用：扣 1000 + 把棒加到台上。
# （v1 简化：本方法不校验是否合法立直，由 BattleController 内的 RiichiValidator 把关）
func on_riichi_declared(seat_id: int) -> void:
	cumulative_scores[seat_id] -= RIICHI_STICK_VALUE
	riichi_sticks += 1

# 守恒检查：sum(cumulative_scores) + riichi_sticks * 1000 == 100000
func is_score_conserved() -> bool:
	return HandSettlement.is_conserved(cumulative_scores, riichi_sticks)
