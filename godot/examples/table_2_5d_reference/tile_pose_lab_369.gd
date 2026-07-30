extends Control

const STACK_GAP := 0.0
const TABLE_CLEARANCE := 0.0

var pose_tiles: Dictionary = {}


func _ready() -> void:
	custom_minimum_size = Vector2(1600, 900)
	size = Vector2(1600, 900)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_background()
	_build_header()
	var hero := _create_panel(Rect2(34, 122, 475, 742),
		"A｜一张牌，固定正反两面",
		"正面竖牌 +90° / 牌背 −90°　｜　桌面竖放\n"
		+ "横置 Yaw +90°　｜　盖牌 Flip X 180°")
	var wall := _create_panel(Rect2(529, 122, 504, 350),
		"B｜牌山与立直",
		"两层牌山：ΔY = 厚度（真实接触）　｜　立直横牌：Yaw +90°")
	var meld := _create_panel(Rect2(1053, 122, 513, 350),
		"C｜副露的物理关系",
		"吃 / 碰横置：Yaw +90°　｜　加杠上叠：同 XZ/Yaw\n"
		+ "暗杠盖牌：Flip X 180°　｜　层距 D（真实接触）")
	var compare := _create_panel(Rect2(529, 492, 1037, 372),
		"D｜只改变观察关系，不改变牌体",
		"四席旋转：0° / −90° / 180° / +90°　｜　近 / 中 / 远：Scale 均为 1")
	_build_hero(hero)
	_build_wall(wall)
	_build_meld(meld)
	_build_comparison(compare)


func _build_background() -> void:
	var background := ColorRect.new()
	background.name = "Background"
	background.position = Vector2.ZERO
	background.size = Vector2(1600, 900)
	background.color = Color("071516")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var top_rule := ColorRect.new()
	top_rule.position = Vector2(34, 105)
	top_rule.size = Vector2(1532, 1)
	top_rule.color = Color("967a48")
	background.add_child(top_rule)


func _build_header() -> void:
	_add_label(self, "#369｜统一单牌实体 · 姿态还原实验",
		Vector2(38, 20), Vector2(760, 42), 30, Color("f0e8d6"))
	_add_label(self,
		"统一实体 72 × 98 × 56 mm-equivalent　｜　日麻 28:21:16　｜　牌底 1/2 D",
		Vector2(40, 64), Vector2(1120, 28), 17, Color("b9cfc4"))
	var badge := _make_badge("青岚织界 / 实体基准先行", Vector2(1220, 29),
		Vector2(346, 48))
	add_child(badge)


func _create_panel(rect: Rect2, title: String, subtitle: String) -> Dictionary:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("0b2021")
	style.border_color = Color("6d6041")
	style.set_border_width_all(1)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var viewport_host := SubViewportContainer.new()
	viewport_host.name = "ViewportHost"
	viewport_host.position = Vector2(1, 54)
	viewport_host.size = Vector2(rect.size.x - 2, rect.size.y - 109)
	viewport_host.stretch = true
	viewport_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(viewport_host)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(int(viewport_host.size.x), int(viewport_host.size.y))
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport_host.add_child(viewport)
	var world := Node3D.new()
	world.name = "World"
	viewport.add_child(world)

	var header := ColorRect.new()
	header.position = Vector2(1, 1)
	header.size = Vector2(rect.size.x - 2, 53)
	header.color = Color("102b2a")
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(header)
	_add_label(header, title, Vector2(16, 10),
		Vector2(rect.size.x - 32, 32), 19, Color("e9dfc8"))

	var footer := ColorRect.new()
	footer.name = "Footer"
	footer.position = Vector2(1, rect.size.y - 55)
	footer.size = Vector2(rect.size.x - 2, 54)
	footer.color = Color(0.025, 0.09, 0.09, 0.93)
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(footer)
	_add_label(footer, subtitle, Vector2(14, 8),
		Vector2(rect.size.x - 28, 38), 14, Color("c3d4c9"),
		HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER)
	return {"panel": panel, "viewport": viewport, "world": world}


