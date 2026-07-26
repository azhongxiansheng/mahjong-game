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


# --- #257 P1-2：下载进度 HTTPRequest 采样（信号链，非仅磁盘） ---

func test_download_progress_signal_emits_mid_values_on_fresh_download() -> void:
	# 慢流真实 HTTP：progress_changed 必须出现 0 < received < total（非仅起终点）
	var big: PackedByteArray = PackedByteArray()
	for _i in range(12):
		big.append_array(_fixture_body)
	assert_gt(big.size(), 6000)
	_http.body = big
	_http.body_chunk_size = 64
	_http.body_chunk_hold_frames = 1
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
	var samples: Array = []
	mgr.progress_changed.connect(func(recv: int, total: int):
		samples.append({"recv": recv, "total": total, "state": mgr.get_lifecycle_state()})
	)
	mgr.ensure_ready()
	var start_ms: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start_ms < 10000:
		var st: StringName = mgr.get_lifecycle_state()
		if st == &"ready" or st == &"failed" or st == &"cancelled":
			break
		await get_tree().process_frame
	var st2: StringName = mgr.get_lifecycle_state()
	assert_eq(st2, &"ready", "慢流须完成: %s samples=%d" % [mgr.get_error_code(), samples.size()])
	var mid := false
	var last_recv := -1
	var monotonic := true
	for s in samples:
		var r: int = int(s["recv"])
		var t: int = int(s["total"])
		assert_eq(t, big.size())
		if r > 0 and r < big.size():
			mid = true
		if r < last_recv:
			monotonic = false
		last_recv = r
	assert_true(mid, "必须有中间进度值 0<recv<total，samples=%s" % str(samples))
	assert_true(monotonic, "进度须单调不减")
	# 终态后不应持续 process 采样
	var after: int = samples.size()
	for _j in range(10):
		await get_tree().process_frame
	assert_eq(samples.size(), after, "ready 后不得继续 progress 采样")


func test_range_resume_progress_includes_request_offset() -> void:
	# Range 续传：progress 必须从 offset 起算（offset + downloaded），不是从 0
	var big: PackedByteArray = PackedByteArray()
	for _i in range(10):
		big.append_array(_fixture_body)
	_http.body = big
	_http.body_chunk_size = 48
	_http.body_chunk_hold_frames = 1
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
	var offset: int = 200
	_write_bytes(mgr.partial_model_path(), big.slice(0, offset))
	var samples: Array = []
	mgr.progress_changed.connect(func(recv: int, total: int):
		samples.append(recv)
	)
	mgr.ensure_ready()
	var start_ms: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start_ms < 10000:
		if mgr.get_lifecycle_state() == &"ready" or mgr.get_lifecycle_state() == &"failed":
			break
		await get_tree().process_frame
	assert_eq(mgr.get_lifecycle_state(), &"ready", mgr.get_error_code())
	var saw_at_least_offset := false
	var saw_above_offset := false
	for r in samples:
		var recv: int = int(r)
		if recv >= offset:
			saw_at_least_offset = true
		if recv > offset and recv < big.size():
			saw_above_offset = true
	assert_true(saw_at_least_offset, "续传进度起点须 >= offset，samples=%s" % str(samples))
	assert_true(
		saw_above_offset or samples.has(big.size()),
		"续传须推进到 offset 以上或完成，samples=%s" % str(samples)
	)


func test_progress_sampling_stops_on_cancel() -> void:
	var big: PackedByteArray = PackedByteArray()
	for _i in range(10):
		big.append_array(_fixture_body)
	_http.body = big
	_http.body_chunk_size = 32
	_http.body_chunk_hold_frames = 2
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
	var samples: Array = []
	mgr.progress_changed.connect(func(recv: int, _t: int):
		samples.append(recv)
	)
	mgr.ensure_ready()
	var start_ms: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start_ms < 8000:
		if samples.size() >= 2:
			break
		if mgr.get_lifecycle_state() == &"ready":
			break
		await get_tree().process_frame
	mgr.cancel()
	await get_tree().process_frame
	var n: int = samples.size()
	for _j in range(12):
		await get_tree().process_frame
	# cancel 后允许一次终态整理进度，但不得持续增长采样（允许 +1 次 finalize）
	assert_lte(samples.size(), n + 2, "cancel 后不得持续 progress 采样")
	assert_eq(mgr.get_lifecycle_state(), &"cancelled")


