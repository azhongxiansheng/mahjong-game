class_name RewardWindowModule extends RefCounted

# E5-04 / #252：欢乐场 RewardWindow 权威状态机（纯逻辑）。
# 练习场 LocalLoopback 与未来公共 Worker 共用；不发 ITEM_GRANTED。
# 合法转换：OPEN→CLOSING→SETTLED|CANCELLED 或 OPEN→CANCELLED。
# 出口优先级：CANCELLED_BY_WIN > DISPLAY_ONLY > FULL_GRANT。

const PHASE_IDLE := &"IDLE"
const PHASE_OPEN := &"OPEN"
const PHASE_CLOSING := &"CLOSING"
const PHASE_SETTLED := &"SETTLED"
const PHASE_CANCELLED := &"CANCELLED"

const EXIT_FULL_GRANT := "FULL_GRANT"
const EXIT_DISPLAY_ONLY := "DISPLAY_ONLY"
const EXIT_CANCELLED := "CANCELLED_BY_WIN"

const SETTLE_REASON_FULL_24 := "FULL_24_NO_WIN"
const SETTLE_REASON_NON_FINAL_DRAW := "NON_FINAL_DRAW"
const SETTLE_REASON_MATCH_END := "MATCH_END_NO_WIN"

const TARGET_DISCARDS := 24
const GRACE_MS := 1500
const ASSIGNMENT_VERSION := "assign_v1"
## #241 模块包络：schema_version 必须为正整数。
const SCHEMA_VERSION := 1
const MODULE_KEY := "reward_window"
## 公开事件递归禁止键（append 与 DTO restore 共用，隐藏信息隔离）。
const PUBLIC_EVENT_FORBIDDEN_KEYS := [
	"hand", "wall", "private_hand", "hidden_tiles", "seats",
	"match_seed", "seed", "private",
]
## 公开 DTO payload 白名单（#241 可接入；不含隐藏牌；可续跑 CLOSING→SETTLE）。
## 公开 DTO 不含 match_seed（隐藏权威 RNG/牌墙重建输入）；seed 仅服务端 capture_state。
const PAYLOAD_KEYS := [
	"phase", "window_id", "window_exit", "hand_seq", "window_index",
	"prize_pool", "discard_count", "closing_boundary_server_seq",
	"context_boundary_server_seq", "grace_deadline_at", "grace_deadline_ms",
	"grant_count", "rule_version", "assignment_version", "settle_reason",
	"pending_exit", "assignment", "matrix_summary", "scored", "grace_aborted",
	"claim_is_terminal", "room_id", "character_ids", "language",
	"public_initial", "utterances_by_seat", "public_events",
]
const _CAPTURE_REQUIRED := [
	"phase", "window_id", "window_exit", "hand_seq", "window_index", "prize_pool",
	"discard_count", "rule_version", "assignment_version",
	"closing_boundary_server_seq", "context_boundary_server_seq", "grace_deadline_at",
	"grant_count", "settle_reason", "scored", "grace_aborted", "matrix_summary",
	"assignment", "transcript_summary", "_match_seed", "_room_id", "_character_ids",
	"_language", "_participants", "_claim_is_terminal", "_grace_deadline_ms",
	"_utterances_by_seat", "_utterance_keys", "_ai_line_emitted", "_public_events",
	"_public_initial", "_opened_payload", "_closing_payload", "_settled_payload",
	"_cancelled_payload", "_pending_exit", "_scorer_called", "_discard_fingerprints",
	"_closing_input_fp",
]

var phase: StringName = PHASE_IDLE
var window_id: String = ""
var window_exit = null
var hand_seq: int = 0
var window_index: int = 0
var prize_pool: Array = []
var discard_count: int = 0
var rule_version: String = ""
var assignment_version: String = ASSIGNMENT_VERSION
var closing_boundary_server_seq = null
var context_boundary_server_seq = null
var grace_deadline_at: String = ""
var grant_count: int = 0
var settle_reason: String = ""
var scored: bool = false
var grace_aborted: bool = false
var matrix_summary: Dictionary = {}
var assignment: Dictionary = {}
var transcript_summary: Dictionary = {}

# 内部权威状态
var _match_seed: int = 0
var _room_id: String = ""
var _character_ids: Array = []
var _language: String = "zh"
var _participants: Array = [] # "HUMAN"/"AI" × 4
var _claim_is_terminal: bool = false
var _grace_deadline_ms: int = 0
var _utterances_by_seat: Dictionary = {"0": [], "1": [], "2": [], "3": []}
var _utterance_keys: Dictionary = {} # window_id|seat|utterance_id → true
var _ai_line_emitted: Dictionary = {} # seat → true
var _public_events: Array = []
var _public_initial: Dictionary = {}
var _opened_payload: Dictionary = {}
var _closing_payload: Dictionary = {}
var _settled_payload: Dictionary = {}
var _cancelled_payload: Dictionary = {}
var _pending_exit: String = "" # FULL_GRANT / DISPLAY_ONLY while CLOSING
var _scorer_called: bool = false
## 窗口内权威弃牌去重：fingerprint → true
var _discard_fingerprints: Dictionary = {}
## CLOSING 输入指纹（boundary|pending|reason|deadline_ms）
var _closing_input_fp: String = ""


## 确定性奖池（委托纯函数；可注入 catalog）。
static func select_prize_pool(
	match_seed: int,
	p_hand_seq: int,
	p_window_index: int,
	p_rule_version: String,
	catalog: Array = []
) -> Array:
	return RewardWindowPrizePool.select_four(
		match_seed, p_hand_seq, p_window_index, p_rule_version, catalog
	)


## 开窗。input 关键字段：seed, hand_seq, window_index, rule_version, room_id,
## character_ids[4], language?, participants?[4], public_initial?, catalog?
## 成功：{ok, kind:"REWARD_WINDOW_OPENED", payload, idempotent}
func open(input: Dictionary) -> Dictionary:
	if phase == PHASE_OPEN and not _opened_payload.is_empty():
		if _same_open_input(input):
			return {
				"ok": true,
				"kind": "REWARD_WINDOW_OPENED",
				"payload": _opened_payload.duplicate(true),
				"idempotent": true,
			}
		return _err("ALREADY_OPEN")
	if phase != PHASE_IDLE and phase != PHASE_SETTLED:
		# FULL_GRANT 后可开下一窗；其它终态/CLOSING 拒绝
		if phase == PHASE_CANCELLED:
			return _err("ALREADY_CANCELLED")
		if phase == PHASE_CLOSING:
			return _err("STILL_CLOSING")
		return _err("INVALID_PHASE")

	if not _is_int(input.get("seed", null)):
		return _err("INVALID_SEED")
	if not _is_int(input.get("hand_seq", null)):
		return _err("INVALID_HAND_SEQ")
	if not _is_int(input.get("window_index", null)):
		return _err("INVALID_WINDOW_INDEX")
	var seed_v: int = int(input["seed"])
	var hs: int = int(input["hand_seq"])
	var wi: int = int(input["window_index"])
	if hs < 0 or wi < 0:
		return _err("INVALID_HAND_SEQ")

	var rv := String(input.get("rule_version", "")).strip_edges()
	if rv.is_empty() or rv != TrashTalkRuleCatalog.rule_version():
		return _err("INVALID_RULE_VERSION")
	var room := String(input.get("room_id", "")).strip_edges()
	if room.is_empty():
		return _err("INVALID_ROOM_ID")

	var chars: Array = _normalize_character_ids(input.get("character_ids", null))
	if chars.is_empty():
		return _err("INVALID_CHARACTER_IDS")

	var catalog: Array = []
	if input.get("catalog", null) is Array:
		catalog = input["catalog"]
	var pool: Array = select_prize_pool(seed_v, hs, wi, rv, catalog)
	if pool.size() != 4:
		return _err("PRIZE_POOL_FAILED")
	var uniq: Dictionary = {}
	for id in pool:
		if uniq.has(String(id)):
			return _err("PRIZE_POOL_DUPLICATE")
		uniq[String(id)] = true

	var lang := String(input.get("language", "zh")).strip_edges().to_lower()
	if lang != "zh" and lang != "en" and lang != "ja":
		return _err("INVALID_LANGUAGE")

	var parts: Array = _normalize_participants(input.get("participants", null))
	var pub_ini: Dictionary = {}
	if typeof(input.get("public_initial", null)) == TYPE_DICTIONARY:
		pub_ini = (input["public_initial"] as Dictionary).duplicate(true)

	var wid := "hand_%d_window_%d" % [hs, wi]
	var payload := {
		"window_id": wid,
		"hand_seq": hs,
		"window_index": wi,
		"prize_pool": pool.duplicate(),
		"rule_version": rv,
		"phase": "OPEN",
		"window_exit": null,
	}

	# 提交状态
	_reset_runtime_for_new_window()
	phase = PHASE_OPEN
	window_id = wid
	window_exit = null
	hand_seq = hs
	window_index = wi
	prize_pool = pool.duplicate()
	rule_version = rv
	assignment_version = ASSIGNMENT_VERSION
	_match_seed = seed_v
	_room_id = room
	_character_ids = chars
	_language = lang
	_participants = parts
	_public_initial = pub_ini
	_opened_payload = payload.duplicate(true)
	return {
		"ok": true,
		"kind": "REWARD_WINDOW_OPENED",
		"payload": payload.duplicate(true),
		"idempotent": false,
	}


