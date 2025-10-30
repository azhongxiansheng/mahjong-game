## 智能纹理提取器
## 从FairyGUI贵州麻将素材中提取并优化麻将牌纹理
## 🔧 作为 AutoLoad 单例使用,移除 class_name 避免冲突
extends Node

## 配置
const ATLAS_DIR = "user://mahjong_atlases"
const OUTPUT_DIR = "user://mahjong_tiles"
const TILE_SIZE = 85
const PADDING = 1

## 🆕 纹理滤波模式 - 最近邻滤波确保像素完美
const TEXTURE_FILTER_MODE = CanvasItem.TEXTURE_FILTER_NEAREST

## 贵州弈乐麻将原始资源位置
const SOURCE_ATLASES = {
	0: "res://assets/mahjong_tiles/mahjong_atlas0.png",
	1: "res://assets/mahjong_tiles/mahjong_atlas0_1.png",
	2: "res://assets/mahjong_tiles/mahjong_atlas0_2.png"
}

## 麻将牌定义
var tile_names = []
var extracted_tiles = {}

func _ready() -> void:
	print("\n   准备提取 34 种麻将牌 (w1-w9, t1-t9, s1-s9, E, S, W, N, Z, F, B)")
	_init_tile_names()

	# 🔧 使用已验证的网格提取方案
	_extract_from_source()

	print("✅ TextureExtractor initialized")

func _init_tile_names() -> void:
	tile_names.clear()

	for i in range(1, 10):
		tile_names.append("w%d" % i)

	for i in range(1, 10):
		tile_names.append("t%d" % i)

	for i in range(1, 10):
		tile_names.append("s%d" % i)

	tile_names.append_array(["E", "S", "W", "N", "Z", "F", "B"])

## 🆕 智能检测 atlas 的实际网格尺寸
func _detect_tile_size(image: Image) -> int:
	var width = image.get_width()
	var height = image.get_height()

	# 根据标准麻将排列推测
	# 通常是 9列 (9个数字) x 4行 (数字+字牌)
	var likely_cols = 9
	var likely_tile_width = int(width / float(likely_cols))

	print("   自动检测: atlas尺寸 %dx%d, 预测列数 %d, 预测瓦片宽度 %d" % [width, height, likely_cols, likely_tile_width])

	# 确保尺寸合理
	if likely_tile_width < 50 or likely_tile_width > 150:
		print("   ⚠️  预测尺寸不合理，使用默认值 %d" % TILE_SIZE)
		return TILE_SIZE

	return likely_tile_width

func _extract_from_source() -> void:
	print("\n🎨 从 atlas 提取麻将牌纹理...")

	var extracted_count = 0

	for atlas_idx in SOURCE_ATLASES:
		var atlas_path = SOURCE_ATLASES[atlas_idx]

		if not ResourceLoader.exists(atlas_path):
			print("⚠️  Atlas not found: %s" % atlas_path)
			continue

		print("📦 Loading atlas %d: %s" % [atlas_idx, atlas_path])

		var atlas = load(atlas_path) as Texture2D
		if not atlas:
			print("❌ Failed to load atlas: %s" % atlas_path)
			continue

		var image = atlas.get_image()
		if not image:
			print("❌ Failed to get image from atlas")
			continue

		var img_width = image.get_width()
		var img_height = image.get_height()
		print("   Atlas size: %dx%d" % [img_width, img_height])

		# 🆕 智能检测瓦片尺寸
		var tile_size = _detect_tile_size(image)

		var max_cols = int(img_width / float(tile_size + PADDING))
		var max_rows = int(img_height / float(tile_size + PADDING))
		print("   Grid: %dx%d (tile size: %d, padding: %d)" % [max_rows, max_cols, tile_size, PADDING])

		var tile_index = 0

		for row in range(max_rows):
			for col in range(max_cols):
				if tile_index >= tile_names.size():
					break

				var x = col * (tile_size + PADDING)
				var y = row * (tile_size + PADDING)

				if x + tile_size > img_width or y + tile_size > img_height:
					continue

				var tile_rect = Rect2i(x, y, tile_size, tile_size)
				var tile_image = image.get_region(tile_rect)

				if not tile_image:
					print("⚠️  无法获取 tile_image at [%d,%d]" % [row, col])
					continue

				# 🔑 关键验证：Image 有效性
				if tile_image.get_width() <= 0 or tile_image.get_height() <= 0:
					print("⚠️  tile_image 尺寸无效: %dx%d at [%d,%d]" % [tile_image.get_width(), tile_image.get_height(), row, col])
					continue

				if _is_empty_image(tile_image):
					continue

				# 🔑 关键：立即创建 ImageTexture
				var tile_texture = ImageTexture.create_from_image(tile_image)

				if not tile_texture:
					print("❌ 无法创建 ImageTexture at [%d,%d]" % [row, col])
					continue

				# 🔑 关键验证：ImageTexture 有效性
				var tex_size = tile_texture.get_size()
				if tex_size.x <= 0 or tex_size.y <= 0:
					print("⚠️  ImageTexture 尺寸无效: %s at [%d,%d]" % [tex_size, row, col])
					continue

				var tile_name = tile_names[tile_index]
				extracted_tiles[tile_name] = tile_texture
				extracted_count += 1
				print("   ✓ [%d,%d]: %s (texture size: %dx%d)" % [row, col, tile_name, tex_size.x, tex_size.y])
				tile_index += 1

		if tile_index >= tile_names.size():
			break

	print("✅ 成功提取 %d 个麻将牌纹理" % extracted_count)
	print("   extracted_tiles 字典大小: %d" % extracted_tiles.size())

	# 验证所有关键牌都被提取了
	var critical_tiles = ["w1", "t5", "s9", "E", "Z"]
	for tile_name in critical_tiles:
		if tile_name in extracted_tiles:
			var tex = extracted_tiles[tile_name]
			var size = tex.get_size()
			print("   ✅ %s: 已提取，尺寸 %dx%d" % [tile_name, size.x, size.y])
		else:
			print("   ❌ %s: 未找到！" % tile_name)

func _is_empty_image(img: Image) -> bool:
	if not img:
		return true

	var width = img.get_width()
	var height = img.get_height()

	if width <= 0 or height <= 0:
		return true

	# 检查 9 个采样点
	var sample_points = [
		img.get_pixel(0, 0),
		img.get_pixel(width - 1, 0),
		img.get_pixel(0, height - 1),
		img.get_pixel(width - 1, height - 1),
		img.get_pixel(int(width / 2.0), int(height / 2.0)),
		img.get_pixel(int(width / 2.0), 0),
		img.get_pixel(int(width / 2.0), height - 1),
		img.get_pixel(0, int(height / 2.0)),
		img.get_pixel(width - 1, int(height / 2.0)),
	]

	for pixel in sample_points:
		if pixel.a > 0.3:
			return false

	return true

func get_tile_texture(tile_name: String) -> Texture2D:
	if tile_name in extracted_tiles:
		return extracted_tiles[tile_name]
	return null
