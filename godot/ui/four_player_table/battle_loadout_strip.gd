class_name BattleLoadoutStrip extends HBoxContainer

# 对局内 loadout 芯片条 — 轻量展示角色能力 / 遗物 / 消耗品，不挤桌面。
# 挂在 PlayableTable 顶栏下；点击芯片弹出简短 tooltip 描述。

const CHIP_H: float = 36.0
const ICON_SIZE: int = 28


static func build_entries(ability_ids: Array, relic_ids: Array, consumable_ids: Array) -> Array:
	var entries: Array = []
	for raw in ability_ids:
		var aid: StringName = raw if raw is StringName else StringName(str(raw))
		var card: AbilityCard = _find_ability(aid)
		var name_str: String = card.display_name if card and card.display_name != "" else String(aid)
		var desc: String = card.description if card else ""
		var icon: String = card.resolved_icon_path() if card else ""
		entries.append({
			"kind": "ability",
			"id": String(aid),
			"name": name_str,
			"description": desc,
			"icon_path": icon,
			"accent": Color(0.85, 0.65, 0.25),
		})
	for raw in relic_ids:
		var rid: StringName = raw if raw is StringName else StringName(str(raw))
		var relic: RelicItem = _find_relic(rid)
		var rname: String = relic.display_name if relic and relic.display_name != "" else String(rid)
		var rdesc: String = relic.description if relic else ""
		var ricon: String = relic.resolved_icon_path() if relic else RelicItem.default_icon_path(rid)
		entries.append({
			"kind": "relic",
			"id": String(rid),
			"name": rname,
			"description": rdesc,
			"icon_path": ricon,
			"accent": Color(0.45, 0.70, 0.95),
		})
	for raw in consumable_ids:
		var cid: StringName = raw if raw is StringName else StringName(str(raw))
		var cons: ConsumableItem = _find_consumable(cid)
		var cname: String = cons.display_name if cons and cons.display_name != "" else String(cid)
		var cdesc: String = cons.description if cons else ""
		var cicon: String = cons.resolved_icon_path() if cons else ConsumableItem.default_icon_path(cid)
		entries.append({
			"kind": "consumable",
			"id": String(cid),
			"name": cname,
			"description": cdesc,
			"icon_path": cicon,
			"accent": Color(0.95, 0.55, 0.25),
		})
	return entries


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	mouse_filter = Control.MOUSE_FILTER_STOP


func bind_entries(entries: Array) -> void:
	for child in get_children():
		child.queue_free()
	for e in entries:
		add_child(_make_chip(e))


func bind_ids(ability_ids: Array, relic_ids: Array, consumable_ids: Array) -> void:
	bind_entries(build_entries(ability_ids, relic_ids, consumable_ids))


func _make_chip(entry: Dictionary) -> Control:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, CHIP_H)
	btn.focus_mode = Control.FOCUS_NONE
	var accent: Color = entry.get("accent", DT.TEXT_TITLE)
	var name_str: String = str(entry.get("name", "?"))
	# 短名：最多 4 字，过长截断
	var short: String = name_str
	if short.length() > 4:
		short = short.substr(0, 4)
	btn.text = short
	btn.add_theme_font_size_override("font_size", DT.FONT_CAPTION)
	btn.tooltip_text = "%s\n%s" % [name_str, str(entry.get("description", ""))]
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.08, 0.09, 0.12, 0.92)
		sb.border_color = accent
		sb.border_width_left = 2
		sb.border_width_top = 2
		sb.border_width_right = 2
		sb.border_width_bottom = 2
		sb.corner_radius_top_left = 6
		sb.corner_radius_top_right = 6
		sb.corner_radius_bottom_left = 6
		sb.corner_radius_bottom_right = 6
		sb.content_margin_left = 6
		sb.content_margin_right = 8
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		if state == "hover":
			sb.bg_color = Color(0.14, 0.15, 0.20, 0.95)
		btn.add_theme_stylebox_override(state, sb)
	var icon_path: String = str(entry.get("icon_path", ""))
	if icon_path != "" and ResourceLoader.exists(icon_path):
		var tex := load(icon_path) as Texture2D
		if tex:
			btn.icon = tex
			btn.expand_icon = true
			btn.add_theme_constant_override("icon_max_width", ICON_SIZE)
	return btn


static func _find_ability(aid: StringName) -> AbilityCard:
	for a in CardPool.all_abilities():
		if a.id == aid:
			return a
	return null


static func _find_relic(rid: StringName) -> RelicItem:
	for r in CardPool.all_relics():
		if r.id == rid:
			return r
	return null


static func _find_consumable(cid: StringName) -> ConsumableItem:
	for c in CardPool.all_consumables():
		if c.id == cid:
			return c
	return null
