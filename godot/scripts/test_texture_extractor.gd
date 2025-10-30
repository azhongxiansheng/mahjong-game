extends Node

## 纹理提取测试脚本
## 用于验证麻将牌纹理是否正确提取

func _ready() -> void:
	print("\n" + "============================================================")
	print("🧪 测试麻将牌纹理提取系统")
	print("============================================================" + "\n")

	# 创建纹理提取器
	var extractor = TextureExtractor.new()
	add_child(extractor)

	# 等待两帧确保完全初始化
	await get_tree().process_frame
	await get_tree().process_frame

	# 测试提取结果
	_test_extraction_results(extractor)

	# 测试每种麻将牌
	_test_all_tiles(extractor)

	print("\n" + "============================================================")
	print("✅ 测试完成")
	print("============================================================" + "\n")

	# 退出游戏
	await get_tree().create_timer(2.0).timeout
	get_tree().quit()

func _test_extraction_results(extractor: TextureExtractor) -> void:
	print("\n📊 提取统计：")
	print("   提取的纹理总数: %d" % extractor.extracted_tiles.size())
	print("   预期纹理数量: 34")

	if extractor.extracted_tiles.size() == 34:
		print("   ✅ 提取完整！")
	elif extractor.extracted_tiles.size() > 0:
		print("   ⚠️  部分提取（%d/34）" % extractor.extracted_tiles.size())
	else:
		print("   ❌ 提取失败！")

	print("\n📝 已提取的麻将牌：")
	for tile_name in extractor.extracted_tiles.keys():
		var texture = extractor.extracted_tiles[tile_name]
		var size = texture.get_size()
		print("   ✓ %s: %dx%d" % [tile_name, size.x, size.y])

func _test_all_tiles(extractor: TextureExtractor) -> void:
	print("\n🎴 测试各类麻将牌：")

	# 测试万牌 (w1-w9)
	print("\n   万牌:")
	for i in range(1, 10):
		var tile_name = "w%d" % i
		var texture = extractor.get_tile_texture(tile_name)
		if texture:
			print("   ✅ %s: %s" % [tile_name, texture.get_size()])
		else:
			print("   ❌ %s: 未找到" % tile_name)

	# 测试筒牌 (t1-t9)
	print("\n   筒牌:")
	for i in range(1, 10):
		var tile_name = "t%d" % i
		var texture = extractor.get_tile_texture(tile_name)
		if texture:
			print("   ✅ %s: %s" % [tile_name, texture.get_size()])
		else:
			print("   ❌ %s: 未找到" % tile_name)

	# 测试条牌 (s1-s9)
	print("\n   条牌:")
	for i in range(1, 10):
		var tile_name = "s%d" % i
		var texture = extractor.get_tile_texture(tile_name)
		if texture:
			print("   ✅ %s: %s" % [tile_name, texture.get_size()])
		else:
			print("   ❌ %s: 未找到" % tile_name)

	# 测试字牌 (E,S,W,N,Z,F,B)
	print("\n   字牌:")
	for tile_name in ["E", "S", "W", "N", "Z", "F", "B"]:
		var texture = extractor.get_tile_texture(tile_name)
		if texture:
			print("   ✅ %s: %s" % [tile_name, texture.get_size()])
		else:
			print("   ❌ %s: 未找到" % tile_name)