# --- #257 P2-1：macOS 异步 HF resolve；Windows 不走旁路 ---

func test_windows_platform_never_uses_hf_curl_resolve() -> void:
	var mgr := _make_manager({
		"id": "fixture-small",
		"version": "fixture-v1",
		"url": WhisperModelManifest.URL_SMALL,
		"size_bytes": _fixture_body.size(),
		"sha256": _fixture_sha,
		"source_revision": "fixture-rev",
		"license": "mit",
		"filename": "ggml-small.bin",
	})
	mgr.platform_name_override = "Windows"
	var curl_calls: Array = []
	mgr.resolve_url_override = func(u: String) -> String:
		curl_calls.append(u)
		return u
	# Windows 不得进入异步 resolve 分支
	assert_false(mgr._should_async_resolve_hf_url(WhisperModelManifest.URL_SMALL))
	mgr.ensure_ready()
	await get_tree().process_frame
	assert_eq(curl_calls.size(), 0, "Windows 不得调用 resolve_url_override/curl")
	# 公网 HF + allow 在 Windows 会直连失败；此处仅断言未走 resolve 旁路
	mgr.cancel()


func test_macos_resolve_success_uses_resolved_url_for_http() -> void:
	# 本地 fixture HTTP：resolve 返回 fixture URL，证明异步完成后才 request
	var big: PackedByteArray = _fixture_body
	_http.body = big
	var sha := _fixture_sha
	var fixture_url: String = _http.base_url()
	var mgr := _make_manager({
		"id": "fixture-small",
		"version": "fixture-v1",
		"url": "https://huggingface.co/ggerganov/whisper.cpp/resolve/deadbeef/ggml-small.bin",
		"size_bytes": big.size(),
		"sha256": sha,
		"source_revision": "fixture-rev",
		"license": "mit",
		"filename": "ggml-small.bin",
	})
	mgr.platform_name_override = "macOS"
	mgr.resolve_url_override = func(_u: String) -> String:
		return fixture_url
	assert_true(mgr._should_async_resolve_hf_url(String(mgr.get_manifest().get("url", ""))))
	mgr.ensure_ready()
	# 至少一帧：resolve deferred
	await get_tree().process_frame
	await get_tree().process_frame
	var st: StringName = await _wait_terminal(mgr, 8000)
	assert_eq(st, &"ready", "resolve→fixture 后应 ready: %s" % mgr.get_error_code())
	assert_eq(_sha256_file(mgr.active_model_path()), sha)


func test_resolve_cancel_ignores_late_result_and_does_not_request() -> void:
	var fixture_url: String = _http.base_url()
	_http.body = _fixture_body
	var mgr := _make_manager({
		"id": "fixture-small",
		"version": "fixture-v1",
		"url": "https://huggingface.co/ggerganov/whisper.cpp/resolve/deadbeef/ggml-small.bin",
		"size_bytes": _fixture_body.size(),
		"sha256": _fixture_sha,
		"source_revision": "fixture-rev",
		"license": "mit",
		"filename": "ggml-small.bin",
	})
	mgr.platform_name_override = "macOS"
	var gate := {"allow": false}
	mgr.resolve_url_override = func(_u: String) -> String:
		# 立即返回；真实延迟由 cancel 抢在 deferred 前完成
		return fixture_url
	mgr.ensure_ready()
	# 在 deferred _on_resolve_finished 前 cancel
	var tok: int = mgr.get_resolve_token_for_test()
	mgr.cancel()
	assert_gt(mgr.get_resolve_token_for_test(), tok, "cancel 必须 invalidate resolve token")
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(mgr.get_lifecycle_state(), &"cancelled")
	assert_eq(_http.request_count, 0, "迟到 resolve 不得发起 HTTP 请求")


func test_resolve_failure_falls_back_to_original_url() -> void:
	# override 返回空 → 回退 manifest 原 URL；原 URL 为 fixture 时应 ready
	var fixture_url: String = _http.base_url()
	_http.body = _fixture_body
	var mgr := _make_manager({
		"id": "fixture-small",
		"version": "fixture-v1",
		"url": fixture_url,
		"size_bytes": _fixture_body.size(),
		"sha256": _fixture_sha,
		"source_revision": "fixture-rev",
		"license": "mit",
		"filename": "ggml-small.bin",
	})
	mgr.platform_name_override = "macOS"
	mgr.resolve_url_override = func(_u: String) -> String:
		return ""  # 解析失败 → 回退 manifest 原 fixture URL
	assert_true(mgr._should_async_resolve_hf_url(fixture_url))
	mgr.ensure_ready()
	var st: StringName = await _wait_terminal(mgr, 8000)
	assert_eq(st, &"ready", "空 resolve 须回退原 URL 并完成: %s" % mgr.get_error_code())
	assert_false(mgr.was_resolve_in_flight())
	assert_eq(_sha256_file(mgr.active_model_path()), _fixture_sha)