## 权威 DISCARD/RIICHI 弃牌计数。鸣牌/杠本身不得调用。
## input: server_seq, seat, kind("DISCARD"|"RIICHI"), now_ms?, is_ai?
## 第 24 次返回 CLOSING effect；否则 {ok, counted, discard_count}。
## 同一 fingerprint 完全重复幂等；同 seq 不同内容拒绝。
func on_discard_applied(input: Dictionary) -> Dictionary:
	if phase == PHASE_SETTLED or phase == PHASE_CANCELLED:
		return {"ok": true, "idempotent": true, "discard_count": discard_count, "counted": false}
	if phase != PHASE_OPEN and phase != PHASE_CLOSING:
		return _err("INVALID_PHASE")
	if phase == PHASE_CLOSING:
		return {"ok": true, "idempotent": true, "discard_count": discard_count, "counted": false}

	if not _is_int(input.get("server_seq", null)):
		return _err("INVALID_SERVER_SEQ")
	var seq: int = int(input["server_seq"])
	if seq <= 0:
		return _err("INVALID_SERVER_SEQ")
	if not _is_int(input.get("seat", null)):
		return _err("INVALID_SEAT")
	var seat: int = int(input["seat"])
	if seat < 0 or seat > 3:
		return _err("INVALID_SEAT")
	var kind := String(input.get("kind", "")).strip_edges().to_upper()
	if kind != "DISCARD" and kind != "RIICHI":
		return _err("INVALID_DISCARD_KIND")

	var fp := "%d|%d|%s" % [seq, seat, kind]
	# 同 server_seq 若曾见过任意弃牌指纹：完全相同 → 幂等；不同内容 → 冲突
	for existing_fp in _discard_fingerprints.keys():
		var parts: PackedStringArray = String(existing_fp).split("|")
		if parts.size() >= 1 and int(parts[0]) == seq:
			if String(existing_fp) == fp:
				return {
					"ok": true,
					"counted": false,
					"discard_count": discard_count,
					"idempotent": true,
				}
			return _err("DISCARD_FINGERPRINT_CONFLICT")
	if _discard_fingerprints.has(fp):
		return {
			"ok": true,
			"counted": false,
			"discard_count": discard_count,
			"idempotent": true,
		}

	_discard_fingerprints[fp] = true
	discard_count += 1
	if bool(input.get("is_ai", false)) and not _ai_line_emitted.get(seat, false):
		_try_emit_ai_line(seat, seq, input)

	if discard_count < TARGET_DISCARDS:
		return {
			"ok": true,
			"counted": true,
			"discard_count": discard_count,
			"idempotent": false,
		}

	var now_ms: int = _require_now_ms(input)
	return begin_closing({
		"closing_boundary_server_seq": seq,
		"now_ms": now_ms,
		"pending_exit": EXIT_FULL_GRANT,
		"settle_reason": SETTLE_REASON_FULL_24,
	})


## 进入 CLOSING。input: closing_boundary_server_seq, now_ms, pending_exit, settle_reason?
## 完全相同输入幂等；冲突输入拒绝。
func begin_closing(input: Dictionary) -> Dictionary:
	if phase == PHASE_SETTLED:
		return _err("ALREADY_SETTLED")
	if phase == PHASE_CANCELLED:
		return _err("ALREADY_CANCELLED")
	if phase != PHASE_OPEN and phase != PHASE_CLOSING:
		return _err("INVALID_PHASE")

	if not _is_int(input.get("closing_boundary_server_seq", null)):
		return _err("INVALID_CLOSING_BOUNDARY")
	var boundary: int = int(input["closing_boundary_server_seq"])
	if boundary <= 0:
		return _err("INVALID_CLOSING_BOUNDARY")

	var now_ms: int = _require_now_ms(input)
	var pending := String(input.get("pending_exit", EXIT_FULL_GRANT))
	if pending != EXIT_FULL_GRANT and pending != EXIT_DISPLAY_ONLY:
		return _err("INVALID_PENDING_EXIT")
	var reason := String(input.get("settle_reason", SETTLE_REASON_FULL_24)).strip_edges()
	if reason.is_empty():
		return _err("INVALID_SETTLE_REASON")

	var deadline_ms: int = now_ms + GRACE_MS
	var in_fp := "%d|%s|%s|%d" % [boundary, pending, reason, deadline_ms]
	if phase == PHASE_CLOSING and not _closing_payload.is_empty():
		if in_fp == _closing_input_fp:
			return {
				"ok": true,
				"kind": "REWARD_WINDOW_CLOSING",
				"payload": _closing_payload.duplicate(true),
				"idempotent": true,
			}
		return _err("CLOSING_INPUT_CONFLICT")

	var deadline_iso := format_iso_ms(deadline_ms)
	var payload := {
		"window_id": window_id,
		"hand_seq": hand_seq,
		"closing_boundary_server_seq": boundary,
		"grace_deadline_at": deadline_iso,
		"phase": "CLOSING",
		"window_exit": null,
	}

	phase = PHASE_CLOSING
	window_exit = null
	closing_boundary_server_seq = boundary
	grace_deadline_at = deadline_iso
	_grace_deadline_ms = deadline_ms
	_pending_exit = pending
	settle_reason = reason
	_closing_input_fp = in_fp
	_closing_payload = payload.duplicate(true)
	return {
		"ok": true,
		"kind": "REWARD_WINDOW_CLOSING",
		"payload": payload.duplicate(true),
		"idempotent": false,
	}


## 无 CLAIM 的 scoring close（流局/终场非和牌）：先 CLOSING 再可 settle。
## input: result_server_seq, now_ms, is_match_end:bool, is_final_hand_continue:bool
func begin_scoring_close(input: Dictionary) -> Dictionary:
	if phase == PHASE_CANCELLED:
		return _err("ALREADY_CANCELLED")
	if phase == PHASE_SETTLED and not _settled_payload.is_empty():
		return {
			"ok": true,
			"kind": "REWARD_WINDOW_SETTLED",
			"payload": _settled_payload.duplicate(true),
			"idempotent": true,
		}
	if not _is_int(input.get("result_server_seq", null)):
		return _err("INVALID_RESULT_SEQ")
	var rseq: int = int(input["result_server_seq"])
	if rseq <= 0:
		return _err("INVALID_RESULT_SEQ")
	var now_ms: int = _require_now_ms(input)
	var is_match_end: bool = bool(input.get("is_match_end", false))
	var pending := EXIT_DISPLAY_ONLY if is_match_end else EXIT_FULL_GRANT
	var reason := SETTLE_REASON_MATCH_END if is_match_end else SETTLE_REASON_NON_FINAL_DRAW

	var close_res: Dictionary
	if phase == PHASE_OPEN:
		close_res = begin_closing({
			"closing_boundary_server_seq": rseq,
			"now_ms": now_ms,
			"pending_exit": pending,
			"settle_reason": reason,
		})
		if not bool(close_res.get("ok", false)):
			return close_res
	elif phase == PHASE_CLOSING:
		close_res = {
			"ok": true,
			"kind": "REWARD_WINDOW_CLOSING",
			"payload": _closing_payload.duplicate(true),
			"idempotent": true,
		}
	else:
		return _err("INVALID_PHASE")

	# 无开放 CLAIM：结果判定序号同时为 context_boundary；claim_is_terminal 立即 true
	var term: Dictionary = mark_claim_terminal({
		"context_boundary_server_seq": rseq,
	})
	if not bool(term.get("ok", false)):
		return term

	var effects: Array = []
	if not bool(close_res.get("idempotent", false)):
		effects.append({
			"kind": "REWARD_WINDOW_CLOSING",
			"payload": close_res["payload"],
		})
	return {
		"ok": true,
		"effects": effects,
		"closing": close_res,
		"claim_terminal": term,
	}


