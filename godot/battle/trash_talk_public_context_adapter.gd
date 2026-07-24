class_name TrashTalkPublicContextAdapter extends RefCounted

# E5-03 / #251：公开上下文适配边界。
# 只接受经 NetworkedEvent.from_dict 验证的权威公开事件 + 严格白名单 public_initial。
# 绝不读取手牌/牌墙/隐藏字段/客户端自报标签。

## 全局可见（任意席可能共享）
const GLOBAL_TAGS: Array[String] = [
	"CTX_RIICHI_OPEN",
	"CTX_MELD_SEEN",
	"CTX_WINDOW_LATE",
	"CTX_DORA_REVEALED",
]

## 逐席标签
const SEAT_TAGS: Array[String] = [
	"CTX_SEAT_LEADING",
	"CTX_SEAT_TRAILING",
	"CTX_IS_DEALER",
	"CTX_RON_WINNER",
	"CTX_TSUMO_WINNER",
	"CTX_DEAL_IN_LOSER",
]

const CLAIM_ACTION_KINDS: Array[String] = [
	"PASS", "CHI", "PON",
]

const MELD_ACTION_KINDS: Array[String] = [
	"CHI", "PON", "KAN",
]

const PUBLIC_INITIAL_REQUIRED: Array[String] = [
	"hand_seq", "dealer_seat", "scores",
]
const PUBLIC_INITIAL_OPTIONAL: Array[String] = [
	"turn_count", "dora_visible_count",
]


## BattleState → 公开白名单快照。禁止复制 seats/hand/wall 等私有字段。
## 练习场唯一构造 public_initial 的权威路径。
static func public_snapshot_from_battle_state(state: BattleState) -> Dictionary:
	if state == null:
		return {}
	var scores: Array = []
	if state.scores is Array:
		for s in state.scores:
			scores.append(int(s))
	while scores.size() < 4:
		scores.append(BattleState.STARTING_SCORE)
	if scores.size() > 4:
		scores = scores.slice(0, 4)
	return {
		"hand_seq": int(state.hand_seq),
		"dealer_seat": int(state.dealer_seat),
		"scores": scores,
		"turn_count": int(state.turn_count),
		"dora_visible_count": _dora_visible_count(state),
	}


## 严格校验 public_initial（白名单 + hand_seq 绑定）。
## 成功：{ok:true, clean:{...}}；失败：{ok:false, reason:"..."}。
static func validate_public_initial(raw: Variant, expected_hand_seq: int) -> Dictionary:
	if raw == null:
		return {"ok": false, "reason": "MISSING_PUBLIC_INITIAL"}
	if typeof(raw) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "INVALID_PUBLIC_INITIAL"}
	var ini: Dictionary = raw

	var allowed: Dictionary = {}
	for k in PUBLIC_INITIAL_REQUIRED:
		allowed[k] = true
	for k2 in PUBLIC_INITIAL_OPTIONAL:
		allowed[k2] = true
	for key in ini.keys():
		var ks := String(key)
		if not allowed.has(ks):
			return {"ok": false, "reason": "PUBLIC_INITIAL_UNKNOWN_KEY"}

	for req in PUBLIC_INITIAL_REQUIRED:
		if not ini.has(req):
			return {"ok": false, "reason": "PUBLIC_INITIAL_MISSING_FIELD"}

	if not _is_int(ini.get("hand_seq", null)):
		return {"ok": false, "reason": "INVALID_PUBLIC_INITIAL_HAND_SEQ"}
	var ini_hs: int = int(ini["hand_seq"])
	if ini_hs < 0:
		return {"ok": false, "reason": "INVALID_PUBLIC_INITIAL_HAND_SEQ"}
	if ini_hs != expected_hand_seq:
		return {"ok": false, "reason": "PUBLIC_INITIAL_HAND_SEQ_MISMATCH"}

	if not _is_int(ini.get("dealer_seat", null)):
		return {"ok": false, "reason": "INVALID_DEALER_SEAT"}
	var dealer: int = int(ini["dealer_seat"])
	if dealer < 0 or dealer > 3:
		return {"ok": false, "reason": "INVALID_DEALER_SEAT"}

	if not (ini.get("scores", null) is Array):
		return {"ok": false, "reason": "INVALID_SCORES"}
	var raw_scores: Array = ini["scores"]
	if raw_scores.size() != 4:
		return {"ok": false, "reason": "INVALID_SCORES"}
	var scores: Array = []
	for s in raw_scores:
		if not _is_int(s):
			return {"ok": false, "reason": "INVALID_SCORES"}
		scores.append(int(s))

	var clean := {
		"hand_seq": ini_hs,
		"dealer_seat": dealer,
		"scores": scores,
	}
	if ini.has("turn_count"):
		if not _is_int(ini.get("turn_count", null)):
			return {"ok": false, "reason": "INVALID_TURN_COUNT"}
		var tc: int = int(ini["turn_count"])
		if tc < 0:
			return {"ok": false, "reason": "INVALID_TURN_COUNT"}
		clean["turn_count"] = tc
	if ini.has("dora_visible_count"):
		if not _is_int(ini.get("dora_visible_count", null)):
			return {"ok": false, "reason": "INVALID_DORA_VISIBLE_COUNT"}
		var dv: int = int(ini["dora_visible_count"])
		if dv < 0:
			return {"ok": false, "reason": "INVALID_DORA_VISIBLE_COUNT"}
		clean["dora_visible_count"] = dv
	return {"ok": true, "clean": clean}


