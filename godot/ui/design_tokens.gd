class_name DesignTokens extends Node

# 设计系统单一来源 — 字号/颜色/间距/尺寸常量,所有 UI 都引用 DT.*。
# Autoload 名: DT (project.godot [autoload])。
#
# 改动这里 = 一处改全局生效,避免 9+ 处近似金色 / 13+ 种背景色 / 字号
# 14~36 七档不规范 的乱象。新增 UI 严禁硬编码颜色/字号,必须走 DT。
#
# _ready 会把 HSlider / OptionButton / CheckButton / LineEdit / PopupMenu
# 等控件样式补进 project Theme，避免设置页等仍是 Godot 默认灰控件。

var _theme_patched: bool = false


func _ready() -> void:
	patch_project_theme()


# ---- 基准 viewport (所有面板设计基准) ----

const VIEW_W: int = 1280
const VIEW_H: int = 800

# ---- 字号 4 档 ----

const FONT_TITLE: int = 36      # 页面主标题
const FONT_SUBTITLE: int = 24   # 卡片/段落标题
const FONT_BODY: int = 18       # 正文
const FONT_CAPTION: int = 14    # 提示、辅助信息

# ---- 间距 4 档 ----

const GAP_TIGHT: int = 8
const GAP_NORMAL: int = 16
const GAP_LOOSE: int = 24
const GAP_SECTION: int = 48

# ---- 颜色 — 唯一定义 ----

const BG_BASE: Color = Color(0.04, 0.06, 0.08, 1.0)         # #0A0F14 全局基底
const TEXT_PRIMARY: Color = Color(0.91, 0.91, 0.91, 1.0)    # #E8E8E8 正文白
const TEXT_MUTED: Color = Color(0.55, 0.55, 0.55, 1.0)      # #8C8C8C 提示灰
const TEXT_TITLE: Color = Color(1.00, 0.85, 0.40, 1.0)      # #FFD966 唯一金 — 取代 9+ 近似金
const TEXT_DANGER: Color = Color(0.88, 0.27, 0.27, 1.0)     # #E04545 警告/失败红
const TEXT_SUCCESS: Color = Color(0.45, 0.85, 0.45, 1.0)    # 通关/正向绿

# ---- 表面 / 卡片（Run 壳层统一）----
const SURFACE_PANEL: Color = Color(0.09, 0.10, 0.14, 0.96)   # 卡片/模态面板底
const SURFACE_PANEL_HOVER: Color = Color(0.14, 0.13, 0.18, 0.97)
const SURFACE_PANEL_PRESSED: Color = Color(0.18, 0.12, 0.14, 0.97)
const SURFACE_GLASS: Color = Color(0.06, 0.07, 0.10, 0.82)   # HUD 玻璃条
const BORDER_GOLD: Color = Color(0.85, 0.71, 0.36, 0.75)     # 金描边默认
const BORDER_GOLD_SOFT: Color = Color(0.85, 0.71, 0.36, 0.40)
const CARD_RADIUS: int = 10
const CARD_BORDER: int = 2

# ---- 节点主色 (8-15% 透明叠在 BG_BASE 上,保留主题信号,底色仍统一) ----

const NODE_TINT_NORMAL: Color = Color(0.40, 0.55, 0.70, 0.08)
const NODE_TINT_ELITE: Color = Color(0.90, 0.35, 0.30, 0.10)
const NODE_TINT_SHOP: Color = Color(0.95, 0.30, 0.20, 0.10)
const NODE_TINT_CAMP: Color = Color(0.30, 0.80, 0.40, 0.08)
const NODE_TINT_EVENT: Color = Color(0.70, 0.40, 0.95, 0.10)
const NODE_TINT_BOSS: Color = Color(0.30, 0.05, 0.05, 0.15)

# ---- 常用尺寸 ----

const CARD_W: int = 220
const CARD_H: int = 280
const BUTTON_H: int = 48
const HUD_H: int = 56           # 取代旧 50,字号 18 + 上下 padding 才够透气
const PANEL_PAD: int = 24       # 全屏面板四周内边距
const MODAL_BG_DIM: float = 0.85  # 模态遮罩不透明度


