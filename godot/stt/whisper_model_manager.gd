class_name WhisperModelManager extends Node

# E4-03（#245）：whisper.cpp 模型生命周期 — 清单、Range 断点续传、SHA-256、原子启用。
# 默认目录 user://models/whisper/<version>/（可注入）；macOS/Windows 同一 Godot 逻辑。
# 每 manifest version 独立目录，校验成功后单次同目录 rename 发布；旧版本路径不动。
# 不实现推理/字幕。失败可重试，不阻断牌局主流程。

signal state_changed(state: StringName)
signal progress_changed(received_bytes: int, total_bytes: int)
signal error_changed(error_code: String)

const DEFAULT_MODELS_ROOT := "user://models/whisper"
const STATE_IDLE := &"idle"
const STATE_CHECKING := &"checking"
const STATE_DOWNLOADING := &"downloading"
const STATE_VERIFYING := &"verifying"
const STATE_READY := &"ready"
const STATE_FAILED := &"failed"
const STATE_CANCELLED := &"cancelled"

var _manifest: Dictionary = {}
var _models_root: String = DEFAULT_MODELS_ROOT
var _state: StringName = STATE_IDLE
var _error_code: String = ""
var _received_bytes: int = 0
var _http: HTTPRequest = null
var _ensure_in_flight: bool = false
var _cancelled: bool = false
var _released: bool = false
var _allow_public_network: bool = true
var _ensure_requested: bool = false
var _request_offset: int = 0
## 当前请求是否从 offset=0 直接写入 .partial（取消/中断时保留前缀）。
var _download_to_partial: bool = false


func _init() -> void:
	# GUT/headless 默认禁止公网 HF，避免误下 487MB；localhost 与显式允许不受影响。
	_allow_public_network = not OS.has_feature("headless")
	_manifest = WhisperModelManifest.production_small()


func _ready() -> void:
	_ensure_http_node()


func _exit_tree() -> void:
	# 卸树：取消在途 HTTP 并释放节点，但保留磁盘 partial；允许同实例 reparent 后续 ensure。
	if _released:
		return
	if _ensure_in_flight or _state == STATE_DOWNLOADING or _state == STATE_CHECKING or _state == STATE_VERIFYING:
		_cancelled = true
		_ensure_in_flight = false
		if _state != STATE_CANCELLED and _state != STATE_READY and _state != STATE_FAILED:
			_set_state(STATE_CANCELLED)
	_teardown_http()


func apply_production_manifest() -> void:
	set_manifest(WhisperModelManifest.production_small())


func set_manifest(manifest: Dictionary) -> void:
	if manifest.is_empty():
		return
	_manifest = manifest.duplicate(true)


func get_manifest() -> Dictionary:
	return _manifest.duplicate(true)


func set_models_root(path: String) -> void:
	if path.is_empty():
		return
	_models_root = path.rstrip("/")


func get_models_root() -> String:
	return _models_root


func set_allow_public_network(allowed: bool) -> void:
	_allow_public_network = allowed


func is_public_network_allowed() -> bool:
	return _allow_public_network


func get_lifecycle_state() -> StringName:
	return _state


func get_error_code() -> String:
	return _error_code


func get_received_bytes() -> int:
	return _received_bytes


func is_model_ready() -> bool:
	return _state == STATE_READY


func is_released() -> bool:
	return _released


func was_ensure_requested() -> bool:
	return _ensure_requested


## 当前 manifest version 的模型目录（独立版本路径，旧版本互不覆盖）。
func model_version_dir() -> String:
	return _models_root.path_join(_version_dir_name())


func active_model_path() -> String:
	return model_version_dir().path_join(_filename())


func partial_model_path() -> String:
	return active_model_path() + ".partial"


func chunk_model_path() -> String:
	return active_model_path() + ".partial.chunk"


## HTTPRequest 总时长超时；大文件按 Godot 4.6 建议为 0（禁用）。
func http_timeout() -> float:
	_ensure_http_node()
	if _http != null and is_instance_valid(_http):
		return _http.timeout
	return 0.0


