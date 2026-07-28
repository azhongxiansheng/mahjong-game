class_name HandSettlement
extends RefCounted

# #375：单局结算纯逻辑值对象 + 提交入口。
# GameDriver 与 LocalLoopbackServer 共用：从 BattleController 结果生成规范
# HAND_SETTLED 字段，一次校验后提交账本；不重复执行 ScoreCalc。

const RIICHI_STICK_VALUE: int = 1000
const STARTING_TOTAL: int = 100000

const OUTCOME_RON := "RON"
const OUTCOME_TSUMO := "TSUMO"
const OUTCOME_EXHAUSTIVE := "EXHAUSTIVE_DRAW"
const OUTCOME_ABORTIVE := "ABORTIVE_DRAW"
const OUTCOME_NAGASHI := "NAGASHI_MANGAN"

const ADJUSTMENT_KIND_IN_HAND := "IN_HAND"
const ADJUSTMENT_KIND_EXTERNAL := "EXTERNAL"

const RESULT_KEYS := [
	"hand_seq", "outcome", "winner_seats", "loser_seat",
	"score_deltas", "scores",
	"dealer_seat", "renchan", "honba", "riichi_sticks", "adjustments",
]


## 从真实 events + 局起始分 + 终态 BattleState 生成规范结算。
## tenpai_array：普通流局 4-bool；缺省时用 WaitCalculator 真实听牌。
## 失败返回 {}（调用方不得半提交）。
static func build(
	events: Array,
	start_scores: Array,
	state: BattleState,
	tenpai_array: Array = [],
	start_honba: int = 0,
	start_riichi_sticks: int = 0
) -> Dictionary:
	if state == null:
		return {}
	if typeof(start_scores) != TYPE_ARRAY or start_scores.size() != 4:
		return {}
	if start_honba < 0 or start_riichi_sticks < 0:
		return {}

	var parsed: Dictionary = _parse_outcome(events, state)
	if parsed.is_empty():
		return {}

	var outcome: String = str(parsed["outcome"])
	var winners: Array = parsed["winner_seats"]
	var loser_seat: int = int(parsed["loser_seat"])
	var win_extra: Dictionary = parsed.get("win_extra", {})
	var dealer_seat: int = int(state.dealer_seat)
	if dealer_seat < 0 or dealer_seat > 3:
		return {}

	var state_scores: Array = _copy4_scores(state.scores)
	if state_scores.is_empty():
		return {}
	var end_sticks: int = int(state.riichi_sticks)
	if end_sticks < 0:
		return {}

	var adjustments: Array = _build_adjustments(
		start_scores, state_scores, start_riichi_sticks, end_sticks
	)

	var final_scores: Array = state_scores.duplicate()
	var renchan := false

	match outcome:
		OUTCOME_RON, OUTCOME_TSUMO:
			if not _apply_win_payout(final_scores, win_extra, winners):
				return {}
			if outcome == OUTCOME_RON:
				if loser_seat < 0 or loser_seat > 3 or winners.has(loser_seat):
					return {}
			end_sticks = 0
			renchan = int(winners[0]) == dealer_seat
		OUTCOME_NAGASHI:
			var nm_winner: int = int(winners[0]) if not winners.is_empty() else -1
			if nm_winner < 0 or nm_winner > 3:
				return {}
			var nm_payout: Dictionary = NagashiMangan.payout(nm_winner, dealer_seat)
			for s in range(4):
				final_scores[s] = int(final_scores[s]) + int(nm_payout.get(s, 0))
			renchan = nm_winner == dealer_seat
		OUTCOME_EXHAUSTIVE:
			var tenpai: Array = tenpai_array
			if tenpai.size() != 4:
				tenpai = detect_tenpai_array(state)
			if tenpai.size() != 4:
				return {}
			var noten: Dictionary = ExhaustiveDraw.noten_payout(tenpai)
			for s in range(4):
				final_scores[s] = int(final_scores[s]) + int(noten.get(s, 0))
			renchan = ExhaustiveDraw.is_dealer_renchan(dealer_seat, tenpai)
		OUTCOME_ABORTIVE:
			renchan = true
		_:
			return {}

	var next_honba: int = (start_honba + 1) if renchan else 0
	var deltas: Array = []
	for i in range(4):
		deltas.append(int(final_scores[i]) - int(start_scores[i]))

	return {
		"hand_seq": int(state.hand_seq),
		"outcome": outcome,
		"winner_seats": winners.duplicate(),
		"loser_seat": loser_seat,
		"score_deltas": deltas,
		"scores": final_scores,
		"dealer_seat": dealer_seat,
		"renchan": renchan,
		"honba": next_honba,
		"riichi_sticks": end_sticks,
		"adjustments": adjustments,
	}