## CLAIM 全过或非和牌鸣牌应用后冻结 context 边界。
func mark_claim_terminal(input: Dictionary) -> Dictionary:
	if phase == PHASE_CANCELLED or phase == PHASE_SETTLED:
		return {"ok": true, "idempotent": true, "claim_is_terminal": _claim_is_terminal}
	if phase != PHASE_CLOSING and phase != PHASE_OPEN:
		return _err("INVALID_PHASE")
	if not _is_int(input.get("context_boundary_server_seq", null)):
		return _err("INVALID_CONTEXT_BOUNDARY")
	var cseq: int = int(input["context_boundary_server_seq"])
	if cseq <= 0:
		return _err("INVALID_CONTEXT_BOUNDARY")
	if closing_boundary_server_seq != null and cseq < int(closing_boundary_server_seq):
		return _err("CONTEXT_BEFORE_CLOSING")

	if _claim_is_terminal and context_boundary_server_seq != null:
		if int(context_boundary_server_seq) == cseq:
			return {
				"ok": true,
				"idempotent": true,
				"claim_is_terminal": true,
				"context_boundary_server_seq": cseq,
			}
		return _err("CONTEXT_BOUNDARY_CONFLICT")

	_claim_is_terminal = true
	context_boundary_server_seq = cseq
	return {
		"ok": true,
		"idempotent": false,
		"claim_is_terminal": true,
		"context_boundary_server_seq": cseq,
	}


## 摄入权威转写。支持 pending→final 单向 terminalize。
## 同 identity + 不可变字段一致：重复幂等；仅 terminal false→true 可升级。
## final 不可退回 pending；文本/seat/PTT 冲突拒绝。
func ingest_utterance(input: Dictionary) -> Dictionary:
	if phase == PHASE_CANCELLED:
		return {"ok": true, "accepted": false, "reason": "CANCELLED", "idempotent": true}
	if phase == PHASE_SETTLED:
		return {"ok": true, "accepted": false, "reason": "SETTLED", "idempotent": true}
	if phase != PHASE_OPEN and phase != PHASE_CLOSING:
		return _err("INVALID_PHASE")

	if not _is_int(input.get("seat", null)):
		return _err("INVALID_SEAT")
	var seat: int = int(input["seat"])
	if seat < 0 or seat > 3:
		return _err("INVALID_SEAT")
	var utt_id := String(input.get("utterance_id", "")).strip_edges()
	if utt_id.is_empty():
		return _err("INVALID_UTTERANCE_ID")
	var key := "%s|%d|%s" % [window_id, seat, utt_id]

	if not _is_int(input.get("ptt_end_server_seq", null)):
		return _err("INVALID_PTT_END_SERVER_SEQ")
	var ptt: int = int(input["ptt_end_server_seq"])
	if ptt <= 0:
		return _err("INVALID_PTT_END_SERVER_SEQ")
	if closing_boundary_server_seq != null and ptt > int(closing_boundary_server_seq):
		return {"ok": true, "accepted": false, "reason": "PTT_AFTER_CLOSING_BOUNDARY"}

	var text := String(input.get("text", ""))
	var lang := String(input.get("language", _language)).strip_edges().to_lower()
	if lang != "zh" and lang != "en" and lang != "ja":
		return _err("INVALID_LANGUAGE")
	var terminal: bool = bool(input.get("terminal", true))

	if _utterance_keys.has(key):
		var existing: Dictionary = _find_utterance(seat, utt_id)
		if existing.is_empty():
			return _err("UTTERANCE_INDEX_CORRUPT")
		# 不可变字段必须一致
		if int(existing.get("ptt_end_server_seq", -1)) != ptt \
				or String(existing.get("text", "")) != text \
				or String(existing.get("language", "")) != lang:
			return _err("UTTERANCE_CONFLICT")
		var was_term: bool = bool(existing.get("terminal", true))
		if was_term == terminal:
			return {"ok": true, "accepted": true, "idempotent": true, "reason": "DUPLICATE"}
		if was_term and not terminal:
			return _err("UTTERANCE_CANNOT_UNTERMINALIZE")
		# pending → final
		existing["terminal"] = true
		return {
			"ok": true,
			"accepted": true,
			"idempotent": false,
			"reason": "TERMINALIZED",
		}

	var rec := {
		"utterance_id": utt_id,
		"text": text,
		"language": lang,
		"ptt_end_server_seq": ptt,
		"terminal": terminal,
	}
	(_utterances_by_seat[str(seat)] as Array).append(rec)
	_utterance_keys[key] = true
	return {"ok": true, "accepted": true, "idempotent": false}


## 追加经 NetworkedEvent.from_dict 验证的权威公开事件（envelope dict）。
## 拒绝隐藏字段；CLOSING 后仅接受 server_seq <= context 边界（若已冻结）的事件。
func append_public_event(ev: Dictionary) -> Dictionary:
	if phase != PHASE_OPEN and phase != PHASE_CLOSING:
		return {"ok": false, "reason": "INVALID_PHASE"}
	if ev.is_empty():
		return {"ok": false, "reason": "EMPTY_EVENT"}
	# 必须能 round-trip 为合法 NetworkedEvent
	var ne: NetworkedEvent = NetworkedEvent.from_dict(ev)
	if ne == null:
		return {"ok": false, "reason": "SCHEMA_REJECTED"}
	var clean: Dictionary = ne.to_dict()
	# 禁止隐藏字段键（与公开 DTO restore 同一完整清单）
	for forbidden in PUBLIC_EVENT_FORBIDDEN_KEYS:
		if _dict_contains_key(clean, forbidden):
			return {"ok": false, "reason": "HIDDEN_FIELD"}
	var seq: int = int(clean.get("server_seq", 0))
	if context_boundary_server_seq != null and seq > int(context_boundary_server_seq):
		return {"ok": false, "reason": "AFTER_CONTEXT_BOUNDARY"}
	_public_events.append(clean)
	return {"ok": true}


func set_public_initial(ini: Dictionary) -> void:
	if phase == PHASE_OPEN or phase == PHASE_IDLE:
		_public_initial = ini.duplicate(true)


## 屏障：claim_is_terminal AND (all_eligible_utterances_terminal OR now>=grace_deadline)
func is_barrier_blocking(now_ms: int = -1) -> bool:
	if phase == PHASE_CANCELLED or phase == PHASE_SETTLED or phase == PHASE_IDLE:
		return false
	if phase != PHASE_CLOSING:
		return false
	return not barrier_released(now_ms)


func barrier_released(now_ms: int = -1) -> bool:
	if phase != PHASE_CLOSING:
		return phase == PHASE_SETTLED or phase == PHASE_CANCELLED
	if not _claim_is_terminal:
		return false
	if _all_eligible_utterances_terminal():
		return true
	var t: int = now_ms
	if t < 0:
		t = 0
	return t >= _grace_deadline_ms


func claim_is_terminal() -> bool:
	return _claim_is_terminal


## 尝试结算。仅 CLOSING 且屏障释放后成功。
## input: now_ms, envelope_server_seq（SETTLED 事件序号，须 ≥ context/closing）
func try_settle(input: Dictionary) -> Dictionary:
	if phase == PHASE_SETTLED and not _settled_payload.is_empty():
		return {
			"ok": true,
			"kind": "REWARD_WINDOW_SETTLED",
			"payload": _settled_payload.duplicate(true),
			"idempotent": true,
		}
	if phase == PHASE_CANCELLED:
		return _err("ALREADY_CANCELLED")
	if phase != PHASE_CLOSING:
		return _err("INVALID_PHASE")

	var now_ms: int = _require_now_ms(input)
	if not barrier_released(now_ms):
		return _err("BARRIER_NOT_RELEASED")

	var pending := _pending_exit
	if pending != EXIT_FULL_GRANT and pending != EXIT_DISPLAY_ONLY:
		return _err("INVALID_PENDING_EXIT")

	# 出口优先级：若外部错误请求与 cancel 冲突，cancel 已先处理
	var score_in := _build_scorer_input(pending)
	var scored_out: Dictionary = TrashTalkContextScorer.score_matrix(score_in)
	_scorer_called = true
	if not bool(scored_out.get("ok", false)):
		return _err("SCORE_FAILED:%s" % String(scored_out.get("reason", "")))

	var matrix: Array = scored_out.get("matrix", [])
	var asg: Dictionary = RewardWindowAssigner.assign_bijection(matrix, prize_pool)
	if not bool(asg.get("ok", false)):
		return _err("ASSIGN_FAILED")

	var summary: Dictionary = RewardWindowAssigner.matrix_summary_from_scorer(
		matrix, prize_pool
	)
	var gcount: int = 4 if pending == EXIT_FULL_GRANT else 0
	var payload := {
		"window_id": window_id,
		"outcome": pending,
		"settle_reason": settle_reason,
		"rule_version": rule_version,
		"assignment_version": ASSIGNMENT_VERSION,
		"prize_pool": prize_pool.duplicate(),
		"matrix_summary": summary,
		"assignment": asg["assignment"],
		"closing_boundary_server_seq": int(closing_boundary_server_seq),
		"context_boundary_server_seq": int(context_boundary_server_seq),
		"grace_deadline_at": grace_deadline_at,
		"grant_count": gcount,
		"hand_seq": hand_seq,
		"transcript_summary": _build_transcript_summary(),
	}

	phase = PHASE_SETTLED
	window_exit = pending
	grant_count = gcount
	scored = true
	grace_aborted = false
	matrix_summary = summary.duplicate(true)
	assignment = (asg["assignment"] as Dictionary).duplicate(true)
	transcript_summary = payload["transcript_summary"]
	_settled_payload = payload.duplicate(true)
	return {
		"ok": true,
		"kind": "REWARD_WINDOW_SETTLED",
		"payload": payload.duplicate(true),
		"idempotent": false,
		"matrix": matrix,
	}


