class_name StatsView extends Control

# 终身统计 + 成就展示 overlay。从 RunSummary / MainMenu / SettingsOverlay 唤起。
# 暗背景 + 中央 Panel,左侧统计数字,右侧成就网格(已解锁亮金色,未解锁灰色)。

signal closed

const PANEL_W: int = 900
const PANEL_H: int = 620


func _init() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(DT.BG_BASE.r, DT.BG_BASE.g, DT.BG_BASE.b, DT.MODAL_BG_DIM)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var panel := DT.make_centered_panel(PANEL_W, PANEL_H)
	add_child(panel)
	DT.popin(panel)

	# 标题
	var title := Label.new()
	title.text = "终身战绩 · 成就"
	title.position = Vector2(0, 22)
	title.size = Vector2(PANEL_W, 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", DT.FONT_TITLE)
	title.add_theme_color_override("font_color", DT.TEXT_TITLE)
	panel.add_child(title)

	# 左:统计数字
	_build_stats_column(panel, 40, 80, 380)
	# 右:成就网格
	_build_achievements_column(panel, PANEL_W - 460 - 20, 80, 460)

	# 关闭按钮
	var close_btn := DT.make_button("关闭", DT.BtnRole.PRIMARY, Vector2(140, 40))
	close_btn.position = Vector2((PANEL_W - 140) / 2.0, PANEL_H - 56)
	close_btn.pressed.connect(_on_close)
	panel.add_child(close_btn)

	z_index = 100


func _build_stats_column(parent: Control, x: int, y: int, w: int) -> void:
	var sm = _sm()
	var lines: Array[String] = [
		"对局总数: %d" % sm.hands_played,
		"胡牌次数: %d" % sm.hands_won,
		"被放铳次数: %d" % sm.hands_lost_by_deal_in,
		"",
		"自摸: %d   荣胡: %d" % [sm.tsumo_count, sm.ron_count],
		"立直: %d   双立直: %d" % [sm.riichi_count, sm.double_riichi_count],
		"一発: %d" % sm.ippatsu_count,
		"海底/河底: %d" % sm.haitei_count,
		"岭上开花: %d" % sm.rinshan_count,
		"",
		"役満: %d   双倍役満: %d" % [sm.yakuman_count, sm.double_yakuman_count],
		"",
		"Run 开局: %d" % sm.runs_started,
		"通关: %d   失败: %d" % [sm.runs_won, sm.runs_failed],
		"",
		"单局最高: %d 点" % sm.highest_single_hand_score,
		"终身胡得分: %d 点" % sm.total_points_won,
	]
	var lbl := Label.new()
	lbl.position = Vector2(x, y)
	lbl.size = Vector2(w, PANEL_H - 160)
	lbl.text = "\n".join(lines)
	lbl.add_theme_font_size_override("font_size", DT.FONT_BODY)
	lbl.add_theme_color_override("font_color", DT.TEXT_PRIMARY)
	parent.add_child(lbl)


func _build_achievements_column(parent: Control, x: int, y: int, w: int) -> void:
	var sm = _sm()
	var ach: Dictionary = sm.ACHIEVEMENTS
	var unlocked: Dictionary = sm.unlocked_achievements
	var grid := VBoxContainer.new()
	grid.position = Vector2(x, y)
	grid.size = Vector2(w, PANEL_H - 160)
	parent.add_child(grid)

	var unlocked_count: int = unlocked.size()
	var total: int = ach.size()
	var hdr := Label.new()
	hdr.text = "成就 (%d / %d)" % [unlocked_count, total]
	hdr.add_theme_font_size_override("font_size", DT.FONT_SUBTITLE)
	hdr.add_theme_color_override("font_color", DT.TEXT_TITLE)
	grid.add_child(hdr)

	# 滚动容器避免超长
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(w, PANEL_H - 200)
	grid.add_child(scroll)
	var inner := VBoxContainer.new()
	inner.custom_minimum_size = Vector2(w - 20, 0)
	scroll.add_child(inner)

	for id in ach.keys():
		var meta: Dictionary = ach[id]
		var nm: String = String(meta.get("name", id))
		var desc: String = String(meta.get("desc", ""))
		var is_unlocked: bool = unlocked.has(id)
		var row := Label.new()
		var prefix: String = "🏆" if is_unlocked else "🔒"
		row.text = "%s  %s — %s" % [prefix, nm, desc]
		row.add_theme_font_size_override("font_size", DT.FONT_CAPTION)
		var color: Color = DT.TEXT_TITLE if is_unlocked else DT.TEXT_MUTED
		row.add_theme_color_override("font_color", color)
		inner.add_child(row)


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k: InputEventKey = event
		if k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
			_on_close()
			get_viewport().set_input_as_handled()


func _on_close() -> void:
	closed.emit()
	queue_free()


func _sm() -> Node:
	return get_node("/root/StatsManager")
