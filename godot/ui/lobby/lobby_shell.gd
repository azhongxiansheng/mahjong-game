class_name LobbyShell extends Control

# 生产大厅路由壳：可见舞台由 lobby_stage.tscn 独立承载；本壳只接回既有
# 规则抽屉、资料馆、音量弹层、公开信号与 BGM 契约。

const SCENE_PATH := "res://ui/lobby/lobby_shell.tscn"
const STAGE_SCENE := preload("res://ui/lobby/lobby_stage.tscn")
const LOBBY_BGM_PATH := "res://assets/bgm/lobby_xuxiguan.ogg"
const FirstUseNotices := preload("res://platform/platform_first_use_notices.gd")

signal practice_pressed
signal match_pressed
signal session_intent_confirmed(intent: SessionIntent)
signal notice_pressed
signal help_pressed
signal settings_pressed
signal character_codex_pressed
signal item_codex_pressed
signal rules_pressed
signal bgm_pressed
signal sfx_pressed

var _stage = null
var _status_label: Label = null
var _drawer_host: Control = null
var _rule_drawer: RuleDrawer = null
var _drawer_source: Control = null
var _codex_host: Control = null
var _codex_overlay: LobbyCodexOverlay = null
var _codex_source: Control = null
var _audio_host: Control = null
var _audio_popup: LobbyAudioPopup = null
var _audio_source: Control = null
var _settings_source: Control = null
var _public_status_overlay: PublicMatchStatusOverlay = null
var _public_status_source: Control = null
# #258：首次公共连接说明进行中时暂存 Intent，避免重复弹窗
var _pending_public_intent: SessionIntent = null
var _public_connect_notice: ConfirmDialog = null


func _ready() -> void:
	custom_minimum_size = Vector2(DesignTokens.VIEW_W, DesignTokens.VIEW_H)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	set_process_input(true)
	request_lobby_bgm()


func _exit_tree() -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am != null and am.has_method("stop_bgm"):
		am.stop_bgm()


func request_lobby_bgm() -> void:
	_request_lobby_bgm()


func request_practice() -> void:
	practice_pressed.emit()
	_open_rule_drawer(&"PRACTICE", get_node_or_null("%PracticeButton") as Control)


func request_match() -> void:
	match_pressed.emit()
	_open_rule_drawer(&"PUBLIC_CASUAL", get_node_or_null("%MatchButton") as Control)


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode != KEY_ESCAPE:
		return
	if _public_status_overlay != null and _public_status_overlay.is_blocking():
		get_viewport().set_input_as_handled()
		return
	if get_tree().root.get_node_or_null("_settings_overlay_root") != null:
		return
	if _codex_host != null and _codex_host.visible:
		_close_codex()
		get_viewport().set_input_as_handled()
		return
	if _audio_host != null and _audio_host.visible:
		_close_audio_popup()
		get_viewport().set_input_as_handled()
		return
	if _drawer_host != null and _drawer_host.visible:
		_close_rule_drawer()
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	_stage = STAGE_SCENE.instantiate() as Control
	add_child(_stage)
	_stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	_register_hook(_stage)
	if _stage.has_method("get_hook_nodes"):
		for hook_node in _stage.get_hook_nodes():
			_register_hook(hook_node)
	_status_label = get_node_or_null("%StatusLabel") as Label
	_connect_stage_intents()
	_build_overlay_hosts()


func _connect_stage_intents() -> void:
	_stage.practice_requested.connect(request_practice)
	_stage.match_requested.connect(request_match)
	_stage.notice_requested.connect(func() -> void: notice_pressed.emit())
	_stage.help_requested.connect(func() -> void: help_pressed.emit())
	_stage.settings_requested.connect(_on_settings_requested)
	_stage.character_codex_requested.connect(_on_character_codex_requested)
	_stage.item_codex_requested.connect(_on_item_codex_requested)
	_stage.rules_requested.connect(_on_rules_requested)
	_stage.bgm_requested.connect(_on_bgm_requested)
	_stage.sfx_requested.connect(_on_sfx_requested)