## 任意和牌：立即 CANCELLED_BY_WIN。不评分、不分配。
## _input 预留 now_ms/grace_was_active（兼容调用方；当前取消不消费）。
func cancel_by_win(_input: Dictionary = {}) -> Dictionary:
	if phase == PHASE_CANCELLED and not _cancelled_payload.is_empty():
		return {
			"ok": true,
			"kind": "REWARD_WINDOW_CANCELLED",
			"payload": _cancelled_payload.duplicate(true),
			"idempotent": true,
		}
	if phase == PHASE_SETTLED:
		return _err("ALREADY_SETTLED")
	if phase != PHASE_OPEN and phase != PHASE_CLOSING:
		return _err("INVALID_PHASE")

	var was_closing: bool = phase == PHASE_CLOSING
	var boundary = closing_boundary_server_seq # 可 null（未满 24 中途和）
	var payload := {
		"window_id": window_id,
		"cancel_reason": EXIT_CANCELLED,
		"closing_boundary_server_seq": boundary,
		"grace_aborted": was_closing,
		"scored": false,
		"grant_count": 0,
		"hand_seq": hand_seq,
	}

	phase = PHASE_CANCELLED
	window_exit = EXIT_CANCELLED
	grant_count = 0
	scored = false
	grace_aborted = was_closing
	matrix_summary = {}
	assignment = {}
	_claim_is_terminal = true # 中止屏障
	_cancelled_payload = payload.duplicate(true)
	return {
		"ok": true,
		"kind": "REWARD_WINDOW_CANCELLED",
		"payload": payload.duplicate(true),
		"idempotent": false,
		"scorer_called": _scorer_called,
	}


## #241 模块包络：{module_key, schema_version:int, payload:Dictionary}。
## #252 RewardWindowSnapshotProvider 权威 serialize 复用本公开 DTO。
func to_snapshot_dto() -> Dictionary:
	return {
		"module_key": MODULE_KEY,
		"schema_version": SCHEMA_VERSION,
		"payload": _snapshot_payload(),
	}


func _snapshot_payload() -> Dictionary:
	return {
		"phase": String(phase),
		"window_id": window_id,
		"window_exit": window_exit,
		"hand_seq": hand_seq,
		"window_index": window_index,
		"prize_pool": prize_pool.duplicate(),
		"discard_count": discard_count,
		"closing_boundary_server_seq": closing_boundary_server_seq,
		"context_boundary_server_seq": context_boundary_server_seq,
		"grace_deadline_at": grace_deadline_at,
		"grace_deadline_ms": _grace_deadline_ms,
		"grant_count": grant_count,
		"rule_version": rule_version,
		"assignment_version": assignment_version,
		"settle_reason": settle_reason,
		"pending_exit": _pending_exit,
		"assignment": assignment.duplicate(true),
		"matrix_summary": matrix_summary.duplicate(true),
		"scored": scored,
		"grace_aborted": grace_aborted,
		"claim_is_terminal": _claim_is_terminal,
		"room_id": _room_id,
		"character_ids": _character_ids.duplicate(),
		"language": _language,
		"public_initial": _public_initial.duplicate(true),
		"utterances_by_seat": _utterances_by_seat.duplicate(true),
		"public_events": _public_events.duplicate(true),
	}


## 公开模块 DTO 恢复（#252 provider can_restore 复用校验；客户端投影不重建权威时钟）。
## 先完整校验构造成候选，再一次性提交；失败时本对象零 mutation。
## CLOSING 可续跑：同一 grace_deadline_ms / pending_exit / 公开评分输入。
func restore_from_snapshot_dto(dto: Dictionary) -> Dictionary:
	var cand: Dictionary = _validate_public_dto_candidate(dto)
	if not bool(cand.get("ok", false)):
		return _err(String(cand.get("reason", "INVALID_DTO")))
	_apply_public_payload(cand["payload"] as Dictionary)
	return {"ok": true}


## 事务冻结：全部权威可变状态深复制 DTO（含内部幂等键/utterance/事件/缓存）。
func capture_state() -> Dictionary:
	return {
		"phase": String(phase),
		"window_id": window_id,
		"window_exit": window_exit,
		"hand_seq": hand_seq,
		"window_index": window_index,
		"prize_pool": prize_pool.duplicate(true),
		"discard_count": discard_count,
		"rule_version": rule_version,
		"assignment_version": assignment_version,
		"closing_boundary_server_seq": closing_boundary_server_seq,
		"context_boundary_server_seq": context_boundary_server_seq,
		"grace_deadline_at": grace_deadline_at,
		"grant_count": grant_count,
		"settle_reason": settle_reason,
		"scored": scored,
		"grace_aborted": grace_aborted,
		"matrix_summary": matrix_summary.duplicate(true),
		"assignment": assignment.duplicate(true),
		"transcript_summary": transcript_summary.duplicate(true),
		"_match_seed": _match_seed,
		"_room_id": _room_id,
		"_character_ids": _character_ids.duplicate(true),
		"_language": _language,
		"_participants": _participants.duplicate(true),
		"_claim_is_terminal": _claim_is_terminal,
		"_grace_deadline_ms": _grace_deadline_ms,
		"_utterances_by_seat": _utterances_by_seat.duplicate(true),
		"_utterance_keys": _utterance_keys.duplicate(true),
		"_ai_line_emitted": _ai_line_emitted.duplicate(true),
		"_public_events": _public_events.duplicate(true),
		"_public_initial": _public_initial.duplicate(true),
		"_opened_payload": _opened_payload.duplicate(true),
		"_closing_payload": _closing_payload.duplicate(true),
		"_settled_payload": _settled_payload.duplicate(true),
		"_cancelled_payload": _cancelled_payload.duplicate(true),
		"_pending_exit": _pending_exit,
		"_scorer_called": _scorer_called,
		"_discard_fingerprints": _discard_fingerprints.duplicate(true),
		"_closing_input_fp": _closing_input_fp,
	}


## 服务端事务快照恢复：先完整校验，再原子应用；失败零 mutation。
func restore_state(snap: Dictionary) -> bool:
	var cand: Dictionary = _validate_capture_candidate(snap)
	if not bool(cand.get("ok", false)):
		return false
	_apply_capture_candidate(cand["data"] as Dictionary)
	return true


func _validate_public_dto_candidate(dto: Dictionary) -> Dictionary:
	if typeof(dto) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "INVALID_DTO"}
	if String(dto.get("module_key", "")) != MODULE_KEY:
		return {"ok": false, "reason": "MODULE_KEY_MISMATCH"}
	if not _is_int(dto.get("schema_version", null)):
		return {"ok": false, "reason": "INVALID_SCHEMA_VERSION"}
	if int(dto["schema_version"]) != SCHEMA_VERSION:
		return {"ok": false, "reason": "UNKNOWN_SCHEMA_VERSION"}
	if typeof(dto.get("payload", null)) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "INVALID_PAYLOAD"}
	var p: Dictionary = dto["payload"]
	for k in p.keys():
		if not PAYLOAD_KEYS.has(String(k)):
			return {"ok": false, "reason": "UNKNOWN_PAYLOAD_KEY"}
	for req in PAYLOAD_KEYS:
		if not p.has(req):
			return {"ok": false, "reason": "MISSING_PAYLOAD_KEY"}
	var inv: Dictionary = _validate_public_invariants(p)
	if not bool(inv.get("ok", false)):
		return inv
	return {"ok": true, "payload": p.duplicate(true)}


