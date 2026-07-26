extends GutTest

# E4-03（#245）：STANDARD 零模型下载链路；TRASH_TALK 首次 bind 创建/ensure WhisperModelManager。
# 禁止公网 487MB；测试可预注入 fixture manager。所有权：release 必须 queue_free，无脱树泄漏。


func _make_config(mode: StringName, session_id: String) -> GameSessionConfig:
	var intent := SessionIntent.new(&"PRACTICE", &"EAST", mode, &"lin_yeche")
	var converted := GameSessionConfig.from_intent(
		intent, 42, session_id, "e4-03-v1", {}
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


func _rm_rf(path: String) -> void:
	if path.is_empty() or not path.begins_with("/tmp/mahjong-whisper-"):
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
				_rm_rf(child)
			else:
				DirAccess.remove_absolute(child)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)


func test_standard_bundle_and_bind_have_zero_model_manager() -> void:
	var bundle := ModeModuleBundle.from_config(_make_config(&"STANDARD", "std-wm"))
	assert_not_null(bundle)
	assert_null(bundle.voice_port, "STANDARD 零 voice_port")

	var table: PlayableTable = load("res://ui/four_player_table/playable_table.gd").new()
	add_child_autofree(table)
	await get_tree().process_frame
	var bc := _launch_pbc(&"STANDARD", "std-bind-wm")
	table.bind_voice_from_battle(bc)
	await get_tree().process_frame
	assert_false(table.has_voice_runtime())
	assert_null(table.get_node_or_null("WhisperModelManager"))
	assert_null(table.get_node_or_null("PttButton"))
	assert_null(table.get_node_or_null("VoiceCapturePipeline"))


func test_trash_talk_bundle_does_not_create_detached_manager() -> void:
	# P2-1：构造期不得创建脱树 WhisperModelManager
	var bundle := ModeModuleBundle.from_config(_make_config(&"TRASH_TALK", "tt-wm-no-detach"))
	assert_not_null(bundle)
	assert_not_null(bundle.voice_port)
	assert_null(
		bundle.voice_port.whisper_model_manager(),
		"ModeModuleBundle 不得在构造期创建脱树 model manager"
	)


func test_playable_table_bind_creates_ensures_and_release_frees() -> void:
	var table: PlayableTable = load("res://ui/four_player_table/playable_table.gd").new()
	add_child_autofree(table)
	await get_tree().process_frame
	var bc := _launch_pbc(&"TRASH_TALK", "tt-bind-wm")
	var vp: VoicePortModule = bc.mode_modules.voice_port
	assert_not_null(vp)
	vp.set_capture_backend(VoicePortModule.CaptureBackend.FIXTURE)
	assert_null(vp.whisper_model_manager(), "bind 前无 manager")

	var root := "/tmp/mahjong-whisper-wiring-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(root)

	# 预注入 fixture 风格 manager：本地 root + 禁止公网，验证 bind ensure 与主流程隔离
	var injected := WhisperModelManager.new()
	injected.apply_production_manifest()
	injected.set_models_root(root)
	injected.set_allow_public_network(false)
	vp.attach_whisper_model_manager(injected)

	table.bind_voice_from_battle(bc)
	await get_tree().process_frame
	await get_tree().process_frame

	var mgr: WhisperModelManager = vp.whisper_model_manager()
	assert_not_null(mgr)
	assert_true(mgr.is_inside_tree(), "bind 后 manager 必须入树")
	assert_eq(mgr.get_parent(), table)
	assert_true(mgr.was_ensure_requested(), "生产绑定必须 ensure")
	assert_not_null(table.get_node_or_null("WhisperModelManager"))
	assert_not_null(table.get_node_or_null("PttButton"), "模型未就绪仍应有 PTT")
	assert_true(vp.press_ptt())
	vp.release_ptt()

	# headless + 禁公网 → 失败/非 ready，但不阻断
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 1500:
		var st: StringName = mgr.get_lifecycle_state()
		if st == &"ready" or st == &"failed" or st == &"cancelled":
			break
		await get_tree().process_frame
	assert_ne(mgr.get_lifecycle_state(), &"ready")

	table.release_voice_runtime()
	# queue_free 后需数帧完成销毁
	for _i in range(5):
		await get_tree().process_frame
	assert_null(vp.whisper_model_manager(), "release 后 port 不得再持有 manager")
	assert_null(table.get_node_or_null("WhisperModelManager"))
	assert_false(is_instance_valid(mgr), "manager 须在数帧后无效（queue_free）")
	_rm_rf(root)


func test_playable_table_creates_production_manager_when_not_injected() -> void:
	var table: PlayableTable = load("res://ui/four_player_table/playable_table.gd").new()
	add_child_autofree(table)
	await get_tree().process_frame
	var bc := _launch_pbc(&"TRASH_TALK", "tt-auto-mgr")
	var vp: VoicePortModule = bc.mode_modules.voice_port
	vp.set_capture_backend(VoicePortModule.CaptureBackend.FIXTURE)
	assert_null(vp.whisper_model_manager())

	table.bind_voice_from_battle(bc)
	await get_tree().process_frame
	var mgr: WhisperModelManager = vp.whisper_model_manager()
	assert_not_null(mgr, "未注入时 bind 须创建生产 manager")
	assert_true(mgr.is_inside_tree())
	assert_true(mgr.was_ensure_requested())
	var m: Dictionary = mgr.get_manifest()
	assert_eq(String(m.get("id", "")), "ggml-small")
	assert_eq(int(m.get("size_bytes", -1)), 487601967)
	if OS.has_feature("headless"):
		assert_false(mgr.is_public_network_allowed())

	table.release_voice_runtime()
	for _i in range(5):
		await get_tree().process_frame
	assert_null(vp.whisper_model_manager())
	assert_null(table.get_node_or_null("WhisperModelManager"))
	assert_false(is_instance_valid(mgr), "production manager 须 queue_free 完成")


func test_voice_port_release_all_frees_detached_manager() -> void:
	# 未绑定牌桌即结束 session：release_all 须释放脱树 manager
	var vp := VoicePortModule.new()
	var mgr := WhisperModelManager.new()
	mgr.apply_production_manifest()
	vp.attach_whisper_model_manager(mgr)
	assert_false(mgr.is_inside_tree())
	vp.release_all()
	assert_null(vp.whisper_model_manager())
	for _i in range(5):
		await get_tree().process_frame
	assert_false(is_instance_valid(mgr), "脱树 manager 须 queue_free 完成")


func test_headless_blocks_public_hf_download() -> void:
	var mgr := WhisperModelManager.new()
	add_child_autofree(mgr)
	var root := "/tmp/mahjong-whisper-hf-block-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(root)
	mgr.set_models_root(root)
	mgr.apply_production_manifest()
	mgr.set_allow_public_network(false)
	mgr.ensure_ready()
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 1500:
		var st: StringName = mgr.get_lifecycle_state()
		if st == &"ready" or st == &"failed" or st == &"cancelled":
			break
		await get_tree().process_frame
	assert_eq(mgr.get_lifecycle_state(), &"failed")
	assert_eq(mgr.get_error_code(), "PUBLIC_NETWORK_BLOCKED")
	assert_false(mgr.is_model_ready())
	var active: String = mgr.active_model_path()
	if FileAccess.file_exists(active):
		assert_lt(FileAccess.get_file_as_bytes(active).size(), 1_000_000)
	_rm_rf(root)
