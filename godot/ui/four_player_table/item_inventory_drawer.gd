extends Control

# E5-06 / #254：本席库存右侧按需抽屉（可滚动，无容量上限）。
# 几何：x=1160..1584, y=96..786。默认关闭。
# 无全局 class_name。使用精确 item_instance_id 发起 ITEM_USE。

signal use_item_requested(item_instance_id: String)
signal close_requested()

# 约 x=1160..1584、y=96..776：底边停在自家手牌带（y≈778）之上，
# 右侧可压 seat1 字幕槽（按需抽屉打开时）；不挡行动栏/PTT。
const DRAWER_X := 1160.0
const DRAWER_Y := 96.0
const DRAWER_W := 424.0
const DRAWER_H := 680.0

var _scroll: ScrollContainer = null
var _list: VBoxContainer = null
var _title: Label = null
var _empty: Label = null
var _rows_by_id: Dictionary = {}


func _ready() -> void:
	name = "ItemInventoryDrawer"
	position = Vector2(DRAWER_X, DRAWER_Y)
	size = Vector2(DRAWER_W, DRAWER_H)
	custom_minimum_size = Vector2(DRAWER_W, DRAWER_H)
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
	# 清空列表
	for c in _list.get_children():
		c.queue_free()
	_rows_by_id.clear()
	if rows.is_empty():
		_empty.visible = true
		_title.text = "库存 0"
		return
	_empty.visible = false
	_title.text = "库存 %d" % rows.size()
	for raw in rows:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = raw
		var iid := String(row.get("item_instance_id", "")).strip_edges()
		if iid.is_empty():
			continue
		var panel := _make_row(row)
		_list.add_child(panel)
		_rows_by_id[iid] = panel


func row_ids() -> Array:
	var ids: Array = _rows_by_id.keys()
	ids.sort()
	return ids


## 与 ItemAuthority.use_item 门控对齐：仅 held 战斗消耗品可 USE；armed/遗物禁用。
static func can_request_use(row: Dictionary) -> bool:
	if row.is_empty():
		return false
	var status := String(row.get("status", "")).strip_edges()
	if status != ItemInstance.STATUS_HELD:
		return false
	var item_id := String(row.get("item_id", "")).strip_edges()
	if item_id.is_empty():
		return false
	if ItemInventoryModule.is_relic_item(item_id):
		return false
	if not ItemInventoryModule.is_battle_consumable(item_id):
		return false
	# 与 ItemAuthority 一致：无稳定语义的 Alpha 非发放 ID
	if item_id == "seat_swap_v1" or item_id == "tsubame_v1":
		return false
	if not ItemInventoryModule.is_grantable(item_id) \
			and not ItemInventoryModule.is_battle_consumable(item_id):
		return false
	return true


func has_full_instance_id_accessible(item_instance_id: String) -> bool:
	var iid := item_instance_id.strip_edges()
	if iid.is_empty() or not _rows_by_id.has(iid):
		return false
	var panel: Control = _rows_by_id[iid] as Control
	if panel == null:
		return false
	var inst_l: Label = panel.find_child("InstanceIdLabel", true, false) as Label
	if inst_l == null:
		return false
	# tooltip 或完整文本含完整 id
	if String(inst_l.tooltip_text) == iid:
		return true
	if String(inst_l.text).contains(iid):
		return true
	return false