func _build_overlay_hosts() -> void:
	_drawer_host = Control.new()
	_drawer_host.name = "RuleDrawerHost"
	_drawer_host.visible = false
	_drawer_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drawer_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_drawer_host)
	_register_hook(_drawer_host)
	_rule_drawer = RuleDrawer.new()
	_drawer_host.add_child(_rule_drawer)
	_rule_drawer.confirmed.connect(_on_rule_drawer_confirmed)
	_rule_drawer.cancelled.connect(_close_rule_drawer)
	for hook_node in _rule_drawer.get_hook_nodes():
		_register_hook(hook_node)

	_codex_host = Control.new()
	_codex_host.name = "CodexHost"
	_codex_host.visible = false
	_codex_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_codex_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_codex_host)
	_register_hook(_codex_host)
	_codex_overlay = LobbyCodexOverlay.new()
	_codex_host.add_child(_codex_overlay)
	_codex_overlay.closed.connect(_close_codex)
	for hook_node in _codex_overlay.get_hook_nodes():
		_register_hook(hook_node)

	_audio_host = Control.new()
	_audio_host.name = "AudioPopupHost"
	_audio_host.visible = false
	_audio_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_audio_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_audio_host)
	_register_hook(_audio_host)
	_audio_popup = LobbyAudioPopup.new()
	_audio_host.add_child(_audio_popup)
	_audio_popup.closed.connect(_close_audio_popup)
	for hook_node in _audio_popup.get_hook_nodes():
		_register_hook(hook_node)

	_public_status_overlay = PublicMatchStatusOverlay.new()
	add_child(_public_status_overlay)
	_public_status_overlay.cancel_requested.connect(_on_public_cancel_requested)
	_public_status_overlay.retry_requested.connect(_on_public_retry_requested)
	_public_status_overlay.close_requested.connect(_on_public_status_closed)
	for hook_node in _public_status_overlay.get_hook_nodes():
		_register_hook(hook_node)
	var coordinator := get_node_or_null("PublicMatchCoordinator") as PublicMatchCoordinator
	if coordinator != null:
		coordinator.view_changed.connect(_on_public_match_view_changed)
		_public_status_overlay.present(coordinator.get_view())


func _register_hook(node: Node) -> void:
	if node == null:
		return
	node.unique_name_in_owner = true
	node.owner = self


func _on_character_codex_requested(source: Control) -> void:
	character_codex_pressed.emit()
	_open_codex(&"characters", source)


func _on_item_codex_requested(source: Control) -> void:
	item_codex_pressed.emit()
	_open_codex(&"items", source)


func _on_rules_requested(source: Control) -> void:
	rules_pressed.emit()
	_open_codex(&"rules", source)


func _on_bgm_requested(source: Control) -> void:
	bgm_pressed.emit()
	_open_audio_popup(source)


func _on_sfx_requested(source: Control) -> void:
	sfx_pressed.emit()
	_open_audio_popup(source)


func _on_settings_requested() -> void:
	settings_pressed.emit()
	_open_settings_overlay(get_node_or_null("%SettingsButton") as Control)


func _set_status(text: String) -> void:
	if _status_label:
		_status_label.text = text


func _open_rule_drawer(room_kind: StringName, source: Control) -> void:
	if _drawer_host == null or _rule_drawer == null:
		return
	_close_codex(false)
	_close_audio_popup(false)
	_close_settings_overlay(false)
	_drawer_source = source
	_drawer_host.visible = true
	_drawer_host.mouse_filter = Control.MOUSE_FILTER_STOP
	_set_status("选择局制与玩法")
	_rule_drawer.open_for(room_kind)


func _close_rule_drawer(restore_focus: bool = true) -> void:
	if _drawer_host == null:
		return
	if _rule_drawer:
		_rule_drawer.close_visual()
	_drawer_host.visible = false
	_drawer_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_status("选择一种游戏方式")
	if restore_focus and _drawer_source and is_instance_valid(_drawer_source) \
			and _drawer_source.focus_mode != Control.FOCUS_NONE:
		_drawer_source.grab_focus()
	_drawer_source = null


func _on_rule_drawer_confirmed(intent: SessionIntent) -> void:
	if intent != null and intent.room_kind == &"PUBLIC_CASUAL":
		_public_status_source = _drawer_source
	# #258：Windows 首次公共连接应用内说明（仅 Windows 运行时；系统防火墙弹窗不保证）
	if intent != null and intent.room_kind == &"PUBLIC_CASUAL":
		if FirstUseNotices.needs_public_connect_notice():
			_begin_public_connect_notice(intent)
			return
	session_intent_confirmed.emit(intent)
	_close_rule_drawer()


func _begin_public_connect_notice(intent: SessionIntent) -> void:
	if _public_connect_notice != null and is_instance_valid(_public_connect_notice):
		return
	_pending_public_intent = intent
	var copy: Dictionary = FirstUseNotices.public_connect_copy()
	var dlg := ConfirmDialog.show_dialog(
		String(copy.get("title", "")),
		String(copy.get("body", "")),
		String(copy.get("confirm", "我知道了")),
		String(copy.get("cancel", "取消")),
		false,
		300
	)
	dlg.name = "FirstPublicConnectNotice"
	_public_connect_notice = dlg
	dlg.confirmed.connect(_on_public_connect_notice_confirmed)
	dlg.cancelled.connect(_on_public_connect_notice_cancelled)
	add_child(dlg)


func _on_public_connect_notice_confirmed() -> void:
	_public_connect_notice = null
	FirstUseNotices.ack_public_connect_notice()
	var intent: SessionIntent = _pending_public_intent
	_pending_public_intent = null
	if intent == null:
		return
	session_intent_confirmed.emit(intent)
	_close_rule_drawer()