func ensure_ready() -> void:
	if _released:
		return
	_ensure_requested = true
	if _state == STATE_READY:
		return
	if _ensure_in_flight:
		return
	if not is_inside_tree():
		call_deferred("ensure_ready")
		return
	_cancelled = false
	_ensure_in_flight = true
	_set_error("")
	_set_state(STATE_CHECKING)
	_run_ensure()


func cancel() -> void:
	if _released:
		return
	if _state == STATE_READY:
		return
	if _state == STATE_IDLE:
		_cancelled = true
		_ensure_in_flight = false
		_set_state(STATE_CANCELLED)
		return
	_cancelled = true
	_ensure_in_flight = false
	# 先关闭 HTTP 句柄，再整理磁盘：保留合法 partial 前缀，丢弃未合并的 chunk
	if _http != null and is_instance_valid(_http):
		_http.cancel_request()
	_finalize_interrupted_download(false)
	_set_state(STATE_CANCELLED)


func release() -> void:
	if _released:
		return
	_released = true
	_cancelled = true
	_ensure_in_flight = false
	_teardown_http()
	if _state != STATE_CANCELLED:
		_set_state(STATE_CANCELLED)


func _run_ensure() -> void:
	if _released or _cancelled:
		_ensure_in_flight = false
		return
	if not WhisperModelManifest.is_valid_manifest(_manifest):
		_fail("INVALID_MANIFEST")
		return
	_ensure_dir()
	# 清理遗留 swap 等临时文件，但绝不删除其它 version 目录下的有效 active
	_cleanup_stale_temps()
	# 1) 已有本 version active 且 size+sha 匹配 → ready
	if _active_matches_manifest():
		_received_bytes = int(_manifest.get("size_bytes", 0))
		progress_changed.emit(_received_bytes, _received_bytes)
		_ensure_in_flight = false
		_set_state(STATE_READY)
		return
	# 本 version 若存在无效 active，可安全删除（不会动其它 version）
	var active: String = active_model_path()
	if FileAccess.file_exists(active) and not _active_matches_manifest():
		_delete_path(active)
	# 2) 处理 partial：超长删除；完整则只校验一次——失败即 failed，不自动继续下
	var partial: String = partial_model_path()
	var expected: int = int(_manifest.get("size_bytes", 0))
	if FileAccess.file_exists(partial):
		var psz: int = _file_size(partial)
		if psz > expected:
			_delete_path(partial)
		elif psz == expected:
			_set_state(STATE_VERIFYING)
			if _verify_and_activate(partial):
				return
			# 完整坏 partial：已删并 failed；必须 return，保持单 in-flight 语义，下次显式 ensure 从零
			return
		# 0 < psz < expected → 续传
	# 3) 网络策略
	var url: String = String(_manifest.get("url", ""))
	if _is_public_host(url) and not _allow_public_network:
		_fail("PUBLIC_NETWORK_BLOCKED")
		return
	_start_download()


func _start_download() -> void:
	if _released or _cancelled:
		_ensure_in_flight = false
		return
	_ensure_http_node()
	var expected: int = int(_manifest.get("size_bytes", 0))
	var offset: int = 0
	var partial: String = partial_model_path()
	if FileAccess.file_exists(partial):
		offset = _file_size(partial)
		if offset < 0:
			offset = 0
		if offset >= expected:
			offset = 0
			_delete_path(partial)
	_request_offset = offset
	_download_to_partial = offset == 0
	_received_bytes = offset
	progress_changed.emit(_received_bytes, expected)
	_set_state(STATE_DOWNLOADING)

	var headers := PackedStringArray()
	if offset > 0:
		headers.append("Range: bytes=%d-" % offset)

	_cleanup_chunk()
	# offset==0：直接写入 .partial，中断可保留前缀；offset>0：写入 .chunk，成功 206 才 append
	if _download_to_partial:
		_http.download_file = partial
	else:
		_http.download_file = chunk_model_path()
	var err: Error = _http.request(String(_manifest.get("url", "")), headers)
	if err != OK:
		_cleanup_chunk()
		_fail("HTTP_REQUEST_ERROR_%d" % err)


