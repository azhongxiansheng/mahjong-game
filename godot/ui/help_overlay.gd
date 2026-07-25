class_name HelpOverlay extends Control

# H 键唤起的快捷帮助 overlay — 列所有键盘热键 + 战斗按钮速查 + 日麻关键术语。
# Pro polish:玩家任何时刻按 H 就能查热键,不用记忆。
#
# 本 overlay 是单页参考文档，不修改对局状态。
# PlayableTable 在 _input 监到 H 键时实例化挂根。

signal closed

const PANEL_W: int = 720
const PANEL_H: int = 600


const SECTIONS: Array = [
	{
		"title": "键盘热键",
		"rows": [
			["ESC", "打开设置面板(音量 / 全屏 / 帧率 / 战绩)"],
			["H", "打开 / 关闭本帮助"],
			["F3", "开关 Debug Overlay(显 FPS / BC state 等)"],
			["D", "切牌(出第一张手牌)— 战斗中可用"],
			["Enter", "确认对话框"],
		]
	},
	{
		"title": "战斗按钮速查",
		"rows": [
			["立直", "门清听牌时宣告,扣 1000 点,胡牌 +1 飜"],
			["自摸", "摸到胡牌张时宣告(无役不胡)"],
			["荣和", "对家弃牌是你的胡牌张时宣告(无役 / 振听不可)"],
			["吃", "上家弃牌 + 你 2 张构顺子(仅上家)"],
			["碰", "任意家弃牌 + 你 2 张构刻子"],
			["杠", "明杠:任意家 + 你 3 张;暗杠:自家 4 张"],
			["九種九牌", "第一巡 14 张含 ≥ 9 种幺九 → 途中流局"],
			["跳过", "鸣牌窗口不响应,让 AI 继续"],
		]
	},
	{
		"title": "日麻术语",
		"rows": [
			["飜 / 番", "yaku 强度;1-5 飜按符算,6+ 飜满贯起跳"],
			["符", "20-110;成牌 20 起,加上待牌 / 暗刻 / 雀头等"],
			["振听", "已切过自己听牌张 → 不能荣胡,只能自摸"],
			["役満", "32000 (亲家 48000),最强 yaku,无飜符算"],
			["立直棒", "胡者独吞,流局未胡 carry over 下一局"],
			["本场棒", "连庄棒,胡 / 流局 +1,影响支付额 +300/+100"],
		]
	}
]


func _init() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 180  # 高于一般 overlay,低于 ConfirmDialog


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

	var title := Label.new()
	title.text = "快捷帮助"
	title.position = Vector2(0, 24)
	title.size = Vector2(PANEL_W, 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", DT.FONT_TITLE)
	title.add_theme_color_override("font_color", DT.TEXT_TITLE)
	panel.add_child(title)

	# 滚动容器装多个 section
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(30, 76)
	scroll.size = Vector2(PANEL_W - 60, PANEL_H - 76 - 56)
	panel.add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(PANEL_W - 80, 0)
	vbox.add_theme_constant_override("separation", 16)
	scroll.add_child(vbox)

	for section in SECTIONS:
		vbox.add_child(_build_section(
			String(section.get("title", "")),
			section.get("rows", [])))

	var close_btn := DT.make_button("关闭 (H / ESC)", DT.BtnRole.PRIMARY, Vector2(180, 40))
	close_btn.position = Vector2((PANEL_W - 180) / 2.0, PANEL_H - 52)
	close_btn.pressed.connect(_on_close)
	panel.add_child(close_btn)


# Section header + 2-column key/value 表格
func _build_section(section_title: String, rows: Array) -> Control:
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(PANEL_W - 80, 0)
	v.add_theme_constant_override("separation", 4)

	var hdr := Label.new()
	hdr.text = section_title
	hdr.add_theme_font_size_override("font_size", 20)
	hdr.add_theme_color_override("font_color", Color(1, 0.78, 0.4))
	v.add_child(hdr)

	for row in rows:
		if not (row is Array) or row.size() < 2:
			continue
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 16)
		var key := Label.new()
		key.text = String(row[0])
		key.custom_minimum_size = Vector2(140, 0)
		key.add_theme_font_size_override("font_size", 14)
		key.add_theme_color_override("font_color", Color(0.95, 0.85, 0.32))
		line.add_child(key)
		var val := Label.new()
		val.text = String(row[1])
		val.add_theme_font_size_override("font_size", 14)
		val.add_theme_color_override("font_color", Color(0.93, 0.91, 0.82))
		val.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		val.custom_minimum_size = Vector2(PANEL_W - 80 - 140 - 16, 0)
		line.add_child(val)
		v.add_child(line)
	return v


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k: InputEventKey = event
		if k.pressed and not k.echo:
			if k.keycode == KEY_ESCAPE or k.keycode == KEY_H:
				_on_close()
				get_viewport().set_input_as_handled()


func _on_close() -> void:
	closed.emit()
	queue_free()
