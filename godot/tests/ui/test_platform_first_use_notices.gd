extends GutTest

# #258：Windows Alpha 首次公共连接 / 首次 PTT 应用内说明。
# Windows 路径经强制 override 测门控；真实 macOS/headless 路径必须跳过。
# 不污染真实 user://settings.json：before/after 完整快照恢复。


const Notices = preload("res://platform/platform_first_use_notices.gd")
const SETTINGS_PATH := "user://settings.json"

var _snap_had_file: bool = false
var _snap_file_bytes: PackedByteArray = PackedByteArray()
var _snap_mem: Dictionary = {}


func _sm() -> Node:
	return get_tree().root.get_node("/root/SettingsManager")


func _snapshot_settings() -> void:
	var sm: Node = _sm()
	_snap_mem = {
		"sfx_volume": sm.sfx_volume,
		"bgm_volume": sm.bgm_volume,
		"fullscreen": sm.fullscreen,
		"skip_deal_animation": sm.skip_deal_animation,
		"framerate_cap": sm.framerate_cap,
		"claim_timeout_sec": sm.claim_timeout_sec,
		"riichi_timeout_sec": sm.riichi_timeout_sec,
		"windows_first_public_connect_notice_acked": sm.windows_first_public_connect_notice_acked,
		"windows_first_ptt_notice_acked": sm.windows_first_ptt_notice_acked,
	}
	_snap_had_file = FileAccess.file_exists(SETTINGS_PATH)
	_snap_file_bytes = PackedByteArray()
	if _snap_had_file:
		var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
		if f != null:
			_snap_file_bytes = f.get_buffer(f.get_length())
			f.close()


func _restore_settings() -> void:
	var sm: Node = _sm()
	if sm == null:
		return
	sm.sfx_volume = float(_snap_mem.get("sfx_volume", 0.8))
	sm.bgm_volume = float(_snap_mem.get("bgm_volume", 0.6))
	sm.fullscreen = bool(_snap_mem.get("fullscreen", false))
	sm.skip_deal_animation = bool(_snap_mem.get("skip_deal_animation", false))
	sm.framerate_cap = int(_snap_mem.get("framerate_cap", 60))
	sm.claim_timeout_sec = float(_snap_mem.get("claim_timeout_sec", 5.0))
	sm.riichi_timeout_sec = float(_snap_mem.get("riichi_timeout_sec", 6.0))
	sm.windows_first_public_connect_notice_acked = bool(
		_snap_mem.get("windows_first_public_connect_notice_acked", false)
	)
	sm.windows_first_ptt_notice_acked = bool(
		_snap_mem.get("windows_first_ptt_notice_acked", false)
	)
	if _snap_had_file:
		var wf := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
		if wf != null:
			wf.store_buffer(_snap_file_bytes)
			wf.close()
	else:
		if FileAccess.file_exists(SETTINGS_PATH):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))


func before_each() -> void:
	_snapshot_settings()
	Notices.clear_windows_runtime_override()


func after_each() -> void:
	Notices.clear_windows_runtime_override()
	_restore_settings()


func _reset_windows_notice_flags_in_mem_only() -> void:
	var sm: Node = _sm()
	sm.windows_first_public_connect_notice_acked = false
	sm.windows_first_ptt_notice_acked = false


