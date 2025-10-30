## 测试脚本:导出提取的纹理以验证内容
extends Node

func _ready():
	print("\n=== 测试纹理导出 ===")
	
	# 等待 TextureExtractor 初始化
	await get_tree().process_frame
	await get_tree().process_frame
	
	if not TextureExtractor:
		print("❌ TextureExtractor 未找到")
		return
	
	# 获取第一张牌的纹理
	var test_texture = TextureExtractor.get_tile_texture("w1")
	if not test_texture:
		print("❌ 无法获取 w1 纹理")
		return
	
	print("✅ 获取到 w1 纹理: %dx%d" % [test_texture.get_width(), test_texture.get_height()])
	
	# 获取图像数据
	var image = test_texture.get_image()
	if not image:
		print("❌ 无法从纹理获取 Image")
		return
	
	# 保存为 PNG
	var save_path = "user://test_w1.png"
	var err = image.save_png(save_path)
	if err == OK:
		print("✅ 纹理已导出到: %s" % save_path)
		print("   (实际路径: %s)" % ProjectSettings.globalize_path(save_path))
	else:
		print("❌ 保存失败: %d" % err)
	
	# 检查像素数据
	var pixel_00 = image.get_pixel(0, 0)
	var pixel_center = image.get_pixel(40, 60)
	print("\n🔍 像素检查:")
	print("   (0,0): %s" % pixel_00)
	print("   (40,60): %s" % pixel_center)
	print("   是否全透明: %s" % (pixel_00.a == 0 and pixel_center.a == 0))
