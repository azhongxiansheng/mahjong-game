class_name RunUi

# 肉鸽流程共享 UI helper。
#
# attach_background：给 run-flow 面板铺斗牌传说风氛围背景。面板根的第 0 个子
# 节点通常是一个纯色 Bg ColorRect —— 在它之后插一张 run_bg TextureRect 盖住，
# 内容节点（VBox 等）在 .tscn 中位于其后，仍渲染在背景之上。
# 背景资产缺失时静默跳过（不影响功能）。

const RUN_BG_PATH := "res://assets/run_bg.png"


# 在 VBox 顶部插一张 panel 头像图(节点种类图标),让 Camp/Event/Shop 等子面板
# 视觉风格与章节地图节点保持一致。资产缺失/参数无效时静默跳过。
static func attach_panel_icon(vbox: VBoxContainer, icon_path: String, icon_size: int = 96) -> void:
	if vbox == null or not ResourceLoader.exists(icon_path):
		return
	var tr := make_item_icon(icon_path, icon_size)
	if tr == null:
		return
	tr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(tr)
	vbox.move_child(tr, 0)


# 通用物品图标；资产缺失时返回 null（调用方决定 fallback）。
static func make_item_icon(icon_path: String, icon_size: int = 64) -> TextureRect:
	if icon_path == "" or not ResourceLoader.exists(icon_path):
		return null
	var tex := load(icon_path) as Texture2D
	if tex == null:
		return null
	var tr := TextureRect.new()
	tr.texture = tex
	tr.custom_minimum_size = Vector2(icon_size, icon_size)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


# 从 GachaResult 解析展示用 icon_path（遗物/消耗品优先；能力有则用）。
static func resolve_gacha_icon_path(r: GachaResult) -> String:
	if r == null:
		return ""
	if r.kind == GachaResult.KIND_RELIC and r.relic:
		return r.relic.resolved_icon_path()
	if r.kind == GachaResult.KIND_CONSUMABLE and r.consumable:
		return r.consumable.resolved_icon_path()
	if r.kind == GachaResult.KIND_ABILITY and r.ability:
		return r.ability.resolved_icon_path()
	return ""


static func attach_background(root: Control) -> void:
	if root == null or not ResourceLoader.exists(RUN_BG_PATH):
		return
	var tex := load(RUN_BG_PATH) as Texture2D
	if tex == null:
		return
	var bg := TextureRect.new()
	bg.name = "RunBgArt"
	bg.texture = tex
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	# 放到第 1 位：盖住 .tscn 里第 0 个的纯色 Bg，仍在内容节点之下。
	root.move_child(bg, 1 if root.get_child_count() > 1 else 0)