## 真实等待牌听牌检测（与 PracticeMatchRunner 语义一致）。
static func detect_tenpai_array(state: BattleState) -> Array:
	var result: Array = []
	if state == null or state.seats.size() != 4:
		return [false, false, false, false]
	for seat_index in range(4):
		var seat: Seat = state.seats[seat_index]
		if seat == null or seat.hand == null:
			result.append(false)
			continue
		var melds: Array = []
		if seat.melds != null:
			for m in seat.melds.all():
				melds.append(m)
		result.append(not WaitCalculator.wait_tiles(seat.hand, melds).is_empty())
	return result


## STANDARD 守恒：sum(scores) + riichi_sticks*1000 == 100000。
static func is_conserved(scores: Array, riichi_sticks: int) -> bool:
	if typeof(scores) != TYPE_ARRAY or scores.size() != 4:
		return false
	if riichi_sticks < 0:
		return false
	var total := 0
	for s in scores:
		total += int(s)
	return total + riichi_sticks * RIICHI_STICK_VALUE == STARTING_TOTAL


## 空 tracker（调用方持有；回滚须整份 restore）。
static func empty_tracker() -> Dictionary:
	return {
		"committed_hand_seq": -1,
		"result": {},
		"fingerprint": "",
	}


## 规范结果指纹（幂等/冲突比对）。
static func result_fingerprint(result: Dictionary) -> String:
	if result == null or result.is_empty():
		return ""
	return JSON.stringify({
		"hand_seq": result.get("hand_seq", null),
		"outcome": result.get("outcome", null),
		"winner_seats": result.get("winner_seats", null),
		"loser_seat": result.get("loser_seat", null),
		"score_deltas": result.get("score_deltas", null),
		"scores": result.get("scores", null),
		"dealer_seat": result.get("dealer_seat", null),
		"renchan": result.get("renchan", null),
		"honba": result.get("honba", null),
		"riichi_sticks": result.get("riichi_sticks", null),
		"adjustments": result.get("adjustments", null),
	})


## 读取已提交规范结果；无则 {}。
static func committed_result(tracker: Dictionary) -> Dictionary:
	if tracker == null or typeof(tracker) != TYPE_DICTIONARY:
		return {}
	if int(tracker.get("committed_hand_seq", -1)) < 0:
		return {}
	var r: Variant = tracker.get("result", {})
	if typeof(r) != TYPE_DICTIONARY:
		return {}
	return (r as Dictionary).duplicate(true)


