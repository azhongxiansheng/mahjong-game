extends SceneTree

# #240：Headless Worker 进程入口。
# #244：可选独立语音 listener（--voice-port / VOICE_WORKER_PORT）。
# #247：可选内部 STT（--stt-url / STT_SERVICE_URL）。
# #256：可选 Control Plane 注册/续租（CONTROL_PLANE_URL + WORKER_REGISTRATION_TOKEN + WORKER_ID 等）。
# 用法：
#   TOKEN_SIGNING_SECRET=... godot --headless --path godot \
#     -s res://server/headless_worker_main.gd [-- --host=127.0.0.1 --port=9000 --voice-port=9001 --stt-url=ws://127.0.0.1:9100]
# 网络端到端未验证。

const DEFAULT_HOST := "127.0.0.1"
const DEFAULT_PORT := 9000
const DEFAULT_CAPACITY := 4
const DEFAULT_RENEW_MS := 5000
const MIN_CAPACITY := 1
const MAX_CAPACITY := 1024
const MIN_RENEW_MS := 500
const MAX_RENEW_MS := 3600000

var _worker: HeadlessWorker = null


## 严格十进制正整数解析；非法返回 {ok:false}。供入口与测试共用。
static func parse_strict_int_env(raw: String, min_v: int, max_v: int) -> Dictionary:
	var s := raw.strip_edges()
	if s.is_empty():
		return {"ok": false, "value": 0, "reason": "empty"}
	# 禁止符号/空白/进制前缀；仅 ASCII 十进制数字
	for i in range(s.length()):
		var c := s.unicode_at(i)
		if c < 48 or c > 57:  # '0'..'9'
			return {"ok": false, "value": 0, "reason": "non_digit"}
	# 禁止前导零（除单独 0，但 min>=1 时 0 也会失败）
	if s.length() > 1 and s.begins_with("0"):
		return {"ok": false, "value": 0, "reason": "leading_zero"}
	if not s.is_valid_int():
		return {"ok": false, "value": 0, "reason": "invalid"}
	var v: int = s.to_int()
	if v < min_v or v > max_v:
		return {"ok": false, "value": v, "reason": "out_of_range"}
	return {"ok": true, "value": v, "reason": ""}


func _initialize() -> void:
	var secret := OS.get_environment("TOKEN_SIGNING_SECRET")
	if secret.length() < 32:
		push_error("TOKEN_SIGNING_SECRET missing or shorter than 32 bytes")
		quit(2)
		return
	var host := DEFAULT_HOST
	var port := DEFAULT_PORT
	var voice_port: int = -1
	var stt_url := ""
	var voice_env := OS.get_environment("VOICE_WORKER_PORT")
	if not voice_env.is_empty():
		var vp := parse_strict_int_env(voice_env, 0, 65535)
		if not bool(vp.get("ok", false)):
			push_error("VOICE_WORKER_PORT invalid")
			quit(2)
			return
		voice_port = int(vp.get("value", -1))
	var stt_env := OS.get_environment("STT_SERVICE_URL")
	if not stt_env.is_empty():
		stt_url = stt_env
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--host="):
			host = a.substr(7)
		elif a.begins_with("--port="):
			var pp := parse_strict_int_env(a.substr(7), 0, 65535)
			if not bool(pp.get("ok", false)):
				push_error("--port invalid")
				quit(2)
				return
			port = int(pp.get("value", DEFAULT_PORT))
		elif a.begins_with("--voice-port="):
			var vpp := parse_strict_int_env(a.substr(13), 0, 65535)
			if not bool(vpp.get("ok", false)):
				push_error("--voice-port invalid")
				quit(2)
				return
			voice_port = int(vpp.get("value", -1))
		elif a.begins_with("--stt-url="):
			stt_url = a.substr(10)
	_worker = HeadlessWorker.new()
	if not _worker.configure(secret, host, port, voice_port, stt_url):
		push_error("worker configure failed")
		quit(2)
		return

	# #256 注册（可选：缺配置则仅监听，不注册）
	var cp_url := OS.get_environment("CONTROL_PLANE_URL").strip_edges()
	var reg_token := OS.get_environment("WORKER_REGISTRATION_TOKEN")
	var worker_id := OS.get_environment("WORKER_ID").strip_edges()
	if not cp_url.is_empty() or not reg_token.is_empty() or not worker_id.is_empty():
		if cp_url.is_empty() or reg_token.is_empty() or worker_id.is_empty():
			push_error("CONTROL_PLANE_URL, WORKER_REGISTRATION_TOKEN, WORKER_ID must all be set together")
			quit(2)
			return
		var game_ep := OS.get_environment("WORKER_GAME_ENDPOINT").strip_edges()
		var voice_ep := OS.get_environment("WORKER_VOICE_ENDPOINT").strip_edges()
		if game_ep.is_empty():
			push_error("WORKER_GAME_ENDPOINT is required when registration is enabled")
			quit(2)
			return
		if voice_ep.is_empty():
			push_error("WORKER_VOICE_ENDPOINT is required when registration is enabled")
			quit(2)
			return
		var cap := DEFAULT_CAPACITY
		var cap_env := OS.get_environment("WORKER_CAPACITY").strip_edges()
		if not cap_env.is_empty():
			var cap_p := parse_strict_int_env(cap_env, MIN_CAPACITY, MAX_CAPACITY)
			if not bool(cap_p.get("ok", false)):
				push_error("WORKER_CAPACITY invalid (strict decimal integer in range)")
				quit(2)
				return
			cap = int(cap_p.get("value", DEFAULT_CAPACITY))
		var renew_ms := DEFAULT_RENEW_MS
		var renew_env := OS.get_environment("WORKER_RENEW_INTERVAL_MS").strip_edges()
		if not renew_env.is_empty():
			var ren_p := parse_strict_int_env(renew_env, MIN_RENEW_MS, MAX_RENEW_MS)
			if not bool(ren_p.get("ok", false)):
				push_error("WORKER_RENEW_INTERVAL_MS invalid (strict decimal integer in range)")
				quit(2)
				return
			renew_ms = int(ren_p.get("value", DEFAULT_RENEW_MS))
		if not _worker.configure_control_plane_registration(
			cp_url, reg_token, worker_id, game_ep, voice_ep, cap, renew_ms
		):
			push_error("control plane registration configure failed")
			quit(2)
			return

	root.add_child(_worker)
	var err: Error = _worker.start_listen()
	if err != OK:
		push_error("listen failed: %s" % error_string(err))
		quit(3)
		return
	var msg := "headless_worker listening on ws://%s:%d" % [host, _worker.get_listen_port()]
	if _worker.get_voice_relay() != null:
		msg += " voice=ws://%s:%d" % [host, _worker.get_voice_listen_port()]
	if not stt_url.is_empty():
		msg += " stt=%s" % stt_url
	if not worker_id.is_empty():
		msg += " worker_id=%s" % worker_id
	msg += " (network e2e not verified)"
	print(msg)


func _finalize() -> void:
	if _worker != null:
		_worker.stop()
