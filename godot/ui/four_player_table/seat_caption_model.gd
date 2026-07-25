extends RefCounted

# E4-04 / #246：四席字幕纯状态模型（UI 注入层）。
# 无全局 class_name；不发射奖励/语音事件；display_revision 仅本层可选。

const TTL_PARTIAL_MS: int = 3000
const TTL_FINAL_MS: int = 5000

const KIND_PARTIAL := "partial"
const KIND_FINAL := "final"

const SOURCE_LOCAL_MIC := "local_mic"
const SOURCE_SERVER_STT := "server_stt"
const SOURCE_AI_TEXT := "ai_text"

const LABEL_LOCAL_MIC := "本地麦克风"
const LABEL_SERVER_STT := "服务端转写"
const LABEL_AI_TEXT := "AI 文本"

# utterance_id → 终态记录（含过期后幂等）
var _by_utt: Dictionary = {}
# seat → 当前可见 utterance_id（空串表示无）
var _seat_utt: Dictionary = {0: "", 1: "", 2: "", 3: ""}


static func source_label(source: String) -> String:
	var canon := _canonicalize_source(source)
	match canon:
		SOURCE_LOCAL_MIC:
			return LABEL_LOCAL_MIC
		SOURCE_SERVER_STT:
			return LABEL_SERVER_STT
		SOURCE_AI_TEXT:
			return LABEL_AI_TEXT
	return ""


static func lang_label(lang: String) -> String:
	match lang.strip_edges().to_lower():
		"zh":
			return "中"
		"en":
			return "EN"
		"ja":
			return "日"
	return ""


static func header_text(seat: int, source_lbl: String, lang: String) -> String:
	return "座位 %d｜%s｜%s" % [seat, source_lbl, lang_label(lang)]


static func _canonicalize_source(raw: String) -> String:
	var s := raw.strip_edges().to_lower()
	match s:
		"local_mic", "local", "whisper_local", "whisper_cpp":
			return SOURCE_LOCAL_MIC
		"server_stt", "server", "faster_whisper", "new_api", "new-api":
			return SOURCE_SERVER_STT
		"ai_text", "ai", "ai_line", "template":
			return SOURCE_AI_TEXT
	return ""


static func _canonicalize_kind(raw: String) -> String:
	var k := raw.strip_edges()
	var lower := k.to_lower()
	if lower == KIND_PARTIAL or k == "TRANSCRIPT_PARTIAL":
		return KIND_PARTIAL
	if lower == KIND_FINAL or k == "TRANSCRIPT_FINAL":
		return KIND_FINAL
	# 大小写不敏感兼容 ADR 大写 kind
	if lower == "transcript_partial":
		return KIND_PARTIAL
	if lower == "transcript_final":
		return KIND_FINAL
	return ""


func side_effect_event_kinds() -> Array:
	return []


func ingest(input: Dictionary) -> Dictionary:
	if typeof(input) != TYPE_DICTIONARY or input.is_empty():
		return _reject("EMPTY")
	if not _is_int(input.get("seat", null)):
		return _reject("INVALID_SEAT")
	var seat: int = int(input["seat"])
	if seat < 0 or seat > 3:
		return _reject("INVALID_SEAT")

	var utt := String(input.get("utterance_id", "")).strip_edges()
	if utt.is_empty():
		return _reject("INVALID_UTTERANCE_ID")

	var text_v: Variant = input.get("text", null)
	if typeof(text_v) != TYPE_STRING and typeof(text_v) != TYPE_STRING_NAME:
		return _reject("INVALID_TEXT")
	var text := String(text_v)
	if text.strip_edges().is_empty():
		return _reject("EMPTY_TEXT")

	var kind := _canonicalize_kind(String(input.get("kind", "")))
	if kind.is_empty():
		return _reject("INVALID_KIND")

	var src_raw := String(input.get("source", "")).strip_edges()
	var source := _canonicalize_source(src_raw)
	if source.is_empty():
		return _reject("INVALID_SOURCE")

	var lang := _resolve_lang(input)
	if lang.is_empty():
		return _reject("INVALID_LANG")

	var now_ms := _resolve_now_ms(input)
	if now_ms < 0:
		return _reject("INVALID_NOW")

	var has_rev := input.has("display_revision")
	var rev: int = -1
	if has_rev:
		if not _is_int(input.get("display_revision", null)):
			return _reject("INVALID_REVISION")
		rev = int(input["display_revision"])
		if rev < 0:
			return _reject("INVALID_REVISION")

	# AI 文本强制非麦克风语义 + final
	if source == SOURCE_AI_TEXT:
		kind = KIND_FINAL

	var fingerprint := _fingerprint(seat, utt, text, kind, source, lang)

	if _by_utt.has(utt):
		var prev: Dictionary = _by_utt[utt]
		if int(prev.get("seat", -1)) != seat:
			return _reject("SEAT_MISMATCH")

		# 精确重复：幂等，不刷新超时、不复活过期展示
		if String(prev.get("fingerprint", "")) == fingerprint:
			return {
				"ok": true,
				"idempotent": true,
				"reason": "DUPLICATE",
			}

		if bool(prev.get("is_final", false)):
			if kind == KIND_PARTIAL:
				return _reject("AFTER_FINAL")
			return _reject("FINAL_CONFLICT")

		# display_revision 只约束 incoming partial（拒绝旧/冲突 partial）。
		# final 是终态，必须无条件替换同 utterance 的 partial，不受 partial rev 拦截。
		if kind == KIND_PARTIAL and has_rev and prev.has("display_revision"):
			var prev_rev: int = int(prev["display_revision"])
			if rev < prev_rev:
				return _reject("STALE_REVISION")
			if rev == prev_rev:
				return _reject("REVISION_CONFLICT")

	var ttl: int = TTL_PARTIAL_MS if kind == KIND_PARTIAL else TTL_FINAL_MS
	var rec := {
		"seat": seat,
		"utterance_id": utt,
		"text": text,
		"kind": kind,
		"source": source,
		"source_label": source_label(source),
		"lang": lang,
		"lang_label": lang_label(lang),
		"header": header_text(seat, source_label(source), lang),
		"is_mic": source == SOURCE_LOCAL_MIC,
		"is_partial": kind == KIND_PARTIAL,
		"is_final": kind == KIND_FINAL,
		"expires_at_ms": now_ms + ttl,
		"fingerprint": fingerprint,
		"accepted_at_ms": now_ms,
	}
	if has_rev:
		rec["display_revision"] = rev

	_by_utt[utt] = rec
	_seat_utt[seat] = utt
	return {"ok": true, "idempotent": false}