## 将原始 public_events 规范为权威 NetworkedEvent 列表。
static func normalize_public_events(
	raw: Variant,
	room_id: String,
	hand_seq: int
) -> Array:
	var out: Array = []
	if not (raw is Array):
		return out
	var expect_room := String(room_id)
	for item in raw:
		var ne: NetworkedEvent = null
		if item is NetworkedEvent:
			ne = item as NetworkedEvent
		elif typeof(item) == TYPE_DICTIONARY:
			ne = NetworkedEvent.from_dict(item)
		if ne == null:
			continue
		if not expect_room.is_empty() and String(ne.room_id) != expect_room:
			continue
		var hs_v: Variant = ne.payload.get("hand_seq", null)
		if typeof(hs_v) == TYPE_INT:
			if int(hs_v) != hand_seq:
				continue
		elif ne.kind in ["ACTION_APPLIED", "CLAIM_WINDOW", "HAND_SETTLED"]:
			continue
		out.append(ne)
	return out


## 全局公开标签（字典序）。public_initial 非法时返回空数组；调用方应检查 derive_seat 的 ok。
static func derive_public_context_tags(input: Dictionary) -> Array:
	var seat_map: Dictionary = derive_seat_public_context_tags(input)
	if not bool(seat_map.get("ok", false)):
		return []
	var global: Dictionary = {}
	for seat in range(4):
		for t in seat_map.get(str(seat), []):
			global[String(t)] = true
	var out: Array = global.keys()
	out.sort()
	return out


## 每席公开标签。
## 成功：{ok:true, dealer_seat, "0".."3": Array}
## 失败：{ok:false, reason, dealer_seat:-1, "0".."3": []}
static func derive_seat_public_context_tags(input: Dictionary) -> Dictionary:
	var empty_fail := func(reason: String) -> Dictionary:
		return {
			"ok": false,
			"reason": reason,
			"dealer_seat": -1,
			"0": [],
			"1": [],
			"2": [],
			"3": [],
		}

	var closing := _require_nonneg_int(input.get("closing_boundary_server_seq", 0))
	var context := _require_nonneg_int(input.get("context_boundary_server_seq", closing))
	if context < closing:
		context = closing

	if not _is_int(input.get("hand_seq", null)):
		return empty_fail.call("INVALID_HAND_SEQ")
	var hand_seq: int = int(input["hand_seq"])
	if hand_seq < 0:
		return empty_fail.call("INVALID_HAND_SEQ")
	var room_id := String(input.get("room_id", ""))

	var validated: Dictionary = validate_public_initial(
		input.get("public_initial", null),
		hand_seq
	)
	if not bool(validated.get("ok", false)):
		return empty_fail.call(String(validated.get("reason", "INVALID_PUBLIC_INITIAL")))
	var clean: Dictionary = validated["clean"]

	var seat_tag_sets: Array = [{}, {}, {}, {}]
	var dealer_seat: int = int(clean["dealer_seat"])
	var scores: Array = clean["scores"]
	var turn_count := 0
	var dora_visible := 0
	if clean.has("turn_count"):
		turn_count = int(clean["turn_count"])
	if clean.has("dora_visible_count"):
		dora_visible = int(clean["dora_visible_count"])

	seat_tag_sets[dealer_seat]["CTX_IS_DEALER"] = true

	var events: Array = normalize_public_events(
		input.get("public_events", []),
		room_id,
		hand_seq
	)
	for ne in events:
		_consume_networked_event(ne as NetworkedEvent, closing, context, seat_tag_sets)

	_apply_score_gap_tags(scores, seat_tag_sets)

	if turn_count >= 12:
		for i in range(4):
			seat_tag_sets[i]["CTX_WINDOW_LATE"] = true
	if dora_visible >= 2:
		for i in range(4):
			seat_tag_sets[i]["CTX_DORA_REVEALED"] = true

	var out := {
		"ok": true,
		"dealer_seat": dealer_seat,
	}
	for i in range(4):
		var keys: Array = seat_tag_sets[i].keys()
		keys.sort()
		out[str(i)] = keys
	return out