# 把一个 Control 摆成"全屏面板":根 anchor=15,内部铺 BG_BASE,可选叠节点 tint。
# 调用者:
#   func _ready():
#       DT.style_full_panel(self, DT.NODE_TINT_SHOP)
#       # 然后正常 add 内容子节点
static func style_full_panel(root: Control, node_tint: Color = Color(0, 0, 0, 0)) -> void:
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	# 第 0 位 BG (单一深色)
	var bg := ColorRect.new()
	bg.name = "DtBg"
	bg.color = BG_BASE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	root.move_child(bg, 0)
	# 第 1 位 节点 tint(透明叠层,可选)
	if node_tint.a > 0.0:
		var tint := ColorRect.new()
		tint.name = "DtNodeTint"
		tint.color = node_tint
		tint.set_anchors_preset(Control.PRESET_FULL_RECT)
		tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(tint)
		root.move_child(tint, 1)


# 把一个 Label 套上标题样式:36 号 + 金色 + 居中
static func apply_title_style(lbl: Label) -> void:
	lbl.add_theme_font_size_override("font_size", FONT_TITLE)
	lbl.add_theme_color_override("font_color", TEXT_TITLE)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


# 把一个 Label 套上副标题样式:24 号 + 正文白 + 居中
static func apply_subtitle_style(lbl: Label) -> void:
	lbl.add_theme_font_size_override("font_size", FONT_SUBTITLE)
	lbl.add_theme_color_override("font_color", TEXT_PRIMARY)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


# 把一个 Label 套上正文样式:18 号 + 正文白 + 居中 + autowrap
static func apply_body_style(lbl: Label) -> void:
	lbl.add_theme_font_size_override("font_size", FONT_BODY)
	lbl.add_theme_color_override("font_color", TEXT_PRIMARY)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


# 把一个 Label 套上提示样式:14 号 + 灰 + 居中 + autowrap
static func apply_caption_style(lbl: Label) -> void:
	lbl.add_theme_font_size_override("font_size", FONT_CAPTION)
	lbl.add_theme_color_override("font_color", TEXT_MUTED)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


# 统一卡片 StyleBoxFlat（normal/hover/pressed 共用边色，hover 提亮底）
static func make_card_stylebox(border_color: Color, state: String = "normal") -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	match state:
		"hover", "focus":
			sb.bg_color = SURFACE_PANEL_HOVER
		"pressed":
			sb.bg_color = SURFACE_PANEL_PRESSED
		"disabled":
			sb.bg_color = Color(0.08, 0.08, 0.09, 0.9)
		_:
			sb.bg_color = SURFACE_PANEL
	sb.border_color = border_color
	sb.set_border_width_all(CARD_BORDER)
	sb.set_corner_radius_all(CARD_RADIUS)
	sb.content_margin_left = GAP_NORMAL
	sb.content_margin_right = GAP_NORMAL
	sb.content_margin_top = GAP_NORMAL
	sb.content_margin_bottom = GAP_NORMAL
	# 轻投影让卡"浮"在背景上
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 8
	sb.shadow_offset = Vector2(0, 4)
	return sb


static func apply_card_button_styles(btn: Button, border_color: Color) -> void:
	if btn == null:
		return
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(state, make_card_stylebox(border_color, state))


# 在父 Container 里建一张"长描述卡片按钮":Button 不带 text(避免单行宽度撑爆
# minimum_size),内嵌 Label autowrap。返回 Button 供 caller 连 signal。
#
# 已知坑(commit bcbcc63):Button.text="多行文字" 时 Godot 用单行宽度作为
# minimum_size,卡片溢出 HBox 把第 N 张切出屏外。用这个 helper 统一规避。
static func make_text_card_button(
		parent: Container,
		body_text: String,
		card_size: Vector2,
		border_color: Color,
) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = card_size
	btn.text = ""
	btn.clip_text = true
	btn.clip_contents = true
	apply_card_button_styles(btn, border_color)
	# 内嵌 Label
	var lbl := Label.new()
	lbl.name = "CardBody"
	lbl.text = body_text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", FONT_BODY)
	lbl.add_theme_color_override("font_color", TEXT_PRIMARY)
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.offset_left = GAP_TIGHT
	lbl.offset_right = -GAP_TIGHT
	lbl.offset_top = GAP_TIGHT
	lbl.offset_bottom = -GAP_TIGHT
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 点击穿透到 Button
	btn.add_child(lbl)
	parent.add_child(btn)
	return btn


