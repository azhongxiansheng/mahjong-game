extends GutTest

# E1-05（#229）：大厅音频弹层必须控制真实本地播放器，不得在运行时调用生成 API。

const LOBBY_SCENE := "res://ui/lobby/lobby_shell.tscn"
const DESIGN_SIZE := Vector2(1600, 900)
const SETTINGS_PATH := "user://settings.json"
const EXPECTED_BGM_PATH := "res://assets/bgm/lobby_xuxiguan.ogg"

var _settings_existed := false
var _settings_backup := ""
var _original_sfx := 0.8
var _original_bgm := 0.6


func before_all() -> void:
	var sm := _sm()
	_original_sfx = float(sm.sfx_volume)
	_original_bgm = float(sm.bgm_volume)
	_settings_existed = FileAccess.file_exists(SETTINGS_PATH)
	if _settings_existed:
		var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
		if file != null:
			_settings_backup = file.get_as_text()
			file.close()


func after_all() -> void:
	if _settings_existed:
		var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
		if file != null:
			file.store_string(_settings_backup)
			file.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))
	var sm := _sm()
	sm.sfx_volume = _original_sfx
	sm.bgm_volume = _original_bgm
	sm.call("_apply_to_audio")


func _sm() -> Node:
	return get_tree().root.get_node("/root/SettingsManager")


func _am() -> Node:
	return get_tree().root.get_node("/root/AudioManager")


func _spawn_lobby() -> LobbyShell:
	var host := Control.new()
	host.name = "AudioPopupTestHost"
	host.size = DESIGN_SIZE
	add_child_autofree(host)
	var shell := load(LOBBY_SCENE).instantiate() as LobbyShell
	host.add_child(shell)
	return shell


func _require_hooks(shell: LobbyShell, names: Array) -> bool:
	var ok := true
	for hook_name in names:
		var node := shell.get_node_or_null("%%%s" % hook_name)
		assert_not_null(node, "音频弹层必须提供稳定挂点 %%%s" % hook_name)
		ok = ok and node != null
	return ok


func _press(shell: LobbyShell, hook_name: String) -> void:
	(shell.get_node("%%%s" % hook_name) as Button).pressed.emit()


func test_bgm_and_sfx_buttons_open_one_shared_popup_with_persisted_values() -> void:
	var shell := _spawn_lobby()
	await get_tree().process_frame
	if not _require_hooks(shell, [
		"AudioPopupHost", "LobbyAudioPopup", "BgmButton", "SfxButton", "BgmSlider", "SfxSlider",
	]):
		return
	var popup := shell.get_node("%LobbyAudioPopup")
	assert_false((shell.get_node("%AudioPopupHost") as Control).visible)
	for source_name in ["BgmButton", "SfxButton"]:
		_press(shell, source_name)
		await get_tree().process_frame
		assert_true((shell.get_node("%AudioPopupHost") as Control).visible)
		assert_same(shell.get_node("%LobbyAudioPopup"), popup, "BGM/SFX 必须复用同一弹层")
		assert_almost_eq((shell.get_node("%BgmSlider") as HSlider).value, _sm().bgm_volume, 0.001)
		assert_almost_eq((shell.get_node("%SfxSlider") as HSlider).value, _sm().sfx_volume, 0.001)
	assert_eq(shell.find_children("LobbyAudioPopup", "", true, false).size(), 1)


func test_sliders_update_real_audio_manager_and_playing_bgm_volume() -> void:
	var shell := _spawn_lobby()
	await get_tree().process_frame
	if not _require_hooks(shell, ["BgmButton", "BgmSlider", "SfxSlider"]):
		return
	_press(shell, "BgmButton")
	await get_tree().process_frame
	var player := _am().get_node_or_null("BgmPlayer") as AudioStreamPlayer
	assert_not_null(player, "AudioManager 必须持有唯一 BgmPlayer")
	if player == null:
		return
	(shell.get_node("%BgmSlider") as HSlider).value = 0.25
	await get_tree().process_frame
	assert_almost_eq(float(_sm().bgm_volume), 0.25, 0.001)
	assert_almost_eq(float(_am().bgm_volume), 0.25, 0.001)
	assert_almost_eq(player.volume_db, linear_to_db(0.25), 0.01,
		"BGM 滑条必须实时改变正在播放的 Player")
	(shell.get_node("%SfxSlider") as HSlider).value = 0.42
	await get_tree().process_frame
	assert_almost_eq(float(_sm().sfx_volume), 0.42, 0.001)
	assert_almost_eq(float(_am().sfx_volume), 0.42, 0.001)


