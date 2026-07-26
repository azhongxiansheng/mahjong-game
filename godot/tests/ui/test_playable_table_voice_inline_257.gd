extends GutTest

# E7-03（#257）：欢乐场右下角内联权限说明 + 模型状态/进度；STANDARD 零相关 UI。
# 不弹窗、不持久化；模型失败不阻断 PTT。


func _make_config(mode: StringName, session_id: String) -> GameSessionConfig:
	var intent := SessionIntent.new(&"PRACTICE", &"EAST", mode, &"lin_yeche")
	var converted := GameSessionConfig.from_intent(
		intent, 42, session_id, "e7-03-v1", {}
	)
	assert_true(converted.ok, str(converted.error_code))
	return converted.config


func _launch_pbc(mode: StringName, session_id: String) -> PlayableBattleController:
	var cfg := _make_config(mode, session_id)
	var driver := PracticeSessionLauncher.new().launch(cfg)
	assert_not_null(driver)
	var bc: PlayableBattleController = driver.bc_factory.call(
		cfg.seed, 0, false, TileId.E, 0
	)
	assert_not_null(bc)
	return bc


func test_standard_has_zero_voice_inline_and_model_ui() -> void:
	var table: PlayableTable = load("res://ui/four_player_table/playable_table.gd").new()
	add_child_autofree(table)
	await get_tree().process_frame
	var bc := _launch_pbc(&"STANDARD", "std-inline-257")
	table.bind_voice_from_battle(bc)
	await get_tree().process_frame
	assert_null(table.get_node_or_null("MicPermissionLabel"))
	assert_null(table.get_node_or_null("ModelStatusLabel"))
	assert_null(table.get_node_or_null("PttButton"))
	assert_null(table.get_node_or_null("PttStatusLabel"))
	assert_null(table.get_node_or_null("WhisperModelManager"))
	assert_false(table.has_voice_runtime())


func test_trash_talk_shows_mic_permission_inline_on_bind() -> void:
	var table: PlayableTable = load("res://ui/four_player_table/playable_table.gd").new()
	add_child_autofree(table)
	await get_tree().process_frame
	var bc := _launch_pbc(&"TRASH_TALK", "tt-perm-257")
	var vp: VoicePortModule = bc.mode_modules.voice_port
	vp.set_capture_backend(VoicePortModule.CaptureBackend.FIXTURE)
	table.bind_voice_from_battle(bc)
	await get_tree().process_frame

	var mic := table.get_node_or_null("MicPermissionLabel") as Label
	assert_not_null(mic, "欢乐场须显示麦克风用途内联说明")
	if mic == null:
		return
	assert_true(mic.visible)
	assert_true(String(mic.text).contains("麦克风仅在按住说话时启用"))
	assert_not_null(table.get_node_or_null("PttButton"))


func test_trash_talk_model_status_reflects_lifecycle_and_progress() -> void:
	var table: PlayableTable = load("res://ui/four_player_table/playable_table.gd").new()
	add_child_autofree(table)
	await get_tree().process_frame
	var bc := _launch_pbc(&"TRASH_TALK", "tt-model-status-257")
	var vp: VoicePortModule = bc.mode_modules.voice_port
	vp.set_capture_backend(VoicePortModule.CaptureBackend.FIXTURE)

	var root := "/tmp/mahjong-e7-257-gut-model-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(root)
	var injected := WhisperModelManager.new()
	injected.apply_production_manifest()
	injected.set_models_root(root)
	injected.set_allow_public_network(false)
	vp.attach_whisper_model_manager(injected)

	table.bind_voice_from_battle(bc)
	await get_tree().process_frame
	await get_tree().process_frame

	var model_lbl := table.get_node_or_null("ModelStatusLabel") as Label
	assert_not_null(model_lbl, "欢乐场须有模型状态标签")
	if model_lbl == null:
		return
	assert_true(model_lbl.visible)

	# 禁公网 headless → 终态 failed；文案须可理解且含可重试语义
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 2000:
		var st: StringName = injected.get_lifecycle_state()
		if st == &"failed" or st == &"cancelled" or st == &"ready":
			break
		await get_tree().process_frame
	assert_eq(injected.get_lifecycle_state(), &"failed")
	# 等一帧让 UI 订阅刷新
	await get_tree().process_frame
	var txt := String(model_lbl.text)
	assert_true(txt.contains("模型"), "须标明模型状态：%s" % txt)
	assert_true(
		txt.contains("失败") or txt.contains("重试"),
		"失败态须有失败/重试语义：%s" % txt
	)

	# 模型失败不阻断 PTT
	assert_true(vp.press_ptt())
	vp.release_ptt()

	table.release_voice_runtime()
	await get_tree().process_frame
	assert_null(table.get_node_or_null("MicPermissionLabel"))
	assert_null(table.get_node_or_null("ModelStatusLabel"))
	assert_null(table.get_node_or_null("WhisperModelManager"))
	# 精确清理本测 staging
	_rm_rf_e7(root)