## 结构完整性：严格类型/范围/交叉规则，禁止静默 int()/str() 转换。
static func is_valid_result(result: Dictionary) -> bool:
	if result == null or typeof(result) != TYPE_DICTIONARY or result.is_empty():
		return false
	if result.keys().size() != RESULT_KEYS.size():
		return false
	for k in RESULT_KEYS:
		if not result.has(k):
			return false

	if typeof(result["hand_seq"]) != TYPE_INT:
		return false
	var hs: int = result["hand_seq"]
	if hs < 0 or hs > Wall.MAX_HAND_SEQ:
		return false

	if typeof(result["outcome"]) != TYPE_STRING:
		return false
	var outcome: String = result["outcome"]
	if outcome not in [
		OUTCOME_RON, OUTCOME_TSUMO, OUTCOME_EXHAUSTIVE, OUTCOME_ABORTIVE, OUTCOME_NAGASHI
	]:
		return false

	if typeof(result["winner_seats"]) != TYPE_ARRAY:
		return false
	var winners: Array = result["winner_seats"]
	var prev := -1
	var seen_w: Dictionary = {}
	for w in winners:
		if typeof(w) != TYPE_INT:
			return false
		var wi: int = w
		if wi < 0 or wi > 3:
			return false
		if seen_w.has(wi):
			return false
		seen_w[wi] = true
		if prev >= 0 and wi <= prev:
			return false
		prev = wi

	if typeof(result["loser_seat"]) != TYPE_INT:
		return false
	var loser: int = result["loser_seat"]
	if loser < -1 or loser > 3:
		return false

	match outcome:
		OUTCOME_RON:
			if winners.size() != 1:
				return false
			if loser < 0 or loser > 3 or seen_w.has(loser):
				return false
		OUTCOME_TSUMO, OUTCOME_NAGASHI:
			if winners.size() != 1:
				return false
			if loser != -1:
				return false
		OUTCOME_EXHAUSTIVE, OUTCOME_ABORTIVE:
			if not winners.is_empty():
				return false
			if loser != -1:
				return false
		_:
			return false

	if not _is_four_strict_ints(result["score_deltas"]):
		return false
	if not _is_four_strict_ints(result["scores"]):
		return false

	if typeof(result["dealer_seat"]) != TYPE_INT:
		return false
	var dealer: int = result["dealer_seat"]
	if dealer < 0 or dealer > 3:
		return false

	if typeof(result["renchan"]) != TYPE_BOOL:
		return false

	if typeof(result["honba"]) != TYPE_INT or result["honba"] < 0:
		return false
	if typeof(result["riichi_sticks"]) != TYPE_INT or result["riichi_sticks"] < 0:
		return false

	if not _is_valid_adjustments(result["adjustments"]):
		return false
	return true


static func _is_four_strict_ints(raw: Variant) -> bool:
	if typeof(raw) != TYPE_ARRAY:
		return false
	var a: Array = raw
	if a.size() != 4:
		return false
	for v in a:
		if typeof(v) != TYPE_INT:
			return false
	return true


static func _is_valid_adjustments(raw: Variant) -> bool:
	if typeof(raw) != TYPE_ARRAY:
		return false
	for item in raw:
		if typeof(item) != TYPE_DICTIONARY:
			return false
		var d: Dictionary = item
		if d.keys().size() != 4:
			return false
		for k in ["kind", "seat", "delta", "source"]:
			if not d.has(k):
				return false
		if typeof(d["kind"]) != TYPE_STRING:
			return false
		if d["kind"] not in [ADJUSTMENT_KIND_IN_HAND, ADJUSTMENT_KIND_EXTERNAL]:
			return false
		if typeof(d["seat"]) != TYPE_INT:
			return false
		var seat: int = d["seat"]
		if seat < 0 or seat > 3:
			return false
		if typeof(d["delta"]) != TYPE_INT:
			return false
		if typeof(d["source"]) != TYPE_STRING:
			return false
		var source: String = d["source"]
		if source.is_empty() or source.length() > 64:
			return false
	return true


