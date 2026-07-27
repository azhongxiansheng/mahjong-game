extends Control

const ICON_RESOLVER := preload("res://ui/four_player_table/table_icon_resolver.gd")

var _icon: TextureRect
var _state_mark: Label
var _affinity_icons: Array = []


func _ready() -> void:
	name = "AbilityBadge"
	position = Vector2(1480.0, 8.0)
	size = Vector2(48.0, 48.0)
	custom_minimum_size = size
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	set_view({})


func set_view(view: Dictionary) -> void:
	if _icon == null:
		return
	var path := String(view.get("icon_path", ICON_RESOLVER.UNKNOWN_ICON))
	_icon.texture = ICON_RESOLVER.texture(path)
	var state := String(view.get("state", "disabled"))
	_state_mark.text = "武" if state == "armed" else ("常" if state == "passive" else "停")
	var affinity_paths: Array = view.get("affinity_icon_paths", [])
	for i in range(_affinity_icons.size()):
		var affinity_icon: TextureRect = _affinity_icons[i]
		affinity_icon.texture = ICON_RESOLVER.texture(String(affinity_paths[i])) \
			if i < affinity_paths.size() else null
	var name := String(view.get("display_name", "角色技能"))
	var state_label := String(view.get("state_label", "未配置"))
	var description := String(view.get("description", "等待真实角色视图"))
	tooltip_text = "%s · %s\n%s" % [name, state_label, description]


func _build() -> void:
	_icon = TextureRect.new()
	_icon.name = "AbilityIcon"
	_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon)

	for i in range(2):
		var affinity_icon := TextureRect.new()
		affinity_icon.name = "AffinityIcon%d" % i
		affinity_icon.position = Vector2(2.0 + i * 11.0, 36.0)
		affinity_icon.size = Vector2(10.0, 10.0)
		affinity_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		affinity_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		affinity_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(affinity_icon)
		_affinity_icons.append(affinity_icon)

	_state_mark = Label.new()
	_state_mark.name = "AbilityStateMark"
	_state_mark.position = Vector2(31.0, 30.0)
	_state_mark.size = Vector2(16.0, 16.0)
	_state_mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_state_mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_state_mark.add_theme_font_size_override("font_size", 10)
	_state_mark.add_theme_color_override("font_color", Color.WHITE)
	var mark_style := StyleBoxFlat.new()
	mark_style.bg_color = Color(0.12, 0.08, 0.18, 0.92)
	mark_style.border_color = Color(0.92, 0.65, 0.30, 0.9)
	mark_style.set_border_width_all(1)
	mark_style.set_corner_radius_all(8)
	_state_mark.add_theme_stylebox_override("normal", mark_style)
	_state_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_state_mark)
