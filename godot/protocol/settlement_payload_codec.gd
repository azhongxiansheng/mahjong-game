class_name SettlementPayloadCodec extends RefCounted

# ARCH-03 #393：结算 payload codec —— HAND_SETTLED / MATCH_SETTLED。
# 校验语义与拆分前 NetworkedEvent 完全一致。

const HAND_SETTLED_KEYS := [
	"hand_seq", "outcome", "winner_seats", "loser_seat", "score_deltas", "scores",
	"dealer_seat", "renchan", "honba", "riichi_sticks", "adjustments",
]

const HAND_OUTCOMES := [
	"RON", "TSUMO", "EXHAUSTIVE_DRAW", "ABORTIVE_DRAW", "NAGASHI_MANGAN",
]

const HAND_SETTLED_ADJUSTMENT_KEYS := ["kind", "seat", "delta", "source"]

const HAND_SETTLED_ADJUSTMENT_KINDS := ["IN_HAND", "EXTERNAL"]

const MATCH_SETTLED_KEYS := ["round_kind", "final_scores", "seat_order"]

const MATCH_ROUND_KINDS := ["EAST", "HANCHAN"]


static func validate_hand_settled(p: Dictionary) -> Variant:
	if not EventPayloadCodecUtil._has_exact_keys(p, HAND_SETTLED_KEYS):
		return null

	if typeof(p["hand_seq"]) != TYPE_INT:
		return null
	var hs: int = p["hand_seq"]
	if hs < 0 or hs > ProtocolConstants.MAX_HAND_SEQ:
		return null

	if typeof(p["outcome"]) != TYPE_STRING:
		return null
	var outcome: String = p["outcome"]
	if outcome not in HAND_OUTCOMES:
		return null

	if typeof(p["winner_seats"]) != TYPE_ARRAY:
		return null
	var winners_raw: Array = p["winner_seats"]
	var winners: Array = []
	var prev := -1
	var seen_w: Dictionary = {}
	for w in winners_raw:
		if typeof(w) != TYPE_INT:
			return null
		var wi: int = w
		if wi < 0 or wi > 3:
			return null
		if seen_w.has(wi):
			return null
		seen_w[wi] = true
		# 输入必须已升序
		if prev >= 0 and wi <= prev:
			return null
		prev = wi
		winners.append(wi)

	if typeof(p["loser_seat"]) != TYPE_INT:
		return null
	var loser: int = p["loser_seat"]
	if loser < -1 or loser > 3:
		return null

	match outcome:
		"RON":
			# 协议：RON 恰好单 winner（不支持多响）
			if winners.size() != 1:
				return null
			if loser < 0 or loser > 3:
				return null
			if seen_w.has(loser):
				return null
		"TSUMO", "NAGASHI_MANGAN":
			if winners.size() != 1:
				return null
			if loser != -1:
				return null
		"EXHAUSTIVE_DRAW", "ABORTIVE_DRAW":
			if not winners.is_empty():
				return null
			if loser != -1:
				return null
		_:
			return null

	# A 契约：score_deltas = 本局最终分 - 本局起始分。
	# 局前桌上立直棒进入赢家分数时局内 delta 和可合法非零，禁止静态 sum==0。
	var deltas: Variant = _validate_four_safe_ints(p["score_deltas"])
	if deltas == null:
		return null

	var scores: Variant = _validate_four_safe_ints(p["scores"])
	if scores == null:
		return null

	if typeof(p["dealer_seat"]) != TYPE_INT:
		return null
	var dealer_seat: int = p["dealer_seat"]
	if dealer_seat < 0 or dealer_seat > 3:
		return null

	if typeof(p["renchan"]) != TYPE_BOOL:
		return null
	var renchan: bool = p["renchan"]

	if typeof(p["honba"]) != TYPE_INT:
		return null
	var honba: int = p["honba"]
	if honba < 0 or honba > ProtocolConstants.MAX_SAFE_INT:
		return null

	if typeof(p["riichi_sticks"]) != TYPE_INT:
		return null
	var riichi_sticks: int = p["riichi_sticks"]
	if riichi_sticks < 0 or riichi_sticks > ProtocolConstants.MAX_SAFE_INT:
		return null

	var adjustments: Variant = _validate_hand_settled_adjustments(p["adjustments"])
	if adjustments == null:
		return null

	return {
		"hand_seq": hs,
		"outcome": outcome,
		"winner_seats": winners,
		"loser_seat": loser,
		"score_deltas": deltas,
		"scores": scores,
		"dealer_seat": dealer_seat,
		"renchan": renchan,
		"honba": honba,
		"riichi_sticks": riichi_sticks,
		"adjustments": adjustments,
	}


