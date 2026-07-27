extends Control

const ICON_RESOLVER := preload("res://ui/four_player_table/table_icon_resolver.gd")

signal use_item_requested(item_instance_id: String)
signal close_requested()

const DRAWER_X := 1384.0
const DRAWER_Y := 456.0
const DRAWER_W := 200.0
const DRAWER_H := 312.0
const PANEL_PADDING_Y := 12.0
const HEADER_H := 24.0
const CELL_H := 64.0
const GRID_GAP_Y := 5.0
const ACTION_H := 28.0
const MAX_SCROLL_H := 204.0

var _panel: PanelContainer
var _scroll: ScrollContainer
var _grid: GridContainer
var _title: Label
var _empty: Label
var _use_selected_btn: Button
var _rows_by_id: Dictionary = {}
var _selected_iid := ""
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
	for child in _grid.get_children():
		child.queue_free()
	_rows_by_id.clear()
	_selected_iid = ""
	_use_selected_btn.visible = false
	_use_selected_btn.disabled = true
	var valid_count := 0
	for raw in rows:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = raw
		var iid := String(row.get("item_instance_id", "")).strip_edges()
		if iid.is_empty():
			continue
		var cell := _make_cell(row)
		_grid.add_child(cell)
		_rows_by_id[iid] = cell
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
	close_btn.focus_mode = Control.FOCUS_NONE
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
	_grid = GridContainer.new()
	_grid.name = "InstanceGrid"
	_grid.columns = 3
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 5)
	_scroll.add_child(_grid)

	_empty = Label.new()
	_empty.name = "EmptyLabel"
	_empty.text = "暂无道具"
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.add_theme_font_size_override("font_size", 12)
	_empty.add_theme_color_override("font_color", DT.TEXT_MUTED)
	layout.add_child(_empty)

	_use_selected_btn = Button.new()
	_use_selected_btn.name = "UseSelectedButton"
	_use_selected_btn.text = "使用所选道具"
	_use_selected_btn.focus_mode = Control.FOCUS_NONE
	_use_selected_btn.custom_minimum_size = Vector2(0, 28)
	_use_selected_btn.visible = false
	_use_selected_btn.disabled = true
	_use_selected_btn.pressed.connect(_use_selected)
	layout.add_child(_use_selected_btn)


func _make_cell(row: Dictionary) -> PanelContainer:
	var iid := String(row.get("item_instance_id", ""))
	var item_id := String(row.get("item_id", ""))
	var display_name := String(row.get("display_name", item_id))
	var effect := String(row.get("effect_summary", row.get("description", "")))
	var status := String(row.get("status", ItemInstance.STATUS_HELD))
	var cell := PanelContainer.new()
	cell.name = "Row_%s" % iid
	cell.custom_minimum_size = Vector2(54, 64)
	cell.set_meta("row", row.duplicate(true))
	cell.add_theme_stylebox_override("panel", _cell_style(false))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	cell.add_child(column)
	var item_button := Button.new()
	item_button.name = "ItemButton"
	item_button.icon = ICON_RESOLVER.texture(String(row.get(
		"icon_path", ICON_RESOLVER.item_icon_path(item_id))))
	item_button.expand_icon = true
	item_button.add_theme_constant_override("icon_max_width", 44)
	item_button.custom_minimum_size = Vector2(52, 48)
	item_button.focus_mode = Control.FOCUS_NONE
	var details := PackedStringArray([display_name])
	if not effect.is_empty():
		details.append(effect)
	details.append(_state_label(status, item_id))
	details.append("实例：%s" % iid)
	item_button.tooltip_text = "\n".join(details)
	item_button.pressed.connect(func() -> void: _select_instance(iid))
	column.add_child(item_button)
	var state_mark := Label.new()
	state_mark.name = "StateLabel"
	state_mark.text = _state_short(status, item_id)
	state_mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	state_mark.add_theme_font_size_override("font_size", 10)
	state_mark.add_theme_color_override("font_color", DT.TEXT_TITLE)
	column.add_child(state_mark)
	return cell


func _select_instance(iid: String) -> void:
	if not _rows_by_id.has(iid):
		return
	_selected_iid = iid
	for key in _rows_by_id:
		var cell: PanelContainer = _rows_by_id[key] as PanelContainer
		cell.add_theme_stylebox_override("panel", _cell_style(String(key) == iid))
	var selected: PanelContainer = _rows_by_id[iid] as PanelContainer
	var row: Dictionary = selected.get_meta("row", {}) as Dictionary
	var usable := can_request_use(row)
	_use_selected_btn.visible = usable
	_use_selected_btn.disabled = not usable
	_sync_panel_height()


func _use_selected() -> void:
	if _selected_iid.is_empty() or not _rows_by_id.has(_selected_iid):
		return
	var cell: PanelContainer = _rows_by_id[_selected_iid] as PanelContainer
	var row: Dictionary = cell.get_meta("row", {}) as Dictionary
	if can_request_use(row):
		use_item_requested.emit(_selected_iid)


func _sync_panel_height() -> void:
	if _panel == null or _scroll == null or _use_selected_btn == null:
		return
	var row_count := ceili(float(_visible_count) / float(_grid.columns))
	var grid_h := 0.0
	if row_count > 0:
		grid_h = row_count * CELL_H + (row_count - 1) * GRID_GAP_Y
	_scroll.visible = _visible_count > 0
	_scroll.custom_minimum_size.y = minf(grid_h, MAX_SCROLL_H)
	var content_h := PANEL_PADDING_Y + HEADER_H
	content_h += GRID_GAP_Y + (grid_h if _visible_count > 0 else 16.0)
	if _use_selected_btn.visible:
		content_h += GRID_GAP_Y + ACTION_H
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


static func _state_short(status: String, item_id: String) -> String:
	var definition := ItemCatalog.definition(StringName(item_id))
	if definition != null and definition.is_relic():
		return "遗"
	match status:
		ItemInstance.STATUS_HELD:
			return "可"
		ItemInstance.STATUS_ARMED:
			return "武"
	return "禁"


static func _state_label(status: String, item_id: String) -> String:
	var definition := ItemCatalog.definition(StringName(item_id))
	if definition != null and definition.is_relic():
		return "常驻遗物"
	match status:
		ItemInstance.STATUS_HELD:
			return "可使用"
		ItemInstance.STATUS_ARMED:
			return "已武装"
		"consumed":
			return "已消耗"
	return "不可使用"