## 原子提交：预校验全部目标后一次写；同 fingerprint 幂等；同 seq 冲突失败零 mutation。
## tracker: empty_tracker() 形状。
## start_scores：本局起分（首次提交必填有效 4 int，用于 score_deltas 交叉校验）。
## enforce_conservation：STANDARD 须 true；TRASH_TALK 为 false。
static func commit(
	result: Dictionary,
	ledger_scores: Array,
	tracker: Dictionary,
	state: BattleState = null,
	start_scores: Array = [],
	enforce_conservation: bool = true
) -> bool:
	if not is_valid_result(result):
		return false
	if typeof(ledger_scores) != TYPE_ARRAY or ledger_scores.size() != 4:
		return false
	# ledger 每席须为 int（禁止 float/str 静默写入）
	for i in range(4):
		if typeof(ledger_scores[i]) != TYPE_INT:
			return false
	if tracker == null or typeof(tracker) != TYPE_DICTIONARY:
		return false

	var hand_seq: int = result["hand_seq"]
	var fp: String = result_fingerprint(result)
	if fp.is_empty():
		return false
	var already: int = -1
	if typeof(tracker.get("committed_hand_seq", -1)) == TYPE_INT:
		already = tracker["committed_hand_seq"]
	elif tracker.has("committed_hand_seq"):
		return false

	if already == hand_seq:
		var stored_fp: String = str(tracker.get("fingerprint", ""))
		if stored_fp != fp:
			return false  # 同 hand 冲突
		# 幂等：复用 canonical，强制 ledger/state 与规范结果对齐（不二次加减）
		var canon: Dictionary = committed_result(tracker)
		if canon.is_empty():
			return false
		return _apply_result_to_targets(canon, ledger_scores, state)

	# 首次提交：起分 × score_deltas 交叉校验 + 可选 STANDARD 守恒
	if not _validate_start_scores_and_deltas(result, start_scores):
		return false
	if enforce_conservation:
		if not is_conserved(result["scores"], result["riichi_sticks"]):
			return false

	# 预检 state 形状（失败零 mutation）
	if state != null:
		if typeof(state.scores) != TYPE_ARRAY or state.scores.size() != 4:
			return false
		for i2 in range(4):
			if typeof(state.scores[i2]) != TYPE_INT:
				return false
		if state.seats.size() != 4:
			return false

	if not _apply_result_to_targets(result, ledger_scores, state):
		return false
	tracker["committed_hand_seq"] = hand_seq
	tracker["result"] = result.duplicate(true)
	tracker["fingerprint"] = fp
	return true


static func _validate_start_scores_and_deltas(result: Dictionary, start_scores: Array) -> bool:
	if typeof(start_scores) != TYPE_ARRAY or start_scores.size() != 4:
		return false
	for i in range(4):
		if typeof(start_scores[i]) != TYPE_INT:
			return false
	var scores: Array = result["scores"]
	var deltas: Array = result["score_deltas"]
	for i2 in range(4):
		if int(scores[i2]) - int(start_scores[i2]) != int(deltas[i2]):
			return false
	return true


static func _apply_result_to_targets(
	result: Dictionary,
	ledger_scores: Array,
	state: BattleState
) -> bool:
	var final_scores: Array = result["scores"]
	for i in range(4):
		if typeof(final_scores[i]) != TYPE_INT:
			return false
		ledger_scores[i] = final_scores[i]
	if state != null:
		for i2 in range(4):
			state.scores[i2] = final_scores[i2]
			if state.seats[i2] is Seat:
				(state.seats[i2] as Seat).points = final_scores[i2]
		if typeof(result["riichi_sticks"]) != TYPE_INT or typeof(result["honba"]) != TYPE_INT:
			return false
		state.riichi_sticks = result["riichi_sticks"]
		state.honba = result["honba"]
	return true


## 将规范 outcome 映射到 GameDriver 历史 kind 字符串。
static func outcome_to_driver_kind(outcome: String) -> String:
	match outcome:
		OUTCOME_RON:
			return "ron"
		OUTCOME_TSUMO:
			return "tsumo"
		OUTCOME_NAGASHI:
			return "nagashi_mangan"
		OUTCOME_ABORTIVE:
			return "abortive_draw"
		OUTCOME_EXHAUSTIVE:
			return "exhaustive_draw"
		_:
			return ""


