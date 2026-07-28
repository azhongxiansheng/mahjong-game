extends SceneTree

# Issue #370 方案 A：以 round-2 的 origin/main 基线对比真实生产实现。

const LOGICAL_SIZE := Vector2i(1600, 900)
const SIZES := [Vector2i(1600, 900), Vector2i(1280, 720)]
const BASELINE_DIR := "/tmp/mahjong-game-issue-370-stylebox-round-2"
const OUTPUT_DIR := "/tmp/mahjong-game-issue-370-stylebox-round-3-final-p2"
const LOBBY_SCENE := "res://ui/lobby/lobby_shell.tscn"
const CAPTURE_PHASE_POLICY_SCRIPT := preload("res://tools/capture_phase_policy_370.gd")
const MATRIX_PAGES := [
	["lobby", "settings", "rule_drawer"],
	["codex", "waiting", "reconnecting"],
	["terminal_error", "hand_settlement", "match_settlement"],
]

var _metrics: Array[Dictionary] = []
var _baseline_rects: Dictionary = {}
var _capture_phase_policy: RefCounted = CAPTURE_PHASE_POLICY_SCRIPT.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var mkdir_error := DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	if mkdir_error != OK and mkdir_error != ERR_ALREADY_EXISTS:
		push_error("无法建立 round-3 目录：%s" % mkdir_error)
		quit(1)
		return
	if not _load_baseline_metrics():
		quit(1)
		return
	root.content_scale_size = LOGICAL_SIZE
	for size in SIZES:
		await _capture_lobby_case(size, "lobby", func(_shell): pass,
			func(shell): return shell.find_child("LobbyStage", true, false))
		await _capture_lobby_case(size, "settings", func(shell):
			(shell.get_node("%SettingsButton") as Button).pressed.emit(),
			func(_shell):
				var overlay := root.get_node_or_null("_settings_overlay_root")
				return overlay.find_child("SettingsModal", true, false) if overlay != null else null)
		await _capture_lobby_case(size, "rule_drawer", func(shell): shell.request_practice(),
			func(shell): return shell.get_node_or_null("%RuleDrawerPanel"))
		await _capture_lobby_case(size, "codex", func(shell):
			(shell.get_node("%CharacterCodexButton") as Button).pressed.emit(),
			func(shell): return shell.get_node_or_null("%CodexPanel"))
		await _capture_lobby_case(size, "waiting", func(shell):
			var coordinator = shell.get_node("PublicMatchCoordinator")
			coordinator.consume_ticket_for_test({
				"ticket_id": "preview-370", "status": "waiting",
				"round_kind": "EAST", "game_mode": "STANDARD",
				"queued_at": "2026-07-28T00:00:00Z",
				"deadline_at": "2026-07-28T00:01:00Z",
			}), func(shell): return shell.get_node_or_null("%PublicMatchModal"))
		await _capture_lobby_case(size, "reconnecting", func(shell):
			var coordinator = shell.get_node("PublicMatchCoordinator")
			coordinator.consume_connection_fact_for_test(
				&"reconnecting", "WS_CLOSED", "连接已断开，等待重新连接。"
			), func(shell): return shell.get_node_or_null("%PublicMatchModal"))
		await _capture_lobby_case(size, "terminal_error", func(shell):
			var coordinator = shell.get_node("PublicMatchCoordinator")
			coordinator.consume_connection_fact_for_test(
				&"terminal_error", "ROOM_FAILED", "匹配房间暂不可用。"
			), func(shell): return shell.get_node_or_null("%PublicMatchModal"))
		await _capture_hand_settlement(size)
		await _capture_match_settlement(size)
		for page_index in MATRIX_PAGES.size():
			await _capture_matrix(size, page_index, MATRIX_PAGES[page_index])
	_write_metrics()
	await _frames(10)
	await create_timer(0.1).timeout
	print("[capture-370-round3] done: ", OUTPUT_DIR)
	quit()


