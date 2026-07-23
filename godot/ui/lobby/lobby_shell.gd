class_name LobbyShell extends Control

# 生产主入口壳（E1-01 / #225）。
# 只提供可启动、可返回的最小大厅导航与练习/匹配稳定挂点。
# 不拥有大厅选择态、正式会话配置、规则抽屉或对局/联网实现。
# 生产级 1600×900 视觉归 #227；选择态归 #228。

const SCENE_PATH := "res://ui/lobby/lobby_shell.tscn"

## 电脑练习入口挂点（后续 #228 接规则抽屉；本 Issue 仅发 signal）。
signal practice_pressed
## 公共匹配入口挂点（后续 #228/#238；本 Issue 仅发 signal，不假装已匹配）。
signal match_pressed

var _status_label: Label = null


func _ready() -> void:
	custom_minimum_size = Vector2(DT.VIEW_W, DT.VIEW_H)
	DT.style_full_panel(self)
	_build_ui()


func request_practice() -> void:
	_set_status("电脑练习即将开放")
	practice_pressed.emit()


func request_match() -> void:
	_set_status("公共匹配即将开放")
	match_pressed.emit()


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.name = "RootVBox"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = DT.PANEL_PAD
	root.offset_top = DT.PANEL_PAD
	root.offset_right = -DT.PANEL_PAD
	root.offset_bottom = -DT.PANEL_PAD
	root.add_theme_constant_override("separation", DT.GAP_LOOSE)
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(root)

	var title := Label.new()
	title.name = "Title"
	title.text = "虚席馆"
	DT.apply_title_style(title)
	root.add_child(title)

	var subtitle := Label.new()
	subtitle.name = "Subtitle"
	subtitle.text = "选择一种游戏方式"
	DT.apply_subtitle_style(subtitle)
	root.add_child(subtitle)

	var entries := VBoxContainer.new()
	entries.name = "EntryColumn"
	entries.add_theme_constant_override("separation", DT.GAP_NORMAL)
	entries.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(entries)

	var practice_btn := DT.make_button("电脑练习", DT.BtnRole.PRIMARY, Vector2(280, DT.BUTTON_H + 8))
	practice_btn.name = "PracticeButton"
	practice_btn.unique_name_in_owner = true
	practice_btn.pressed.connect(request_practice)
	entries.add_child(practice_btn)
	# 代码构建子节点时须显式 owner，%UniqueName 才挂到本场景根
	practice_btn.owner = self

	var practice_hint := Label.new()
	practice_hint.text = "1 人 + 3 AI"
	DT.apply_caption_style(practice_hint)
	entries.add_child(practice_hint)

	var match_btn := DT.make_button("公共匹配", DT.BtnRole.SECONDARY, Vector2(280, DT.BUTTON_H + 8))
	match_btn.name = "MatchButton"
	match_btn.unique_name_in_owner = true
	match_btn.pressed.connect(request_match)
	entries.add_child(match_btn)
	match_btn.owner = self

	var match_hint := Label.new()
	match_hint.text = "真人优先 / AI 补位"
	DT.apply_caption_style(match_hint)
	entries.add_child(match_hint)

	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	_status_label.text = "请选择游戏方式"
	DT.apply_caption_style(_status_label)
	root.add_child(_status_label)


func _set_status(text: String) -> void:
	if _status_label:
		_status_label.text = text
