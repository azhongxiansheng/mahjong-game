extends GutTest

# E4-03（#245）：whisper.cpp 模型清单 / Range 断点续传 / SHA-256 / 原子启用 / 生命周期。
# 核心下载用本地真实 TCP HTTP fixture + 小二进制，不走公网、不 mock HTTP/文件/SHA/rename。

var _fixture_body: PackedByteArray = PackedByteArray()
var _fixture_sha: String = ""
var _http: _RangeHttpFixture = null
var _models_root: String = ""
var _case_i: int = 0


class _RangeHttpFixture extends Node:
	var server: TCPServer = TCPServer.new()
	var body: PackedByteArray = PackedByteArray()
	var port: int = 0
	var ignore_range: bool = false
	var force_416: bool = false
	var bad_content_range: bool = false
	var response_delay_frames: int = 0
	## 响应 body 每次最多发送的字节；>0 时跨多帧流式发送（真实慢下载）。
	var body_chunk_size: int = 0
	## 两次 body chunk 之间额外空转的 process 帧数（进一步降速）。
	var body_chunk_hold_frames: int = 0
	## >=0 时：headers 后只发送这么多 body 字节就断开（模拟网络中断）。
	var disconnect_after_body_bytes: int = -1
	var request_count: int = 0
	var last_range_header: String = ""
	var last_range_start: int = -1
	var total_body_bytes_sent: int = 0
	var _peers: Array = []

	func start_on_ephemeral_port() -> int:
		var err: Error = server.listen(0, "127.0.0.1")
		assert(err == OK)
		port = server.get_local_port()
		set_process(true)
		return port

	func stop() -> void:
		set_process(false)
		for item in _peers:
			var peer: StreamPeerTCP = _peer_of(item)
			if peer != null:
				peer.disconnect_from_host()
		_peers.clear()
		if server.is_listening():
			server.stop()

	func base_url() -> String:
		return "http://127.0.0.1:%d/model.bin" % port

	func _peer_of(item: Variant) -> StreamPeerTCP:
		if item is StreamPeerTCP:
			return item as StreamPeerTCP
		if item is Dictionary:
			return (item as Dictionary).get("peer", null) as StreamPeerTCP
		return null

	func _process(_dt: float) -> void:
		if server.is_connection_available():
			var peer: StreamPeerTCP = server.take_connection()
			if peer != null:
				_peers.append(peer)
		var still: Array = []
		for item in _peers:
			if item is Dictionary:
				var d: Dictionary = item
				var peer_d: StreamPeerTCP = d.get("peer", null) as StreamPeerTCP
				if peer_d == null:
					continue
				peer_d.poll()
				var mode: String = String(d.get("mode", ""))
				if mode == "stream":
					_stream_body_tick(d, still)
					continue
				var left: int = int(d.get("delay_left", 0))
				if left > 0:
					d["delay_left"] = left - 1
					still.append(d)
					continue
				_begin_response(peer_d, int(d.get("range_start", -1)), still)
				continue
			var peer2: StreamPeerTCP = item as StreamPeerTCP
			if peer2 == null:
				continue
			peer2.poll()
			var st: StreamPeerTCP.Status = peer2.get_status()
			if st == StreamPeerTCP.STATUS_CONNECTED:
				if peer2.get_available_bytes() > 0:
					var raw: String = peer2.get_utf8_string(peer2.get_available_bytes())
					if raw.is_empty():
						still.append(peer2)
						continue
					request_count += 1
					var range_start: int = -1
					last_range_header = ""
					last_range_start = -1
					for line in raw.split("\r\n"):
						var lower: String = line.to_lower()
						if lower.begins_with("range:"):
							last_range_header = line
							var spec: String = line.substr(line.find(":") + 1).strip_edges()
							if spec.begins_with("bytes="):
								var part: String = spec.substr(6)
								var dash: int = part.find("-")
								if dash > 0:
									range_start = int(part.substr(0, dash))
									last_range_start = range_start
					if response_delay_frames > 0:
						still.append({
							"peer": peer2,
							"range_start": range_start,
							"delay_left": response_delay_frames,
						})
					else:
						_begin_response(peer2, range_start, still)
				else:
					still.append(peer2)
			elif st == StreamPeerTCP.STATUS_CONNECTING:
				still.append(peer2)
		_peers = still

	func _begin_response(peer: StreamPeerTCP, range_start: int, still: Array) -> void:
		var total: int = body.size()
		if force_416:
			peer.put_data("HTTP/1.1 416 Range Not Satisfiable\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".to_utf8_buffer())
			peer.disconnect_from_host()
			return
		var payload: PackedByteArray
		var hdr: String
		if range_start >= 0 and not ignore_range:
			if range_start >= total:
				peer.put_data("HTTP/1.1 416 Range Not Satisfiable\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".to_utf8_buffer())
				peer.disconnect_from_host()
				return
			payload = body.slice(range_start)
			var end_i: int = total - 1
			var cr: String = "bytes %d-%d/%d" % [range_start, end_i, total]
			if bad_content_range:
				cr = "bytes %d-%d/%d" % [range_start + 9, end_i, total]
			hdr = (
				"HTTP/1.1 206 Partial Content\r\n"
				+ "Content-Length: %d\r\n" % payload.size()
				+ "Content-Range: %s\r\n" % cr
				+ "Accept-Ranges: bytes\r\n"
				+ "Connection: close\r\n\r\n"
			)
		else:
			payload = body
			hdr = (
				"HTTP/1.1 200 OK\r\n"
				+ "Content-Length: %d\r\n" % payload.size()
				+ "Accept-Ranges: bytes\r\n"
				+ "Connection: close\r\n\r\n"
			)
		peer.put_data(hdr.to_utf8_buffer())
		var need_stream: bool = body_chunk_size > 0 or disconnect_after_body_bytes >= 0
		if not need_stream:
			peer.put_data(payload)
			peer.disconnect_from_host()
			return
		still.append({
			"mode": "stream",
			"peer": peer,
			"payload": payload,
			"body_sent": 0,
			"hold_left": 0,
		})

	func _stream_body_tick(d: Dictionary, still: Array) -> void:
		var peer: StreamPeerTCP = d.get("peer", null) as StreamPeerTCP
		if peer == null:
			return
		var st: StreamPeerTCP.Status = peer.get_status()
		if st != StreamPeerTCP.STATUS_CONNECTED and st != StreamPeerTCP.STATUS_CONNECTING:
			return
		var hold_left: int = int(d.get("hold_left", 0))
		if hold_left > 0:
			d["hold_left"] = hold_left - 1
			still.append(d)
			return
		var payload: PackedByteArray = d.get("payload", PackedByteArray()) as PackedByteArray
		var body_sent: int = int(d.get("body_sent", 0))
		if body_sent >= payload.size():
			peer.disconnect_from_host()
			return
		if disconnect_after_body_bytes >= 0 and body_sent >= disconnect_after_body_bytes:
			peer.disconnect_from_host()
			return
		var remain: int = payload.size() - body_sent
		var step: int = remain
		if body_chunk_size > 0:
			step = mini(body_chunk_size, remain)
		if disconnect_after_body_bytes >= 0:
			step = mini(step, disconnect_after_body_bytes - body_sent)
		if step <= 0:
			peer.disconnect_from_host()
			return
		var piece: PackedByteArray = payload.slice(body_sent, body_sent + step)
		peer.put_data(piece)
		body_sent += step
		total_body_bytes_sent += step
		d["body_sent"] = body_sent
		d["hold_left"] = body_chunk_hold_frames
		if disconnect_after_body_bytes >= 0 and body_sent >= disconnect_after_body_bytes:
			peer.disconnect_from_host()
			return
		if body_sent >= payload.size():
			peer.disconnect_from_host()
			return
		still.append(d)


