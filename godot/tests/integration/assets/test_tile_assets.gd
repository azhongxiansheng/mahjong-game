extends GutTest

# 资产完整性集成测试 — 验证 38 张麻将牌资产真实存在、可加载、尺寸合规，
# 且 TextureExtractor / CardTileBack 的 key 映射全覆盖。无 mock：直接读
# autoload 加载的真实纹理与磁盘文件。

const TILES_DIR := "res://assets/mahjong_tiles_riichi/"
const EXPECT_W := 272
const EXPECT_H := 389

# 34 标准牌 + 3 赤宝 + 牌背 = 38
func _all_keys() -> Array[String]:
	var keys: Array[String] = []
	for n in range(1, 10):
		keys.append("%dm" % n)
		keys.append("%dp" % n)
		keys.append("%ds" % n)
	for z in range(1, 8):
		keys.append("%dz" % z)
	keys.append_array(["0m", "0p", "0s", "back"])
	return keys

func test_all_38_tile_files_exist_on_disk() -> void:
	for key in _all_keys():
		var path := TILES_DIR + key + ".png"
		assert_true(ResourceLoader.exists(path), "缺资产文件: %s" % path)

func test_all_38_tiles_load_as_texture() -> void:
	for key in _all_keys():
		var tex := load(TILES_DIR + key + ".png") as Texture2D
		assert_not_null(tex, "%s 无法加载为 Texture2D" % key)

func test_all_tiles_have_uniform_size() -> void:
	for key in _all_keys():
		var tex := load(TILES_DIR + key + ".png") as Texture2D
		if tex == null:
			continue
		assert_eq(tex.get_width(), EXPECT_W, "%s 宽度应为 %d" % [key, EXPECT_W])
		assert_eq(tex.get_height(), EXPECT_H, "%s 高度应为 %d" % [key, EXPECT_H])

func test_texture_extractor_autoload_loaded_all() -> void:
	var extractor := get_tree().root.get_node_or_null("TextureExtractor")
	assert_not_null(extractor, "TextureExtractor autoload 应存在")
	if extractor == null:
		return
	for key in _all_keys():
		var tex: Texture2D = extractor.get_tile_texture(key)
		assert_not_null(tex, "TextureExtractor 缺纹理: %s" % key)

# CardTileBack.tile_id_to_atlas_key 必须为全部 34 个标准 TileId 返回有效 key，
# 且该 key 对应的资产真实存在。
func test_tile_id_to_atlas_key_covers_all_standard_tiles() -> void:
	for tid in range(0, 34):
		var key: String = CardTileBack.tile_id_to_atlas_key(tid)
		assert_ne(key, "", "TileId %d 无 atlas key 映射" % tid)
		assert_true(ResourceLoader.exists(TILES_DIR + key + ".png"),
			"TileId %d → %s 对应资产缺失" % [tid, key])