func _capture_lobby_case(
		window_size: Vector2i, tag: String, setup: Callable, target_selector: Callable) -> void:
	var rects := {}
	for phase in ["before", "after"]:
		DisplayServer.window_set_size(window_size)
		var shell := (load(LOBBY_SCENE) as PackedScene).instantiate() as Control
		root.add_child(shell)
		await _frames(8)
		setup.call(shell)
		await create_timer(0.45).timeout
		await _frames(4)
		var target := target_selector.call(shell) as Control
		if target == null:
			push_error("%s 缺少 protected-zone 目标" % tag)
		else:
			rects[phase] = _rect_dict(target.get_global_rect())
		await _store_full(tag, phase, window_size)
		_cleanup_settings_overlay()
		root.remove_child(shell)
		shell.queue_free()
		await _frames(3)
	_record_metrics(tag, window_size, rects)


func _capture_hand_settlement(window_size: Vector2i) -> void:
	var rects := {}
	for phase in ["before", "after"]:
		DisplayServer.window_set_size(window_size)
		var playable := (load("res://ui/four_player_table/playable_table.gd") as Script).new() as Control
		root.add_child(playable)
		await _frames(8)
		var controller_script := load("res://battle/playable_battle_controller.gd") as Script
		playable._bc = controller_script.new(370)
		playable._show_hand_result_overlay({"last_event": "ABORTIVE_DRAW"})
		await create_timer(0.8).timeout
		await _frames(4)
		var overlay := playable.get_node("ResultOverlay") as Control
		var target := overlay.get_node("ResultModal") as Control
		rects[phase] = _rect_dict(target.get_global_rect())
		await _store_full("hand_settlement", phase, window_size)
		root.remove_child(playable)
		playable.queue_free()
		await _frames(3)
	_record_metrics("hand_settlement", window_size, rects)


func _capture_match_settlement(window_size: Vector2i) -> void:
	var rects := {}
	for phase in ["before", "after"]:
		DisplayServer.window_set_size(window_size)
		var playable := (load("res://ui/four_player_table/playable_table.gd") as Script).new() as Control
		root.add_child(playable)
		await _frames(8)
		var panel := (load("res://ui/four_player_table/match_settlement_panel.gd") as Script).new() as Control
		playable.add_child(panel)
		var settlement_script := load("res://session/match_settlement.gd") as Script
		panel.present(settlement_script.call("build_view", [32000, 28000, 22000, 18000], &"EAST"))
		await _frames(8)
		var target := panel.find_child("SettlementModal", true, false) as Control
		rects[phase] = _rect_dict(target.get_global_rect())
		await _store_full("match_settlement", phase, window_size)
		root.remove_child(playable)
		playable.queue_free()
		await _frames(3)
	_record_metrics("match_settlement", window_size, rects)


func _capture_matrix(window_size: Vector2i, page_index: int, tags: Array) -> void:
	DisplayServer.window_set_size(window_size)
	var canvas := Control.new()
	canvas.size = LOGICAL_SIZE
	var bg := ColorRect.new()
	bg.color = Color("08090e")
	bg.size = canvas.size
	canvas.add_child(bg)
	var title := _label("#370 方案 A｜origin/main / 真实生产｜第 %d 页" % (page_index + 1), 28)
	title.position = Vector2(24, 12)
	title.size = Vector2(1552, 42)
	canvas.add_child(title)
	for column in 2:
		var heading := _label("BEFORE · origin/main" if column == 0 else "AFTER · A 生产实现", 18)
		heading.position = Vector2(180 + column * 700, 56)
		heading.size = Vector2(650, 30)
		heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		canvas.add_child(heading)
	for row in tags.size():
		var tag := String(tags[row])
		var row_y := 92.0 + row * 264.0
		var row_label := _label(_display_name(tag), 18)
		row_label.position = Vector2(24, row_y)
		row_label.size = Vector2(145, 220)
		row_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		canvas.add_child(row_label)
		for column in 2:
			var phase := "before" if column == 0 else "after"
			var texture := _load_external_texture(_full_path(tag, phase, window_size))
			var preview := TextureRect.new()
			preview.position = Vector2(180 + column * 700, row_y)
			preview.size = Vector2(680, 230)
			preview.texture = texture
			preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			preview.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			canvas.add_child(preview)
	root.add_child(canvas)
	await _frames(3)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image.get_size() != window_size:
		image.resize(window_size.x, window_size.y, Image.INTERPOLATE_LANCZOS)
	var output := "%s/matrix_%d_%dx%d.png" % [
		OUTPUT_DIR, page_index + 1, window_size.x, window_size.y,
	]
	var error := image.save_png(output)
	print("[capture-370-round3] ", output, " error=", error)
	root.remove_child(canvas)
	canvas.queue_free()
	await _frames(3)


