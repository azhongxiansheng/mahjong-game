extends GutTest

const TILE_SCRIPT_PATH := \
	"res://ui/four_player_table/table3d/tile_3d.gd"
const SKIN_SCRIPT_PATH := \
	"res://ui/four_player_table/table3d/tile_3d_skin.gd"
const DEFAULT_SKIN_PATH := \
	"res://ui/four_player_table/table3d/skins/qinglan_weave.tres"
const APPROVED_DEPTH := 0.056


func _make_tile(tile_id: int = TileId.W1, red: bool = false,
		face_up: bool = true) -> Tile3D:
	var tile := Tile3D.new()
	add_child_autofree(tile)
	tile.setup(tile_id, face_up, red)
	return tile


func _surface_material(tile: Tile3D,
		surface_index: int) -> StandardMaterial3D:
	return tile._mesh.get_surface_override_material(surface_index) \
		as StandardMaterial3D


func _make_material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _make_override_face() -> Texture2D:
	var image := Image.create(32, 40, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	for y in range(8, 32):
		for x in range(7, 25):
			if x in range(13, 19) or y in range(17, 23):
				image.set_pixel(x, y, Color(0.08, 0.18, 0.72, 1.0))
	return ImageTexture.create_from_image(image)


func _make_alternate_skin():
	if not ResourceLoader.exists(SKIN_SCRIPT_PATH):
		return null
	var skin_script := load(SKIN_SCRIPT_PATH) as Script
	if skin_script == null:
		return null
	var skin = skin_script.new()
	skin.set("skin_id", &"contract_alternate")
	skin.set("face_material_template",
		_make_material(Color.WHITE, 0.31))
	skin.set("face_background_color", Color(0.88, 0.80, 0.64))
	skin.set("back_material_template",
		_make_material(Color(0.18, 0.11, 0.48), 0.63))
	skin.set("edge_material",
		_make_material(Color(0.84, 0.72, 0.54), 0.31))
	skin.set("bevel_material",
		_make_material(Color(0.54, 0.43, 0.30), 0.31))
	skin.set("side_material",
		_make_material(Color(0.72, 0.58, 0.40), 0.31))
	skin.set("back_shell_material",
		_make_material(Color(0.18, 0.11, 0.48), 0.63))
	skin.set("face_textures", {"1m": _make_override_face()})
	return skin


func _assert_neutral_opaque_corners(texture: Texture2D,
		context: String) -> void:
	assert_not_null(texture, "%s 必须有最终牌面纹理" % context)
	if texture == null:
		return
	var image := texture.get_image()
	assert_not_null(image)
	if image == null or image.is_empty():
		return
	for point in [Vector2i.ZERO,
			Vector2i(image.get_width() - 1, 0),
			Vector2i(0, image.get_height() - 1),
			Vector2i(image.get_width() - 1, image.get_height() - 1)]:
		var color := image.get_pixelv(point)
		assert_gte(color.a, 0.99,
			"%s 不得保留 2D 牌胚的透明圆角" % context)
		assert_gte(minf(color.r, minf(color.g, color.b)), 0.97,
			"%s 四角必须回填为中性牌面，不得烘焙旧边缘" % context)


func _has_color(texture: Texture2D, family: StringName) -> bool:
	if texture == null:
		return false
	var image := texture.get_image()
	if image == null or image.is_empty():
		return false
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			match family:
				&"red":
					if color.r > 0.45 and color.r > color.g * 1.35 \
							and color.r > color.b * 1.35:
						return true
				&"green":
					if color.g > 0.22 and color.g > color.r * 1.35 \
							and color.g > color.b * 1.20:
						return true
				&"blue":
					if color.b > 0.16 and color.b > color.r * 1.35 \
							and color.b > color.g * 1.08:
						return true
	return false


func _assert_real_source_color_is_preserved(texture: Texture2D,
		atlas_key: String, family: StringName) -> void:
	var extractor := get_tree().root.get_node_or_null("TextureExtractor")
	assert_not_null(extractor)
	if extractor == null:
		return
	var source := extractor.get_tile_texture(atlas_key) as Texture2D
	assert_not_null(source, "%s 必须来自真实 TextureExtractor" % atlas_key)
	if source == null or texture == null:
		return
	var source_image := source.get_image()
	var final_image := texture.get_image()
	assert_eq(final_image.get_size(), source_image.get_size(),
		"派生牌面必须保留真实纹理空间，禁止用任意色块自证")
	var best_point := Vector2i(-1, -1)
	var best_score := -1.0
	for y in range(source_image.get_height()):
		for x in range(source_image.get_width()):
			var color := source_image.get_pixel(x, y)
			var score := 0.0
			match family:
				&"red":
					score = color.r - maxf(color.g, color.b)
				&"green":
					score = color.g - maxf(color.r, color.b)
				&"blue":
					score = color.b - maxf(color.r, color.g)
			if color.a > 0.99 and score > best_score:
				best_score = score
				best_point = Vector2i(x, y)
	assert_gt(best_score, 0.15,
		"真实源图必须存在可交叉验证的 %s 像素" % family)
	if best_point.x < 0:
		return
	var source_color := source_image.get_pixelv(best_point)
	var final_color := final_image.get_pixelv(best_point)
	assert_almost_eq(final_color.r, source_color.r, 0.015,
		"最终牌面必须在相同像素坐标保留真实源图颜色")
	assert_almost_eq(final_color.g, source_color.g, 0.015)
	assert_almost_eq(final_color.b, source_color.b, 0.015)


func test_default_qinglan_skin_is_a_real_godot_resource() -> void:
	assert_true(ResourceLoader.exists(SKIN_SCRIPT_PATH),
		"可替换皮肤必须由模块内 Resource 脚本定义")
	assert_true(ResourceLoader.exists(DEFAULT_SKIN_PATH),
		"青岚织界默认皮肤必须是可直接 load 的 .tres")
	if not ResourceLoader.exists(DEFAULT_SKIN_PATH):
		return
	var skin := load(DEFAULT_SKIN_PATH)
	assert_not_null(skin)
	if skin == null:
		return
	assert_eq(StringName(skin.get("skin_id")), &"qinglan_weave")
	for property_name in [
		"face_material_template", "back_material_template",
		"edge_material", "bevel_material", "side_material",
		"back_shell_material",
	]:
		assert_true(skin.get(property_name) is StandardMaterial3D,
			"默认皮肤必须提供 %s" % property_name)
	assert_true(skin.get("face_textures") is Dictionary,
		"皮肤必须允许按 atlas key 覆盖整套牌面")
	assert_true(skin.get("face_background_color") is Color,
		"牌面底色必须烘进派生纹理，材质调制保持 WHITE")
	var tile := _make_tile()
	assert_same(tile.get_tile_skin(), skin,
		"生产 Tile3D 默认外观必须直接加载青岚织界资源")
	assert_eq(tile.get_tile_skin().resource_path, DEFAULT_SKIN_PATH)


func test_approved_56mm_depth_is_opt_in_without_breaking_legacy_34mm() -> void:
	var legacy := _make_tile()
	legacy.setup_entity(TileId.W1, true, false, 36956)
	var legacy_peer := _make_tile(TileId.T1)
	var legacy_mesh := legacy._mesh.mesh
	assert_same(legacy_peer._mesh.mesh, legacy_mesh)
	assert_almost_eq(legacy._mesh.mesh.get_aabb().size.y,
		Tile3D.TILE_D, 0.00002,
		"既有 Tile3D 调用方必须继续保持 34mm 厚度")
	assert_true(legacy.has_method("set_geometry_depth"),
		"生产组件必须允许 #369 显式选择 56mm 实体深度")
	if not legacy.has_method("set_geometry_depth"):
		return
	legacy.call("set_geometry_depth", APPROVED_DEPTH)
	assert_almost_eq(legacy._mesh.mesh.get_aabb().size.y,
		APPROVED_DEPTH, 0.00002)
	assert_not_same(legacy._mesh.mesh, legacy_mesh,
		"56mm opt-in 必须切到另一份共享几何，不能原地污染 34mm mesh")
	assert_same(legacy_peer._mesh.mesh, legacy_mesh)
	assert_almost_eq(legacy_peer._mesh.mesh.get_aabb().size.y,
		Tile3D.TILE_D, 0.00002,
		"另一张既有牌必须继续保持 34mm")
	var approved_peer := _make_tile(TileId.S1)
	approved_peer.call("set_geometry_depth", APPROVED_DEPTH)
	assert_same(approved_peer._mesh.mesh, legacy._mesh.mesh,
		"相同 56mm 深度的实例必须复用同一 ArrayMesh")
	assert_eq(legacy.tile_id, TileId.W1)
	assert_eq(legacy.tile_instance_id, 36956,
		"换几何预设不得破坏牌实体身份")
	var shape := legacy._collision.shape as BoxShape3D
	assert_not_null(shape)
	if shape != null:
		assert_almost_eq(shape.size.y, APPROVED_DEPTH, 0.00002,
			"碰撞体必须与 56mm 最终 mesh 同步")
	var script := load(TILE_SCRIPT_PATH) as Script
	var constants := script.get_script_constant_map()
	assert_true(constants.has("APPROVED_TILE_D"),
		"56mm 必须是生产组件的命名预设，不能散落魔法数")
	if constants.has("APPROVED_TILE_D"):
		assert_almost_eq(float(constants["APPROVED_TILE_D"]),
			APPROVED_DEPTH, 0.000001)


func test_same_depth_tiles_share_geometry_but_keep_instance_face_materials() -> void:
	var one_man := _make_tile(TileId.W1)
	var red_dragon := _make_tile(TileId.CHUN)
	assert_same(one_man._mesh.mesh, red_dragon._mesh.mesh,
		"相同尺寸的所有牌必须共享一个 ArrayMesh")
	for surface_index in range(one_man._mesh.mesh.get_surface_count()):
		assert_null(one_man._mesh.mesh.surface_get_material(surface_index),
			"共享 ArrayMesh 只能保存几何，禁止写入牌面或皮肤材质")
	var one_face := _surface_material(one_man, 0)
	var dragon_face := _surface_material(red_dragon, 0)
	assert_not_null(one_face)
	assert_not_null(dragon_face)
	if one_face != null and dragon_face != null:
		assert_not_same(one_face.albedo_texture, dragon_face.albedo_texture,
			"不同 tile_id 必须在实例 override 上使用不同真实牌面")


func test_one_instance_can_switch_tile_id_and_red_dora_without_rebuilding_mesh() -> void:
	var tile := _make_tile(TileId.W1)
	tile.setup_entity(TileId.W1, true, false, 36901)
	var shared_mesh := tile._mesh.mesh
	var one_man_texture := _surface_material(tile, 0).albedo_texture
	assert_true(tile.has_method("set_tile_visual"),
		"同一动作实体换牌面必须有不清空 instance_id 的专用入口")
	if not tile.has_method("set_tile_visual"):
		return
	tile.call("set_tile_visual", TileId.W5, false)
	var normal_five_texture := _surface_material(tile, 0).albedo_texture
	tile.call("set_tile_visual", TileId.W5, true)
	var red_five_texture := _surface_material(tile, 0).albedo_texture
	assert_same(tile._mesh.mesh, shared_mesh,
		"换牌面不得重建几何或复制 mesh")
	assert_eq(tile.tile_instance_id, 36901,
		"视觉切换不得清空动作 identity；setup() 的既有清空语义保持不变")
	assert_not_same(one_man_texture, normal_five_texture)
	assert_not_same(normal_five_texture, red_five_texture,
		"普通五与赤五必须消费 5m / 0m 两张真实纹理")
	_assert_neutral_opaque_corners(red_five_texture, "赤五万")
	assert_true(_has_color(red_five_texture, &"red"),
		"赤五万真实红色字样不得在去牌胚时丢失")


func test_switching_skin_preserves_mesh_and_entity_identity() -> void:
	var tile := _make_tile(TileId.W1)
	tile.setup_entity(TileId.W1, true, false, 36956)
	var mesh_before := tile._mesh.mesh
	var skin_before = tile.call("get_tile_skin") \
		if tile.has_method("get_tile_skin") else null
	var face_before := _surface_material(tile, 0)
	assert_true(tile.has_method("set_tile_skin"),
		"Tile3D 必须提供实例级换肤入口")
	var alternate = _make_alternate_skin()
	assert_not_null(alternate, "测试皮肤必须可由同一 Resource 脚本构造")
	if not tile.has_method("set_tile_skin") or alternate == null:
		return
	tile.call("set_tile_skin", alternate)
	assert_same(tile._mesh.mesh, mesh_before,
		"换皮肤只能重绑材质，不得重建共享 mesh")
	assert_eq(tile.tile_id, TileId.W1)
	assert_eq(tile.tile_instance_id, 36956,
		"换皮肤不得破坏动作 identity")
	assert_not_same(tile.call("get_tile_skin"), skin_before)
	var face_after := _surface_material(tile, 0)
	assert_not_null(face_after)
	if face_before != null and face_after != null:
		assert_eq(face_before.albedo_color, Color.WHITE,
			"真实牌面颜色必须使用 WHITE 材质调制")
		assert_eq(face_after.albedo_color, Color.WHITE,
			"换肤也不得用材质 tint 破坏红蓝绿字样")
		assert_not_same(face_after.albedo_texture,
			face_before.albedo_texture,
			"皮肤中的 1m 覆盖纹理必须进入最终实例材质")
		var overrides := alternate.get("face_textures") as Dictionary
		assert_same(face_after.albedo_texture, overrides["1m"],
			"皮肤显式覆盖是最终牌面，组件不得再次改色或重采样")
		tile.set_tile_visual(TileId.W5, false)
		assert_not_same(_surface_material(tile, 0).albedo_texture,
			overrides["1m"],
			"皮肤未覆盖的 atlas key 必须回退真实 TextureExtractor")
		assert_eq(tile.tile_instance_id, 36956)


func test_face_down_swaps_back_texture_and_colored_half_to_visible_side() -> void:
	var tile := _make_tile(TileId.W1, false, true)
	tile.setup_entity(TileId.W1, true, false, 36902)
	var shared_mesh := tile._mesh.mesh
	var face_up_top := _surface_material(tile, 0)
	var face_up_ivory_half := _surface_material(tile, 4)
	var face_up_back_half := _surface_material(tile, 5)
	assert_not_null(face_up_top)
	assert_not_null(face_up_ivory_half)
	assert_not_null(face_up_back_half)
	if face_up_ivory_half == null or face_up_back_half == null:
		return
	assert_ne(face_up_ivory_half.albedo_color,
		face_up_back_half.albedo_color,
		"青绿牌底与象牙牌胚必须是两个真实半层 surface")
	tile.set_face_up(false)
	var face_down_top := _surface_material(tile, 0)
	assert_not_null(face_down_top)
	if face_up_top != null and face_down_top != null:
		assert_not_same(face_down_top.albedo_texture,
			face_up_top.albedo_texture,
			"face_down 须在可见顶面切换为真实牌背")
	assert_eq(_surface_material(tile, 4).albedo_color,
		face_up_back_half.albedo_color,
		"翻到牌背时青绿 1/2 层必须与可见牌背相邻")
	assert_eq(_surface_material(tile, 5).albedo_color,
		face_up_ivory_half.albedo_color)
	assert_eq(_surface_material(tile, 2).albedo_color,
		face_up_back_half.albedo_color,
		"牌背朝上时顶面嵌入边必须与牌背壳同色")
	assert_eq(_surface_material(tile, 3).albedo_color,
		face_up_back_half.albedo_color,
		"牌背朝上时顶面倒角不得残留象牙色差")
	assert_same(tile._mesh.mesh, shared_mesh)
	assert_eq(tile.tile_instance_id, 36902)
	tile.set_face_up(true)
	assert_eq(_surface_material(tile, 4).albedo_color,
		face_up_ivory_half.albedo_color,
		"正背往返后必须恢复原来的象牙半层")


func test_all_color_families_survive_the_real_face_texture_chain() -> void:
	var pin_five := _make_tile(TileId.T5)
	var sou_five := _make_tile(TileId.S5)
	var red_five := _make_tile(TileId.W5, true)
	var pin_texture := _surface_material(pin_five, 0).albedo_texture
	var sou_texture := _surface_material(sou_five, 0).albedo_texture
	var red_texture := _surface_material(red_five, 0).albedo_texture
	_assert_neutral_opaque_corners(pin_texture, "五筒")
	_assert_neutral_opaque_corners(sou_texture, "五索")
	_assert_neutral_opaque_corners(red_texture, "赤五万")
	assert_true(_has_color(pin_texture, &"blue"),
		"筒子蓝色图案不得被一万专用红黑 mask 误删")
	assert_true(_has_color(sou_texture, &"green"),
		"索子绿色图案不得被一万专用红黑 mask 误删")
	assert_true(_has_color(red_texture, &"red"))
	_assert_real_source_color_is_preserved(pin_texture, "5p", &"blue")
	_assert_real_source_color_is_preserved(sou_texture, "5s", &"green")
	_assert_real_source_color_is_preserved(red_texture, "0m", &"red")


func test_real_mahjong_table_3d_creation_chain_keeps_legacy_geometry_and_skin() -> void:
	var table := MahjongTable3D.new()
	add_child_autofree(table)
	await get_tree().process_frame
	var state := BattleState.for_east_round(369, 0, 1, 0, 0)
	table.bind_battle_state(state, 0, 4)
	assert_false(table._hand_tiles.is_empty())
	if table._hand_tiles.is_empty():
		return
	var hand_tile := table._hand_tiles[0] as Tile3D
	assert_not_null(hand_tile)
	assert_almost_eq(hand_tile.get_geometry_depth(), Tile3D.TILE_D, 0.000001,
		"真实 MahjongTable3D 调用方必须继续默认使用 34mm")
	assert_eq(hand_tile.get_tile_skin().resource_path, DEFAULT_SKIN_PATH)
	assert_not_null(_surface_material(hand_tile, 0).albedo_texture,
		"真实手牌创建链必须消费 tile_id 对应牌面")
	table._rebuild_opponent_backs(1, 1)
	assert_eq(table._opp_tiles[1].size(), 1)
	var back_tile := table._opp_tiles[1][0] as Tile3D
	assert_false(back_tile.face_up)
	assert_eq(_surface_material(back_tile, 2).albedo_color,
		_surface_material(back_tile, 4).albedo_color,
		"真实对手暗手的可见顶边与上半侧壁必须同属牌背色系")


func test_null_skin_and_missing_face_keep_existing_visual_fallback() -> void:
	var tile := _make_tile(-1)
	assert_true(tile.has_method("set_tile_skin"))
	assert_true(tile.has_method("get_tile_skin"))
	if not tile.has_method("set_tile_skin") \
			or not tile.has_method("get_tile_skin"):
		return
	tile.call("set_tile_skin", null)
	assert_not_null(tile.call("get_tile_skin"),
		"null 皮肤必须回退青岚织界默认资源")
	assert_eq(tile.call("get_tile_skin").resource_path, DEFAULT_SKIN_PATH)
	var face := _surface_material(tile, 0)
	assert_not_null(face)
	if face != null:
		assert_null(face.albedo_texture,
			"未知 tile_id 应保留纯牌胚 fallback，不得伪造牌面")
		assert_gte(face.albedo_color.r, 0.90)
		assert_gte(face.albedo_color.g, 0.90)
		assert_gte(face.albedo_color.b, 0.85)