# --- #257 P1-2：真实异步 resolver 生命周期（非 resolve_url_override 冒充）---

func test_real_curl_resolve_worker_clears_after_finish() -> void:
	if not FileAccess.file_exists("/usr/bin/curl"):
		pending("no /usr/bin/curl")
		return
	if OS.get_name() != "macOS":
		pending("real curl resolve only exercised on macOS host")
		return
	var mgr := WhisperModelManager.new()
	add_child_autofree(mgr)
	var root := "/tmp/mahjong-e7-257-thread-join-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(root)
	mgr.set_models_root(root)
	mgr.apply_production_manifest()
	mgr.set_allow_public_network(true)
	mgr.platform_name_override = "macOS"
	mgr.curl_bin_override = "/usr/bin/curl"
	# 不注入 resolve_url_override → 真实可 kill 子进程 + curl HEAD
	mgr.ensure_ready()
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 35000:
		if not mgr.has_pending_resolve_worker() and not mgr.was_resolve_in_flight():
			# 解析阶段结束（随后可能进入 HTTP 下载）
			if mgr.get_lifecycle_state() != &"checking":
				break
		await get_tree().process_frame
	# 解析完成后不得残留活跃 worker
	assert_false(mgr.has_pending_resolve_worker(), "解析完成后不得残留活跃 resolve 子进程")
	assert_false(mgr.has_pending_resolve_thread())
	mgr.release()
	start = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 2000:
		if not mgr.has_pending_resolve_worker():
			break
		await get_tree().process_frame
	assert_false(mgr.has_pending_resolve_worker())
	_rm_rf_tmp_e7(root)


func test_real_thread_cancel_and_table_release_no_orphan() -> void:
	if not FileAccess.file_exists("/usr/bin/curl"):
		pending("no /usr/bin/curl")
		return
	if OS.get_name() != "macOS":
		pending("macOS only")
		return
	var table: PlayableTable = load("res://ui/four_player_table/playable_table.gd").new()
	add_child_autofree(table)
	await get_tree().process_frame
	var intent := SessionIntent.new(&"PRACTICE", &"EAST", &"TRASH_TALK", &"lin_yeche")
	var converted := GameSessionConfig.from_intent(intent, 7, "tt-thread-rel", "e7-r4", {})
	assert_true(converted.ok)
	var driver := PracticeSessionLauncher.new().launch(converted.config)
	var bc: PlayableBattleController = driver.bc_factory.call(7, 0, false, TileId.E, 0)
	var vp: VoicePortModule = bc.mode_modules.voice_port
	vp.set_capture_backend(VoicePortModule.CaptureBackend.FIXTURE)
	var root := "/tmp/mahjong-e7-257-thread-rel-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(root)
	var mgr := WhisperModelManager.new()
	mgr.apply_production_manifest()
	mgr.set_models_root(root)
	mgr.set_allow_public_network(true)
	mgr.platform_name_override = "macOS"
	mgr.curl_bin_override = "/usr/bin/curl"
	vp.attach_whisper_model_manager(mgr)
	table.bind_voice_from_battle(bc)
	await get_tree().process_frame
	# 解析/下载进行中立即释放牌桌
	table.release_voice_runtime()
	for _i in range(90):
		await get_tree().process_frame
		if not is_instance_valid(mgr):
			break
	assert_null(vp.whisper_model_manager())
	assert_null(table.get_node_or_null("WhisperModelManager"))
	assert_false(is_instance_valid(mgr), "释放后 manager 须销毁完毕")
	_rm_rf_tmp_e7(root)