func _load_external_texture(path: String) -> ImageTexture:
	var source := Image.new()
	var error := source.load(path)
	if error != OK:
		push_error("无法读取矩阵源图：%s（%s）" % [path, error])
		return null
	return ImageTexture.create_from_image(source)


func _store_full(tag: String, phase: String, window_size: Vector2i) -> void:
	if not _capture_phase_policy.should_save_current_frame(phase):
		var source := "%s/%s_before_%dx%d.png" % [
			BASELINE_DIR, tag, window_size.x, window_size.y,
		]
		var copy_error := DirAccess.copy_absolute(source, _full_path(tag, phase, window_size))
		if copy_error != OK:
			push_error("无法复制 round-2 基线：%s（%s）" % [source, copy_error])
		return
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image.get_size() != window_size:
		image.resize(window_size.x, window_size.y, Image.INTERPOLATE_LANCZOS)
	var output := _full_path(tag, phase, window_size)
	var error := image.save_png(output)
	print("[capture-370-round3] ", output, " error=", error)


func _full_path(tag: String, phase: String, window_size: Vector2i) -> String:
	return "%s/%s_%s_%dx%d.png" % [OUTPUT_DIR, tag, phase, window_size.x, window_size.y]


func _record_metrics(tag: String, window_size: Vector2i, rects: Dictionary) -> void:
	var key := "%s@%dx%d" % [tag, window_size.x, window_size.y]
	var before: Dictionary = _baseline_rects.get(key, {})
	var after: Dictionary = rects.get("after", {})
	_metrics.append({
		"consumer": tag,
		"resolution": "%dx%d" % [window_size.x, window_size.y],
		"before": before,
		"after": after,
		"delta": {
			"x": _pixel_delta(after.get("x", 0.0), before.get("x", 0.0)),
			"y": _pixel_delta(after.get("y", 0.0), before.get("y", 0.0)),
			"w": _pixel_delta(after.get("w", 0.0), before.get("w", 0.0)),
			"h": _pixel_delta(after.get("h", 0.0), before.get("h", 0.0)),
		},
	})


func _pixel_delta(after_value: Variant, before_value: Variant) -> float:
	var delta := float(after_value) - float(before_value)
	return 0.0 if absf(delta) < 0.001 else delta


func _load_baseline_metrics() -> bool:
	var path := "%s/protected_zone_metrics.json" % BASELINE_DIR
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("无法读取 round-2 protected-zone 基线：%s" % path)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Array:
		push_error("round-2 protected-zone 基线格式无效：%s" % path)
		return false
	for row in parsed:
		if not row is Dictionary:
			continue
		var item := row as Dictionary
		var key := "%s@%s" % [String(item.get("consumer", "")), String(item.get("resolution", ""))]
		_baseline_rects[key] = item.get("before", {})
	return _baseline_rects.size() == SIZES.size() * 9


func _write_metrics() -> void:
	var file := FileAccess.open("%s/protected_zone_metrics.json" % OUTPUT_DIR, FileAccess.WRITE)
	file.store_string(JSON.stringify(_metrics, "  "))
	file.close()


func _rect_dict(rect: Rect2) -> Dictionary:
	return {"x": rect.position.x, "y": rect.position.y, "w": rect.size.x, "h": rect.size.y}


func _display_name(tag: String) -> String:
	match tag:
		"lobby": return "大厅"
		"settings": return "设置"
		"rule_drawer": return "规则抽屉"
		"codex": return "图鉴"
		"waiting": return "等待匹配"
		"reconnecting": return "重连"
		"terminal_error": return "终止错误"
		"hand_settlement": return "局结算"
		"match_settlement": return "整场结算"
		_: return tag


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("f4dcae"))
	return label


func _cleanup_settings_overlay() -> void:
	var settings := root.get_node_or_null("_settings_overlay_root")
	if settings != null:
		root.remove_child(settings)
		settings.queue_free()


func _frames(count: int) -> void:
	for _index in range(count):
		await process_frame