func before_all() -> void:
	_fixture_body = ("WHISPER-FIXTURE-v1-").to_utf8_buffer()
	for i in range(256):
		_fixture_body.append(i)
	for i in range(256):
		_fixture_body.append(i)
	for i in range(256):
		_fixture_body.append(i)
	for i in range(256):
		_fixture_body.append(i)
	assert_eq(_fixture_body.size(), 1043, "fixture 长度固定便于审查")
	_fixture_sha = _sha256_bytes(_fixture_body)
	assert_false(_fixture_sha.is_empty())


func before_each() -> void:
	_case_i += 1
	_models_root = "/tmp/mahjong-whisper-test-%d-%d" % [Time.get_ticks_usec(), _case_i]
	DirAccess.make_dir_recursive_absolute(_models_root)
	_http = _RangeHttpFixture.new()
	_http.body = _fixture_body
	add_child_autofree(_http)
	_http.start_on_ephemeral_port()


func after_each() -> void:
	if _http != null and is_instance_valid(_http):
		_http.stop()
	_http = null
	_rm_rf(_models_root)


func _sha256_bytes(data: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(data)
	return ctx.finish().hex_encode()


func _sha256_file(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	while true:
		var chunk: PackedByteArray = f.get_buffer(4096)
		if chunk.is_empty():
			break
		ctx.update(chunk)
	return ctx.finish().hex_encode()


func _rm_rf(path: String) -> void:
	if path.is_empty() or not path.begins_with("/tmp/mahjong-whisper-test-"):
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry == "." or entry == "..":
			entry = dir.get_next()
			continue
		var child: String = path.path_join(entry)
		if dir.current_is_dir():
			_rm_rf(child)
		else:
			DirAccess.remove_absolute(child)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)


func _manifest(
	url: String = "",
	size_bytes: int = -1,
	sha: String = "",
	version: String = "fixture-v1"
) -> Dictionary:
	return {
		"id": "fixture-small",
		"version": version,
		"url": url if not url.is_empty() else _http.base_url(),
		"size_bytes": _fixture_body.size() if size_bytes < 0 else size_bytes,
		"sha256": _fixture_sha if sha.is_empty() else sha,
		"source_revision": "fixture-rev",
		"license": "mit",
		"filename": "ggml-small.bin",
	}


func _make_manager(manifest: Dictionary = {}, use_autofree: bool = true) -> WhisperModelManager:
	var mgr := WhisperModelManager.new()
	mgr.name = "WhisperModelManagerUnderTest"
	if use_autofree:
		add_child_autofree(mgr)
	else:
		add_child(mgr)
	mgr.set_models_root(_models_root)
	mgr.set_allow_public_network(true)
	if manifest.is_empty():
		mgr.set_manifest(_manifest())
	else:
		mgr.set_manifest(manifest)
	return mgr


func _write_bytes(path: String, data: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(f, "无法写入 %s" % path)
	f.store_buffer(data)
	f.close()


func _wait_terminal(mgr: WhisperModelManager, timeout_ms: int = 8000) -> StringName:
	var start: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < timeout_ms:
		var st: StringName = mgr.get_lifecycle_state()
		if st == &"ready" or st == &"failed" or st == &"cancelled":
			return st
		await get_tree().process_frame
	return mgr.get_lifecycle_state()


func test_production_manifest_has_frozen_fields() -> void:
	var m: Dictionary = WhisperModelManifest.production_small()
	assert_eq(String(m.get("id", "")), "ggml-small")
	assert_false(String(m.get("version", "")).is_empty(), "version 必须绑定 revision 的稳定标识")
	assert_true(String(m.get("version", "")).contains("5359861c"), "version 须含 source revision 前缀")
	assert_eq(
		String(m.get("url", "")),
		"https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-small.bin"
	)
	assert_eq(int(m.get("size_bytes", -1)), 487601967)
	assert_eq(
		String(m.get("sha256", "")),
		"1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b"
	)
	assert_eq(
		String(m.get("source_revision", "")),
		"5359861c739e955e79d9a303bcbc70fb988958b1"
	)
	assert_eq(String(m.get("license", "")).to_lower(), "mit")
	assert_eq(String(m.get("filename", "")), "ggml-small.bin")
	assert_false(String(m.get("url", "")).contains("/main/"), "禁止可漂移 main URL")


func test_http_timeout_disabled_for_large_downloads() -> void:
	var mgr := _make_manager()
	assert_eq(mgr.http_timeout(), 0.0, "大文件下载 timeout 须为 0（禁用总时长超时）")


func test_fresh_download_verifies_and_atomically_enables() -> void:
	var mgr := _make_manager()
	assert_eq(mgr.get_lifecycle_state(), &"idle")
	mgr.ensure_ready()
	var st: StringName = await _wait_terminal(mgr)
	assert_eq(st, &"ready", "全新下载应 ready: err=%s" % mgr.get_error_code())
	assert_true(mgr.is_model_ready())
	var active: String = mgr.active_model_path()
	assert_true(active.contains("fixture-v1"), "active 须落在 version 子目录")
	assert_true(FileAccess.file_exists(active))
	assert_eq(FileAccess.get_file_as_bytes(active).size(), _fixture_body.size())
	assert_eq(_sha256_file(active), _fixture_sha)
	assert_false(FileAccess.file_exists(mgr.partial_model_path()), "成功后不应残留 partial")
	assert_gte(_http.request_count, 1)


func test_partial_resume_sends_range_and_appends() -> void:
	var mgr := _make_manager()
	_write_bytes(mgr.partial_model_path(), _fixture_body.slice(0, 400))
	mgr.ensure_ready()
	var st: StringName = await _wait_terminal(mgr)
	assert_eq(st, &"ready", "续传应成功: %s" % mgr.get_error_code())
	assert_true(
		String(_http.last_range_header).contains("bytes=400-")
		or String(_http.last_range_header).contains("bytes=400"),
		"必须发送 Range: bytes=400- ，实际=%s" % _http.last_range_header
	)
	assert_eq(_sha256_file(mgr.active_model_path()), _fixture_sha)


func test_range_ignored_200_replaces_partial_safely() -> void:
	_http.ignore_range = true
	var mgr := _make_manager()
	_write_bytes(mgr.partial_model_path(), PackedByteArray([9, 9, 9, 9, 9]))
	mgr.ensure_ready()
	var st: StringName = await _wait_terminal(mgr)
	assert_eq(st, &"ready", "200 全量应覆盖 partial: %s" % mgr.get_error_code())
	assert_eq(FileAccess.get_file_as_bytes(mgr.active_model_path()).size(), _fixture_body.size())
	assert_eq(_sha256_file(mgr.active_model_path()), _fixture_sha)


func test_bad_content_range_recovers_retryable() -> void:
	var mgr := _make_manager()
	_write_bytes(mgr.partial_model_path(), _fixture_body.slice(0, 100))
	_http.bad_content_range = true
	mgr.ensure_ready()
	var st: StringName = await _wait_terminal(mgr)
	assert_eq(st, &"failed")
	_http.bad_content_range = false
	mgr.ensure_ready()
	st = await _wait_terminal(mgr)
	assert_eq(st, &"ready", "修复服务后重试应成功: %s" % mgr.get_error_code())


func test_http_416_recovers_retryable() -> void:
	var mgr := _make_manager()
	_write_bytes(mgr.partial_model_path(), _fixture_body.slice(0, 50))
	_http.force_416 = true
	mgr.ensure_ready()
	var st: StringName = await _wait_terminal(mgr)
	assert_eq(st, &"failed")
	_http.force_416 = false
	mgr.ensure_ready()
	st = await _wait_terminal(mgr)
	assert_eq(st, &"ready", "416 恢复后重试: %s" % mgr.get_error_code())


func test_wrong_hash_deletes_partial_and_retries_from_zero() -> void:
	var bad_sha := "0".repeat(64)
	var mgr := _make_manager(_manifest("", -1, bad_sha))
	mgr.ensure_ready()
	var st: StringName = await _wait_terminal(mgr)
	assert_eq(st, &"failed")
	if FileAccess.file_exists(mgr.partial_model_path()):
		assert_ne(
			FileAccess.get_file_as_bytes(mgr.partial_model_path()).size(),
			_fixture_body.size(),
			"坏校验后不应保留完整坏 partial"
		)
	mgr.set_manifest(_manifest())
	mgr.ensure_ready()
	st = await _wait_terminal(mgr)
	assert_eq(st, &"ready", "hash 修正后重试: %s" % mgr.get_error_code())


func test_failed_download_does_not_clobber_existing_active() -> void:
	var mgr_ok := _make_manager()
	_write_bytes(mgr_ok.active_model_path(), _fixture_body)
	mgr_ok.ensure_ready()
	var st_ok: StringName = await _wait_terminal(mgr_ok)
	assert_eq(st_ok, &"ready")
	var active_a: String = mgr_ok.active_model_path()
	assert_eq(_sha256_file(active_a), _fixture_sha)

	# 同 version 换错误 manifest 尺寸/hash：失败不得半文件覆盖
	_http.body = PackedByteArray([1, 2, 3])
	var mgr2 := _make_manager(_manifest("", 3, "11".repeat(32)))
	# 同 version 目录；先写好的 active 对新年 manifest 无效会被删后重下失败
	mgr2.ensure_ready()
	var st2: StringName = await _wait_terminal(mgr2)
	assert_eq(st2, &"failed", "错误 hash 应失败: %s" % mgr2.get_error_code())
	# 失败后不得留下 size=3 的假 active 冒充 ready 产物；半文件不可作为 active
	if FileAccess.file_exists(mgr2.active_model_path()):
		assert_ne(FileAccess.get_file_as_bytes(mgr2.active_model_path()).size(), 1, "半文件不可为 active")


func test_version_b_fail_preserves_version_a() -> void:
	# P1-2：版本 A ready 后，B 下载/校验失败时 A 仍在独立路径
	var mgr_a := _make_manager(_manifest("", -1, "", "fixture-vA"))
	mgr_a.ensure_ready()
	var st_a: StringName = await _wait_terminal(mgr_a)
	assert_eq(st_a, &"ready")
	var path_a: String = mgr_a.active_model_path()
	assert_true(FileAccess.file_exists(path_a))
	assert_true(path_a.contains("fixture-vA"))
	var sha_a := _sha256_file(path_a)

	_http.body = PackedByteArray([9, 9, 9])
	var mgr_b := _make_manager(_manifest("", 3, "22".repeat(32), "fixture-vB"))
	mgr_b.ensure_ready()
	var st_b: StringName = await _wait_terminal(mgr_b)
	assert_eq(st_b, &"failed")
	assert_true(FileAccess.file_exists(path_a), "B 失败不得删除 A active")
	assert_eq(_sha256_file(path_a), sha_a)
	assert_false(FileAccess.file_exists(mgr_b.active_model_path()), "B 失败不得留下坏 active")


func test_version_b_success_via_single_rename_keeps_a() -> void:
	var mgr_a := _make_manager(_manifest("", -1, "", "fixture-vA"))
	mgr_a.ensure_ready()
	assert_eq(await _wait_terminal(mgr_a), &"ready")
	var path_a: String = mgr_a.active_model_path()
	var sha_a := _sha256_file(path_a)

	var mgr_b := _make_manager(_manifest("", -1, "", "fixture-vB"))
	mgr_b.ensure_ready()
	assert_eq(await _wait_terminal(mgr_b), &"ready")
	assert_true(FileAccess.file_exists(path_a))
	assert_eq(_sha256_file(path_a), sha_a)
	assert_true(FileAccess.file_exists(mgr_b.active_model_path()))
	assert_true(mgr_b.active_model_path().contains("fixture-vB"))
	assert_eq(_sha256_file(mgr_b.active_model_path()), _fixture_sha)


func test_stale_swap_cleanup_does_not_delete_valid_other_version() -> void:
	# 模拟旧实现遗留 .swap：清理不得误删其它 version 的有效 A
	var mgr_a := _make_manager(_manifest("", -1, "", "fixture-vA"))
	_write_bytes(mgr_a.active_model_path(), _fixture_body)
	var path_a: String = mgr_a.active_model_path()
	# 在 B 目录写 stale swap
	var mgr_b := _make_manager(_manifest("", -1, "", "fixture-vB"))
	var swap_b: String = mgr_b.active_model_path() + ".swap"
	_write_bytes(swap_b, PackedByteArray([1, 2, 3, 4]))
	mgr_b.ensure_ready()
	assert_eq(await _wait_terminal(mgr_b), &"ready")
	assert_true(FileAccess.file_exists(path_a), "清理 stale 不得动 A")
	assert_false(FileAccess.file_exists(swap_b), "本 version swap 应被清理")


func test_full_bad_partial_fails_without_auto_download_then_coalesced_retry() -> void:
	# P2-2：完整坏 partial → 第一次 failed 且无网络；下次 ensure 合并单次下载
	var mgr := _make_manager()
	var bad := _fixture_body.duplicate()
	bad[0] = (bad[0] + 1) % 256
	_write_bytes(mgr.partial_model_path(), bad)
	var before_req: int = _http.request_count
	mgr.ensure_ready()
	var st: StringName = await _wait_terminal(mgr)
	assert_eq(st, &"failed", "完整坏 partial 必须 failed: %s" % mgr.get_error_code())
	assert_eq(mgr.get_error_code(), "SHA256_MISMATCH")
	assert_eq(_http.request_count, before_req, "第一次不得自动发起网络下载")
	assert_false(FileAccess.file_exists(mgr.partial_model_path()), "坏 partial 应清理")

	mgr.ensure_ready()
	mgr.ensure_ready()
	mgr.ensure_ready()
	st = await _wait_terminal(mgr)
	assert_eq(st, &"ready", "下次 ensure 应成功: %s" % mgr.get_error_code())
	assert_eq(_http.request_count, before_req + 1, "并发 ensure 只能一次下载")


func test_reparent_after_unparent_completes_ready() -> void:
	# P1-1：卸树 teardown HTTP 后 reparent，信号须重连并完成 ready
	var host1 := Node.new()
	add_child_autofree(host1)
	var mgr := WhisperModelManager.new()
	host1.add_child(mgr)
	mgr.set_models_root(_models_root)
	mgr.set_allow_public_network(true)
	mgr.set_manifest(_manifest())
	# 预置 partial 触发续传路径
	_write_bytes(mgr.partial_model_path(), _fixture_body.slice(0, 100))
	mgr.ensure_ready()
	var start_ms: int = Time.get_ticks_msec()
	while mgr.get_lifecycle_state() != &"downloading" and Time.get_ticks_msec() - start_ms < 2000:
		await get_tree().process_frame
	# 卸树（触发 _exit_tree → teardown HTTP）
	host1.remove_child(mgr)
	await get_tree().process_frame
	assert_false(mgr.is_inside_tree())
	# reparent 同一实例
	var host2 := Node.new()
	add_child_autofree(host2)
	host2.add_child(mgr)
	await get_tree().process_frame
	mgr.ensure_ready()
	var st: StringName = await _wait_terminal(mgr)
	assert_eq(st, &"ready", "reparent 后须能完成: %s" % mgr.get_error_code())
	assert_eq(_sha256_file(mgr.active_model_path()), _fixture_sha)
	mgr.release()
	if mgr.get_parent() != null:
		mgr.get_parent().remove_child(mgr)
	mgr.free()


func _file_len(path: String) -> int:
	if path.is_empty() or not FileAccess.file_exists(path):
		return 0
	# 下载过程中 HTTPRequest 可能独占写句柄；get_size 不依赖完整读入
	var sz: int = FileAccess.get_size(path)
	if sz < 0:
		return 0
	return sz


func _disk_progress_size(mgr: WhisperModelManager) -> int:
	return maxi(_file_len(mgr.chunk_model_path()), _file_len(mgr.partial_model_path()))


func test_cancel_mid_fresh_download_preserves_real_http_progress_and_resumes_range() -> void:
	# P1 round3：空目录真实 HTTP 流式下载中途 cancel，必须保留本次已落盘前缀并 Range 续传。
	# 禁止预置 partial 的假续传。
	var big: PackedByteArray = PackedByteArray()
	for _i in range(8):
		big.append_array(_fixture_body)
	assert_gt(big.size(), 4000)
	_http.body = big
	_http.body_chunk_size = 32
	_http.body_chunk_hold_frames = 2
	_http.total_body_bytes_sent = 0
	var sha_big := _sha256_bytes(big)
	var mgr := _make_manager({
		"id": "fixture-small",
		"version": "fixture-v1",
		"url": _http.base_url(),
		"size_bytes": big.size(),
		"sha256": sha_big,
		"source_revision": "fixture-rev",
		"license": "mit",
		"filename": "ggml-small.bin",
	})
	assert_false(FileAccess.file_exists(mgr.partial_model_path()), "必须从空目录开始")
	assert_false(FileAccess.file_exists(mgr.chunk_model_path()))

	mgr.ensure_ready()
	var expected: int = big.size()
	var saw_progress: bool = false
	var progress: int = 0
	var start_ms: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start_ms < 8000:
		# 等服务端已真正吐出 body，再读磁盘（offset=0 直写 partial）
		if _http.total_body_bytes_sent > 32:
			progress = _disk_progress_size(mgr)
			if progress > 0 and progress < expected:
				saw_progress = true
				break
		if mgr.get_lifecycle_state() == &"ready" or mgr.get_lifecycle_state() == &"failed":
			break
		await get_tree().process_frame
	if not saw_progress:
		# 避免慢流 + 失败断言后 HTTP 挂起：强制收尾
		mgr.cancel()
		await get_tree().process_frame
	assert_true(
		saw_progress,
		"取消前必须已有真实 HTTP 落盘进度 0<size<expected，实际 progress=%d server_sent=%d state=%s" % [
			progress, _http.total_body_bytes_sent, mgr.get_lifecycle_state()
		]
	)
	if not saw_progress:
		return

	mgr.cancel()
	var st: StringName = await _wait_terminal(mgr, 3000)
	assert_eq(st, &"cancelled")
	assert_true(
		FileAccess.file_exists(mgr.partial_model_path()),
		"cancel 后必须保留 partial（真实下载前缀），不能只删 chunk 归零"
	)
	var saved: int = _file_len(mgr.partial_model_path())
	assert_gt(saved, 0, "partial 大小必须 >0")
	assert_lt(saved, expected, "partial 不得已是完整文件")
	assert_gte(saved, progress, "cancel 不得丢弃已观察到的真实进度")

	# 恢复全速完整响应，验证 Range 续传而非从 0 重下
	_http.body_chunk_size = 0
	_http.disconnect_after_body_bytes = -1
	_http.last_range_header = ""
	_http.last_range_start = -1
	var req_before: int = _http.request_count
	mgr.ensure_ready()
	st = await _wait_terminal(mgr)
	assert_eq(st, &"ready", "取消后续传应 ready: %s" % mgr.get_error_code())
	assert_eq(_sha256_file(mgr.active_model_path()), sha_big)
	assert_eq(_http.request_count, req_before + 1, "续传应仅 1 次后续请求")
	assert_eq(
		_http.last_range_start,
		saved,
		"服务端必须看到 Range: bytes=%d- ，实际 header=%s start=%d" % [
			saved, _http.last_range_header, _http.last_range_start
		]
	)


func test_network_disconnect_mid_download_keeps_prefix_and_range_resumes() -> void:
	# 合法 headers + 部分 body 后服务端断开 → retryable failed，保留前缀；恢复后 Range 续传。
	var big: PackedByteArray = PackedByteArray()
	for _i in range(6):
		big.append_array(_fixture_body)
	_http.body = big
	_http.body_chunk_size = 32
	_http.disconnect_after_body_bytes = 180
	var sha_big := _sha256_bytes(big)
	var mgr := _make_manager({
		"id": "fixture-small",
		"version": "fixture-v1",
		"url": _http.base_url(),
		"size_bytes": big.size(),
		"sha256": sha_big,
		"source_revision": "fixture-rev",
		"license": "mit",
		"filename": "ggml-small.bin",
	})
	mgr.ensure_ready()
	var st: StringName = await _wait_terminal(mgr, 10000)
	assert_eq(st, &"failed", "中断应进入可重试 failed，实际=%s err=%s" % [st, mgr.get_error_code()])
	assert_true(
		FileAccess.file_exists(mgr.partial_model_path()),
		"网络中断后必须保留已下载合法前缀 partial"
	)
	var saved: int = _file_len(mgr.partial_model_path())
	assert_gt(saved, 0)
	assert_lt(saved, big.size())
	assert_lte(saved, 180)

	_http.body_chunk_size = 0
	_http.disconnect_after_body_bytes = -1
	_http.last_range_start = -1
	var req_before: int = _http.request_count
	mgr.ensure_ready()
	st = await _wait_terminal(mgr)
	assert_eq(st, &"ready", "恢复后续传: %s" % mgr.get_error_code())
	assert_eq(_sha256_file(mgr.active_model_path()), sha_big)
	assert_eq(_http.request_count, req_before + 1)
	assert_eq(
		_http.last_range_start,
		saved,
		"恢复后必须 Range 续传 offset=%d header=%s" % [saved, _http.last_range_header]
	)


func test_concurrent_ensure_coalesces_single_download() -> void:
	var mgr := _make_manager()
	mgr.ensure_ready()
	mgr.ensure_ready()
	mgr.ensure_ready()
	var st: StringName = await _wait_terminal(mgr)
	assert_eq(st, &"ready")
	assert_eq(_http.request_count, 1, "并发 ensure 不得并发多写 partial，请求数=%d" % _http.request_count)


func test_release_cancels_and_does_not_leak_callbacks() -> void:
	_http.response_delay_frames = 40
	var mgr := WhisperModelManager.new()
	add_child(mgr)
	mgr.set_models_root(_models_root)
	mgr.set_allow_public_network(true)
	mgr.set_manifest(_manifest())
	mgr.ensure_ready()
	var start_ms: int = Time.get_ticks_msec()
	while mgr.get_lifecycle_state() != &"downloading" and Time.get_ticks_msec() - start_ms < 2000:
		await get_tree().process_frame
	mgr.release()
	assert_true(mgr.is_released())
	await get_tree().create_timer(0.25).timeout
	assert_ne(mgr.get_lifecycle_state(), &"ready")
	mgr.ensure_ready()
	await get_tree().process_frame
	assert_true(mgr.is_released())
	assert_ne(mgr.get_lifecycle_state(), &"ready")
	mgr.queue_free()
	await get_tree().process_frame


func test_default_models_root_is_user_whisper_not_platform_hardcoded() -> void:
	var mgr := WhisperModelManager.new()
	add_child_autofree(mgr)
	var root: String = mgr.get_models_root()
	assert_true(
		root == "user://models/whisper" or root.begins_with("user://models/whisper"),
		"默认应走 user://models/whisper，实际=%s" % root
	)
	assert_false(root.contains("/Library/"), "不得硬编码 macOS Library 路径")
	assert_false(root.to_lower().contains("appdata"), "不得硬编码 Windows AppData")


func test_oversized_partial_resets_retryable() -> void:
	var mgr := _make_manager()
	var too_big: PackedByteArray = _fixture_body + PackedByteArray([7, 7, 7])
	_write_bytes(mgr.partial_model_path(), too_big)
	mgr.ensure_ready()
	var st: StringName = await _wait_terminal(mgr)
	assert_eq(st, &"ready", "超长 partial 恢复: %s" % mgr.get_error_code())
	assert_eq(FileAccess.get_file_as_bytes(mgr.active_model_path()).size(), _fixture_body.size())