## 事件是否进入本窗公开上下文。
## meld_kind 仅 KAN 需要：MINKAN 走 CLAIM 边界；ANKAN/ADDED_KAN 走 closing。
static func event_in_public_context(
	kind: String,
	action_kind: String,
	server_seq: int,
	closing_boundary: int,
	context_boundary: int,
	meld_kind: String = ""
) -> bool:
	if server_seq < 0:
		return false
	if server_seq > context_boundary:
		return false
	if kind == "CLAIM_WINDOW":
		return server_seq <= context_boundary
	if kind == "HAND_SETTLED":
		return server_seq <= context_boundary
	if kind == "ACTION_APPLIED":
		var ak := action_kind
		if ak == "RON" or ak == "TSUMO":
			return server_seq <= context_boundary
		if CLAIM_ACTION_KINDS.has(ak):
			return server_seq <= context_boundary
		if ak == "KAN":
			var mk := meld_kind
			if mk == "MINKAN":
				return server_seq <= context_boundary
			return server_seq <= closing_boundary
		return server_seq <= closing_boundary
	return server_seq <= closing_boundary


static func _consume_networked_event(
	ne: NetworkedEvent,
	closing: int,
	context: int,
	seat_tag_sets: Array
) -> void:
	var kind := String(ne.kind)
	var payload: Dictionary = ne.payload
	var seq: int = int(ne.server_seq)
	var action_kind := String(payload.get("action_kind", ""))
	var meld_kind := ""
	if action_kind == "KAN":
		var rp: Variant = payload.get("resolved_payload", {})
		if rp is Dictionary:
			var meld: Variant = (rp as Dictionary).get("meld", {})
			if meld is Dictionary:
				meld_kind = String((meld as Dictionary).get("kind", ""))

	if not event_in_public_context(kind, action_kind, seq, closing, context, meld_kind):
		return

	if kind == "ACTION_APPLIED":
		var actor: int = int(payload.get("seat", -1))
		var rp2: Dictionary = {}
		if payload.get("resolved_payload", null) is Dictionary:
			rp2 = payload["resolved_payload"]
		match action_kind:
			"RIICHI":
				for i in range(4):
					seat_tag_sets[i]["CTX_RIICHI_OPEN"] = true
			"CHI", "PON":
				for i in range(4):
					seat_tag_sets[i]["CTX_MELD_SEEN"] = true
			"KAN":
				if meld_kind in ["MINKAN", "ANKAN", "ADDED_KAN"]:
					for i in range(4):
						seat_tag_sets[i]["CTX_MELD_SEEN"] = true
			"RON":
				if actor >= 0 and actor <= 3:
					seat_tag_sets[actor]["CTX_RON_WINNER"] = true
				var from_seat: int = int(rp2.get("from_seat", -1))
				if from_seat >= 0 and from_seat <= 3:
					seat_tag_sets[from_seat]["CTX_DEAL_IN_LOSER"] = true
			"TSUMO":
				if actor >= 0 and actor <= 3:
					seat_tag_sets[actor]["CTX_TSUMO_WINNER"] = true
			_:
				pass
	elif kind == "HAND_SETTLED":
		var outcome := String(payload.get("outcome", ""))
		var winners: Array = payload.get("winner_seats", [])
		var loser_v: Variant = payload.get("loser_seat", null)
		if outcome == "RON":
			for w in winners:
				if _is_int(w) and int(w) >= 0 and int(w) <= 3:
					seat_tag_sets[int(w)]["CTX_RON_WINNER"] = true
			if _is_int(loser_v) and int(loser_v) >= 0 and int(loser_v) <= 3:
				seat_tag_sets[int(loser_v)]["CTX_DEAL_IN_LOSER"] = true
		elif outcome == "TSUMO":
			for w2 in winners:
				if _is_int(w2) and int(w2) >= 0 and int(w2) <= 3:
					seat_tag_sets[int(w2)]["CTX_TSUMO_WINNER"] = true


static func _apply_score_gap_tags(scores: Array, seat_tag_sets: Array) -> void:
	if scores.size() < 4:
		return
	var max_s: int = int(scores[0])
	var min_s: int = int(scores[0])
	for i in range(1, 4):
		var v: int = int(scores[i])
		if v > max_s:
			max_s = v
		if v < min_s:
			min_s = v
	if max_s == min_s:
		return
	for i in range(4):
		var v2: int = int(scores[i])
		if v2 == max_s:
			seat_tag_sets[i]["CTX_SEAT_LEADING"] = true
		if v2 == min_s:
			seat_tag_sets[i]["CTX_SEAT_TRAILING"] = true


static func _dora_visible_count(state: BattleState) -> int:
	if state == null or state.dora_indicators == null:
		return 0
	var di: DoraIndicators = state.dora_indicators
	if di.visible is Array:
		return di.visible.size()
	return 0


static func _require_nonneg_int(v: Variant) -> int:
	if typeof(v) != TYPE_INT:
		return 0
	var n: int = int(v)
	if n < 0:
		return 0
	return n


static func _is_int(v: Variant) -> bool:
	return typeof(v) == TYPE_INT
