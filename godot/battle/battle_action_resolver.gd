class_name BattleActionResolver
extends RefCounted
## 确定性 reaction intent 裁决（不改 domain state）。
## 3 条实际 RON → SANCHA_HOURA；1–2 条 RON → 自 discarder 起顺时针最近者；
## 非 RON：RON > MINKAN > PON > CHI > PASS，同优先亦按相对距离（不得按 seat 数字）。

const OUTCOME_SANCHA_HOURA := "SANCHA_HOURA"
const OUTCOME_WINNER := "WINNER"
const OUTCOME_ALL_PASS := "ALL_PASS"


## intents: Array[Action]；discarder_seat: 弃牌/加杠宣告座。
## 返 {outcome: String, winner: Action|null}；winner 为深拷贝。
static func resolve(intents: Array, discarder_seat: int) -> Dictionary:
	if typeof(discarder_seat) != TYPE_INT or discarder_seat < 0 or discarder_seat > 3:
		return {"outcome": OUTCOME_ALL_PASS, "winner": null}
	var cloned: Array = []
	for raw in intents:
		if not (raw is Action):
			continue
		var c: Action = Action.from_dict((raw as Action).to_dict())
		if c != null:
			cloned.append(c)

	var ron_list: Array = []
	for a in cloned:
		if (a as Action).kind == "RON":
			ron_list.append(a)
	if ron_list.size() >= 3:
		return {"outcome": OUTCOME_SANCHA_HOURA, "winner": null}
	if ron_list.size() >= 1:
		return {
			"outcome": OUTCOME_WINNER,
			"winner": _pick_nearest(ron_list, discarder_seat),
		}

	var best: Action = null
	var best_pri: int = -1
	var best_dist: int = 99
	for a in cloned:
		var act: Action = a as Action
		var pri: int = _priority(act)
		if pri < 0:
			continue
		var dist: int = _clockwise_distance(discarder_seat, act.seat)
		if pri > best_pri or (pri == best_pri and dist < best_dist):
			best_pri = pri
			best_dist = dist
			best = act
	if best == null or best.kind == "PASS" or best_pri <= 0:
		return {"outcome": OUTCOME_ALL_PASS, "winner": null}
	return {
		"outcome": OUTCOME_WINNER,
		"winner": Action.from_dict(best.to_dict()),
	}


static func _pick_nearest(actions: Array, discarder_seat: int) -> Action:
	var best: Action = null
	var best_dist: int = 99
	for a in actions:
		var act: Action = a as Action
		var dist: int = _clockwise_distance(discarder_seat, act.seat)
		if dist < best_dist:
			best_dist = dist
			best = act
	if best == null:
		return null
	return Action.from_dict(best.to_dict())


## 自 discarder 起顺时针到 seat 的距离（1..3）；同座返 4（不参与头跳）。
static func _clockwise_distance(discarder_seat: int, seat: int) -> int:
	if seat == discarder_seat:
		return 4
	return (seat - discarder_seat + 4) % 4


static func _priority(action: Action) -> int:
	if action == null:
		return -1
	match action.kind:
		"RON":
			return 40
		"KAN":
			# MINKAN only in claim reactions
			if str(action.payload.get("kan_kind", "")) == "MINKAN":
				return 30
			return -1
		"PON":
			return 20
		"CHI":
			return 10
		"PASS":
			return 0
		_:
			return -1