func _build_hero(panel: Dictionary) -> void:
	var world := panel.world as Node3D
	_configure_stage(world, Vector2(0.43, 0.43),
		Vector3(0, 0.52, 0.72), Vector3(0, 0.028, 0), 31.0)
	_add_tile(world, "front_standing",
		Vector3(-0.075, 0, -0.085),
		Vector3(0, Tile3D.TILE_H * 0.5 + TABLE_CLEARANCE, 0),
		Vector3(90, 0, 0))
	_add_tile(world, "back_standing",
		Vector3(0.075, 0, -0.085),
		Vector3(0, Tile3D.TILE_H * 0.5 + TABLE_CLEARANCE, 0),
		Vector3(-90, 0, 0))
	_add_tile(world, "flat_portrait",
		Vector3(-0.105, 0, 0.105), _flat_position(), Vector3.ZERO)
	_add_tile(world, "flat_sideways",
		Vector3(0.0, 0, 0.105), _flat_position(), Vector3(0, 90, 0))
	_add_tile(world, "back_flat",
		Vector3(0.105, 0, 0.105), _flat_position(), Vector3(180, 0, 0))


func _build_wall(panel: Dictionary) -> void:
	var world := panel.world as Node3D
	_configure_stage(world, Vector2(0.52, 0.26),
		Vector3(0, 0.31, 0.39), Vector3(0, 0.018, 0), 30.0)
	var lower := _flat_position()
	var upper := lower + Vector3(0, _tile_depth() + STACK_GAP, 0)
	_add_tile(world, "wall_lower",
		Vector3(-0.115, 0, 0), lower, Vector3(180, 0, 0))
	_add_tile(world, "wall_upper",
		Vector3(-0.115, 0, 0), upper, Vector3(180, 0, 0))
	_add_tile(world, "riichi_sideways",
		Vector3(0.125, 0, 0), _flat_position(), Vector3(0, 90, 0))


func _build_meld(panel: Dictionary) -> void:
	var world := panel.world as Node3D
	_configure_stage(world, Vector2(0.55, 0.27),
		Vector3(0, 0.32, 0.40), Vector3(0, 0.018, 0), 31.0)
	_add_tile(world, "meld_called_sideways",
		Vector3(-0.19, 0, -0.055), _flat_position(), Vector3(0, 90, 0))
	_add_tile(world, "meld_companion_left",
		Vector3(-0.10, 0, -0.055), _flat_position(), Vector3.ZERO)
	_add_tile(world, "meld_companion_right",
		Vector3(-0.02, 0, -0.055), _flat_position(), Vector3.ZERO)
	var base := _flat_position()
	var top := base + Vector3(0, _tile_depth() + STACK_GAP, 0)
	_add_tile(world, "added_kan_base",
		Vector3(0.17, 0, -0.055), base, Vector3(0, 90, 0))
	_add_tile(world, "added_kan_top",
		Vector3(0.17, 0, -0.055), top, Vector3(0, 90, 0))
	var ankan_x := [-0.125, -0.042, 0.042, 0.125]
	_add_tile(world, "ankan_left",
		Vector3(ankan_x[0], 0, 0.07), _flat_position(), Vector3(180, 0, 0))
	_add_tile(world, "ankan_inner_left",
		Vector3(ankan_x[1], 0, 0.07), _flat_position(), Vector3.ZERO)
	_add_tile(world, "ankan_inner_right",
		Vector3(ankan_x[2], 0, 0.07), _flat_position(), Vector3.ZERO)
	_add_tile(world, "ankan_right",
		Vector3(ankan_x[3], 0, 0.07), _flat_position(), Vector3(180, 0, 0))


func _build_comparison(panel: Dictionary) -> void:
	var world := panel.world as Node3D
	_configure_stage(world, Vector2(0.88, 0.30),
		Vector3(0, 0.36, 0.44), Vector3(0, 0.015, 0), 30.0)
	var seat_positions := [
		Vector3(-0.22, 0, 0.10), Vector3(-0.11, 0, 0),
		Vector3(-0.22, 0, -0.10), Vector3(-0.33, 0, 0),
	]
	var seat_rotations := [0.0, -90.0, 180.0, 90.0]
	for index in range(4):
		_add_tile(world, "seat_%d" % index,
			seat_positions[index], _flat_position(),
			Vector3(0, seat_rotations[index], 0))
	_add_tile(world, "near",
		Vector3(0.24, 0, 0.08), _flat_position(), Vector3.ZERO)
	_add_tile(world, "middle",
		Vector3(0.24, 0, -0.03), _flat_position(), Vector3.ZERO)
	_add_tile(world, "far",
		Vector3(0.24, 0, -0.14), _flat_position(), Vector3.ZERO)