func test_lobby_plays_one_real_looping_ogg_bgm() -> void:
	assert_true(ResourceLoader.exists(EXPECTED_BGM_PATH), "大厅 BGM 必须作为本地 Ogg 资产入库")
	var shell := _spawn_lobby()
	await get_tree().process_frame
	await get_tree().process_frame
	var player := _am().get_node_or_null("BgmPlayer") as AudioStreamPlayer
	assert_not_null(player)
	if player == null:
		return
	assert_true(player.stream is AudioStreamOggVorbis, "大厅长 BGM 应使用可无缝循环的 Ogg Vorbis")
	if player.stream is AudioStreamOggVorbis:
		assert_true((player.stream as AudioStreamOggVorbis).loop, "BGM stream 必须显式开启 loop")
		assert_eq(player.stream.resource_path, EXPECTED_BGM_PATH)
	assert_true(player.playing, "大厅冷启动后必须默认播放 BGM")
	var same_player := player
	assert_true(_am().has_method("play_bgm"))
	if _am().has_method("play_bgm"):
		_am().call("play_bgm", EXPECTED_BGM_PATH)
	assert_same(_am().get_node_or_null("BgmPlayer"), same_player,
		"重复播放不得创建第二个 BGM Player")
	assert_eq(_am().find_children("BgmPlayer", "AudioStreamPlayer", false, false).size(), 1)
	shell.queue_free()


func test_zero_bgm_volume_mutes_the_real_player() -> void:
	var player := _am().get_node_or_null("BgmPlayer") as AudioStreamPlayer
	assert_not_null(player)
	if player == null:
		return
	_sm().set_bgm_volume(0.0)
	await get_tree().process_frame
	assert_lte(player.volume_db, -79.0, "0 音量必须让真实 BGM Player 静音")


func test_sfx_preview_uses_real_button_click_asset() -> void:
	assert_true(ResourceLoader.exists("res://assets/sfx/button_click.wav"))
	var shell := _spawn_lobby()
	await get_tree().process_frame
	if not _require_hooks(shell, ["SfxButton", "SfxPreviewButton"]):
		return
	_sm().set_sfx_volume(0.8)
	_press(shell, "SfxButton")
	_press(shell, "SfxPreviewButton")
	await get_tree().process_frame
	var found_real_stream := false
	for child in _am().get_children():
		if child is AudioStreamPlayer and child.name != "BgmPlayer":
			var player := child as AudioStreamPlayer
			if player.stream != null and player.stream.resource_path == "res://assets/sfx/button_click.wav":
				found_real_stream = true
	assert_true(found_real_stream, "SFX 试听必须实际调用现有 button_click.wav")


func test_audio_values_are_saved_and_reloaded_from_real_settings_file() -> void:
	var sm := _sm()
	sm.set_bgm_volume(0.31)
	sm.set_sfx_volume(0.47)
	assert_true(FileAccess.file_exists(SETTINGS_PATH))
	sm.bgm_volume = 0.91
	sm.sfx_volume = 0.92
	sm.call("_load_from_disk")
	assert_almost_eq(float(sm.bgm_volume), 0.31, 0.001)
	assert_almost_eq(float(sm.sfx_volume), 0.47, 0.001)


func test_popup_close_and_escape_restore_focus_without_voice_controls() -> void:
	var shell := _spawn_lobby()
	await get_tree().process_frame
	if not _require_hooks(shell, [
		"AudioPopupHost", "AudioPopupCloseButton", "BgmButton", "SfxButton", "LobbyAudioPopup",
	]):
		return
	for source_name in ["BgmButton", "SfxButton"]:
		var source := shell.get_node("%%%s" % source_name) as Button
		source.grab_focus()
		_press(shell, source_name)
		await get_tree().process_frame
		if source_name == "BgmButton":
			_press(shell, "AudioPopupCloseButton")
		else:
			var escape := InputEventKey.new()
			escape.pressed = true
			escape.keycode = KEY_ESCAPE
			get_viewport().push_input(escape)
		await get_tree().process_frame
		assert_false((shell.get_node("%AudioPopupHost") as Control).visible)
		assert_same(get_viewport().gui_get_focus_owner(), source)

	_press(shell, "BgmButton")
	await get_tree().process_frame
	var visible_copy := ""
	for node in shell.get_node("%LobbyAudioPopup").find_children("*", "Label", true, false):
		if (node as Label).is_visible_in_tree():
			visible_copy += " " + (node as Label).text
	for forbidden in ["语音", "麦克风", "座位静音", "举报", "自动禁言", "e6"]:
		assert_false(visible_copy.to_lower().contains(forbidden), "音频弹层不得出现：%s" % forbidden)