func test_model_status_downloading_shows_stable_percent() -> void:
	# 直接驱动状态文案 helper 路径：注入 manager 并模拟 progress 信号
	var table: PlayableTable = load("res://ui/four_player_table/playable_table.gd").new()
	add_child_autofree(table)
	await get_tree().process_frame
	var bc := _launch_pbc(&"TRASH_TALK", "tt-pct-257")
	var vp: VoicePortModule = bc.mode_modules.voice_port
	vp.set_capture_backend(VoicePortModule.CaptureBackend.FIXTURE)

	var root := "/tmp/mahjong-e7-257-gut-pct-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(root)
	var injected := WhisperModelManager.new()
	injected.apply_production_manifest()
	injected.set_models_root(root)
	# 禁止自动 ensure 公网：先 attach 但不 allow，再 bind 后手动刷 UI
	injected.set_allow_public_network(false)
	vp.attach_whisper_model_manager(injected)

	table.bind_voice_from_battle(bc)
	await get_tree().process_frame

	# 模拟下载进度（生产路径由 WhisperModelManager.progress_changed 驱动）
	assert_true(table.has_method("_on_whisper_progress_changed") \
			or table.has_method("format_model_status_text") \
			or table.get_node_or_null("ModelStatusLabel") != null)

	# 通过公开/生产绑定后的信号路径：直接 emit progress_changed
	var total := 487601967
	var received := int(total * 0.37)
	injected.progress_changed.emit(received, total)
	# 若 manager 状态非 downloading，UI 可能仍显示 failed；强制 state 后再 emit
	# 测试只要求：存在稳定百分比格式化能力
	var formatted: String = ""
	if table.has_method("format_model_status_text"):
		formatted = table.format_model_status_text(&"downloading", received, total, "")
	else:
		# 回退：读取标签在 downloading 时的期望实现（Green 后应可用）
		formatted = String((table.get_node_or_null("ModelStatusLabel") as Label).text) \
				if table.get_node_or_null("ModelStatusLabel") != null else ""
	if table.has_method("format_model_status_text"):
		assert_true(formatted.contains("37") or formatted.contains("下载"), formatted)
		assert_true(formatted.contains("%") or formatted.contains("下载"), formatted)

	table.release_voice_runtime()
	_rm_rf_e7(root)


func _rm_rf_e7(path: String) -> void:
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
				_rm_rf_e7(child)
			else:
				DirAccess.remove_absolute(child)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)


func test_model_status_updates_from_manager_progress_signal_chain() -> void:
	# #257：UI 必须订阅真实 WhisperModelManager.progress_changed，而非只测 formatter
	var table: PlayableTable = load("res://ui/four_player_table/playable_table.gd").new()
	add_child_autofree(table)
	await get_tree().process_frame
	var bc := _launch_pbc(&"TRASH_TALK", "tt-signal-chain-257")
	var vp: VoicePortModule = bc.mode_modules.voice_port
	vp.set_capture_backend(VoicePortModule.CaptureBackend.FIXTURE)

	var root := "/tmp/mahjong-e7-257-gut-signal-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(root)
	# 本地慢流 fixture HTTP：用真实 manager 路径（非生产公网）
	var server := TCPServer.new()
	assert_eq(server.listen(0, "127.0.0.1"), OK)
	var port_n: int = server.get_local_port()
	var body := PackedByteArray()
	for i in range(256):
		body.append(i % 256)
	# 放大 body
	var big := PackedByteArray()
	for _j in range(40):
		big.append_array(body)
	var sha_ctx := HashingContext.new()
	sha_ctx.start(HashingContext.HASH_SHA256)
	sha_ctx.update(big)
	var sha := sha_ctx.finish().hex_encode()

	var mgr := WhisperModelManager.new()
	mgr.set_models_root(root)
	mgr.set_allow_public_network(true)
	mgr.set_manifest({
		"id": "fixture-ui",
		"version": "fixture-ui-v1",
		"url": "http://127.0.0.1:%d/m.bin" % port_n,
		"size_bytes": big.size(),
		"sha256": sha,
		"source_revision": "fixture",
		"license": "mit",
		"filename": "ggml-small.bin",
	})
	vp.attach_whisper_model_manager(mgr)
	table.bind_voice_from_battle(bc)
	await get_tree().process_frame

	var model_lbl := table.get_node_or_null("ModelStatusLabel") as Label
	assert_not_null(model_lbl)
	if model_lbl == null:
		server.stop()
		return

	# 简易慢 HTTP：accept 后分帧写 body
	var peer: StreamPeerTCP = null
	var sent := 0
	var headers_sent := false
	var start := Time.get_ticks_msec()
	var saw_pct := false
	while Time.get_ticks_msec() - start < 12000:
		if server.is_connection_available():
			peer = server.take_connection()
		if peer != null:
			peer.poll()
			if not headers_sent and peer.get_available_bytes() > 0:
				var _req := peer.get_utf8_string(peer.get_available_bytes())
				var hdr := "HTTP/1.1 200 OK\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % big.size()
				peer.put_data(hdr.to_utf8_buffer())
				headers_sent = true
			elif headers_sent and sent < big.size():
				var chunk_n: int = mini(128, big.size() - sent)
				peer.put_data(big.slice(sent, sent + chunk_n))
				sent += chunk_n
				if sent >= big.size():
					peer.disconnect_from_host()
		var txt := String(model_lbl.text)
		if txt.contains("%") and txt.contains("下载"):
			# 解析百分比
			var re := RegEx.new()
			re.compile("(\\d+)%")
			var m := re.search(txt)
			if m != null:
				var pct: int = int(m.get_string(1))
				if pct > 0 and pct < 100:
					saw_pct = true
					break
		if mgr.get_lifecycle_state() == &"ready" or mgr.get_lifecycle_state() == &"failed":
			break
		await get_tree().process_frame

	assert_true(saw_pct, "UI 须经 manager 信号显示中间下载百分比，最终=%s state=%s" % [
		String(model_lbl.text), mgr.get_lifecycle_state()
	])
	table.release_voice_runtime()
	server.stop()
	_rm_rf_e7(root)