# 模态/设置类：居中 Panel + 金边表面（调用方再塞内容）
static func make_centered_panel(width: float, height: float) -> Panel:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(width, height)
	panel.size = Vector2(width, height)
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -width / 2.0
	panel.offset_top = -height / 2.0
	panel.offset_right = width / 2.0
	panel.offset_bottom = height / 2.0
	var sb := make_card_stylebox(BORDER_GOLD, "normal")
	sb.content_margin_left = PANEL_PAD
	sb.content_margin_right = PANEL_PAD
	sb.content_margin_top = PANEL_PAD
	sb.content_margin_bottom = PANEL_PAD
	sb.shadow_size = 16
	panel.add_theme_stylebox_override("panel", sb)
	return panel


# ---- 交互控件样式（按钮角色 / 滑条 / 下拉 / 开关）----

enum BtnRole { PRIMARY, SECONDARY, DANGER, GHOST }


static func _flat_sb(bg: Color, border: Color, bw: int = 2, radius: int = 8,
		pad_h: int = 14, pad_v: int = 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad_h
	sb.content_margin_right = pad_h
	sb.content_margin_top = pad_v
	sb.content_margin_bottom = pad_v
	return sb


# 给已有 Button 套角色外观（不改 text / 信号）
static func apply_button_role(btn: Button, role: int = BtnRole.PRIMARY) -> void:
	if btn == null:
		return
	var bg_n: Color
	var bg_h: Color
	var bg_p: Color
	var bg_d: Color
	var border: Color
	var font_c: Color = TEXT_PRIMARY
	match role:
		BtnRole.DANGER:
			bg_n = Color(0.42, 0.12, 0.12, 0.96)
			bg_h = Color(0.55, 0.16, 0.16, 0.98)
			bg_p = Color(0.32, 0.08, 0.08, 0.98)
			bg_d = Color(0.18, 0.10, 0.10, 0.85)
			border = TEXT_DANGER
			font_c = Color(1.0, 0.88, 0.88)
		BtnRole.SECONDARY:
			bg_n = Color(0.12, 0.13, 0.17, 0.96)
			bg_h = Color(0.18, 0.17, 0.22, 0.98)
			bg_p = Color(0.10, 0.10, 0.14, 0.98)
			bg_d = Color(0.08, 0.08, 0.09, 0.85)
			border = BORDER_GOLD_SOFT
		BtnRole.GHOST:
			bg_n = Color(0, 0, 0, 0)
			bg_h = Color(1, 1, 1, 0.06)
			bg_p = Color(1, 1, 1, 0.10)
			bg_d = Color(0, 0, 0, 0)
			border = Color(0, 0, 0, 0)
			font_c = TEXT_MUTED
		_:  # PRIMARY — 金边暗底
			bg_n = Color(0.16, 0.13, 0.10, 0.97)
			bg_h = Color(0.24, 0.18, 0.10, 0.98)
			bg_p = Color(0.12, 0.10, 0.08, 0.98)
			bg_d = Color(0.10, 0.09, 0.08, 0.85)
			border = BORDER_GOLD
			font_c = TEXT_TITLE
	btn.add_theme_stylebox_override("normal", _flat_sb(bg_n, border))
	btn.add_theme_stylebox_override("hover", _flat_sb(bg_h, border.lightened(0.15)))
	btn.add_theme_stylebox_override("pressed", _flat_sb(bg_p, border.darkened(0.1)))
	btn.add_theme_stylebox_override("focus", _flat_sb(bg_h, border.lightened(0.2)))
	btn.add_theme_stylebox_override("disabled", _flat_sb(bg_d, Color(0.3, 0.3, 0.32, 0.5)))
	btn.add_theme_color_override("font_color", font_c)
	btn.add_theme_color_override("font_hover_color", font_c.lightened(0.1))
	btn.add_theme_color_override("font_pressed_color", font_c)
	btn.add_theme_color_override("font_disabled_color", TEXT_MUTED)
	btn.add_theme_font_size_override("font_size", FONT_BODY)
	if btn.custom_minimum_size.y < BUTTON_H:
		btn.custom_minimum_size.y = BUTTON_H


static func make_button(text: String, role: int = BtnRole.PRIMARY,
		min_size: Vector2 = Vector2(140, BUTTON_H)) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = min_size
	apply_button_role(btn, role)
	return btn


static func style_hslider(slider: HSlider) -> void:
	if slider == null:
		return
	# 轨道
	var grabber_area := _flat_sb(Color(0.12, 0.12, 0.14, 1), BORDER_GOLD_SOFT, 1, 6, 0, 0)
	grabber_area.content_margin_top = 6
	grabber_area.content_margin_bottom = 6
	var grabber_area_hl := _flat_sb(Color(0.18, 0.15, 0.12, 1), BORDER_GOLD, 1, 6, 0, 0)
	grabber_area_hl.content_margin_top = 6
	grabber_area_hl.content_margin_bottom = 6
	slider.add_theme_stylebox_override("slider", grabber_area)
	slider.add_theme_stylebox_override("grabber_area", grabber_area_hl)
	slider.add_theme_stylebox_override("grabber_area_highlight", grabber_area_hl)
	# 滑块用小 StyleBox 圆角方块（无自定义 icon 时用 style）
	var grab := _flat_sb(TEXT_TITLE, Color(0.4, 0.3, 0.1, 1), 1, 8, 0, 0)
	grab.content_margin_left = 0
	grab.content_margin_right = 0
	# Godot 4 HSlider grabber 主要靠 icon；style 侧用 theme color 辅助
	slider.add_theme_constant_override("grabber_offset", 0)
	slider.custom_minimum_size.y = 28


static func style_option_button(opt: OptionButton) -> void:
	if opt == null:
		return
	apply_button_role(opt, BtnRole.SECONDARY)
	opt.custom_minimum_size.y = maxf(opt.custom_minimum_size.y, 36.0)
	# 下拉 PopupMenu 在 theme 层由 patch_project_theme 统一


static func style_check_button(cb: CheckButton) -> void:
	if cb == null:
		return
	cb.add_theme_color_override("font_color", TEXT_PRIMARY)
	cb.add_theme_color_override("font_pressed_color", TEXT_TITLE)
	cb.add_theme_color_override("font_hover_color", TEXT_TITLE)
	cb.add_theme_font_size_override("font_size", FONT_BODY)


static func style_line_edit(le: LineEdit) -> void:
	if le == null:
		return
	var n := _flat_sb(Color(0.08, 0.09, 0.12, 0.98), BORDER_GOLD_SOFT, 1, 6, 10, 8)
	var f := _flat_sb(Color(0.10, 0.11, 0.15, 0.98), BORDER_GOLD, 2, 6, 10, 8)
	var r := _flat_sb(Color(0.06, 0.07, 0.09, 0.9), Color(0.3, 0.3, 0.32), 1, 6, 10, 8)
	le.add_theme_stylebox_override("normal", n)
	le.add_theme_stylebox_override("focus", f)
	le.add_theme_stylebox_override("read_only", r)
	le.add_theme_color_override("font_color", TEXT_PRIMARY)
	le.add_theme_color_override("font_placeholder_color", TEXT_MUTED)
	le.add_theme_color_override("caret_color", TEXT_TITLE)
	le.add_theme_color_override("selection_color", Color(0.85, 0.65, 0.25, 0.35))
	le.add_theme_font_size_override("font_size", FONT_BODY)
	le.custom_minimum_size.y = maxf(le.custom_minimum_size.y, 36.0)


# 把缺失的控件类型样式写进 project Theme（全局生效）
func patch_project_theme() -> void:
	if _theme_patched:
		return
	var theme: Theme = ThemeDB.get_project_theme()
	if theme == null:
		# 兜底：从资源加载
		if ResourceLoader.exists("res://ui/run_theme.tres"):
			theme = load("res://ui/run_theme.tres") as Theme
	if theme == null:
		return
	_apply_controls_to_theme(theme)
	# 确保当前树用的是这份 theme
	if ThemeDB.get_project_theme() == null:
		pass  # project.godot 已设 custom theme
	_theme_patched = true


static func _apply_controls_to_theme(theme: Theme) -> void:
	if theme == null:
		return
	# --- HSlider ---
	var track := _flat_sb(Color(0.12, 0.12, 0.15, 1), BORDER_GOLD_SOFT, 1, 6, 0, 0)
	track.content_margin_top = 5
	track.content_margin_bottom = 5
	var fill := _flat_sb(Color(0.55, 0.42, 0.15, 1), BORDER_GOLD, 1, 6, 0, 0)
	fill.content_margin_top = 5
	fill.content_margin_bottom = 5
	theme.set_stylebox("slider", "HSlider", track)
	theme.set_stylebox("grabber_area", "HSlider", fill)
	theme.set_stylebox("grabber_area_highlight", "HSlider", fill)
	# --- OptionButton 字体色 ---
	theme.set_color("font_color", "OptionButton", TEXT_PRIMARY)
	theme.set_color("font_hover_color", "OptionButton", TEXT_TITLE)
	theme.set_color("font_pressed_color", "OptionButton", TEXT_TITLE)
	theme.set_color("font_disabled_color", "OptionButton", TEXT_MUTED)
	var opt_n := _flat_sb(Color(0.12, 0.13, 0.17, 0.96), BORDER_GOLD_SOFT, 2, 8, 12, 8)
	var opt_h := _flat_sb(Color(0.18, 0.17, 0.22, 0.98), BORDER_GOLD, 2, 8, 12, 8)
	theme.set_stylebox("normal", "OptionButton", opt_n)
	theme.set_stylebox("hover", "OptionButton", opt_h)
	theme.set_stylebox("pressed", "OptionButton", opt_h)
	theme.set_stylebox("disabled", "OptionButton",
		_flat_sb(Color(0.08, 0.08, 0.09, 0.85), Color(0.3, 0.3, 0.32, 0.5), 1, 8, 12, 8))
	theme.set_stylebox("focus", "OptionButton", opt_h)
	# --- PopupMenu（OptionButton 下拉）---
	var pop_panel := _flat_sb(SURFACE_PANEL, BORDER_GOLD, 2, 8, 8, 8)
	pop_panel.shadow_size = 10
	pop_panel.shadow_color = Color(0, 0, 0, 0.5)
	theme.set_stylebox("panel", "PopupMenu", pop_panel)
	theme.set_stylebox("hover", "PopupMenu",
		_flat_sb(Color(0.22, 0.18, 0.12, 0.95), BORDER_GOLD_SOFT, 0, 4, 8, 6))
	theme.set_color("font_color", "PopupMenu", TEXT_PRIMARY)
	theme.set_color("font_hover_color", "PopupMenu", TEXT_TITLE)
	theme.set_color("font_accelerator_color", "PopupMenu", TEXT_MUTED)
	theme.set_color("font_separator_color", "PopupMenu", TEXT_MUTED)
	# --- CheckButton / CheckBox ---
	theme.set_color("font_color", "CheckButton", TEXT_PRIMARY)
	theme.set_color("font_pressed_color", "CheckButton", TEXT_TITLE)
	theme.set_color("font_hover_color", "CheckButton", TEXT_TITLE)
	theme.set_color("font_hover_pressed_color", "CheckButton", TEXT_TITLE)
	theme.set_color("font_disabled_color", "CheckButton", TEXT_MUTED)
	theme.set_color("font_color", "CheckBox", TEXT_PRIMARY)
	theme.set_color("font_pressed_color", "CheckBox", TEXT_TITLE)
	theme.set_color("font_hover_color", "CheckBox", TEXT_TITLE)
	# --- LineEdit ---
	var le_n := _flat_sb(Color(0.08, 0.09, 0.12, 0.98), BORDER_GOLD_SOFT, 1, 6, 10, 8)
	var le_f := _flat_sb(Color(0.10, 0.11, 0.15, 0.98), BORDER_GOLD, 2, 6, 10, 8)
	theme.set_stylebox("normal", "LineEdit", le_n)
	theme.set_stylebox("focus", "LineEdit", le_f)
	theme.set_stylebox("read_only", "LineEdit",
		_flat_sb(Color(0.06, 0.07, 0.09, 0.9), Color(0.3, 0.3, 0.32), 1, 6, 10, 8))
	theme.set_color("font_color", "LineEdit", TEXT_PRIMARY)
	theme.set_color("font_placeholder_color", "LineEdit", TEXT_MUTED)
	theme.set_color("caret_color", "LineEdit", TEXT_TITLE)
	theme.set_color("selection_color", "LineEdit", Color(0.85, 0.65, 0.25, 0.35))
	# --- TextEdit ---
	theme.set_stylebox("normal", "TextEdit", le_n)
	theme.set_stylebox("focus", "TextEdit", le_f)
	theme.set_color("font_color", "TextEdit", TEXT_PRIMARY)
	theme.set_color("caret_color", "TextEdit", TEXT_TITLE)
	theme.set_color("selection_color", "TextEdit", Color(0.85, 0.65, 0.25, 0.35))
	# --- HSeparator / VSeparator ---
	var sep := StyleBoxLine.new()
	sep.color = BORDER_GOLD_SOFT
	sep.thickness = 1
	sep.vertical = false
	theme.set_stylebox("separator", "HSeparator", sep)
	var vsep := StyleBoxLine.new()
	vsep.color = BORDER_GOLD_SOFT
	vsep.thickness = 1
	vsep.vertical = true
	theme.set_stylebox("separator", "VSeparator", vsep)
	# --- ScrollBar ---
	var scroll_bg := _flat_sb(Color(0.06, 0.07, 0.09, 0.9), Color(0, 0, 0, 0), 0, 4, 0, 0)
	var scroll_grab := _flat_sb(Color(0.35, 0.30, 0.18, 0.9), BORDER_GOLD_SOFT, 1, 4, 0, 0)
	theme.set_stylebox("scroll", "VScrollBar", scroll_bg)
	theme.set_stylebox("grabber", "VScrollBar", scroll_grab)
	theme.set_stylebox("grabber_highlight", "VScrollBar",
		_flat_sb(Color(0.55, 0.45, 0.22, 0.95), BORDER_GOLD, 1, 4, 0, 0))
	theme.set_stylebox("grabber_pressed", "VScrollBar",
		_flat_sb(Color(0.65, 0.52, 0.25, 1), BORDER_GOLD, 1, 4, 0, 0))
	theme.set_stylebox("scroll", "HScrollBar", scroll_bg)
	theme.set_stylebox("grabber", "HScrollBar", scroll_grab)
	# --- TooltipPanel ---
	var tip := _flat_sb(Color(0.08, 0.09, 0.12, 0.97), BORDER_GOLD, 1, 6, 10, 8)
	tip.shadow_size = 6
	theme.set_stylebox("panel", "TooltipPanel", tip)
	theme.set_color("font_color", "TooltipLabel", TEXT_PRIMARY)
	theme.set_font_size("font_size", "TooltipLabel", FONT_CAPTION)


# ---- 入场/强调动效 (Anima 插件, addons/anima) ----
#
# 模态面板/对话框统一入场。两档:
#   popin(panel)   — zoom_in 0.25s,用于结算/确认等"重"弹窗
#   fadein(panel)  — fade_in 0.18s,用于面板切换等"轻"过渡
# single_shot:AnimaNode 播完自毁,不留孤儿;headless(GUT)下同样可跑。
static func popin(panel: Node) -> void:
	if panel == null or not panel.is_inside_tree():
		return
	# zoom_in 动画不自带 pivot,Control 默认从左上角缩放 — 手动设中心
	if panel is Control:
		(panel as Control).pivot_offset = (panel as Control).size / 2.0
	Anima.begin_single_shot(panel).then(
		Anima.Node(panel).anima_animation("zoom_in", 0.25)
	).play()


static func fadein(panel: Node) -> void:
	if panel == null or not panel.is_inside_tree():
		return
	Anima.begin_single_shot(panel).then(
		Anima.Node(panel).anima_animation("fade_in", 0.18)
	).play()


# 强调动效:对已可见节点播 attention seeker(pulse / tada / shake_x /
# heartbeat / flash ...,详见 addons/anima/animations/attention_seeker)。
# 役満结算 tada、放铳面板 shake_x、关键按钮 pulse 都走这里。
static func attention(node: Node, anim: String = "pulse",
		duration: float = 0.5, delay: float = 0.0) -> void:
	if node == null or not node.is_inside_tree():
		return
	var anima_node := Anima.begin_single_shot(node).then(
		Anima.Node(node).anima_animation(anim, duration)
	)
	if delay > 0.0:
		anima_node.play_with_delay(delay)
	else:
		anima_node.play()


# 一组同级节点错峰入场(奖励卡/商店槽位)。nodes 须已 add 进同一父节点。
static func stagger_in(nodes: Array, anim: String = "fade_in_up",
		duration: float = 0.3, item_delay: float = 0.06) -> void:
	if nodes.is_empty():
		return
	var first = nodes[0]
	if not (first is Node) or not (first as Node).is_inside_tree():
		return
	Anima.begin_single_shot((first as Node).get_parent()).then(
		Anima.Nodes(nodes, item_delay).anima_animation(anim, duration)
	).play()