func _make_config(mode: StringName, session_id: String) -> GameSessionConfig:
	var intent := SessionIntent.new(&"PRACTICE", &"EAST", mode, &"lin_yeche")
	var converted := GameSessionConfig.from_intent(
		intent, 42, session_id, "e7-04-v1", {}
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


func test_settings_windows_flags_and_existing_fields_round_trip() -> void:
	var sm: Node = _sm()
	assert_true("windows_first_public_connect_notice_acked" in sm)
	assert_true("windows_first_ptt_notice_acked" in sm)
	assert_false(sm.has_method("save_now"), "不得暴露仅测试用 save_now")
	# 既有字段 round-trip 不回归
	var saved_sfx: float = float(sm.sfx_volume)
	sm.set_sfx_volume(0.37)
	assert_almost_eq(float(sm.sfx_volume), 0.37, 0.001)
	sm.set_sfx_volume(saved_sfx)
	# Windows flag 内存语义
	_reset_windows_notice_flags_in_mem_only()
	assert_true(sm.needs_windows_first_public_connect_notice())
	assert_true(sm.needs_windows_first_ptt_notice())
	sm.ack_windows_first_public_connect_notice()
	sm.ack_windows_first_ptt_notice()
	assert_false(sm.needs_windows_first_public_connect_notice())
	assert_false(sm.needs_windows_first_ptt_notice())
	# 重新 load 证明落盘键名
	sm.windows_first_public_connect_notice_acked = false
	sm.windows_first_ptt_notice_acked = false
	sm._load_from_disk()
	assert_true(bool(sm.windows_first_public_connect_notice_acked))
	assert_true(bool(sm.windows_first_ptt_notice_acked))


func test_notice_copy_mentions_windows_firewall_mic_and_model() -> void:
	var pub: Dictionary = Notices.public_connect_copy()
	var ptt: Dictionary = Notices.ptt_copy()
	assert_true(String(pub.get("body", "")).contains("防火墙") or String(pub.get("body", "")).contains("出站"))
	assert_true(String(pub.get("body", "")).contains("SmartScreen") or String(pub.get("body", "")).contains("来源未知"))
	assert_true(String(ptt.get("body", "")).contains("麦克风"))
	assert_true(String(ptt.get("body", "")).contains("SHA-256") or String(ptt.get("body", "")).contains("校验"))


func test_non_windows_runtime_skips_notices_without_ack() -> void:
	# 真实当前宿主（macOS/headless）或强制 false：不得弹窗、不得消费 flag
	Notices.set_windows_runtime_override(false)
	_reset_windows_notice_flags_in_mem_only()
	assert_false(Notices.is_windows_runtime())
	assert_false(Notices.needs_public_connect_notice())
	assert_false(Notices.needs_ptt_notice())

	var lobby_scene := load("res://ui/lobby/lobby_shell.tscn") as PackedScene
	var lobby := lobby_scene.instantiate()
	add_child_autofree(lobby)
	await get_tree().process_frame
	var intents: Array = []
	lobby.session_intent_confirmed.connect(func(i): intents.append(i))
	lobby._on_rule_drawer_confirmed(
		SessionIntent.new(&"PUBLIC_CASUAL", &"EAST", &"STANDARD", &"lin_yeche")
	)
	await get_tree().process_frame
	assert_eq(intents.size(), 1, "非 Windows 应直接放行 PUBLIC_CASUAL")
	assert_null(lobby.get_node_or_null("FirstPublicConnectNotice"))
	assert_true(bool(_sm().needs_windows_first_public_connect_notice()), "不得 ack Windows flag")

	# 真实自动检测：本机非 Windows 时应为 false
	Notices.clear_windows_runtime_override()
	if OS.get_name() != "Windows" and not OS.has_feature("windows"):
		assert_false(Notices.is_windows_runtime())
		assert_false(Notices.needs_public_connect_notice())


func test_windows_public_connect_notice_gates_intent_until_acked() -> void:
	Notices.set_windows_runtime_override(true)
	_reset_windows_notice_flags_in_mem_only()
	var lobby_scene := load("res://ui/lobby/lobby_shell.tscn") as PackedScene
	var lobby := lobby_scene.instantiate()
	add_child_autofree(lobby)
	await get_tree().process_frame

	var intents: Array = []
	lobby.session_intent_confirmed.connect(func(i): intents.append(i))
	var intent := SessionIntent.new(&"PUBLIC_CASUAL", &"EAST", &"STANDARD", &"lin_yeche")
	lobby._on_rule_drawer_confirmed(intent)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_eq(intents.size(), 0, "未确认首次公共连接说明前不得 emit intent")
	var dlg = lobby.get_node_or_null("FirstPublicConnectNotice")
	assert_not_null(dlg, "Windows 应弹出首次公共连接说明")

	if dlg.has_method("_on_cancel"):
		dlg._on_cancel()
	await get_tree().process_frame
	assert_eq(intents.size(), 0)
	assert_true(_sm().needs_windows_first_public_connect_notice())

	lobby._on_rule_drawer_confirmed(intent)
	await get_tree().process_frame
	dlg = lobby.get_node_or_null("FirstPublicConnectNotice")
	assert_not_null(dlg)
	if dlg.has_method("_on_confirm"):
		dlg._on_confirm()
	await get_tree().process_frame
	assert_eq(intents.size(), 1)
	assert_eq(intents[0].room_kind, &"PUBLIC_CASUAL")
	assert_false(_sm().needs_windows_first_public_connect_notice())

	lobby._on_rule_drawer_confirmed(
		SessionIntent.new(&"PUBLIC_CASUAL", &"HANCHAN", &"STANDARD", &"lin_yeche")
	)
	await get_tree().process_frame
	assert_eq(intents.size(), 2)
	assert_null(lobby.get_node_or_null("FirstPublicConnectNotice"))


func test_practice_intent_skips_public_connect_notice_on_windows() -> void:
	Notices.set_windows_runtime_override(true)
	_reset_windows_notice_flags_in_mem_only()
	var lobby_scene := load("res://ui/lobby/lobby_shell.tscn") as PackedScene
	var lobby := lobby_scene.instantiate()
	add_child_autofree(lobby)
	await get_tree().process_frame
	var intents: Array = []
	lobby.session_intent_confirmed.connect(func(i): intents.append(i))
	lobby._on_rule_drawer_confirmed(
		SessionIntent.new(&"PRACTICE", &"EAST", &"STANDARD", &"lin_yeche")
	)
	await get_tree().process_frame
	assert_eq(intents.size(), 1)
	assert_true(_sm().needs_windows_first_public_connect_notice())
	assert_null(lobby.get_node_or_null("FirstPublicConnectNotice"))


func test_windows_first_ptt_notice_blocks_until_acked_then_allows() -> void:
	Notices.set_windows_runtime_override(true)
	_reset_windows_notice_flags_in_mem_only()
	var table: PlayableTable = load("res://ui/four_player_table/playable_table.gd").new()
	add_child_autofree(table)
	await get_tree().process_frame
	var bc := _launch_pbc(&"TRASH_TALK", "tt-first-ptt")
	var vp: VoicePortModule = bc.mode_modules.voice_port
	vp.set_capture_backend(VoicePortModule.CaptureBackend.FIXTURE)
	table.bind_voice_from_battle(bc)
	await get_tree().process_frame

	var controls: Array = []
	vp.outbound_control.connect(func(m: Dictionary): controls.append(m.duplicate(true)))
	var btn := table.get_node_or_null("PttButton") as BaseButton
	assert_not_null(btn)

	btn.button_down.emit()
	await get_tree().process_frame
	assert_false(vp.is_ptt_pressed())
	assert_eq(controls.size(), 0)
	var dlg = table.get_node_or_null("FirstPttNotice")
	assert_not_null(dlg)

	if dlg.has_method("_on_cancel"):
		dlg._on_cancel()
	await get_tree().process_frame
	assert_true(_sm().needs_windows_first_ptt_notice())

	btn.button_down.emit()
	await get_tree().process_frame
	dlg = table.get_node_or_null("FirstPttNotice")
	assert_not_null(dlg)
	if dlg.has_method("_on_confirm"):
		dlg._on_confirm()
	await get_tree().process_frame
	assert_false(_sm().needs_windows_first_ptt_notice())
	assert_false(vp.is_ptt_pressed())
	btn.button_down.emit()
	await get_tree().process_frame
	assert_true(vp.is_ptt_pressed())
	assert_eq(controls.size(), 1)
	btn.button_up.emit()
	await get_tree().process_frame


func test_standard_still_zero_mic_and_model_with_notice_module() -> void:
	Notices.set_windows_runtime_override(true)
	_reset_windows_notice_flags_in_mem_only()
	var table: PlayableTable = load("res://ui/four_player_table/playable_table.gd").new()
	add_child_autofree(table)
	await get_tree().process_frame
	var bc := _launch_pbc(&"STANDARD", "std-first-use")
	table.bind_voice_from_battle(bc)
	await get_tree().process_frame
	assert_null(table.get_node_or_null("PttButton"))
	assert_null(table.get_node_or_null("WhisperModelManager"))
	assert_false(table.has_voice_runtime())
	assert_true(_sm().needs_windows_first_ptt_notice())