func _configure_stage(world: Node3D, surface_size: Vector2,
		camera_position: Vector3, target: Vector3, fov: float) -> void:
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("06191a")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("d6ddd2")
	environment.ambient_light_energy = 0.66
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment_node.environment = environment
	world.add_child(environment_node)

	var table := MeshInstance3D.new()
	var table_mesh := BoxMesh.new()
	table_mesh.size = Vector3(surface_size.x, 0.018, surface_size.y)
	table.mesh = table_mesh
	table.position.y = -0.009
	var felt := StandardMaterial3D.new()
	felt.albedo_color = Color("0b3d3a")
	felt.roughness = 0.94
	felt.metallic = 0.0
	table.material_override = felt
	world.add_child(table)
	_add_stage_frame(world, surface_size)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -28, 0)
	sun.light_color = Color("fff2d2")
	sun.light_energy = 2.15
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 3.0
	world.add_child(sun)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-0.22, 0.33, 0.28)
	fill.light_color = Color("a7d9d2")
	fill.light_energy = 1.1
	fill.omni_range = 1.5
	world.add_child(fill)

	var camera := Camera3D.new()
	camera.fov = fov
	camera.near = 0.03
	camera.current = true
	world.add_child(camera)
	camera.look_at_from_position(camera_position, target, Vector3.UP)


func _add_stage_frame(world: Node3D, surface_size: Vector2) -> void:
	var frame_material := StandardMaterial3D.new()
	frame_material.albedo_color = Color("6c4c2d")
	frame_material.roughness = 0.46
	frame_material.metallic = 0.12
	var rail := 0.012
	_add_box(world, Vector3(surface_size.x + rail * 2, 0.026, rail),
		Vector3(0, -0.004, -surface_size.y * 0.5 - rail * 0.5), frame_material)
	_add_box(world, Vector3(surface_size.x + rail * 2, 0.026, rail),
		Vector3(0, -0.004, surface_size.y * 0.5 + rail * 0.5), frame_material)
	_add_box(world, Vector3(rail, 0.026, surface_size.y),
		Vector3(-surface_size.x * 0.5 - rail * 0.5, -0.004, 0), frame_material)
	_add_box(world, Vector3(rail, 0.026, surface_size.y),
		Vector3(surface_size.x * 0.5 + rail * 0.5, -0.004, 0), frame_material)


func _add_box(world: Node3D, box_size: Vector3, box_position: Vector3,
		box_material: Material) -> void:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = box_size
	instance.mesh = mesh
	instance.position = box_position
	instance.material_override = box_material
	world.add_child(instance)


func _add_tile(world: Node3D, pose_name: String, anchor_position: Vector3,
		local_position: Vector3,
		pose_rotation: Vector3) -> Tile3D:
	var anchor := Node3D.new()
	anchor.name = "%sAnchor" % pose_name.to_pascal_case()
	anchor.position = anchor_position
	world.add_child(anchor)
	var tile := Tile3D.new()
	tile.name = pose_name
	tile.set_geometry_depth(Tile3D.APPROVED_TILE_D)
	tile.setup(TileId.W1, true, false)
	anchor.add_child(tile)
	tile.position = local_position
	tile.rotation_degrees = pose_rotation
	pose_tiles[pose_name] = tile
	return tile


func _flat_position() -> Vector3:
	return Vector3(0, _tile_depth() * 0.5 + TABLE_CLEARANCE, 0)


func _tile_depth() -> float:
	return Tile3D.APPROVED_TILE_D


func _add_label(parent: Control, text: String, label_position: Vector2,
		label_size: Vector2, font_size: int, color: Color,
		alignment: HorizontalAlignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = text
	label.position = label_position
	label.size = label_size
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color("061011"))
	label.add_theme_constant_override("outline_size", 3)
	label.horizontal_alignment = alignment
	label.vertical_alignment = VerticalAlignment.VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _make_badge(text: String, badge_position: Vector2,
		badge_size: Vector2) -> Panel:
	var panel := Panel.new()
	panel.position = badge_position
	panel.size = badge_size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("102d2c")
	style.border_color = Color("a2874f")
	style.set_border_width_all(1)
	style.corner_radius_top_left = 20
	style.corner_radius_top_right = 20
	style.corner_radius_bottom_left = 20
	style.corner_radius_bottom_right = 20
	panel.add_theme_stylebox_override("panel", style)
	_add_label(panel, text, Vector2(12, 4), badge_size - Vector2(24, 8),
		15, Color("e1d4b7"), HorizontalAlignment.HORIZONTAL_ALIGNMENT_CENTER)
	return panel
