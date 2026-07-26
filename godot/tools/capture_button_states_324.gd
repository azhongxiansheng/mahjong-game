extends SceneTree

# #324 黑曜符札按钮专项：输出两分辨率状态矩阵与真实生产按钮抽样。
# godot --path godot -s tools/capture_button_states_324.gd

const CAPTURE_SIZES := [Vector2i(1600, 900), Vector2i(1280, 720)]
const STATES := ["normal", "hover", "focus", "pressed", "disabled", "ellipsis"]
const STATE_TEXTS := [
	"开始",
	"开始公开匹配",
	"対局を開始",
	"ConfirmSupernaturalPower",
	"匹配 12/16",
	"Supercalifragilisticexpialidocious",
]
const ROLES := [
	["PRIMARY", 0],
	["SECONDARY", 1],
	["DANGER", 2],
	["GHOST", 3],
]
const COLOR_TEXT := Color("f3f1ff")
const COLOR_SECONDARY := Color("3ca9d6")
const COLOR_MUTED := Color("8c8c8c")

var _dt_script: Script = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# -s 脚本编译早于 Autoload；运行时 load 避免把 Anima/生产 class_name
	# 拖进早期编译闭包（同 tools/capture_screens.gd）。
	_dt_script = load("res://ui/design_tokens.gd") as Script
	for capture_size in CAPTURE_SIZES:
		root.content_scale_size = capture_size
		DisplayServer.window_set_size(capture_size)
		await process_frame
		await process_frame
		await _capture_matrix(capture_size)
		await _capture_production(capture_size)
	await process_frame
	await process_frame
	await create_timer(0.1).timeout
	print("[capture-324] done")
	quit()


func _capture_matrix(capture_size: Vector2i) -> void:
	var canvas := _make_canvas(capture_size, "#324 黑曜符札｜四角色 × 五态 + 长文案")
	root.add_child(canvas)
	var left := 170.0
	var top := 126.0
	var col_w := (capture_size.x - left - 34.0) / float(STATES.size())
	var row_h := (capture_size.y - top - 34.0) / float(ROLES.size())
	for col in STATES.size():
		var header := _label(STATES[col], 16, COLOR_SECONDARY)
		header.position = Vector2(left + col_w * col, 84)
		header.size = Vector2(col_w - 12, 30)
		canvas.add_child(header)
	for row in ROLES.size():
		var role_name := String(ROLES[row][0])
		var role := int(ROLES[row][1])
		var role_label := _label(role_name, 17, COLOR_TEXT)
		role_label.position = Vector2(24, top + row_h * row + 14)
		role_label.size = Vector2(136, 34)
		canvas.add_child(role_label)
		for col in STATES.size():
			var state := String(STATES[col])
			var button := _dt_script.call("make_button",
				STATE_TEXTS[col], role, Vector2(col_w - 16, 52)
			) as Button
			button.position = Vector2(left + col_w * col, top + row_h * row + 6)
			button.size = Vector2(col_w - 16, 52)
			_force_visual_state(button, state)
			canvas.add_child(button)
			var note := _label(_state_note(state), 13, COLOR_MUTED)
			note.position = button.position + Vector2(0, 62)
			note.size = Vector2(col_w - 16, 34)
			canvas.add_child(note)
	await _save_canvas(canvas, capture_size, "matrix")


func _capture_production(capture_size: Vector2i) -> void:
	var canvas := _make_canvas(capture_size, "#324 生产 Button / 调用契约抽样｜父页面几何未改")
	root.add_child(canvas)
	var source_host := Control.new()
	source_host.visible = false
	canvas.add_child(source_host)
	var samples := await _collect_production_samples(source_host)
	var columns := 2
	var cell_w := (capture_size.x - 72.0) / float(columns)
	var cell_h := (capture_size.y - 142.0) / 3.0
	for index in samples.size():
		var column := index % columns
		var row := index / columns
		var origin := Vector2(30 + cell_w * column, 112 + cell_h * row)
		var sample: Dictionary = samples[index]
		var caption := _label(String(sample.label), 18, COLOR_TEXT)
		caption.position = origin
		caption.size = Vector2(210, 36)
		canvas.add_child(caption)
		var button := sample.button as Button
		button.visible = true
		button.disabled = false
		button.position = origin + Vector2(220, 0)
		button.size = button.custom_minimum_size
		canvas.add_child(button)
		var geometry := _label(
			"槽位 %d×%d｜tooltip: %s" % [
				int(button.custom_minimum_size.x),
				int(button.custom_minimum_size.y),
				button.tooltip_text if not button.tooltip_text.is_empty() else "—",
			],
			13,
			COLOR_MUTED,
		)
		geometry.position = origin + Vector2(220, 62)
		geometry.size = Vector2(cell_w - 230, 30)
		canvas.add_child(geometry)
	source_host.queue_free()
	await _save_canvas(canvas, capture_size, "production")