func _on_request_completed(
	result: int, response_code: int, headers: PackedStringArray, _body: PackedByteArray
) -> void:
	if _released:
		return
	if _cancelled:
		# cancel() 已整理磁盘；此处只收尾状态
		_ensure_in_flight = false
		if _state != STATE_CANCELLED:
			_set_state(STATE_CANCELLED)
		return

	var expected: int = int(_manifest.get("size_bytes", 0))
	var chunk_path: String = chunk_model_path()
	var partial: String = partial_model_path()

	if result != HTTPRequest.RESULT_SUCCESS:
		# 传输失败：保留已从零写入的合法 partial 前缀；丢弃未验证 chunk
		_finalize_interrupted_download(true)
		_fail("HTTP_RESULT_%d" % result)
		return

	if response_code == 416:
		_cleanup_chunk()
		_delete_path(partial)
		_fail("HTTP_416")
		return

	if response_code == 206:
		if _request_offset <= 0:
			# 未请求 Range 却 206：不信任，清理污染
			_cleanup_chunk()
			if _download_to_partial:
				_delete_path(partial)
			_fail("UNEXPECTED_206")
			return
		var cr: Dictionary = _parse_content_range(headers)
		if cr.is_empty():
			_cleanup_chunk()
			# 不删除旧 partial（续传前缀仍有效）
			_fail("BAD_CONTENT_RANGE")
			return
		var start: int = int(cr.get("start", -1))
		if start != _request_offset:
			_cleanup_chunk()
			_fail("CONTENT_RANGE_MISMATCH")
			return
		# 完整 206 body 在 chunk（或极少情况下已在 partial——不期望）
		if _download_to_partial:
			# offset 应 >0 时不会走 partial 直写
			_fail("INVALID_DOWNLOAD_TARGET")
			return
		if not _append_chunk_to_partial(chunk_path, partial):
			_cleanup_chunk()
			_fail("PARTIAL_APPEND_FAILED")
			return
		_cleanup_chunk()
	elif response_code == 200:
		# 全量 200：必须安全覆盖 partial，绝不能 append 到旧 partial
		if _download_to_partial:
			# 已直接写入 partial；若曾有旧前缀，WRITE 模式从零覆盖（HTTPRequest 打开即截断）
			pass
		else:
			if not FileAccess.file_exists(chunk_path):
				_fail("EMPTY_DOWNLOAD")
				return
			_delete_path(partial)
			var ren_err: Error = DirAccess.rename_absolute(chunk_path, partial)
			if ren_err != OK:
				if not _copy_file(chunk_path, partial):
					_cleanup_chunk()
					_fail("PARTIAL_WRITE_FAILED")
					return
				_cleanup_chunk()
			else:
				_cleanup_chunk()
		_request_offset = 0
	else:
		# 非法状态码：不保留可能污染的直写 partial
		_cleanup_chunk()
		if _download_to_partial:
			_delete_path(partial)
		_fail("HTTP_STATUS_%d" % response_code)
		return

	var psz: int = _file_size(partial)
	_received_bytes = maxi(psz, 0)
	progress_changed.emit(_received_bytes, expected)

	if psz < 0:
		_fail("PARTIAL_STAT_FAILED")
		return
	if psz > expected:
		_delete_path(partial)
		_fail("PARTIAL_TOO_LARGE")
		return
	if psz < expected:
		# 完整响应却长度不足：视为可重试中断，保留前缀
		_fail("INCOMPLETE_DOWNLOAD")
		return

	_set_state(STATE_VERIFYING)
	_verify_and_activate(partial)


