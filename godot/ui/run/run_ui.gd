class_name RunUi

# 肉鸽流程共享 UI helper。
#
# attach_background：给 run-flow 面板铺暗色麻将桌氛围背景 + 暗角。
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
	if root == null:
		return
	# 1) 氛围图
	if ResourceLoader.exists(RUN_BG_PATH):
		var tex := load(RUN_BG_PATH) as Texture2D
		if tex != null:
			var bg := TextureRect.new()
			bg.name = "RunBgArt"
			bg.texture = tex
			bg.set_anchors_preset(Control.PRESET_FULL_RECT)
			bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
			root.add_child(bg)
			# 盖住 .tscn 第 0 纯色 Bg，仍在内容之下
			root.move_child(bg, 1 if root.get_child_count() > 1 else 0)
	# 2) 暗角：上下两条半透明条 + 全屏轻暗，让文字可读、焦点落中
	if root.get_node_or_null("RunVignette") != null:
		return
	var vig := Control.new()
	vig.name = "RunVignette"
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var wash := ColorRect.new()
	wash.color = Color(0.02, 0.03, 0.05, 0.35)
	wash.set_anchors_preset(Control.PRESET_FULL_RECT)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vig.add_child(wash)
	var top := ColorRect.new()
	top.color = Color(0.02, 0.03, 0.05, 0.55)
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 90
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vig.add_child(top)
	var bot := ColorRect.new()
	bot.color = Color(0.02, 0.03, 0.05, 0.50)
	bot.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bot.offset_top = -100
	bot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vig.add_child(bot)
	root.add_child(vig)
	# 尽量贴在背景之后、内容之前
	var insert_at: int = 0
	for i in range(root.get_child_count()):
		var ch: Node = root.get_child(i)
		if ch.name == "RunBgArt" or ch.name == "DtBg" or ch.name == "Bg":
			insert_at = i + 1
	root.move_child(vig, mini(insert_at, root.get_child_count() - 1))


# 物品/奖励/商店统一卡面：大 icon + 稀有度色晕顶条 + 名称 + 描述区
# 返回 PanelContainer；caller 可再塞底部按钮。
static func make_item_card_shell(
		card_size: Vector2,
		border_color: Color,
		icon_path: String,
		title: String,
		subtitle: String,
		body: String,
		icon_size: int = 96,
) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = card_size
	panel.add_theme_stylebox_override("panel", DT.make_card_stylebox(border_color, "normal"))

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", DT.GAP_TIGHT)
	panel.add_child(vbox)

	# 顶条稀有度色晕
	var stripe := ColorRect.new()
	stripe.custom_minimum_size = Vector2(0, 6)
	stripe.color = border_color
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(stripe)

	var icon := make_item_icon(icon_path, icon_size)
	if icon:
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vbox.add_child(icon)
	else:
		# 无图时用色块占位，避免卡片塌空
		var ph := ColorRect.new()
		ph.custom_minimum_size = Vector2(icon_size, icon_size)
		ph.color = Color(border_color.r, border_color.g, border_color.b, 0.25)
		ph.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(ph)

	var name_lbl := Label.new()
	name_lbl.name = "CardTitle"
	name_lbl.text = title
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.add_theme_font_size_override("font_size", DT.FONT_SUBTITLE)
	name_lbl.add_theme_color_override("font_color", border_color)
	vbox.add_child(name_lbl)

	if subtitle != "":
		var sub := Label.new()
		sub.name = "CardSubtitle"
		sub.text = subtitle
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		DT.apply_caption_style(sub)
		sub.add_theme_color_override("font_color", DT.TEXT_MUTED)
		vbox.add_child(sub)

	if body != "":
		var desc := Label.new()
		desc.name = "CardBody"
		desc.text = body
		desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		desc.add_theme_font_size_override("font_size", DT.FONT_CAPTION)
		desc.add_theme_color_override("font_color", DT.TEXT_PRIMARY)
		desc.custom_minimum_size = Vector2(0, 64)
		vbox.add_child(desc)

	return panel


# 起始包/角色卡顶部的大字头圆章（守/攻/速）
static func make_glyph_badge(glyph: String, accent: Color, diameter: float = 88.0) -> Control:
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(diameter, diameter)
	wrap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var disc := Panel.new()
	disc.set_anchors_preset(Control.PRESET_FULL_RECT)
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(accent.r * 0.25, accent.g * 0.25, accent.b * 0.25, 0.95)
	sb.border_color = accent
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(int(diameter / 2.0))
	sb.shadow_color = Color(accent.r, accent.g, accent.b, 0.35)
	sb.shadow_size = 10
	disc.add_theme_stylebox_override("panel", sb)
	wrap.add_child(disc)
	var lbl := Label.new()
	lbl.text = glyph
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 40)
	lbl.add_theme_color_override("font_color", accent)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(lbl)
	return wrap