## #257 R5 P1：活跃慢 resolver 期间 release/销毁必须严格短时完成（不可用同步 Callable 冒充）。
func test_active_slow_resolve_release_never_blocks_main_thread() -> void:
	if OS.get_name() != "macOS":
		pending("macOS only")
		return
	var usec: int = Time.get_ticks_usec()
	# 单进程 Python shim（exec 后 pid 即该解释器，kill 可靠；禁止同步 Callable 冒充）
	var shim: String = "/tmp/mahjong-e7-257-slow-curl-%d.py" % usec
	var f := FileAccess.open(shim, FileAccess.WRITE)
	assert_ne(f, null, "write slow curl shim")
	f.store_string(
		"#!/usr/bin/env python3\n"
		+ "import time, sys\n"
		+ "time.sleep(8)\n"
		+ "sys.stdout.write('https://example.invalid/e7-257-never-get.bin')\n"
	)
	f.close()
	OS.execute("/bin/chmod", PackedStringArray(["+x", shim]), [], false, false)

	var table: PlayableTable = load("res://ui/four_player_table/playable_table.gd").new()
	add_child_autofree(table)
	await get_tree().process_frame
	var intent := SessionIntent.new(&"PRACTICE", &"EAST", &"TRASH_TALK", &"lin_yeche")
	var converted := GameSessionConfig.from_intent(intent, 7, "tt-slow-rel", "e7-r5", {})
	assert_true(converted.ok)
	var driver := PracticeSessionLauncher.new().launch(converted.config)
	var bc: PlayableBattleController = driver.bc_factory.call(7, 0, false, TileId.E, 0)
	var vp: VoicePortModule = bc.mode_modules.voice_port
	vp.set_capture_backend(VoicePortModule.CaptureBackend.FIXTURE)
	var root := "/tmp/mahjong-e7-257-slow-rel-%d" % usec
	DirAccess.make_dir_recursive_absolute(root)
	var mgr := WhisperModelManager.new()
	mgr.apply_production_manifest()
	mgr.set_models_root(root)
	mgr.set_allow_public_network(true)
	mgr.platform_name_override = "macOS"
	mgr.curl_bin_override = shim
	# 禁止 resolve_url_override：必须走真实外部异步 worker
	assert_false(mgr.resolve_url_override.is_valid())
	vp.attach_whisper_model_manager(mgr)
	table.bind_voice_from_battle(bc)
	await get_tree().process_frame

	# 等 worker 真正启动（pid/thread 句柄存在）
	var boot := Time.get_ticks_msec()
	while Time.get_ticks_msec() - boot < 2000:
		if mgr.has_pending_resolve_worker() or mgr.has_pending_resolve_thread():
			break
		await get_tree().process_frame
	assert_true(
		mgr.has_pending_resolve_worker() or mgr.has_pending_resolve_thread(),
		"释放前必须仍有活跃异步 resolver worker"
	)
	var worker_pid: int = mgr.get_resolve_pid_for_test()
	var tok_before: int = mgr.get_resolve_token_for_test()

	var t0: int = Time.get_ticks_msec()
	table.release_voice_runtime()
	var release_ms: int = Time.get_ticks_msec() - t0
	assert_lt(release_ms, 250, "release_voice_runtime 不得阻塞主线程（实测 %dms）" % release_ms)

	# queue_free → PREDELETE 也不得阻塞（旧实现 wait_to_finish 可卡 ~8s）
	for _i in range(45):
		await get_tree().process_frame
		if not is_instance_valid(mgr):
			break
	var total_ms: int = Time.get_ticks_msec() - t0
	assert_lt(total_ms, 800, "manager 销毁/主线程帧推进须在短时上界内（实测 %dms）" % total_ms)
	assert_false(is_instance_valid(mgr), "manager 须已销毁")
	assert_null(vp.whisper_model_manager())
	assert_null(table.get_node_or_null("WhisperModelManager"))

	# 迟到结果不得再启动模型 GET：shim 永远写 example.invalid，且 token 已 invalidate
	assert_gt(tok_before, 0)
	# worker 进程须被终止（若有 pid）
	if worker_pid > 0:
		var still: Array = []
		var kill0: int = OS.execute("/bin/kill", PackedStringArray(["-0", str(worker_pid)]), still, true, false)
		assert_ne(kill0, 0, "活跃 resolver 进程须在释放后终止（pid=%d）" % worker_pid)

	DirAccess.remove_absolute(shim)
	_rm_rf_tmp_e7(root)


func _rm_rf_tmp_e7(path: String) -> void:
	if path.is_empty() or not path.begins_with("/tmp/mahjong-e7-257-"):
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var child: String = path.path_join(entry)
			if dir.current_is_dir():
				_rm_rf_tmp_e7(child)
			else:
				DirAccess.remove_absolute(child)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)
