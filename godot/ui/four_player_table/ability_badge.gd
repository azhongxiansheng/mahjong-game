extends Control

const ICON_RESOLVER := preload("res://ui/four_player_table/table_icon_resolver.gd")

var _icon: TextureRect
var _name_label: Label
var _state_label: Label
var _affinity_icons: Array = []


func _ready() -> void:
	name = "AbilityBadge"
	position = Vector2(1152.0, 8.0)
	size = Vector2(216.0, 48.0)
	custom_minimum_size = size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	set_view({})


func set_view(view: Dictionary) -> void:
	if _icon == null:
		return
	var path := String(view.get("icon_path", ICON_RESOLVER.UNKNOWN_ICON))
	_icon.texture = ICON_RESOLVER.texture(path)
	_name_label.text = String(view.get("display_name", "角色技能"))
	_state_label.text = String(view.get("state_label", "未配置"))
	var affinity_paths: Array = view.get("affinity_icon_paths", [])
	for i in range(_affinity_icons.size()):
		var affinity_icon: TextureRect = _affinity_icons[i]
		affinity_icon.texture = ICON_RESOLVER.texture(String(affinity_paths[i])) \
			if i < affinity_paths.size() else null
	tooltip_text = String(view.get("description", "等待真实角色视图"))


func _build() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.14, 0.94)
	style.border_color = Color(0.83, 0.50, 0.88, 0.9)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 5
	style.content_margin_right = 7
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)
	_icon = TextureRect.new()
	_icon.name = "AbilityIcon"
	_icon.custom_minimum_size = Vector2(40, 40)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_icon)
	var labels := VBoxContainer.new()
	labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	labels.add_theme_constant_override("separation", 0)
	row.add_child(labels)
	_name_label = Label.new()
	_name_label.name = "AbilityName"
	_name_label.add_theme_font_size_override("font_size", 13)
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	labels.add_child(_name_label)
	var state_row := HBoxContainer.new()
	state_row.add_theme_constant_override("separation", 3)
	labels.add_child(state_row)
	_state_label = Label.new()
	_state_label.name = "AbilityStateLabel"
	_state_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_state_label.add_theme_font_size_override("font_size", 11)
	_state_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.42))
	state_row.add_child(_state_label)
	for i in range(2):
		var affinity_icon := TextureRect.new()
		affinity_icon.name = "AffinityIcon%d" % i
		affinity_icon.custom_minimum_size = Vector2(14, 14)
		affinity_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		affinity_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		affinity_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		state_row.add_child(affinity_icon)
		_affinity_icons.append(affinity_icon)