## 中断/取消后的磁盘策略：保留 0<size<expected 的 partial；丢弃 chunk。
func _finalize_interrupted_download(from_failure: bool) -> void:
	var expected: int = int(_manifest.get("size_bytes", 0))
	var partial: String = partial_model_path()
	_cleanup_chunk()
	if not FileAccess.file_exists(partial):
		return
	var psz: int = _file_size(partial)
	if psz <= 0 or psz > expected:
		_delete_path(partial)
		return
	if psz == expected and from_failure:
		# 完整但未校验成功的文件留给后续 verify 路径；失败回调里通常 size 不足
		return
	# 0 < psz < expected：保留供 Range 续传
	_received_bytes = psz
	progress_changed.emit(psz, expected)


func _verify_and_activate(partial_path: String) -> bool:
	if _released or _cancelled:
		_ensure_in_flight = false
		return false
	var expected: int = int(_manifest.get("size_bytes", 0))
	var sz: int = _file_size(partial_path)
	if sz != expected:
		_delete_path(partial_path)
		_fail("SIZE_MISMATCH")
		return false
	var digest: String = _sha256_file(partial_path)
	var want: String = String(_manifest.get("sha256", "")).to_lower()
	if digest.is_empty() or digest.to_lower() != want:
		_delete_path(partial_path)
		_fail("SHA256_MISMATCH")
		return false
	# 原子启用：本 version 目录内单次 rename partial → active。
	# 目标 active 在到达此处前应不存在（无效 active 已清理；其它 version 在独立目录）。
	var active: String = active_model_path()
	if FileAccess.file_exists(active):
		# 防御：仍存在则先确认是否已是正确文件
		if _active_matches_manifest():
			_delete_path(partial_path)
			_cleanup_chunk()
			_received_bytes = expected
			progress_changed.emit(expected, expected)
			_ensure_in_flight = false
			_set_state(STATE_READY)
			return true
		_delete_path(active)
	var e2: Error = DirAccess.rename_absolute(partial_path, active)
	if e2 != OK:
		_fail("ATOMIC_RENAME_FAILED")
		return false
	_cleanup_chunk()
	_received_bytes = expected
	progress_changed.emit(expected, expected)
	_ensure_in_flight = false
	_set_state(STATE_READY)
	return true


func _append_chunk_to_partial(chunk_path: String, partial_path: String) -> bool:
	if not FileAccess.file_exists(chunk_path):
		return false
	var chunk := FileAccess.open(chunk_path, FileAccess.READ)
	if chunk == null:
		return false
	var out: FileAccess
	if FileAccess.file_exists(partial_path):
		out = FileAccess.open(partial_path, FileAccess.READ_WRITE)
		if out == null:
			chunk.close()
			return false
		out.seek_end()
	else:
		out = FileAccess.open(partial_path, FileAccess.WRITE)
		if out == null:
			chunk.close()
			return false
	while true:
		var buf: PackedByteArray = chunk.get_buffer(65536)
		if buf.is_empty():
			break
		out.store_buffer(buf)
	chunk.close()
	out.close()
	return true


func _copy_file(from_path: String, to_path: String) -> bool:
	var src := FileAccess.open(from_path, FileAccess.READ)
	if src == null:
		return false
	var dst := FileAccess.open(to_path, FileAccess.WRITE)
	if dst == null:
		src.close()
		return false
	while true:
		var buf: PackedByteArray = src.get_buffer(65536)
		if buf.is_empty():
			break
		dst.store_buffer(buf)
	src.close()
	dst.close()
	return true


func _active_matches_manifest() -> bool:
	var active: String = active_model_path()
	if not FileAccess.file_exists(active):
		return false
	var expected: int = int(_manifest.get("size_bytes", 0))
	if _file_size(active) != expected:
		return false
	var digest: String = _sha256_file(active)
	return digest.to_lower() == String(_manifest.get("sha256", "")).to_lower()


