class_name TileStamp extends Panel

# 麻将王 — 里程碑 3 第 3 步：技能印章 + tooltip（plan-3 D5）
#
# 16×16 px 圆形印章，仅 `tile_instance.skill != null` 时显示；
# 颜色按 `skill.rarity ∈ [0,3]` 取灰/蓝/紫/金（spec §9.1 稀有度）。
# hover tooltip 显示 skill id / display_name / description / triggers。

const STAMP_SIZE: int = 16
const STAMP_CORNER_RADIUS: int = 8

# spec §9.1：4 档稀有度色
const RARITY_COLORS: Array[Color] = [
	Color(0.55, 0.55, 0.55),  # 0 普通 灰
	Color(0.30, 0.55, 0.85),  # 1 精良 蓝
	Color(0.65, 0.30, 0.85),  # 2 史诗 紫
	Color(1.00, 0.80, 0.20),  # 3 神话 金
]

const UNKNOWN_RARITY_COLOR: Color = Color(0.20, 0.20, 0.20)

var _skill: SkillResource = null

func _init() -> void:
	custom_minimum_size = Vector2(STAMP_SIZE, STAMP_SIZE)
	size = Vector2(STAMP_SIZE, STAMP_SIZE)
	mouse_filter = Control.MOUSE_FILTER_PASS  # 让 tooltip 工作

func _ready() -> void:
	_refresh()

# ---- public setters ----

func set_skill(skill: SkillResource) -> void:
	_skill = skill
	if is_inside_tree():
		_refresh()

# ---- helpers (static, 测试可用) ----

static func rarity_color(rarity: int) -> Color:
	if rarity < 0 or rarity >= RARITY_COLORS.size():
		return UNKNOWN_RARITY_COLOR
	return RARITY_COLORS[rarity]

static func rarity_label(rarity: int) -> String:
	match rarity:
		0: return "普通"
		1: return "精良"
		2: return "史诗"
		3: return "神话"
	return "?"

# 把 skill 转成 tooltip 文本（多行）
static func format_tooltip(skill: SkillResource) -> String:
	if skill == null:
		return ""
	var lines: Array[String] = []
	var name_str: String = skill.display_name if skill.display_name != "" else String(skill.id)
	lines.append("【%s】" % name_str)
	lines.append("id: %s" % String(skill.id))
	lines.append("稀有度: %s" % rarity_label(skill.rarity))
	if skill.description != "":
		lines.append(skill.description)
	var triggers: Array[String] = []
	for t in skill.owner_triggers:
		triggers.append("owner@%s" % String(t))
	for t in skill.holder_triggers:
		triggers.append("holder@%s" % String(t))
	if triggers.size() > 0:
		lines.append("触发: " + ", ".join(triggers))
	if skill.is_ability:
		lines.append("(角色能力)")
	return "\n".join(lines)

# ---- internal ----

func _refresh() -> void:
	if _skill == null:
		visible = false
		tooltip_text = ""
		return
	visible = true
	tooltip_text = format_tooltip(_skill)

	var sb := StyleBoxFlat.new()
	sb.bg_color = rarity_color(_skill.rarity)
	sb.corner_radius_top_left = STAMP_CORNER_RADIUS
	sb.corner_radius_top_right = STAMP_CORNER_RADIUS
	sb.corner_radius_bottom_left = STAMP_CORNER_RADIUS
	sb.corner_radius_bottom_right = STAMP_CORNER_RADIUS
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_color = Color.BLACK
	add_theme_stylebox_override("panel", sb)
