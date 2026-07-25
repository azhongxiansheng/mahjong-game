class_name WorkerControlPlaneClient
extends Node

# #256：Headless Worker → Control Plane 内部 HTTP 注册/续租/房间完成客户端。
# 单 HTTPRequest 串行；续租与 complete 使用独立 deadline，complete 不得饿死租约。
# 密钥不写日志。网络端到端未验证。

const DEFAULT_CAPACITY := 4
const DEFAULT_RENEW_INTERVAL_MS := 5000
const DEFAULT_RETRY_MS := 2000
const MIN_RENEW_MS := 500

var control_plane_base: String = ""
var registration_token: String = ""
var worker_id: String = ""
var game_endpoint: String = ""
var voice_endpoint: String = ""
var capacity: int = DEFAULT_CAPACITY
var renew_interval_ms: int = DEFAULT_RENEW_INTERVAL_MS
var retry_ms: int = DEFAULT_RETRY_MS
var last_lease_ttl_ms: int = 0

var _http: HTTPRequest = null
var _started: bool = false
var _in_flight: bool = false
## 下一次允许发起 register/renew 的时刻。
var _next_renew_ms: int = 0
## 下一次允许发起 complete 的时刻（失败退避；成功后可立即尝试下一间）。
var _next_complete_ms: int = 0
var _last_error: String = ""
var _active_rooms_snapshot: int = 0
var clock_now_ms: int = -1
var last_response_json: Dictionary = {}
var register_success_count: int = 0
var register_attempt_count: int = 0
var complete_success_count: int = 0
var complete_attempt_count: int = 0
var _complete_queue: Array = []
var _pending_kind: String = ""
var _pending_room_id: String = ""


func configure(
	p_base_url: String,
	p_token: String,
	p_worker_id: String,
	p_game_endpoint: String,
	p_voice_endpoint: String,
	p_capacity: int = DEFAULT_CAPACITY,
	p_renew_interval_ms: int = DEFAULT_RENEW_INTERVAL_MS
) -> bool:
	control_plane_base = p_base_url.strip_edges().trim_suffix("/")
	registration_token = p_token
	worker_id = p_worker_id.strip_edges()
	game_endpoint = p_game_endpoint.strip_edges()
	voice_endpoint = p_voice_endpoint.strip_edges()
	if p_capacity < 1:
		return false
	if p_renew_interval_ms < MIN_RENEW_MS:
		return false
	capacity = p_capacity
	renew_interval_ms = p_renew_interval_ms
	if control_plane_base.is_empty() or registration_token.is_empty() or worker_id.is_empty():
		return false
	if game_endpoint.is_empty() or voice_endpoint.is_empty():
		return false
	if not (control_plane_base.begins_with("http://") or control_plane_base.begins_with("https://")):
		return false
	return true


func is_configured() -> bool:
	return not control_plane_base.is_empty() and not registration_token.is_empty() and not worker_id.is_empty()


func start() -> void:
	if not is_configured():
		return
	_ensure_http()
	_started = true
	_next_renew_ms = 0
	_next_complete_ms = 0
	_in_flight = false


func stop() -> void:
	_started = false
	_in_flight = false
	_complete_queue.clear()
	_pending_kind = ""
	_pending_room_id = ""
	if _http != null:
		_http.cancel_request()
		if is_instance_valid(_http):
			_http.queue_free()
		_http = null


func is_started() -> bool:
	return _started


func get_last_error() -> String:
	return _last_error


func get_next_renew_ms_for_test() -> int:
	return _next_renew_ms


func get_next_complete_ms_for_test() -> int:
	return _next_complete_ms


func complete_queue_size_for_test() -> int:
	return _complete_queue.size()


func build_register_body(active_rooms: int) -> String:
	var rooms: int = maxi(0, active_rooms)
	return (
		"{"
		+ "\"worker_id\":%s," % JSON.stringify(worker_id)
		+ "\"game_endpoint\":%s," % JSON.stringify(game_endpoint)
		+ "\"voice_endpoint\":%s," % JSON.stringify(voice_endpoint)
		+ "\"capacity\":%d," % capacity
		+ "\"active_rooms\":%d" % rooms
		+ "}"
	)


func build_complete_body(room_id: String) -> String:
	return (
		"{"
		+ "\"worker_id\":%s," % JSON.stringify(worker_id)
		+ "\"room_id\":%s" % JSON.stringify(room_id)
		+ "}"
	)


func enqueue_room_complete(room_id: String) -> void:
	var rid := room_id.strip_edges()
	if rid.is_empty():
		return
	if _complete_queue.has(rid) or _pending_room_id == rid:
		return
	_complete_queue.append(rid)
	# 若未在退避中，允许立即尝试 complete（仍次于到期的 renew）
	if _next_complete_ms < 0:
		_next_complete_ms = 0