func _validate_public_invariants(p: Dictionary) -> Dictionary:
	var ph := String(p.get("phase", ""))
	if ph != "IDLE" and ph != "OPEN" and ph != "CLOSING" and ph != "SETTLED" and ph != "CANCELLED":
		return {"ok": false, "reason": "INVALID_PHASE"}
	if not _is_int(p.get("hand_seq", null)) or int(p["hand_seq"]) < 0:
		return {"ok": false, "reason": "INVALID_HAND_SEQ"}
	if not _is_int(p.get("window_index", null)) or int(p["window_index"]) < 0:
		return {"ok": false, "reason": "INVALID_WINDOW_INDEX"}
	if not _is_int(p.get("discard_count", null)):
		return {"ok": false, "reason": "INVALID_DISCARD_COUNT"}
	var dc: int = int(p["discard_count"])
	if dc < 0 or dc > TARGET_DISCARDS:
		return {"ok": false, "reason": "INVALID_DISCARD_COUNT"}
	if not _is_int(p.get("grant_count", null)):
		return {"ok": false, "reason": "INVALID_GRANT_COUNT"}
	var gc: int = int(p["grant_count"])
	if typeof(p.get("scored", null)) != TYPE_BOOL or typeof(p.get("grace_aborted", null)) != TYPE_BOOL \
			or typeof(p.get("claim_is_terminal", null)) != TYPE_BOOL:
		return {"ok": false, "reason": "INVALID_BOOL"}
	var exit_v = p.get("window_exit", null)
	var pool_v = p.get("prize_pool", null)
	if ph == "OPEN" or ph == "CLOSING":
		if exit_v != null:
			return {"ok": false, "reason": "EXIT_MUST_BE_NULL"}
		if gc != 0:
			return {"ok": false, "reason": "GRANT_MUST_BE_ZERO"}
	if ph == "SETTLED":
		if typeof(exit_v) != TYPE_STRING:
			return {"ok": false, "reason": "INVALID_EXIT"}
		var ex := String(exit_v)
		if ex != EXIT_FULL_GRANT and ex != EXIT_DISPLAY_ONLY:
			return {"ok": false, "reason": "INVALID_EXIT"}
		if ex == EXIT_FULL_GRANT and gc != 4:
			return {"ok": false, "reason": "FULL_GRANT_COUNT"}
		if ex == EXIT_DISPLAY_ONLY and gc != 0:
			return {"ok": false, "reason": "DISPLAY_GRANT_COUNT"}
		if not bool(p["scored"]):
			return {"ok": false, "reason": "SETTLED_MUST_SCORE"}
	if ph == "CANCELLED":
		if String(exit_v) != EXIT_CANCELLED:
			return {"ok": false, "reason": "CANCEL_EXIT"}
		if gc != 0 or bool(p["scored"]):
			return {"ok": false, "reason": "CANCEL_SCORE_GRANT"}
	if ph == "OPEN" or ph == "CLOSING" or ph == "SETTLED":
		if not (pool_v is Array) or (pool_v as Array).size() != 4:
			return {"ok": false, "reason": "INVALID_POOL"}
		var seen: Dictionary = {}
		for idv in pool_v:
			var id := String(idv).strip_edges()
			if id.is_empty() or seen.has(id):
				return {"ok": false, "reason": "INVALID_POOL"}
			seen[id] = true
	var cb = p.get("closing_boundary_server_seq", null)
	var xb = p.get("context_boundary_server_seq", null)
	if ph == "CLOSING" or ph == "SETTLED":
		if not _is_positive_int(cb):
			return {"ok": false, "reason": "INVALID_CLOSING_BOUNDARY"}
		if typeof(p.get("grace_deadline_at", null)) != TYPE_STRING \
				or String(p["grace_deadline_at"]).is_empty():
			return {"ok": false, "reason": "INVALID_DEADLINE"}
		# CLOSING 续跑：grace_deadline_ms 与 ISO 必须一致（有 ms 时）；禁止不一致静默
		if ph == "CLOSING":
			var gms = p.get("grace_deadline_ms", null)
			var parsed_iso: int = parse_iso_ms(String(p["grace_deadline_at"]))
			if parsed_iso <= 0:
				return {"ok": false, "reason": "INVALID_DEADLINE_PARSE"}
			if _is_int(gms):
				if int(gms) <= 0:
					return {"ok": false, "reason": "INVALID_GRACE_MS"}
				if int(gms) != parsed_iso:
					return {"ok": false, "reason": "DEADLINE_MS_MISMATCH"}
			var pe := String(p.get("pending_exit", ""))
			if pe.is_empty():
				pe = _pending_exit_from_settle_reason(String(p.get("settle_reason", "")))
			if pe != EXIT_FULL_GRANT and pe != EXIT_DISPLAY_ONLY:
				return {"ok": false, "reason": "INVALID_PENDING_EXIT"}
	if ph == "SETTLED":
		if not _is_positive_int(xb):
			return {"ok": false, "reason": "INVALID_CONTEXT_BOUNDARY"}
		if int(xb) < int(cb):
			return {"ok": false, "reason": "CONTEXT_BEFORE_CLOSING"}
	if ph == "CANCELLED" and cb != null and not _is_positive_int(cb):
		return {"ok": false, "reason": "INVALID_CLOSING_BOUNDARY"}
	if typeof(p.get("assignment", null)) != TYPE_DICTIONARY \
			or typeof(p.get("matrix_summary", null)) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "INVALID_ASSIGN_MATRIX"}
	if typeof(p.get("rule_version", null)) != TYPE_STRING \
			or typeof(p.get("assignment_version", null)) != TYPE_STRING:
		return {"ok": false, "reason": "INVALID_VERSION"}
	# 公开 DTO 禁止隐藏 seed / 权威 RNG 输入（capture_state 仍保留 _match_seed）
	if p.has("match_seed") or p.has("seed"):
		return {"ok": false, "reason": "PUBLIC_SEED_FORBIDDEN"}
	# 续跑评分输入（公开）：键存在则严格校验，禁止损坏 DTO 静默评分
	# IDLE（开窗前首帧 SNAP）：允许空 room_id / 空 character_ids；OPEN+ 必须完整
	if p.has("room_id"):
		if typeof(p["room_id"]) != TYPE_STRING and typeof(p["room_id"]) != TYPE_STRING_NAME:
			return {"ok": false, "reason": "BAD_ROOM_ID"}
		if String(p["room_id"]).strip_edges().is_empty() and ph != "IDLE":
			return {"ok": false, "reason": "EMPTY_ROOM_ID"}
	if p.has("language"):
		var lang_v := String(p["language"]).strip_edges().to_lower()
		# IDLE 默认 "zh"；仍须合法语言码
		if lang_v != "zh" and lang_v != "en" and lang_v != "ja":
			return {"ok": false, "reason": "INVALID_LANGUAGE"}
	if p.has("character_ids"):
		var chars_raw: Variant = p["character_ids"]
		if ph == "IDLE":
			if typeof(chars_raw) != TYPE_ARRAY:
				return {"ok": false, "reason": "INVALID_CHARACTER_IDS"}
			# 允许空数组（开窗前）；非空则须 4 合法 id
			if not (chars_raw as Array).is_empty():
				var chars_idle: Array = _normalize_character_ids(chars_raw)
				if chars_idle.is_empty():
					return {"ok": false, "reason": "INVALID_CHARACTER_IDS"}
		else:
			var chars_norm: Array = _normalize_character_ids(chars_raw)
			if chars_norm.is_empty():
				return {"ok": false, "reason": "INVALID_CHARACTER_IDS"}
	if p.has("public_initial"):
		if not (p["public_initial"] is Dictionary):
			return {"ok": false, "reason": "BAD_PUBLIC_INITIAL"}
		var pi: Dictionary = p["public_initial"]
		# 非空才走 #251 白名单；空 dict 仅允许 IDLE/尚未注入
		if not pi.is_empty():
			var hs_expect: int = int(p["hand_seq"]) if _is_int(p.get("hand_seq", null)) else -1
			var piv: Dictionary = TrashTalkPublicContextAdapter.validate_public_initial(
				pi, hs_expect
			)
			if not bool(piv.get("ok", false)):
				return {"ok": false, "reason": "INVALID_PUBLIC_INITIAL"}
	if p.has("utterances_by_seat"):
		var utt_chk: Dictionary = _validate_public_utterances(
			p["utterances_by_seat"], ph, cb
		)
		if not bool(utt_chk.get("ok", false)):
			return utt_chk
	if p.has("public_events"):
		var pe_chk: Dictionary = _validate_public_events_list(p["public_events"], xb)
		if not bool(pe_chk.get("ok", false)):
			return pe_chk
	return {"ok": true}


