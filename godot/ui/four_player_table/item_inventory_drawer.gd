extends Control

const ICON_RESOLVER := preload("res://ui/four_player_table/table_icon_resolver.gd")

signal use_item_requested(item_instance_id: String)
signal close_requested()

const DRAWER_X := 1384.0
const DRAWER_Y := 480.0
const DRAWER_W := 200.0
const DRAWER_H := 288.0
const PANEL_PADDING_Y := 12.0
const HEADER_H := 24.0
const ROW_H := 76.0
const ROW_GAP_Y := 4.0
const MAX_SCROLL_H := 229.0

var _panel: PanelContainer
var _scroll: ScrollContainer
var _list: VBoxContainer
var _title: Label
var _empty: Label
var _rows_by_id: Dictionary = {}
var _visible_count := 0


func _ready() -> void:
	name = "ItemInventoryDrawer"
	position = Vector2(DRAWER_X, DRAWER_Y)
	size = Vector2(DRAWER_W, DRAWER_H)
	custom_minimum_size = size
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func drawer_rect() -> Rect2:
	return Rect2(DRAWER_X, DRAWER_Y, DRAWER_W, DRAWER_H)


func scroll_container() -> ScrollContainer:
	return _scroll


func open_drawer() -> void:
	visible = true


func close_drawer() -> void:
	visible = false


func is_open() -> bool:
	return visible


func set_instances(rows: Array) -> void:
	for child in _list.get_children():
		child.queue_free()
	_rows_by_id.clear()
	var valid_count := 0
	for raw in rows:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = raw
		var iid := String(row.get("item_instance_id", "")).strip_edges()
		if iid.is_empty():
			continue
		var instance_row := _make_row(row)
		_list.add_child(instance_row)
		_rows_by_id[iid] = instance_row
		valid_count += 1
	_title.text = "库存 %d" % valid_count
	_empty.visible = valid_count == 0
	_visible_count = valid_count
	_sync_panel_height()


func row_ids() -> Array:
	var ids: Array = _rows_by_id.keys()
	ids.sort()
	return ids


## 与 ItemAuthority.use_item 门控对齐：仅 held 战斗消耗品可 USE；armed/遗物禁用。
static func can_request_use(row: Dictionary) -> bool:
	if row.is_empty():
		return false
	var status := String(row.get("status", "")).strip_edges()
	var item_id := String(row.get("item_id", "")).strip_edges()
	return not item_id.is_empty() \
		and ItemCatalog.can_use(StringName(item_id), status)


func has_full_instance_id_accessible(item_instance_id: String) -> bool:
	var iid := item_instance_id.strip_edges()
	if iid.is_empty() or not _rows_by_id.has(iid):
		return false
	var cell: Control = _rows_by_id[iid] as Control
	var item_button := cell.find_child("ItemButton", true, false) as Button
	return item_button != null and item_button.tooltip_text.contains(iid)


func select_instance(item_instance_id: String) -> void:
	_select_instance(item_instance_id)


func focus_first() -> void:
	var ids := row_ids()
	if ids.is_empty():
		return
	var row: Control = _rows_by_id[ids[0]] as Control
	var item_button := row.find_child("ItemButton", true, false) as Button
	if item_button != null:
		item_button.grab_focus()


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.name = "DrawerPanel"
	_panel.position = Vector2.ZERO
	_panel.size = Vector2(DRAWER_W, DRAWER_H)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.05, 0.07, 0.96)
	style.border_color = Color(0.72, 0.50, 0.24, 0.78)
	style.set_border_width_all(1)
	style.set_corner_radius_all(9)
	style.content_margin_left = 7
	style.content_margin_right = 7
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 5)
	_panel.add_child(layout)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	layout.add_child(header)
	_title = Label.new()
	_title.name = "DrawerTitle"
	_title.text = "库存 0"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_font_size_override("font_size", 13)
	header.add_child(_title)
	var close_btn := Button.new()
	close_btn.name = "CloseButton"
	close_btn.text = "×"
	close_btn.focus_mode = Control.FOCUS_ALL
	close_btn.custom_minimum_size = Vector2(28, 24)
	close_btn.pressed.connect(func() -> void:
		close_drawer()
		close_requested.emit()
	)
	header.add_child(close_btn)

	_scroll = ScrollContainer.new()
	_scroll.name = "ScrollContainer"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.name = "InstanceList"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", int(ROW_GAP_Y))
	_scroll.add_child(_list)

	_empty = Label.new()
	_empty.name = "EmptyLabel"
	_empty.text = "暂无道具"
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.add_theme_font_size_override("font_size", 12)
	_empty.add_theme_color_override("font_color", DT.TEXT_MUTED)
	layout.add_child(_empty)

