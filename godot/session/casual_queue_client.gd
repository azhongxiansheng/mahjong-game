class_name CasualQueueClient extends Node

# #323：公共休闲队列真实 HTTP 客户端。token 仅保存在内部字段，不写日志/公开 view。

signal ticket_updated(ticket: Dictionary)
signal request_failed(code: String, message: String)

const DEFAULT_TIMEOUT_SEC := 5.0
const VALID_TICKET_STATES := ["waiting", "cancelled", "assigned", "failed"]

var _base_url := ""
var _http: HTTPRequest = null
var _pending_kind := ""
var _intent: SessionIntent = null
var _guest_id := ""
var _session_token := ""
var _ticket_id := ""
var _last_status := ""


func configure(base_url: String) -> bool:
	_base_url = base_url.strip_edges().trim_suffix("/")
	if not (_base_url.begins_with("http://") or _base_url.begins_with("https://")):
		_base_url = ""
		return false
	return true


func begin(intent: SessionIntent) -> bool:
	if intent == null or intent.room_kind != &"PUBLIC_CASUAL" or is_busy() or _base_url.is_empty():
		return false
	_intent = intent
	_guest_id = ""
	_session_token = ""
	_ticket_id = ""
	_last_status = ""
	return _request("guest", "/v1/guest-sessions", HTTPClient.METHOD_POST)


func poll_ticket() -> bool:
	if is_busy() or _ticket_id.is_empty() or _session_token.is_empty():
		return false
	return _request("poll", "/v1/queues/casual/%s" % _ticket_id, HTTPClient.METHOD_GET)


func cancel_ticket() -> bool:
	if is_busy() or _ticket_id.is_empty() or _session_token.is_empty():
		return false
	return _request("cancel", "/v1/queues/casual/%s" % _ticket_id, HTTPClient.METHOD_DELETE)


func is_busy() -> bool:
	return not _pending_kind.is_empty()


func get_session_id() -> String:
	return _guest_id


func get_public_debug_view() -> Dictionary:
	return {
		"busy": is_busy(),
		"has_session": not _guest_id.is_empty(),
		"has_ticket": not _ticket_id.is_empty(),
		"status": _last_status,
	}


func _ensure_http() -> void:
	if _http != null and is_instance_valid(_http):
		return
	_http = HTTPRequest.new()
	_http.timeout = DEFAULT_TIMEOUT_SEC
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)


func _request(kind: String, path: String, method: HTTPClient.Method, body: String = "") -> bool:
	_ensure_http()
	var headers := PackedStringArray(["Accept: application/json"])
	if kind != "guest":
		headers.append("Authorization: Bearer %s" % _session_token)
	if not body.is_empty():
		headers.append("Content-Type: application/json")
	_pending_kind = kind
	var err := _http.request(_base_url + path, headers, method, body)
	if err != OK:
		_pending_kind = ""
		request_failed.emit("NETWORK", "request init failed")
		return false
	return true


func _request_enqueue() -> bool:
	if _intent == null:
		return false
	var body := JSON.stringify({
		"round_kind": String(_intent.round_kind),
		"game_mode": String(_intent.game_mode),
	})
	return _request("enqueue", "/v1/queues/casual", HTTPClient.METHOD_POST, body)


func _on_request_completed(
	result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray
) -> void:
	var kind := _pending_kind
	_pending_kind = ""
	if result != HTTPRequest.RESULT_SUCCESS:
		request_failed.emit("NETWORK", "HTTP transport failed")
		return
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		request_failed.emit("INVALID_RESPONSE", "response is not valid JSON")
		return
	var parsed: Variant = json.data
	if typeof(parsed) != TYPE_DICTIONARY:
		request_failed.emit("INVALID_RESPONSE", "response is not a JSON object")
		return
	var data: Dictionary = parsed
	if response_code < 200 or response_code >= 300:
		request_failed.emit(str(data.get("code", "HTTP_%d" % response_code)), str(data.get("message", "request failed")))
		return
	if kind == "guest":
		_guest_id = str(data.get("guest_id", ""))
		_session_token = str(data.get("session_token", ""))
		if _guest_id.is_empty() or _session_token.is_empty():
			_guest_id = ""
			_session_token = ""
			request_failed.emit("INVALID_RESPONSE", "guest session fields missing")
			return
		_request_enqueue()
		return
	_consume_ticket(data)


func _consume_ticket(data: Dictionary) -> void:
	var status := str(data.get("status", ""))
	var ticket_id := str(data.get("ticket_id", ""))
	if status not in VALID_TICKET_STATES or ticket_id.is_empty():
		request_failed.emit("INVALID_RESPONSE", "ticket fields missing")
		return
	if _ticket_id.is_empty():
		_ticket_id = ticket_id
	elif _ticket_id != ticket_id:
		request_failed.emit("INVALID_RESPONSE", "ticket id changed")
		return
	_last_status = status
	ticket_updated.emit(data.duplicate(true))


func _exit_tree() -> void:
	_session_token = ""
	if _http != null and is_instance_valid(_http):
		_http.cancel_request()
