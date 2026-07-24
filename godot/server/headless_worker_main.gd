extends SceneTree

# #240：Headless Worker 进程入口。
# 用法：
#   TOKEN_SIGNING_SECRET=... godot --headless --path godot \
#     -s res://server/headless_worker_main.gd [-- --host=127.0.0.1 --port=9000]
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
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--host="):
			host = a.substr(7)
		elif a.begins_with("--port="):
			port = int(a.substr(7))
	_worker = HeadlessWorker.new()
	if not _worker.configure(secret, host, port):
		push_error("worker configure failed")
		quit(2)
		return
	root.add_child(_worker)
	var err: Error = _worker.start_listen()
	if err != OK:
		push_error("listen failed: %s" % error_string(err))
		quit(3)
		return
	print("headless_worker listening on ws://%s:%d (network e2e not verified)" % [host, port])


func _finalize() -> void:
	if _worker != null:
		_worker.stop()