## 公开 utterances_by_seat：键仅 "0".."3"；非空 ID、合法语言、正 PTT、必填 terminal；
## 同席无重复 identity；CLOSING/SETTLED 时 ptt_end <= closing_boundary。
func _validate_public_utterances(raw: Variant, ph: String, closing_boundary: Variant) -> Dictionary:
	if not (raw is Dictionary):
		return {"ok": false, "reason": "BAD_UTTERANCES"}
	var utts: Dictionary = raw
	var need_boundary: bool = ph == "CLOSING" or ph == "SETTLED"
	var close_b: int = -1
	if need_boundary and _is_positive_int(closing_boundary):
		close_b = int(closing_boundary)
	for k in utts.keys():
		var ks := String(k)
		if ks != "0" and ks != "1" and ks != "2" and ks != "3":
			return {"ok": false, "reason": "BAD_UTTERANCE_SEAT"}
		if not (utts[k] is Array):
			return {"ok": false, "reason": "BAD_UTTERANCE_LIST"}
		var seen_ids: Dictionary = {}
		for u in utts[k]:
			if typeof(u) != TYPE_DICTIONARY:
				return {"ok": false, "reason": "BAD_UTTERANCE_REC"}
			var rec: Dictionary = u
			if typeof(rec.get("utterance_id", null)) != TYPE_STRING \
					and typeof(rec.get("utterance_id", null)) != TYPE_STRING_NAME:
				return {"ok": false, "reason": "BAD_UTTERANCE_ID"}
			var uid := String(rec["utterance_id"]).strip_edges()
			if uid.is_empty():
				return {"ok": false, "reason": "EMPTY_UTTERANCE_ID"}
			if seen_ids.has(uid):
				return {"ok": false, "reason": "DUP_UTTERANCE_ID"}
			seen_ids[uid] = true
			if typeof(rec.get("text", null)) != TYPE_STRING \
					and typeof(rec.get("text", null)) != TYPE_STRING_NAME:
				return {"ok": false, "reason": "BAD_UTTERANCE_TEXT"}
			if typeof(rec.get("language", null)) != TYPE_STRING \
					and typeof(rec.get("language", null)) != TYPE_STRING_NAME:
				return {"ok": false, "reason": "BAD_UTTERANCE_LANG"}
			var lang_u := String(rec["language"]).strip_edges().to_lower()
			if lang_u != "zh" and lang_u != "en" and lang_u != "ja":
				return {"ok": false, "reason": "INVALID_UTTERANCE_LANGUAGE"}
			if not _is_int(rec.get("ptt_end_server_seq", null)):
				return {"ok": false, "reason": "BAD_UTTERANCE_PTT"}
			var ptt_u: int = int(rec["ptt_end_server_seq"])
			if ptt_u <= 0:
				return {"ok": false, "reason": "NONPOS_UTTERANCE_PTT"}
			if close_b > 0 and ptt_u > close_b:
				return {"ok": false, "reason": "UTTERANCE_AFTER_CLOSING_BOUNDARY"}
			if not rec.has("terminal") or typeof(rec["terminal"]) != TYPE_BOOL:
				return {"ok": false, "reason": "BAD_UTTERANCE_TERMINAL"}
	return {"ok": true}


## 公开 public_events：合法 NetworkedEvent；完整隐藏键过滤；context 边界内。
func _validate_public_events_list(raw: Variant, context_boundary: Variant) -> Dictionary:
	if not (raw is Array):
		return {"ok": false, "reason": "BAD_PUBLIC_EVENTS"}
	var ctx_b: int = -1
	if _is_positive_int(context_boundary):
		ctx_b = int(context_boundary)
	for item in raw:
		if typeof(item) != TYPE_DICTIONARY:
			return {"ok": false, "reason": "BAD_PUBLIC_EVENT"}
		var ne: NetworkedEvent = NetworkedEvent.from_dict(item)
		if ne == null:
			return {"ok": false, "reason": "PUBLIC_EVENT_SCHEMA"}
		var clean: Dictionary = ne.to_dict()
		for forbidden in PUBLIC_EVENT_FORBIDDEN_KEYS:
			if _dict_contains_key(clean, forbidden):
				return {"ok": false, "reason": "PUBLIC_EVENT_HIDDEN"}
		var seq_v: int = int(clean.get("server_seq", 0))
		if ctx_b > 0 and seq_v > ctx_b:
			return {"ok": false, "reason": "PUBLIC_EVENT_AFTER_CONTEXT"}
	return {"ok": true}


func _apply_public_payload(p: Dictionary) -> void:
	phase = StringName(String(p["phase"]))
	window_id = String(p["window_id"])
	window_exit = p["window_exit"]
	hand_seq = int(p["hand_seq"])
	window_index = int(p["window_index"])
	prize_pool = (p["prize_pool"] as Array).duplicate(true) if p["prize_pool"] is Array else []
	discard_count = int(p["discard_count"])
	closing_boundary_server_seq = p["closing_boundary_server_seq"]
	context_boundary_server_seq = p["context_boundary_server_seq"]
	grace_deadline_at = String(p["grace_deadline_at"])
	# 优先权威整数毫秒（#252 续跑契约）；禁止仅依赖易受时区影响的 ISO 回算
	var gms_v: Variant = p.get("grace_deadline_ms", null)
	if typeof(gms_v) == TYPE_INT:
		_grace_deadline_ms = int(gms_v)
	elif typeof(gms_v) == TYPE_FLOAT:
		# 拒绝浮点毫秒（不静默截断）
		_grace_deadline_ms = -1
	else:
		_grace_deadline_ms = parse_iso_ms(grace_deadline_at)
	grant_count = int(p["grant_count"])
	rule_version = String(p["rule_version"])
	assignment_version = String(p["assignment_version"])
	settle_reason = String(p["settle_reason"])
	var pe := String(p.get("pending_exit", ""))
	if pe.is_empty():
		pe = _pending_exit_from_settle_reason(settle_reason)
	_pending_exit = pe
	assignment = (p["assignment"] as Dictionary).duplicate(true)
	matrix_summary = (p["matrix_summary"] as Dictionary).duplicate(true)
	scored = bool(p["scored"])
	grace_aborted = bool(p["grace_aborted"])
	_claim_is_terminal = bool(p["claim_is_terminal"])
	_room_id = String(p.get("room_id", ""))
	_character_ids = (p.get("character_ids", []) as Array).duplicate(true) \
		if p.get("character_ids", null) is Array else []
	_language = String(p.get("language", "zh"))
	# match_seed 不从公开 DTO 恢复；保留实例既有值（start/open 由服务端注入）
	_public_initial = (p.get("public_initial", {}) as Dictionary).duplicate(true) \
		if p.get("public_initial", null) is Dictionary else {}
	_utterances_by_seat = (p.get("utterances_by_seat", {}) as Dictionary).duplicate(true) \
		if p.get("utterances_by_seat", null) is Dictionary else {"0": [], "1": [], "2": [], "3": []}
	_public_events = (p.get("public_events", []) as Array).duplicate(true) \
		if p.get("public_events", null) is Array else []
	# 幂等键由 utterance 重建
	_utterance_keys = {}
	for seat_k in _utterances_by_seat.keys():
		for u in _utterances_by_seat[seat_k]:
			if typeof(u) == TYPE_DICTIONARY:
				var uid := String(u.get("utterance_id", ""))
				if not uid.is_empty():
					_utterance_keys["%s|%s|%s" % [window_id, String(seat_k), uid]] = true


func _pending_exit_from_settle_reason(reason: String) -> String:
	if reason == SETTLE_REASON_MATCH_END:
		return EXIT_DISPLAY_ONLY
	if reason == SETTLE_REASON_FULL_24 or reason == SETTLE_REASON_NON_FINAL_DRAW:
		return EXIT_FULL_GRANT
	return ""


