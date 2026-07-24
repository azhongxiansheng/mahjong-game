class_name MatchSettlement extends RefCounted

# E2-05（#235）：整场结算纯逻辑。
# 排名契约对齐 NetworkedEvent.MATCH_SETTLED：final_scores 降序，同分 seat_id 升序。
# 不发射网络事件，不触达 Run 奖励。


static func build_seat_order(final_scores: Array) -> Array:
	if final_scores == null or final_scores.size() != 4:
		return []
	var pairs: Array = []
	for seat_id in range(4):
		var raw: Variant = final_scores[seat_id]
		if typeof(raw) != TYPE_INT and typeof(raw) != TYPE_FLOAT:
			return []
		pairs.append([int(raw), seat_id])
	pairs.sort_custom(func(a: Array, b: Array) -> bool:
		if int(a[0]) != int(b[0]):
			return int(a[0]) > int(b[0])
		return int(a[1]) < int(b[1])
	)
	var order: Array = []
	for pair in pairs:
		order.append(int(pair[1]))
	return order


static func seat_display_name(seat_id: int) -> String:
	if seat_id == 0:
		return "你"
	return "AI %d" % seat_id


static func build_view(final_scores: Array, round_kind: StringName = &"") -> Dictionary:
	var order: Array = build_seat_order(final_scores)
	var rows: Array = []
	for i in range(order.size()):
		var seat_id: int = int(order[i])
		var score: int = 0
		if seat_id >= 0 and seat_id < final_scores.size():
			score = int(final_scores[seat_id])
		rows.append({
			"rank": i + 1,
			"seat_id": seat_id,
			"name": seat_display_name(seat_id),
			"score": score,
		})
	var scores_copy: Array = []
	if final_scores != null:
		for v in final_scores:
			scores_copy.append(int(v) if typeof(v) in [TYPE_INT, TYPE_FLOAT] else 0)
	return {
		"title": "对局结束",
		"round_kind": round_kind,
		"final_scores": scores_copy,
		"seat_order": order,
		"rows": rows,
	}