func test_audio_popup_tab_focus_stays_inside_popup() -> void:
	var shell := _spawn_lobby()
	await get_tree().process_frame
	if not _require_hooks(shell, ["LobbyAudioPopup", "BgmButton"]):
		return
	_press(shell, "BgmButton")
	await get_tree().process_frame
	var popup := shell.get_node("%LobbyAudioPopup") as Control
	for _step in range(12):
		var focus_next := InputEventAction.new()
		focus_next.action = &"ui_focus_next"
		focus_next.pressed = true
		get_viewport().push_input(focus_next)
		await get_tree().process_frame
		var focus_owner := get_viewport().gui_get_focus_owner()
		assert_not_null(focus_owner)
		if focus_owner != null:
			assert_true(popup == focus_owner or popup.is_ancestor_of(focus_owner),
				"音量弹层打开时 Tab 不得泄漏到底层大厅")


func test_audio_popup_consumes_omamori_case_and_slider_assets() -> void:
	var shell := _spawn_lobby()
	await get_tree().process_frame
	if not _require_hooks(shell, ["BgmButton", "AudioPopupPanel", "BgmSlider", "SfxSlider"]):
		return
	_press(shell, "BgmButton")
	await get_tree().process_frame
	var panel_style := (shell.get_node("%AudioPopupPanel") as Control).get_theme_stylebox("panel")
	assert_true(panel_style is StyleBoxTexture, "音量弹层必须是御守匣生产资产")
	assert_eq((panel_style as StyleBoxTexture).texture.resource_path,
		"res://assets/ui/lobby_materials/lobby_omamori_case_9slice.png")
	var panel_rect := (shell.get_node("%AudioPopupPanel") as Control).get_global_rect()
	assert_true(Rect2(shell.global_position, DESIGN_SIZE).encloses(panel_rect),
		"御守匣在 1600×900 下不得裁切")
	for slider_name in ["BgmSlider", "SfxSlider"]:
		var slider := shell.get_node("%%%s" % slider_name) as HSlider
		assert_eq(slider.get_theme_icon("grabber").resource_path,
			"res://assets/ui/lobby_materials/lobby_slider_grabber.png")


func test_lobby_exit_stops_global_lobby_bgm_player() -> void:
	var am := _am()
	am.call("play_bgm", "res://assets/sfx/game_begin.wav")
	var player := am.get_node_or_null("BgmPlayer") as AudioStreamPlayer
	assert_not_null(player)
	if player == null:
		return
	assert_true(player.playing, "生命周期测试应先启动真实本地音频")
	var shell := _spawn_lobby()
	await get_tree().process_frame
	assert_true(player.playing)
	shell.queue_free()
	await get_tree().process_frame
	assert_false(player.playing, "退出大厅后必须停止大厅 BGM，不能带入牌桌")


func test_runtime_audio_code_has_no_generation_api_calls() -> void:
	for path in [
		"res://audio/audio_manager.gd",
		"res://meta/settings_manager.gd",
		"res://ui/lobby/lobby_shell.gd",
		"res://ui/lobby/lobby_audio_popup.gd",
	]:
		assert_true(ResourceLoader.exists(path), "运行时代码必须存在：%s" % path)
		if not ResourceLoader.exists(path):
			continue
		var script := load(path) as GDScript
		assert_not_null(script)
		if script == null:
			continue
		var source := script.source_code.to_lower()
		for forbidden in ["httprequest", "httpclient", "/suno/", "new-api", "openai_api_key"]:
			assert_false(source.contains(forbidden), "运行时不得包含生成 API：%s" % forbidden)


func test_capture_tool_has_real_audio_popup_shot() -> void:
	var script := load("res://tools/capture_screens.gd") as GDScript
	assert_not_null(script)
	if script == null:
		return
	assert_true(script.source_code.contains("shot_lobby_audio_popup.png"))
	assert_true(script.source_code.contains("func _capture_lobby_audio_popup"))