## 调度：单 HTTPRequest 串行。
## 1) renew 到期 → 优先 register（即使 complete 队列非空）
## 2) 否则 complete 队列非空且已过 complete retry deadline → 发 complete
## complete 失败只推进 _next_complete_ms，不得阻塞 _next_renew_ms。
func poll(active_rooms: int = 0) -> void:
	if not _started:
		return
	_active_rooms_snapshot = maxi(0, active_rooms)
	if _in_flight:
		return
	var now: int = _now_ms()
	if now >= _next_renew_ms:
		_fire_register()
		return
	if not _complete_queue.is_empty() and now >= _next_complete_ms:
		var rid: String = str(_complete_queue.pop_front())
		_fire_complete(rid)


func _ensure_http() -> void:
	if _http != null and is_instance_valid(_http):
		return
	_http = HTTPRequest.new()
	_http.timeout = 5.0
	add_child(_http)
	if not _http.request_completed.is_connected(_on_request_completed):
		_http.request_completed.connect(_on_request_completed)


func _fire_register() -> void:
	_ensure_http()
	var url := "%s/v1/internal/workers/register" % control_plane_base
	var body := build_register_body(_active_rooms_snapshot)
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer %s" % registration_token,
	])
	register_attempt_count += 1
	_in_flight = true
	_pending_kind = "register"
	_pending_room_id = ""
	var err: Error = _http.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		_in_flight = false
		_pending_kind = ""
		_fail_renew_retry("request_init_%d" % err)


func _fire_complete(room_id: String) -> void:
	_ensure_http()
	var url := "%s/v1/internal/workers/rooms/complete" % control_plane_base
	var body := build_complete_body(room_id)
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer %s" % registration_token,
	])
	complete_attempt_count += 1
	_in_flight = true
	_pending_kind = "complete"
	_pending_room_id = room_id
	var err: Error = _http.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		_in_flight = false
		_pending_kind = ""
		_pending_room_id = ""
		_complete_queue.push_front(room_id)
		_fail_complete_retry("complete_init_%d" % err)


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if not _started:
		_in_flight = false
		_pending_kind = ""
		_pending_room_id = ""
		return
	var kind := _pending_kind
	var room_id := _pending_room_id
	_in_flight = false
	_pending_kind = ""
	_pending_room_id = ""
	if result != HTTPRequest.RESULT_SUCCESS:
		if kind == "complete" and not room_id.is_empty():
			_complete_queue.push_front(room_id)
			_fail_complete_retry("http_result_%d" % result)
		else:
			_fail_renew_retry("http_result_%d" % result)
		return
	if kind == "complete":
		if response_code >= 200 and response_code < 300:
			complete_success_count += 1
			_last_error = ""
			# 成功后允许立刻处理队列下一间（仍受 renew 优先约束）
			_next_complete_ms = _now_ms()
			return
		if response_code == 409 or response_code == 404 or response_code == 403:
			# 终态冲突：丢弃，不重试
			_last_error = "complete_http_%d" % response_code
			_next_complete_ms = _now_ms()
			return
		_complete_queue.push_front(room_id)
		_fail_complete_retry("complete_http_%d" % response_code)
		return
	# register
	if response_code >= 200 and response_code < 300:
		register_success_count += 1
		_last_error = ""
		last_response_json = {}
		if not body.is_empty():
			var text := body.get_string_from_utf8()
			if not text.is_empty():
				var parsed: Variant = JSON.parse_string(text)
				if typeof(parsed) == TYPE_DICTIONARY:
					last_response_json = parsed as Dictionary
					if last_response_json.has("lease_ttl_ms"):
						last_lease_ttl_ms = int(last_response_json.get("lease_ttl_ms", 0))
		_next_renew_ms = _now_ms() + _safe_renew_delay_ms()
		return
	_fail_renew_retry("http_%d" % response_code)


func _safe_renew_delay_ms() -> int:
	var delay: int = renew_interval_ms
	if last_lease_ttl_ms > 0:
		var window: int = maxi(MIN_RENEW_MS, int(last_lease_ttl_ms / 3))
		if delay > window:
			delay = window
	return maxi(MIN_RENEW_MS, delay)


func _fail_renew_retry(reason: String) -> void:
	_last_error = reason
	_next_renew_ms = _now_ms() + retry_ms


func _fail_complete_retry(reason: String) -> void:
	_last_error = reason
	_next_complete_ms = _now_ms() + retry_ms


func _now_ms() -> int:
	if clock_now_ms >= 0:
		return clock_now_ms
	return Time.get_ticks_msec()