func _make_row(row: Dictionary) -> PanelContainer:
	var iid := String(row.get("item_instance_id", ""))
	var item_id := String(row.get("item_id", ""))
	var display_name := String(row.get("display_name", item_id))
	var effect := String(row.get("effect_summary", row.get("description", "")))
	var status := String(row.get("status", ItemInstance.STATUS_HELD))
	var instance_row := PanelContainer.new()
	instance_row.name = "Row_%s" % iid
	instance_row.custom_minimum_size = Vector2(DRAWER_W - 14.0, ROW_H)
	instance_row.set_meta("row", row.duplicate(true))
	instance_row.add_theme_stylebox_override("panel", _cell_style(false))
	var row_layout := HBoxContainer.new()
	row_layout.add_theme_constant_override("separation", 4)
	instance_row.add_child(row_layout)
	var icon_column := VBoxContainer.new()
	icon_column.custom_minimum_size = Vector2(46.0, 0.0)
	icon_column.add_theme_constant_override("separation", 0)
	row_layout.add_child(icon_column)
	var item_button := Button.new()
	item_button.name = "ItemButton"
	item_button.icon = ICON_RESOLVER.texture(String(row.get(
		"icon_path", ICON_RESOLVER.item_icon_path(item_id))))
	item_button.expand_icon = true
	item_button.add_theme_constant_override("icon_max_width", 42)
	item_button.custom_minimum_size = Vector2(46, 48)
	item_button.focus_mode = Control.FOCUS_ALL
	var details := PackedStringArray([display_name])
	if not effect.is_empty():
		details.append(effect)
	details.append(_state_label(status, item_id))
	details.append(_affinity_label(row))
	details.append(_armed_label(row))
	details.append("item_id：%s" % item_id)
	details.append("instance_id：%s" % iid)
	item_button.tooltip_text = "\n".join(details)
	item_button.pressed.connect(func() -> void: _select_instance(iid))
	icon_column.add_child(item_button)
	var armed_label := Label.new()
	armed_label.name = "ArmedLabel"
	armed_label.text = _armed_label(row)
	armed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	armed_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	armed_label.add_theme_font_size_override("font_size", 10)
	armed_label.add_theme_color_override("font_color", DT.TEXT_TITLE)
	icon_column.add_child(armed_label)

	var details_column := VBoxContainer.new()
	details_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details_column.add_theme_constant_override("separation", 0)
	row_layout.add_child(details_column)
	var top_line := HBoxContainer.new()
	top_line.add_theme_constant_override("separation", 2)
	details_column.add_child(top_line)
	var name_label := Label.new()
	name_label.name = "ItemName"
	name_label.text = display_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", DT.TEXT_PRIMARY)
	top_line.add_child(name_label)
	var use_button := Button.new()
	use_button.name = "UseButton"
	use_button.text = "用" if can_request_use(row) else "锁"
	use_button.focus_mode = Control.FOCUS_ALL
	use_button.disabled = not can_request_use(row)
	use_button.custom_minimum_size = Vector2(30.0, 22.0)
	use_button.tooltip_text = "使用 %s" % display_name if can_request_use(row) \
		else "%s：%s" % [display_name, _state_label(status, item_id)]
	use_button.pressed.connect(func() -> void:
		_select_instance(iid)
		if can_request_use(row):
			use_item_requested.emit(iid)
	)
	top_line.add_child(use_button)
	var effect_label := Label.new()
	effect_label.name = "EffectSummary"
	effect_label.text = effect if not effect.is_empty() else "无效果摘要"
	effect_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	effect_label.add_theme_font_size_override("font_size", 11)
	effect_label.add_theme_color_override("font_color", DT.TEXT_PRIMARY)
	details_column.add_child(effect_label)
	var state_label := Label.new()
	state_label.name = "StateLabel"
	state_label.text = "状态：%s" % _state_label(status, item_id)
	state_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	state_label.add_theme_font_size_override("font_size", 11)
	state_label.add_theme_color_override("font_color", DT.TEXT_TITLE)
	details_column.add_child(state_label)
	var affinity_label := Label.new()
	affinity_label.name = "AffinityLabel"
	affinity_label.text = _affinity_label(row)
	affinity_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	affinity_label.add_theme_font_size_override("font_size", 11)
	affinity_label.add_theme_color_override("font_color", Color(0.91, 0.72, 0.43))
	details_column.add_child(affinity_label)
	return instance_row


func _select_instance(iid: String) -> void:
	if not _rows_by_id.has(iid):
		return
	for key in _rows_by_id:
		var cell: PanelContainer = _rows_by_id[key] as PanelContainer
		cell.add_theme_stylebox_override("panel", _cell_style(String(key) == iid))
	_sync_panel_height()


func _sync_panel_height() -> void:
	if _panel == null or _scroll == null:
		return
	var list_h := 0.0
	if _visible_count > 0:
		list_h = _visible_count * ROW_H + (_visible_count - 1) * ROW_GAP_Y
	_scroll.visible = _visible_count > 0
	_scroll.custom_minimum_size.y = minf(list_h, MAX_SCROLL_H)
	var content_h := PANEL_PADDING_Y + HEADER_H
	content_h += ROW_GAP_Y + (list_h if _visible_count > 0 else 16.0)
	_panel.custom_minimum_size = Vector2(DRAWER_W, minf(content_h, DRAWER_H))
	_panel.size = _panel.custom_minimum_size


static func _cell_style(selected: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.16, 0.10, 0.20, 0.72) if selected else Color.TRANSPARENT
	style.border_color = Color(0.95, 0.68, 0.30, 0.95) if selected \
		else Color(0.72, 0.50, 0.24, 0.24)
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	style.content_margin_left = 1
	style.content_margin_right = 1
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	return style


static func _state_label(status: String, item_id: String) -> String:
	var definition := ItemCatalog.definition(StringName(item_id))
	if definition != null and definition.is_relic():
		return "常驻遗物"
	match status:
		ItemInstance.STATUS_HELD:
			return "可用"
		ItemInstance.STATUS_ARMED:
			return "已武装"
		"consumed":
			return "已消耗"
	return "不可使用"


static func _affinity_label(row: Dictionary) -> String:
	var labels: Array = row.get("tag_labels", []) as Array
	var affinity := String(labels[0]) if not labels.is_empty() else "无属性"
	return "属性：%s · %s" % [
		affinity,
		"契合" if bool(row.get("affinity_match", false)) else "未契合",
	]


static func _armed_label(row: Dictionary) -> String:
	var armed_value: Variant = row.get("armed_for_window_id", null)
	var armed_for := "" if armed_value == null else String(armed_value)
	return "已武装" if String(row.get("status", "")) == ItemInstance.STATUS_ARMED \
		or not armed_for.is_empty() else "未武装"