## GameDriver kind → 协议 outcome。
static func driver_kind_to_outcome(kind: String) -> String:
	match kind:
		"ron":
			return OUTCOME_RON
		"tsumo":
			return OUTCOME_TSUMO
		"nagashi_mangan":
			return OUTCOME_NAGASHI
		"abortive_draw":
			return OUTCOME_ABORTIVE
		"exhaustive_draw":
			return OUTCOME_EXHAUSTIVE
		_:
			return ""


# ---- internal ----

static func _copy4_scores(raw: Array) -> Array:
	if raw == null or raw.size() != 4:
		return []
	var out: Array = []
	for i in range(4):
		out.append(int(raw[i]))
	return out


static func _parse_outcome(events: Array, state: BattleState) -> Dictionary:
	if events == null:
		return {}
	# 倒序：WIN > NAGASHI > ABORTIVE > EXHAUSTIVE
	for i in range(events.size() - 1, -1, -1):
		var ev: BattleEvent = events[i] as BattleEvent
		if ev == null:
			continue
		if ev.type == &"WIN_DECLARED":
			var extra: Dictionary = ev.extra if typeof(ev.extra) == TYPE_DICTIONARY else {}
			var winner: int = int(ev.actor_seat)
			if winner < 0 or winner > 3:
				return {}
			var is_tsumo: bool = bool(extra.get("is_tsumo", false))
			var loser: int = int(extra.get("discarder_seat", -1))
			# 若缺 is_tsumo / discarder，用前方 RON/TSUMO_DECLARED 推断
			if not extra.has("is_tsumo") or (not is_tsumo and loser < 0):
				is_tsumo = true
				for j in range(i - 1, -1, -1):
					var earlier: BattleEvent = events[j] as BattleEvent
					if earlier == null:
						continue
					if earlier.type == &"RON_DECLARED":
						is_tsumo = false
						if loser < 0 and typeof(earlier.extra) == TYPE_DICTIONARY:
							loser = int(earlier.extra.get("discarder_seat", -1))
						break
					if earlier.type == &"TSUMO_DECLARED":
						break
			if is_tsumo:
				return {
					"outcome": OUTCOME_TSUMO,
					"winner_seats": [winner],
					"loser_seat": -1,
					"win_extra": extra,
				}
			# 将推断到的 discarder 写回 extra，供 payout 校验使用
			if loser >= 0 and not extra.has("discarder_seat"):
				extra = extra.duplicate()
				extra["discarder_seat"] = loser
			return {
				"outcome": OUTCOME_RON,
				"winner_seats": [winner],
				"loser_seat": loser,
				"win_extra": extra,
			}
		if ev.type == &"NAGASHI_MANGAN":
			var nm_w: int = int(ev.actor_seat)
			if nm_w < 0:
				nm_w = int(ev.extra.get("winner_seat", -1)) if typeof(ev.extra) == TYPE_DICTIONARY else -1
			if nm_w < 0 or nm_w > 3:
				return {}
			return {
				"outcome": OUTCOME_NAGASHI,
				"winner_seats": [nm_w],
				"loser_seat": -1,
				"win_extra": {},
			}
		if ev.type == &"ABORTIVE_DRAW":
			return {
				"outcome": OUTCOME_ABORTIVE,
				"winner_seats": [],
				"loser_seat": -1,
				"win_extra": {},
			}
		if ev.type == &"EXHAUSTIVE_DRAW":
			# 若同批已有 NAGASHI，倒序会先命中 NAGASHI；此处为普通流局
			# 仍兜底 detect（events 未带 NAGASHI 但条件成立）
			var det: int = NagashiMangan.detect_winner_seat(state)
			if det >= 0:
				return {
					"outcome": OUTCOME_NAGASHI,
					"winner_seats": [det],
					"loser_seat": -1,
					"win_extra": {},
				}
			return {
				"outcome": OUTCOME_EXHAUSTIVE,
				"winner_seats": [],
				"loser_seat": -1,
				"win_extra": {},
			}
	# 无结算事件时：仍可能是流し満貫（GameDriver 历史兜底）
	if state != null:
		var det2: int = NagashiMangan.detect_winner_seat(state)
		if det2 >= 0:
			return {
				"outcome": OUTCOME_NAGASHI,
				"winner_seats": [det2],
				"loser_seat": -1,
				"win_extra": {},
			}
	return {}


