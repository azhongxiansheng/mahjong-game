extends SceneTree

# #240：Headless Worker 进程入口。
# #244：可选独立语音 listener（--voice-port / VOICE_WORKER_PORT）。
# #247：可选内部 STT（--stt-url / STT_SERVICE_URL）。
# 用法：
#   TOKEN_SIGNING_SECRET=... godot --headless --path godot \
#     -s res://server/headless_worker_main.gd [-- --host=127.0.0.1 --port=9000 --voice-port=9001 --stt-url=ws://127.0.0.1:9100]
# 网络端到端未验证。

const DEFAULT_HOST := "127.0.0.1"
const DEFAULT_PORT := 9000

var _worker: HeadlessWorker = null


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
		voice_port = int(voice_env)
	var stt_env := OS.get_environment("STT_SERVICE_URL")
	if not stt_env.is_empty():
		stt_url = stt_env
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--host="):
			host = a.substr(7)
		elif a.begins_with("--port="):
			port = int(a.substr(7))
		elif a.begins_with("--voice-port="):
			voice_port = int(a.substr(13))
		elif a.begins_with("--stt-url="):
			stt_url = a.substr(10)
	_worker = HeadlessWorker.new()
	if not _worker.configure(secret, host, port, voice_port, stt_url):
		push_error("worker configure failed")
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
	msg += " (network e2e not verified)"
	print(msg)


func _finalize() -> void:
	if _worker != null:
		_worker.stop()