func _on_public_connect_notice_cancelled() -> void:
	_public_connect_notice = null
	_pending_public_intent = null
	# 不 ack：再次进入公共匹配仍提示


func _open_codex(page: StringName, source: Control) -> void:
	if _codex_host == null or _codex_overlay == null:
		return
	_close_rule_drawer(false)
	_close_audio_popup(false)
	_close_settings_overlay(false)
	_codex_source = source
	_codex_host.visible = true
	_codex_host.mouse_filter = Control.MOUSE_FILTER_STOP
	_codex_overlay.open_on_page(page)


func _close_codex(restore_focus: bool = true) -> void:
	if _codex_host == null:
		return
	_codex_host.visible = false
	_codex_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if restore_focus and _codex_source and is_instance_valid(_codex_source) \
			and _codex_source.focus_mode != Control.FOCUS_NONE:
		_codex_source.grab_focus()
	_codex_source = null


func _open_audio_popup(source: Control) -> void:
	if _audio_host == null or _audio_popup == null:
		return
	_close_rule_drawer(false)
	_close_codex(false)
	_close_settings_overlay(false)
	_audio_source = source
	_audio_host.visible = true
	_audio_host.mouse_filter = Control.MOUSE_FILTER_STOP
	_audio_popup.open_popup()


func _close_audio_popup(restore_focus: bool = true) -> void:
	if _audio_host == null:
		return
	_audio_host.visible = false
	_audio_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if restore_focus and _audio_source and is_instance_valid(_audio_source) \
			and _audio_source.focus_mode != Control.FOCUS_NONE:
		_audio_source.grab_focus()
	_audio_source = null


func _open_settings_overlay(source: Control) -> void:
	var existing := get_tree().root.get_node_or_null("_settings_overlay_root") as SettingsOverlay
	if existing != null:
		return
	_close_rule_drawer(false)
	_close_codex(false)
	_close_audio_popup(false)
	_settings_source = source
	var overlay := SettingsOverlay.new()
	overlay.name = "_settings_overlay_root"
	overlay.closed.connect(_on_settings_overlay_closed)
	get_tree().root.add_child(overlay)


func _close_settings_overlay(restore_focus: bool = true) -> void:
	var overlay := get_tree().root.get_node_or_null("_settings_overlay_root") as SettingsOverlay
	if not restore_focus:
		_settings_source = null
	if overlay != null:
		overlay.close_overlay()
	elif restore_focus:
		_restore_settings_focus()


func _on_settings_overlay_closed() -> void:
	_restore_settings_focus()


func _restore_settings_focus() -> void:
	if _settings_source != null and is_instance_valid(_settings_source) \
			and _settings_source.focus_mode != Control.FOCUS_NONE:
		_settings_source.grab_focus()
	_settings_source = null


func _on_public_match_view_changed(view: Dictionary) -> void:
	if _public_status_overlay == null:
		return
	var state := str(view.get("state", "idle"))
	if state not in ["idle", "cancelled", "recovered", "playing", "entered"]:
		_close_rule_drawer(false)
		_close_codex(false)
		_close_audio_popup(false)
		_close_settings_overlay(false)
	_public_status_overlay.present(view)
	move_child(_public_status_overlay, get_child_count() - 1)
	if state == "cancelled":
		_restore_public_status_focus()
	elif state == "playing" or state == "entered":
		# #377：遮罩解除后焦点交给公共牌桌
		var coordinator := get_node_or_null("PublicMatchCoordinator") as PublicMatchCoordinator
		var table: Control = null
		if coordinator != null:
			table = coordinator.get_active_table() as Control
		if table != null and is_instance_valid(table):
			table.focus_mode = Control.FOCUS_ALL
			table.grab_focus()
		else:
			_restore_public_status_focus()


func _on_public_cancel_requested() -> void:
	var coordinator := get_node_or_null("PublicMatchCoordinator") as PublicMatchCoordinator
	if coordinator != null:
		coordinator.request_cancel()


func _on_public_retry_requested() -> void:
	var coordinator := get_node_or_null("PublicMatchCoordinator") as PublicMatchCoordinator
	if coordinator != null:
		coordinator.request_retry()


func _on_public_status_closed() -> void:
	if _public_status_overlay != null:
		_public_status_overlay.visible = false
		_public_status_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_restore_public_status_focus()


func _restore_public_status_focus() -> void:
	var source := _public_status_source
	if source == null or not is_instance_valid(source):
		source = get_node_or_null("%MatchButton") as Control
	if source != null and source.focus_mode != Control.FOCUS_NONE:
		source.grab_focus()
	_public_status_source = null


func _request_lobby_bgm() -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am == null:
		return
	var sm := get_node_or_null("/root/SettingsManager")
	if sm != null and "bgm_volume" in am:
		am.bgm_volume = float(sm.bgm_volume)
	if am.has_method("play_bgm"):
		am.play_bgm(LOBBY_BGM_PATH)
