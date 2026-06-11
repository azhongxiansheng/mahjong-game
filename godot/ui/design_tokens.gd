class_name DesignTokens extends Node

# 设计系统单一来源 — 字号/颜色/间距/尺寸常量,所有 UI 都引用 DT.*。
# Autoload 名: DT (project.godot [autoload])。
#
# 改动这里 = 一处改全局生效,避免 9+ 处近似金色 / 13+ 种背景色 / 字号
# 14~36 七档不规范 的乱象。新增 UI 严禁硬编码颜色/字号,必须走 DT。

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
	# 描边 stylebox — 显式构建暗底,不能 duplicate 主题 base:
	# 主题已是 StyleBoxTexture,强转 StyleBoxFlat 得 null → 默认亮灰底
	var state_bg := {
		"normal": Color(0.13, 0.12, 0.15, 0.97),
		"hover": Color(0.20, 0.17, 0.20, 0.97),
		"pressed": Color(0.26, 0.14, 0.16, 0.97),
		"focus": Color(0.20, 0.17, 0.20, 0.97),
		"disabled": Color(0.10, 0.10, 0.11, 0.9),
	}
	for state in state_bg:
		var sb := StyleBoxFlat.new()
		sb.bg_color = state_bg[state]
		sb.border_color = border_color
		sb.border_width_left = 3
		sb.border_width_top = 3
		sb.border_width_right = 3
		sb.border_width_bottom = 3
		sb.corner_radius_top_left = 4
		sb.corner_radius_top_right = 4
		sb.corner_radius_bottom_left = 4
		sb.corner_radius_bottom_right = 4
		btn.add_theme_stylebox_override(state, sb)
	# 内嵌 Label
	var lbl := Label.new()
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
