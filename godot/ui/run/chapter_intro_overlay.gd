class_name ChapterIntroOverlay extends Control

# 章节切换 / 通关时的剧情过场。3 句对话框 + 跳过按钮 + auto advance。
# 由 RunFlow 在检测到 chapter 变化或 run_won 时实例化挂根。
#
# 触发场景:
#   - ENTER_CHAPTER_2: 打过章 1 Boss → 进入章 2 前
#   - ENTER_CHAPTER_3: 打过章 2 Boss → 进入章 3 前 (最终关)
#   - WIN: 打过章 3 Boss 通关
#
# 文案 v1 硬编码:让玩家"为剧情想通关"而不只是为机制。3 句台词控制在 30 字
# 内,避免打断节奏。每句 2.5s 自动推进,玩家可按空格/点击/跳过提前推。

signal closed

enum Beat { ENTER_CHAPTER_2, ENTER_CHAPTER_3, WIN }

const SCRIPTS := {
	Beat.ENTER_CHAPTER_2: {
		"title": "—— 第二章 ——",
		"subtitle": "暗街的赌场",
		"lines": [
			"你打通了第一章的铁帘。镇上的人开始低声谈论你的名字。",
			"但这里的麻将,不再是为了钱。",
			"是为了——命。",
		],
	},
	Beat.ENTER_CHAPTER_3: {
		"title": "—— 第三章 ——",
		"subtitle": "鹫巣城",
		"lines": [
			"穿过浓雾,你站在城门前。",
			"这一桌的人,每一张牌都可能是你的最后一张。",
			"准备好了吗?",
		],
	},
	Beat.WIN: {
		"title": "—— 通关 ——",
		"subtitle": "麻将王",
		"lines": [
			"你坐在桌前,把最后一张牌轻轻放下。",
			"「自摸」—— 满座寂静。",
			"麻将王的称号,属于你了。",
		],
	},
}

const LINE_DURATION: float = 2.5  # 每句自动推进秒数
const FADE_DURATION: float = 0.4

var _beat: int = Beat.ENTER_CHAPTER_2
var _line_index: int = 0
var _line_label: Label = null
var _advance_tween: Tween = null
var _closed: bool = false


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 500


func set_beat(b: int) -> void:
	_beat = b


func _ready() -> void:
	if not SCRIPTS.has(_beat):
		_close()
		return
	var script_data: Dictionary = SCRIPTS[_beat]

	# Bg 渐入 — 全黑暗底 + 微微透出后面战斗结算让玩家觉得"有过渡"
	var bg := ColorRect.new()
	bg.color = Color(DT.BG_BASE.r, DT.BG_BASE.g, DT.BG_BASE.b, 0.92)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# 章节标题(金大字)
	var title := Label.new()
	title.text = script_data.get("title", "")
	title.set_anchors_preset(Control.PRESET_FULL_RECT)
	title.offset_top = 140
	title.offset_bottom = 220
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", DT.TEXT_TITLE)
	add_child(title)

	# 副标题(灰白小字)
	var subtitle := Label.new()
	subtitle.text = script_data.get("subtitle", "")
	subtitle.set_anchors_preset(Control.PRESET_FULL_RECT)
	subtitle.offset_top = 220
	subtitle.offset_bottom = 270
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", DT.FONT_SUBTITLE)
	subtitle.add_theme_color_override("font_color", DT.TEXT_MUTED)
	add_child(subtitle)

	# 对话框 — 居中,占屏中下部
	var dialog_bg := ColorRect.new()
	dialog_bg.color = Color(0, 0, 0, 0.55)
	dialog_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	dialog_bg.offset_left = 140
	dialog_bg.offset_right = -140
	dialog_bg.offset_top = 420
	dialog_bg.offset_bottom = -160
	dialog_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dialog_bg)

	_line_label = Label.new()
	_line_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_line_label.offset_left = 160
	_line_label.offset_right = -160
	_line_label.offset_top = 450
	_line_label.offset_bottom = -190
	_line_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_line_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_line_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line_label.add_theme_font_size_override("font_size", 26)
	_line_label.add_theme_color_override("font_color", DT.TEXT_PRIMARY)
	add_child(_line_label)

	# 提示:点击/空格继续 + 跳过
	var hint := Label.new()
	hint.text = "点击继续 · ESC 跳过全部"
	hint.set_anchors_preset(Control.PRESET_FULL_RECT)
	hint.offset_top = -100
	hint.offset_bottom = -60
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", DT.FONT_CAPTION)
	hint.add_theme_color_override("font_color", DT.TEXT_MUTED)
	add_child(hint)

	# 渐入
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, FADE_DURATION)

	_show_line(0)


func _show_line(index: int) -> void:
	var script_data: Dictionary = SCRIPTS[_beat]
	var lines: Array = script_data.get("lines", [])
	if index >= lines.size():
		_close()
		return
	_line_index = index
	_line_label.text = String(lines[index])
	# auto advance
	if _advance_tween and _advance_tween.is_valid():
		_advance_tween.kill()
	_advance_tween = create_tween()
	_advance_tween.tween_interval(LINE_DURATION)
	_advance_tween.tween_callback(func(): _show_line(_line_index + 1))


func _input(event: InputEvent) -> void:
	if _closed:
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.pressed:
			_advance_now()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		var k: InputEventKey = event
		if k.pressed and not k.echo:
			if k.keycode == KEY_ESCAPE:
				_close()
				get_viewport().set_input_as_handled()
			elif k.keycode == KEY_SPACE or k.keycode == KEY_ENTER:
				_advance_now()
				get_viewport().set_input_as_handled()


func _advance_now() -> void:
	if _advance_tween and _advance_tween.is_valid():
		_advance_tween.kill()
	_show_line(_line_index + 1)


func _close() -> void:
	if _closed:
		return
	_closed = true
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, FADE_DURATION)
	tw.tween_callback(func():
		emit_signal("closed")
		queue_free())