func _validate_capture_candidate(snap: Dictionary) -> Dictionary:
	if typeof(snap) != TYPE_DICTIONARY or snap.is_empty():
		return {"ok": false, "reason": "EMPTY"}
	for k in _CAPTURE_REQUIRED:
		if not snap.has(k):
			return {"ok": false, "reason": "MISSING_KEY"}
	# 类型硬校验（禁止缺键默认值静默恢复）
	if typeof(snap["phase"]) != TYPE_STRING and typeof(snap["phase"]) != TYPE_STRING_NAME:
		return {"ok": false, "reason": "BAD_PHASE"}
	var ph := String(snap["phase"])
	if ph != "IDLE" and ph != "OPEN" and ph != "CLOSING" and ph != "SETTLED" and ph != "CANCELLED":
		return {"ok": false, "reason": "BAD_PHASE"}
	if not _is_int(snap["hand_seq"]) or not _is_int(snap["window_index"]) \
			or not _is_int(snap["discard_count"]) or not _is_int(snap["grant_count"]) \
			or not _is_int(snap["_match_seed"]) or not _is_int(snap["_grace_deadline_ms"]):
		return {"ok": false, "reason": "BAD_INT"}
	if int(snap["discard_count"]) < 0 or int(snap["discard_count"]) > TARGET_DISCARDS:
		return {"ok": false, "reason": "BAD_DISCARD_COUNT"}
	if typeof(snap["scored"]) != TYPE_BOOL or typeof(snap["grace_aborted"]) != TYPE_BOOL \
			or typeof(snap["_claim_is_terminal"]) != TYPE_BOOL \
			or typeof(snap["_scorer_called"]) != TYPE_BOOL:
		return {"ok": false, "reason": "BAD_BOOL"}
	if not (snap["prize_pool"] is Array) or not (snap["matrix_summary"] is Dictionary) \
			or not (snap["assignment"] is Dictionary) \
			or not (snap["transcript_summary"] is Dictionary) \
			or not (snap["_utterances_by_seat"] is Dictionary) \
			or not (snap["_utterance_keys"] is Dictionary) \
			or not (snap["_discard_fingerprints"] is Dictionary) \
			or not (snap["_public_events"] is Array) \
			or not (snap["_character_ids"] is Array) \
			or not (snap["_participants"] is Array) \
			or not (snap["_ai_line_emitted"] is Dictionary) \
			or not (snap["_public_initial"] is Dictionary) \
			or not (snap["_opened_payload"] is Dictionary) \
			or not (snap["_closing_payload"] is Dictionary) \
			or not (snap["_settled_payload"] is Dictionary) \
			or not (snap["_cancelled_payload"] is Dictionary):
		return {"ok": false, "reason": "BAD_CONTAINER"}
	if typeof(snap["_room_id"]) != TYPE_STRING and typeof(snap["_room_id"]) != TYPE_STRING_NAME:
		return {"ok": false, "reason": "BAD_ROOM"}
	if typeof(snap["_language"]) != TYPE_STRING and typeof(snap["_language"]) != TYPE_STRING_NAME:
		return {"ok": false, "reason": "BAD_LANG"}
	if typeof(snap["_pending_exit"]) != TYPE_STRING and typeof(snap["_pending_exit"]) != TYPE_STRING_NAME:
		return {"ok": false, "reason": "BAD_PENDING"}
	if typeof(snap["_closing_input_fp"]) != TYPE_STRING and typeof(snap["_closing_input_fp"]) != TYPE_STRING_NAME:
		return {"ok": false, "reason": "BAD_CLOSING_FP"}
	# 复用公开不变量（phase/exit/pool/boundary）
	var pub_like := {
		"phase": ph,
		"window_id": String(snap["window_id"]),
		"window_exit": snap["window_exit"],
		"hand_seq": int(snap["hand_seq"]),
		"window_index": int(snap["window_index"]),
		"prize_pool": snap["prize_pool"],
		"discard_count": int(snap["discard_count"]),
		"closing_boundary_server_seq": snap["closing_boundary_server_seq"],
		"context_boundary_server_seq": snap["context_boundary_server_seq"],
		"grace_deadline_at": String(snap["grace_deadline_at"]),
		"grant_count": int(snap["grant_count"]),
		"rule_version": String(snap["rule_version"]),
		"assignment_version": String(snap["assignment_version"]),
		"settle_reason": String(snap["settle_reason"]),
		"assignment": snap["assignment"],
		"matrix_summary": snap["matrix_summary"],
		"scored": bool(snap["scored"]),
		"grace_aborted": bool(snap["grace_aborted"]),
		"claim_is_terminal": bool(snap["_claim_is_terminal"]),
	}
	if ph != "IDLE":
		var inv: Dictionary = _validate_public_invariants(pub_like)
		if not bool(inv.get("ok", false)):
			return inv
	# CLOSING 续跑必须有正 deadline_ms
	if ph == "CLOSING" and int(snap["_grace_deadline_ms"]) <= 0:
		return {"ok": false, "reason": "BAD_GRACE_MS"}
	return {"ok": true, "data": snap.duplicate(true)}


func _apply_capture_candidate(snap: Dictionary) -> void:
	phase = StringName(String(snap["phase"]))
	window_id = String(snap["window_id"])
	window_exit = snap["window_exit"]
	hand_seq = int(snap["hand_seq"])
	window_index = int(snap["window_index"])
	prize_pool = (snap["prize_pool"] as Array).duplicate(true)
	discard_count = int(snap["discard_count"])
	rule_version = String(snap["rule_version"])
	assignment_version = String(snap["assignment_version"])
	closing_boundary_server_seq = snap["closing_boundary_server_seq"]
	context_boundary_server_seq = snap["context_boundary_server_seq"]
	grace_deadline_at = String(snap["grace_deadline_at"])
	grant_count = int(snap["grant_count"])
	settle_reason = String(snap["settle_reason"])
	scored = bool(snap["scored"])
	grace_aborted = bool(snap["grace_aborted"])
	matrix_summary = (snap["matrix_summary"] as Dictionary).duplicate(true)
	assignment = (snap["assignment"] as Dictionary).duplicate(true)
	transcript_summary = (snap["transcript_summary"] as Dictionary).duplicate(true)
	_match_seed = int(snap["_match_seed"])
	_room_id = String(snap["_room_id"])
	_character_ids = (snap["_character_ids"] as Array).duplicate(true)
	_language = String(snap["_language"])
	_participants = (snap["_participants"] as Array).duplicate(true)
	_claim_is_terminal = bool(snap["_claim_is_terminal"])
	_grace_deadline_ms = int(snap["_grace_deadline_ms"])
	_utterances_by_seat = (snap["_utterances_by_seat"] as Dictionary).duplicate(true)
	_utterance_keys = (snap["_utterance_keys"] as Dictionary).duplicate(true)
	_ai_line_emitted = (snap["_ai_line_emitted"] as Dictionary).duplicate(true)
	_public_events = (snap["_public_events"] as Array).duplicate(true)
	_public_initial = (snap["_public_initial"] as Dictionary).duplicate(true)
	_opened_payload = (snap["_opened_payload"] as Dictionary).duplicate(true)
	_closing_payload = (snap["_closing_payload"] as Dictionary).duplicate(true)
	_settled_payload = (snap["_settled_payload"] as Dictionary).duplicate(true)
	_cancelled_payload = (snap["_cancelled_payload"] as Dictionary).duplicate(true)
	_pending_exit = String(snap["_pending_exit"])
	_scorer_called = bool(snap["_scorer_called"])
	_discard_fingerprints = (snap["_discard_fingerprints"] as Dictionary).duplicate(true)
	_closing_input_fp = String(snap["_closing_input_fp"])


func _is_positive_int(v: Variant) -> bool:
	return _is_int(v) and int(v) > 0


static func format_iso_ms(unix_ms: int) -> String:
	# 明确整数除法（毫秒 → 秒 + 余毫秒）
	@warning_ignore("integer_division")
	var sec: int = unix_ms / 1000
	var ms: int = unix_ms % 1000
	if ms < 0:
		ms += 1000
		sec -= 1
	var d: Dictionary = Time.get_datetime_dict_from_unix_time(sec)
	return "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ" % [
		int(d["year"]), int(d["month"]), int(d["day"]),
		int(d["hour"]), int(d["minute"]), int(d["second"]), ms,
	]