func _collect_production_samples(host: Control) -> Array[Dictionary]:
	var samples: Array[Dictionary] = []
	var stage: Node = (load("res://ui/lobby/lobby_stage.tscn") as PackedScene).instantiate()
	host.add_child(stage)
	await process_frame
	samples.append({
		"label": "大厅底栏｜雀士名录",
		"button": (stage.get_node("BottomNav/NavRow/CharacterNavButton") as Button).duplicate(),
	})

	var drawer: Variant = (load("res://ui/lobby/rule_drawer.gd") as Script).new()
	host.add_child(drawer)
	await process_frame
	samples.append({"label": "规则抽屉｜开始", "button": drawer._start_btn.duplicate()})

	# SettingsOverlay._ready() 会启动既有 Anima 入场；专项截图按其真实生产
	# make_button 参数构造，避免把无关 tween 生命周期带进截图门禁。
	var settings_button := _dt_script.call(
		"make_button", "关闭 (ESC)", 0, Vector2(140, 40)
	) as Button
	samples.append({
		"label": "设置｜关闭 (ESC)",
		"button": settings_button,
	})

	var codex: Variant = (load("res://ui/lobby/lobby_codex_overlay.gd") as Script).new()
	host.add_child(codex)
	await process_frame
	samples.append({"label": "资料馆｜关闭", "button": codex._close_btn.duplicate()})

	var action: Variant = (load("res://ui/four_player_table/player_action_panel.tscn") as PackedScene).instantiate()
	host.add_child(action)
	await process_frame
	samples.append({"label": "牌桌行动栏｜荣和", "button": action._btn_ron.duplicate()})

	var settlement: Variant = (load("res://ui/four_player_table/match_settlement_panel.gd") as Script).new()
	host.add_child(settlement)
	await process_frame
	settlement._rematch_btn.text = "ConfirmSupernaturalPowerWithoutOverflow"
	settlement._rematch_btn.tooltip_text = ""
	_dt_script.call(
		"apply_button_role",
		settlement._rematch_btn,
		int(settlement._rematch_btn.get_meta("dt_button_role")),
	)
	samples.append({
		"label": "结算｜超长英文",
		"button": settlement._rematch_btn.duplicate(),
	})
	return samples


func _force_visual_state(button: Button, state: String) -> void:
	if state == "disabled":
		button.disabled = true
		return
	if state == "ellipsis":
		return
	var style := button.get_theme_stylebox(state)
	if state == "focus":
		# 真实 Button 会把透明 focus StyleBox 叠在 normal 上；矩阵将两层合成，
		# 避免专项样张把底色错误展示为完全透明。
		style = style.duplicate()
		(style as StyleBoxFlat).bg_color = (
			button.get_theme_stylebox("normal") as StyleBoxFlat
		).bg_color
	button.add_theme_stylebox_override("normal", style)
	var color_name := "font_color" if state == "normal" else "font_%s_color" % state
	button.add_theme_color_override("font_color", button.get_theme_color(color_name))


func _state_note(state: String) -> String:
	match state:
		"hover":
			return "提亮 + 上/右缘"
		"focus":
			return "苍青环 + 左记号"
		"pressed":
			return "下移 2px + 朱红印"
		"disabled":
			return "断缘 + 无阴影"
		"ellipsis":
			return "单行 … / 全文 tooltip"
		_:
			return "黑曜薄底 + 角色缘"


func _make_canvas(capture_size: Vector2i, title: String) -> Control:
	var canvas := Control.new()
	canvas.size = capture_size
	var background := ColorRect.new()
	background.color = Color("080a12")
	background.size = capture_size
	canvas.add_child(background)
	var heading := _label(title, 26, COLOR_TEXT)
	heading.position = Vector2(24, 20)
	heading.size = Vector2(capture_size.x - 48, 46)
	canvas.add_child(heading)
	return canvas


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _save_canvas(canvas: Control, capture_size: Vector2i, suffix: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var tag := "%dx%d" % [capture_size.x, capture_size.y]
	var output := "/tmp/shot_button_324_%s_%s.png" % [tag, suffix]
	var error := image.save_png(output)
	print("[capture-324] ", output, " size=", image.get_size(), " error=", error)
	canvas.queue_free()
	await process_frame
	await process_frame
