## 智能纹理提取器
## 从FairyGUI贵州麻将素材中提取并优化麻将牌纹理
## 🔧 作为 AutoLoad 单例使用,移除 class_name 避免冲突
extends Node

## 配置 - 根据反编译的Python脚本修正
const ATLAS_DIR = "user://mahjong_atlases"
const OUTPUT_DIR = "user://mahjong_tiles"
## 🔑 关键修正:麻将牌真实尺寸是 80x120,不是 85x85!
const TILE_WIDTH = 80
const TILE_HEIGHT = 120
const PADDING = 0 # 没有间距

## NEAREST 滤波由 project.godot `rendering/textures/canvas_textures/default_texture_filter=1`
## 在工程级别设置；AtlasTexture 本身没有 filter_mode 属性，无法在此处设置。

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

	# 🔧 使用已验证的精确坐标提取
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

func _extract_from_source() -> void:
	print("\n🎨 从 atlas 提取麻将牌纹理...")

	var extracted_count = 0
	var atlas_path = SOURCE_ATLASES[0]

	if not ResourceLoader.exists(atlas_path):
		print("⚠️  Atlas not found: %s" % atlas_path)
		return

	print("📦 Loading atlas: %s" % atlas_path)

	var atlas_texture = load(atlas_path) as Texture2D
	if not atlas_texture:
		print("❌ Failed to load atlas")
		return

	var img_width = atlas_texture.get_width()
	var img_height = atlas_texture.get_height()
	print("   Atlas size: %dx%d" % [img_width, img_height])

	# 🔑 关键修复:使用 AtlasTexture 而不是 get_region!
	# AtlasTexture 是 Godot官方推荐的图集提取方式
	var tile_coords = []
	
	# 万牌 (y=0)
	for i in range(9):
		tile_coords.append(["w%d" % (i+1), i * TILE_WIDTH, 0, TILE_WIDTH, TILE_HEIGHT])
	
	# 筒牌 (y=120)
	for i in range(9):
		tile_coords.append(["t%d" % (i+1), i * TILE_WIDTH, 120, TILE_WIDTH, TILE_HEIGHT])
	
	# 条牌 (y=240)
	for i in range(9):
		tile_coords.append(["s%d" % (i+1), i * TILE_WIDTH, 240, TILE_WIDTH, TILE_HEIGHT])
	
	# 字牌 (y=360)
	var zi_tiles = ["E", "S", "W", "N", "Z", "F", "B"]
	for i in range(zi_tiles.size()):
		tile_coords.append([zi_tiles[i], i * TILE_WIDTH, 360, TILE_WIDTH, TILE_HEIGHT])

	print("   准备提取 %d 个麻将牌 (80x120 像素)" % tile_coords.size())

	for coord in tile_coords:
		var tile_name = coord[0]
		var x = coord[1]
		var y = coord[2]
		var w = coord[3]
		var h = coord[4]

		# 🔑 使用 AtlasTexture 而不是 ImageTexture.create_from_image!
		var atlas_tex = AtlasTexture.new()
		atlas_tex.atlas = atlas_texture
		atlas_tex.region = Rect2(x, y, w, h)
		# NEAREST 滤波在 project.godot 工程级别已设置（见文件顶部常量注释）。

		extracted_tiles[tile_name] = atlas_tex
		extracted_count += 1
		print("✅ [%s] %dx%d" % [tile_name, w, h])

	print("✅ 成功提取 %d 个麻将牌纹理" % extracted_count)

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