## 确定性解析 `YYYY-MM-DDTHH:MM:SS.mmmZ`；失败返回 -1。只用整数，禁止墙钟/浮点。
static func parse_iso_ms(iso: String) -> int:
	var s := iso.strip_edges()
	if s.length() < 19:
		return -1
	if s.ends_with("Z"):
		s = s.substr(0, s.length() - 1)
	var ms_part := 0
	var base := s
	var dot := s.find(".")
	if dot >= 0:
		base = s.substr(0, dot)
		var frac := s.substr(dot + 1)
		var digits := ""
		for i in range(mini(3, frac.length())):
			var ch := frac[i]
			if ch < "0" or ch > "9":
				break
			digits += ch
		while digits.length() < 3:
			digits += "0"
		if not digits.is_valid_int():
			return -1
		ms_part = int(digits)
	var t_parts: PackedStringArray = base.split("T")
	if t_parts.size() != 2:
		return -1
	var d_parts: PackedStringArray = t_parts[0].split("-")
	var tm_parts: PackedStringArray = t_parts[1].split(":")
	if d_parts.size() != 3 or tm_parts.size() != 3:
		return -1
	if not d_parts[0].is_valid_int() or not d_parts[1].is_valid_int() or not d_parts[2].is_valid_int():
		return -1
	if not tm_parts[0].is_valid_int() or not tm_parts[1].is_valid_int() or not tm_parts[2].is_valid_int():
		return -1
	var dt := {
		"year": int(d_parts[0]),
		"month": int(d_parts[1]),
		"day": int(d_parts[2]),
		"hour": int(tm_parts[0]),
		"minute": int(tm_parts[1]),
		"second": int(tm_parts[2]),
	}
	var unix_sec: int = int(Time.get_unix_time_from_datetime_dict(dt))
	if unix_sec < 0:
		return -1
	return unix_sec * 1000 + ms_part


func scorer_was_called() -> bool:
	return _scorer_called


func public_events_count() -> int:
	return _public_events.size()


## 权威事务回滚时恢复为未开窗空模块（仅 start 失败等；action 失败用 restore_state）。
func hard_reset() -> void:
	phase = PHASE_IDLE
	window_id = ""
	window_exit = null
	hand_seq = 0
	window_index = 0
	prize_pool = []
	rule_version = ""
	assignment_version = ASSIGNMENT_VERSION
	_match_seed = 0
	_room_id = ""
	_character_ids = []
	_language = "zh"
	_participants = []
	_public_initial = {}
	_opened_payload = {}
	_reset_runtime_for_new_window()


# ---- internal ----

func _reset_runtime_for_new_window() -> void:
	discard_count = 0
	closing_boundary_server_seq = null
	context_boundary_server_seq = null
	grace_deadline_at = ""
	_grace_deadline_ms = 0
	grant_count = 0
	settle_reason = ""
	scored = false
	grace_aborted = false
	matrix_summary = {}
	assignment = {}
	transcript_summary = {}
	_claim_is_terminal = false
	_utterances_by_seat = {"0": [], "1": [], "2": [], "3": []}
	_utterance_keys = {}
	_ai_line_emitted = {}
	_public_events = []
	_closing_payload = {}
	_settled_payload = {}
	_cancelled_payload = {}
	_pending_exit = ""
	_scorer_called = false
	window_exit = null
	_discard_fingerprints = {}
	_closing_input_fp = ""


func _find_utterance(seat: int, utt_id: String) -> Dictionary:
	var arr: Array = _utterances_by_seat.get(str(seat), [])
	for u in arr:
		if typeof(u) == TYPE_DICTIONARY and String(u.get("utterance_id", "")) == utt_id:
			return u
	return {}


func _dict_contains_key(v: Variant, key: String) -> bool:
	if typeof(v) == TYPE_DICTIONARY:
		var d: Dictionary = v
		if d.has(key):
			return true
		for k in d.keys():
			if _dict_contains_key(d[k], key):
				return true
	elif typeof(v) == TYPE_ARRAY:
		for item in v:
			if _dict_contains_key(item, key):
				return true
	return false


func _same_open_input(input: Dictionary) -> bool:
	if not _is_int(input.get("hand_seq", null)) or not _is_int(input.get("window_index", null)):
		return false
	return int(input["hand_seq"]) == hand_seq and int(input["window_index"]) == window_index


func _try_emit_ai_line(seat: int, discard_seq: int, input: Dictionary) -> void:
	if _ai_line_emitted.get(seat, false):
		return
	_ai_line_emitted[seat] = true
	# 允许测试注入固定 utterance
	if typeof(input.get("ai_utterance", null)) == TYPE_DICTIONARY:
		var inj: Dictionary = input["ai_utterance"]
		ingest_utterance({
			"seat": seat,
			"utterance_id": String(inj.get("utterance_id", "ai_%d_%s" % [seat, window_id])),
			"text": String(inj.get("text", "")),
			"language": String(inj.get("language", _language)),
			"ptt_end_server_seq": int(inj.get("ptt_end_server_seq", discard_seq)),
			"terminal": true,
		})
		return
	if seat >= _character_ids.size():
		return
	var line_v: Variant = TrashTalkAiLineSelector.select_ai_line({
		"has_first_discard": true,
		"rule_version": rule_version,
		"seed": _match_seed,
		"hand_seq": hand_seq,
		"window_id": window_id,
		"seat": seat,
		"discard_server_seq": discard_seq,
		"character_id": String(_character_ids[seat]),
		"language": _language,
		"public_context_tags": [],
	})
	if typeof(line_v) != TYPE_DICTIONARY:
		return
	var line: Dictionary = line_v
	ingest_utterance({
		"seat": seat,
		"utterance_id": String(line.get("utterance_id", "ai_%d_%s" % [seat, window_id])),
		"text": String(line.get("text", "")),
		"language": String(line.get("language", _language)),
		"ptt_end_server_seq": discard_seq,
		"terminal": true,
	})


func _all_eligible_utterances_terminal() -> bool:
	# 无在途非终态 utterance 即 terminal；空窗视为 terminal
	for seat in range(4):
		var arr: Array = _utterances_by_seat.get(str(seat), [])
		for u in arr:
			if typeof(u) != TYPE_DICTIONARY:
				continue
			# 仅 eligible：ptt_end <= closing_boundary（已在 ingest 过滤）
			if not bool(u.get("terminal", true)):
				return false
	return true


func _build_scorer_input(window_exit_str: String) -> Dictionary:
	var utts: Dictionary = {"0": [], "1": [], "2": [], "3": []}
	for seat in range(4):
		var arr: Array = _utterances_by_seat.get(str(seat), [])
		var cleaned: Array = []
		for u in arr:
			if typeof(u) != TYPE_DICTIONARY:
				continue
			cleaned.append({
				"utterance_id": String(u.get("utterance_id", "")),
				"text": String(u.get("text", "")),
				"language": String(u.get("language", _language)),
				"ptt_end_server_seq": int(u.get("ptt_end_server_seq", 0)),
			})
		utts[str(seat)] = cleaned
	var pub_ini: Dictionary = _public_initial.duplicate(true)
	if pub_ini.is_empty():
		pub_ini = {
			"hand_seq": hand_seq,
			"dealer_seat": 0,
			"scores": [
				BattleState.STARTING_SCORE, BattleState.STARTING_SCORE,
				BattleState.STARTING_SCORE, BattleState.STARTING_SCORE,
			],
		}
	return {
		"window_exit": window_exit_str,
		"rule_version": rule_version,
		"window_id": window_id,
		"hand_seq": hand_seq,
		"room_id": _room_id,
		"character_ids": _character_ids.duplicate(),
		"pool_item_ids": prize_pool.duplicate(),
		"language": _language,
		"closing_boundary_server_seq": int(closing_boundary_server_seq),
		"context_boundary_server_seq": int(context_boundary_server_seq),
		"utterances_by_seat": utts,
		"public_events": _public_events.duplicate(true),
		"public_initial": pub_ini,
	}


func _build_transcript_summary() -> Dictionary:
	var by_seat: Dictionary = {}
	for seat in range(4):
		var texts: Array = []
		for u in _utterances_by_seat.get(str(seat), []):
			if typeof(u) == TYPE_DICTIONARY:
				texts.append(String(u.get("text", "")))
		by_seat[str(seat)] = texts
	return {"by_seat": by_seat}


func _normalize_character_ids(raw: Variant) -> Array:
	if not (raw is Array) or (raw as Array).size() != 4:
		return []
	var out: Array = []
	for v in raw:
		var s := String(v).strip_edges()
		if s.is_empty() or CharacterPool.find(StringName(s)) == null:
			return []
		out.append(s)
	return out


func _normalize_participants(raw: Variant) -> Array:
	if not (raw is Array) or (raw as Array).size() != 4:
		return ["HUMAN", "AI", "AI", "AI"]
	var out: Array = []
	for v in raw:
		var s := String(v).strip_edges().to_upper()
		if s != "HUMAN" and s != "AI":
			return ["HUMAN", "AI", "AI", "AI"]
		out.append(s)
	return out


func _require_now_ms(input: Dictionary) -> int:
	if _is_int(input.get("now_ms", null)):
		return int(input["now_ms"])
	# 可回放默认：固定 0 基线 + 调用方应显式注入
	return 0


func _is_int(v: Variant) -> bool:
	return typeof(v) == TYPE_INT


func _err(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