func display_for_seat(seat: int) -> Dictionary:
	if seat < 0 or seat > 3:
		return {}
	var utt: String = String(_seat_utt.get(seat, ""))
	if utt.is_empty() or not _by_utt.has(utt):
		return {}
	var rec: Dictionary = _by_utt[utt]
	if int(rec.get("seat", -1)) != seat:
		return {}
	return _public_view(rec)


func has_visible_for_seat(seat: int, now_ms: int) -> bool:
	var d: Dictionary = display_for_seat(seat)
	if d.is_empty():
		return false
	return int(d.get("expires_at_ms", -1)) > now_ms


func tick(now_ms: int) -> void:
	for seat in range(4):
		var utt: String = String(_seat_utt.get(seat, ""))
		if utt.is_empty() or not _by_utt.has(utt):
			continue
		var rec: Dictionary = _by_utt[utt]
		if int(rec.get("expires_at_ms", -1)) <= now_ms:
			_seat_utt[seat] = ""


func _public_view(rec: Dictionary) -> Dictionary:
	var out := {
		"seat": int(rec["seat"]),
		"utterance_id": String(rec["utterance_id"]),
		"text": String(rec["text"]),
		"kind": String(rec["kind"]),
		"source": String(rec["source"]),
		"source_label": String(rec["source_label"]),
		"lang": String(rec["lang"]),
		"lang_label": String(rec.get("lang_label", lang_label(String(rec["lang"])))),
		"header": String(rec.get("header", header_text(
			int(rec["seat"]), String(rec["source_label"]), String(rec["lang"])))),
		"is_mic": bool(rec["is_mic"]),
		"is_partial": bool(rec["is_partial"]),
		"is_final": bool(rec["is_final"]),
		"expires_at_ms": int(rec["expires_at_ms"]),
	}
	if rec.has("display_revision"):
		out["display_revision"] = int(rec["display_revision"])
	return out


static func _fingerprint(seat: int, utt: String, text: String, kind: String,
		source: String, lang: String) -> String:
	return "%d|%s|%s|%s|%s|%s" % [seat, utt, text, kind, source, lang]


static func _resolve_lang(input: Dictionary) -> String:
	var raw := ""
	if input.has("lang"):
		raw = String(input.get("lang", ""))
	elif input.has("language"):
		raw = String(input.get("language", ""))
	else:
		return ""
	var lang := raw.strip_edges().to_lower()
	if lang == "zh" or lang == "en" or lang == "ja":
		return lang
	return ""


static func _resolve_now_ms(input: Dictionary) -> int:
	if not input.has("now_ms"):
		return Time.get_ticks_msec()
	if not _is_int(input.get("now_ms", null)):
		return -1
	return int(input["now_ms"])


static func _is_int(v: Variant) -> bool:
	return typeof(v) == TYPE_INT


static func _reject(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