static func _apply_win_payout(
	final_scores: Array, win_extra: Dictionary, winners: Array
) -> bool:
	if winners.size() != 1:
		return false
	var winner_actor: int = int(winners[0])
	if winner_actor < 0 or winner_actor > 3:
		return false
	var payout: Variant = win_extra.get("payout", {})
	if typeof(payout) != TYPE_DICTIONARY:
		return false
	for seat_id in payout:
		var si: int = int(seat_id)
		if si < 0 or si > 3:
			return false
		# PayoutCalculator：正值 = 该席应付给赢家的金额
		final_scores[si] = int(final_scores[si]) - int(payout[seat_id])
	final_scores[winner_actor] = int(final_scores[winner_actor]) \
		+ int(win_extra.get("winner_total", 0))
	return true


## 局内 state.scores 相对起始分的可解释调整。
## invariant：对每席 sum(adjustments.delta) == state[i]-start[i]（不重叠计数）。
## 守恒 transfer / 立直扣分 → IN_HAND；mint/burn 缺口 → EXTERNAL。
static func _build_adjustments(
	start_scores: Array,
	state_scores: Array,
	start_riichi_sticks: int,
	end_riichi_sticks: int
) -> Array:
	var seat_delta: Array = []
	var sum_delta := 0
	for i in range(4):
		var d: int = int(state_scores[i]) - int(start_scores[i])
		seat_delta.append(d)
		sum_delta += d
	var stick_delta: int = end_riichi_sticks - start_riichi_sticks
	var external_total: int = sum_delta + stick_delta * RIICHI_STICK_VALUE

	var external_share: Array = [0, 0, 0, 0]
	if external_total != 0:
		var candidates: Array = []
		for i2 in range(4):
			if external_total > 0 and int(seat_delta[i2]) > 0:
				candidates.append(i2)
			elif external_total < 0 and int(seat_delta[i2]) < 0:
				candidates.append(i2)
		if candidates.is_empty():
			var best := 0
			for i3 in range(1, 4):
				if absi(int(seat_delta[i3])) > absi(int(seat_delta[best])):
					best = i3
			external_share[best] = external_total
		else:
			var weight_sum := 0
			for c in candidates:
				weight_sum += absi(int(seat_delta[c]))
			var assigned := 0
			for idx in range(candidates.size()):
				var seat_i: int = int(candidates[idx])
				if idx == candidates.size() - 1:
					external_share[seat_i] = external_total - assigned
				else:
					var part: int = int(round(
						float(external_total) * float(absi(int(seat_delta[seat_i]))) / float(weight_sum)
					))
					if external_total > 0:
						part = mini(part, int(seat_delta[seat_i]))
						part = maxi(part, 0)
					else:
						part = maxi(part, int(seat_delta[seat_i]))
						part = mini(part, 0)
					external_share[seat_i] = part
					assigned += part

	var out: Array = []
	for i4 in range(4):
		var ext: int = int(external_share[i4])
		var in_hand: int = int(seat_delta[i4]) - ext
		if in_hand != 0:
			out.append({
				"kind": ADJUSTMENT_KIND_IN_HAND,
				"seat": i4,
				"delta": in_hand,
				"source": "battle_state_scores",
			})
		if ext != 0:
			out.append({
				"kind": ADJUSTMENT_KIND_EXTERNAL,
				"seat": i4,
				"delta": ext,
				"source": "mint_or_burn",
			})
	return out