func _build() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.09, 0.08, 0.96)
	style.border_color = DT.BORDER_GOLD
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8

	var root := PanelContainer.new()
	root.name = "DrawerPanel"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_stylebox_override("panel", style)
	add_child(root)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	root.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	vbox.add_child(header)

	_title = Label.new()
	_title.name = "DrawerTitle"
	_title.text = "库存 0"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_font_size_override("font_size", DT.FONT_CAPTION)
	_title.add_theme_color_override("font_color", DT.TEXT_TITLE)
	header.add_child(_title)

	var close_btn := Button.new()
	close_btn.name = "CloseButton"
	close_btn.text = "关闭"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.custom_minimum_size = Vector2(64, 28)
	close_btn.pressed.connect(func():
		close_drawer()
		close_requested.emit()
	)
	header.add_child(close_btn)

	_scroll = ScrollContainer.new()
	_scroll.name = "ScrollContainer"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(_scroll)

	_list = VBoxContainer.new()
	_list.name = "InstanceList"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	_scroll.add_child(_list)

	_empty = Label.new()
	_empty.name = "EmptyLabel"
	_empty.text = "本席暂无道具"
	_empty.add_theme_font_size_override("font_size", DT.FONT_CAPTION)
	_empty.add_theme_color_override("font_color", DT.TEXT_MUTED)
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_empty)


func _make_row(row: Dictionary) -> PanelContainer:
	var iid := String(row.get("item_instance_id", ""))
	var item_id := String(row.get("item_id", ""))
	var display_name := String(row.get("display_name", item_id))
	var status := String(row.get("status", "held"))
	var effect := String(row.get("effect_summary", row.get("description", "")))
	var affinity := bool(row.get("affinity_match", false))
	var armed_for = row.get("armed_for_window_id", null)

	var panel := PanelContainer.new()
	panel.name = "Row_%s" % iid
	var ss := StyleBoxFlat.new()
	ss.bg_color = Color(0.08, 0.11, 0.10, 0.95)
	ss.border_color = DT.BORDER_GOLD_SOFT
	ss.set_border_width_all(1)
	ss.set_corner_radius_all(6)
	ss.content_margin_left = 8
	ss.content_margin_right = 8
	ss.content_margin_top = 6
	ss.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", ss)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	panel.add_child(v)

	var name_l := Label.new()
	name_l.text = display_name
	name_l.add_theme_font_size_override("font_size", 14)
	name_l.add_theme_color_override("font_color", DT.TEXT_PRIMARY)
	v.add_child(name_l)

	var id_l := Label.new()
	id_l.text = "id: %s" % item_id
	id_l.add_theme_font_size_override("font_size", 11)
	id_l.add_theme_color_override("font_color", DT.TEXT_MUTED)
	id_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(id_l)

	var inst_l := Label.new()
	inst_l.name = "InstanceIdLabel"
	inst_l.text = "instance: %s" % iid
	inst_l.tooltip_text = iid  # 完整 item_instance_id 可悬停查看
	inst_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inst_l.add_theme_font_size_override("font_size", 10)
	inst_l.add_theme_color_override("font_color", DT.TEXT_MUTED)
	# 不使用 TRIM_ELLIPSIS 截断权威 identity
	inst_l.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	v.add_child(inst_l)

	if not effect.is_empty():
		var eff_l := Label.new()
		eff_l.text = effect
		eff_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		eff_l.add_theme_font_size_override("font_size", 11)
		eff_l.add_theme_color_override("font_color", DT.TEXT_PRIMARY)
		v.add_child(eff_l)

	var status_parts: PackedStringArray = PackedStringArray()
	status_parts.append(status)
	if affinity:
		status_parts.append("affinity")
	if armed_for != null and String(armed_for) != "":
		status_parts.append("armed→%s" % String(armed_for))
	var st_l := Label.new()
	st_l.text = " · ".join(status_parts)
	st_l.add_theme_font_size_override("font_size", 11)
	st_l.add_theme_color_override("font_color", DT.TEXT_TITLE)
	v.add_child(st_l)

	var use_btn := Button.new()
	use_btn.name = "UseButton"
	use_btn.text = "使用"
	use_btn.focus_mode = Control.FOCUS_NONE
	use_btn.disabled = not can_request_use(row)
	use_btn.custom_minimum_size = Vector2(72, 28)
	var captured := iid
	use_btn.pressed.connect(func():
		if can_request_use(row):
			use_item_requested.emit(captured)
	)
	v.add_child(use_btn)

	return panel