static func _validate_hand_settled_adjustments(raw: Variant) -> Variant:
	if typeof(raw) != TYPE_ARRAY:
		return null
	var out: Array = []
	for item in raw:
		if typeof(item) != TYPE_DICTIONARY:
			return null
		var d: Dictionary = item
		if not EventPayloadCodecUtil._has_exact_keys(d, HAND_SETTLED_ADJUSTMENT_KEYS):
			return null
		if typeof(d["kind"]) != TYPE_STRING:
			return null
		var kind: String = d["kind"]
		if kind not in HAND_SETTLED_ADJUSTMENT_KINDS:
			return null
		if typeof(d["seat"]) != TYPE_INT:
			return null
		var seat: int = d["seat"]
		if seat < 0 or seat > 3:
			return null
		if typeof(d["delta"]) != TYPE_INT:
			return null
		var delta: int = d["delta"]
		if delta < -ProtocolConstants.MAX_SAFE_INT or delta > ProtocolConstants.MAX_SAFE_INT:
			return null
		if typeof(d["source"]) != TYPE_STRING:
			return null
		var source: String = d["source"]
		if source.is_empty() or source.length() > 64:
			return null
		out.append({
			"kind": kind,
			"seat": seat,
			"delta": delta,
			"source": source,
		})
	return out


static func validate_match_settled(p: Dictionary) -> Variant:
	if not EventPayloadCodecUtil._has_exact_keys(p, MATCH_SETTLED_KEYS):
		return null
	if typeof(p["round_kind"]) != TYPE_STRING:
		return null
	var rk: String = p["round_kind"]
	if rk not in MATCH_ROUND_KINDS:
		return null
	var finals: Variant = _validate_four_safe_ints(p["final_scores"])
	if finals == null:
		return null
	if typeof(p["seat_order"]) != TYPE_ARRAY:
		return null
	var order_raw: Array = p["seat_order"]
	if order_raw.size() != 4:
		return null
	var order: Array = []
	var seen: Dictionary = {}
	for s in order_raw:
		if typeof(s) != TYPE_INT:
			return null
		var si: int = s
		if si < 0 or si > 3:
			return null
		if seen.has(si):
			return null
		seen[si] = true
		order.append(si)
	if seen.size() != 4:
		return null
	# seat_order 必须恰好按 final_scores 降序；同分 seat 数字升序。拒绝不合顺序，不静默重排。
	var finals_arr: Array = finals as Array
	for i in range(order.size() - 1):
		var a: int = int(order[i])
		var b: int = int(order[i + 1])
		var sa: int = int(finals_arr[a])
		var sb: int = int(finals_arr[b])
		if sa < sb:
			return null
		if sa == sb and a > b:
			return null
	return {
		"round_kind": rk,
		"final_scores": finals,
		"seat_order": order,
	}


static func _validate_four_safe_ints(raw: Variant) -> Variant:
	if typeof(raw) != TYPE_ARRAY:
		return null
	var arr: Array = raw
	if arr.size() != 4:
		return null
	var out: Array = []
	for v in arr:
		var n: Variant = EventPayloadCodecUtil._require_safe_int(v)
		if n == null:
			return null
		out.append(int(n))
	return out