func _parse_content_range(headers: PackedStringArray) -> Dictionary:
	for h in headers:
		var line: String = String(h)
		var lower: String = line.to_lower()
		if lower.find("content-range") < 0:
			continue
		var colon: int = line.find(":")
		var value: String = line.substr(colon + 1).strip_edges() if colon >= 0 else line
		value = value.trim_prefix("bytes").strip_edges()
		var slash: int = value.find("/")
		if slash < 0:
			return {}
		var range_part: String = value.substr(0, slash)
		var dash: int = range_part.find("-")
		if dash < 0:
			return {}
		var start_s: String = range_part.substr(0, dash).strip_edges()
		var end_s: String = range_part.substr(dash + 1).strip_edges()
		if not start_s.is_valid_int() or not end_s.is_valid_int():
			return {}
		return {"start": int(start_s), "end": int(end_s)}
	return {}


func _sha256_file(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	while true:
		var chunk: PackedByteArray = f.get_buffer(65536)
		if chunk.is_empty():
			break
		ctx.update(chunk)
	f.close()
	return ctx.finish().hex_encode()


func _file_size(path: String) -> int:
	if not FileAccess.file_exists(path):
		return -1
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return -1
	var sz: int = f.get_length()
	f.close()
	return sz


func _ensure_dir() -> void:
	DirAccess.make_dir_recursive_absolute(model_version_dir())


func _version_dir_name() -> String:
	var v: String = String(_manifest.get("version", ""))
	if v.is_empty():
		v = String(_manifest.get("source_revision", ""))
	if v.is_empty():
		v = String(_manifest.get("id", "unknown"))
	# 路径安全：不引入层级
	v = v.replace("/", "_").replace("\\", "_").replace("..", "_")
	return v


func _filename() -> String:
	var fname: String = String(_manifest.get("filename", ""))
	if fname.is_empty():
		return WhisperModelManifest.FILENAME_SMALL
	return fname


func _is_public_host(url: String) -> bool:
	var u: String = url.to_lower()
	if u.contains("127.0.0.1") or u.contains("localhost") or u.contains("[::1]"):
		return false
	return u.contains("huggingface.co") or u.begins_with("https://") or u.begins_with("http://")


func _fail(code: String) -> void:
	_ensure_in_flight = false
	# 注意：调用方若已 _finalize_interrupted_download，则不要二次误删 partial。
	# 此处仅保证 chunk 不残留；partial 保留策略由调用路径决定。
	if code.begins_with("HTTP_RESULT_") or code == "INCOMPLETE_DOWNLOAD":
		pass
	elif code == "SHA256_MISMATCH" or code == "SIZE_MISMATCH" or code == "PARTIAL_TOO_LARGE" \
			or code == "HTTP_416" or code.begins_with("HTTP_STATUS_"):
		_cleanup_chunk()
	else:
		_cleanup_chunk()
	_set_error(code)
	_set_state(STATE_FAILED)


func _set_state(s: StringName) -> void:
	if _state == s:
		return
	_state = s
	state_changed.emit(_state)


func _set_error(code: String) -> void:
	_error_code = code
	error_changed.emit(_error_code)


func _ensure_http_node() -> void:
	if _http != null and is_instance_valid(_http):
		if not _http.request_completed.is_connected(_on_request_completed):
			_http.request_completed.connect(_on_request_completed)
		return
	_http = HTTPRequest.new()
	_http.name = "WhisperModelHttp"
	# Godot 4.6：大型下载建议 timeout=0 禁用总时长超时
	_http.timeout = 0.0
	# 主线程推进，便于 cancel/落盘与 process_frame 对齐（不 mock 核心）
	_http.use_threads = false
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)


func _teardown_http() -> void:
	if _http != null and is_instance_valid(_http):
		_http.cancel_request()
		if _http.request_completed.is_connected(_on_request_completed):
			_http.request_completed.disconnect(_on_request_completed)
		if _http.get_parent() == self:
			remove_child(_http)
		_http.free()
	_http = null
	_cleanup_chunk()


func _cleanup_chunk() -> void:
	_delete_path(chunk_model_path())


func _cleanup_stale_temps() -> void:
	# 仅清理本 version 目录内遗留 swap/chunk，不影响其它 version 的 active
	var active: String = active_model_path()
	_delete_path(active + ".swap")
	_cleanup_chunk()


func _delete_path(path: String) -> void:
	if path.is_empty():
		return
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
