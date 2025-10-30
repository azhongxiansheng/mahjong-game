extends Control

## 麻将牌显示测试
## 直观查看真实麻将纹理效果

var texture_extractor: TextureExtractor
var cards_container: HBoxContainer

func _ready() -> void:
	print("\n🎴 麻将牌显示测试")
	
	# 设置背景
	var bg = ColorRect.new()
	bg.color = Color(0.1, 0.15, 0.1)  # 深绿色麻将桌
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	
	# 创建标题
	var title = Label.new()
	title.text = "真实麻将牌纹理测试"
	title.add_theme_font_size_override("font_size", 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 20)
	title.size = Vector2(1152, 50)
	title.add_theme_color_override("font_color", Color.WHITE)
	add_child(title)
	
	# 创建容器
	cards_container = HBoxContainer.new()
	cards_container.position = Vector2(50, 150)
	cards_container.add_theme_constant_override("separation", 10)
	add_child(cards_container)
	
	# 初始化纹理提取器
	texture_extractor = TextureExtractor.new()
	add_child(texture_extractor)
	
	# 等待纹理提取完成
	await get_tree().process_frame
	await get_tree().process_frame
	
	# 显示麻将牌
	_display_sample_tiles()
	
	# 显示说明
	_show_instructions()

func _display_sample_tiles() -> void:
	"""显示示例麻将牌"""
	
	# 创建一些示例牌
	var sample_tiles = [
		{"name": "w1", "label": "一万"},
		{"name": "w9", "label": "九万"},
		{"name": "t1", "label": "一筒"},
		{"name": "t9", "label": "九筒"},
		{"name": "s1", "label": "一条"},
		{"name": "s9", "label": "九条"},
		{"name": "E", "label": "东风"},
		{"name": "Z", "label": "红中"},
		{"name": "F", "label": "发财"}
	]
	
	for tile_info in sample_tiles:
		var tile_name = tile_info["name"]
		var tile_label = tile_info["label"]
		
		# 获取纹理
		var texture = texture_extractor.get_tile_texture(tile_name)
		
		# 创建显示容器
		var vbox = VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 5)
		
		if texture:
			# 创建纹理显示
			var texture_rect = TextureRect.new()
			texture_rect.texture = texture
			texture_rect.custom_minimum_size = Vector2(85, 120)
			texture_rect.expand_mode = TextureRect.EXPAND_FIT_HEIGHT_PROPORTIONAL
			texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			
			# 添加边框效果
			var panel = Panel.new()
			var style = StyleBoxFlat.new()
			style.bg_color = Color(0.2, 0.2, 0.2)
			style.border_color = Color(0.8, 0.6, 0.2)
			for i in range(4):
				style.set_border_width(i, 2)
			style.set_corner_radius_all(5)
			panel.add_theme_stylebox_override("panel", style)
			panel.custom_minimum_size = Vector2(95, 130)
			panel.add_child(texture_rect)
			texture_rect.position = Vector2(5, 5)
			
			vbox.add_child(panel)
			
			print("✅ 显示 %s (%s): %s" % [tile_label, tile_name, texture.get_size()])
		else:
			# 如果纹理不存在，显示占位符
			var placeholder = ColorRect.new()
			placeholder.color = Color(0.3, 0.3, 0.3)
			placeholder.custom_minimum_size = Vector2(85, 120)
			vbox.add_child(placeholder)
			
			var error_label = Label.new()
			error_label.text = "❌"
			error_label.add_theme_font_size_override("font_size", 32)
			error_label.position = Vector2(25, 45)
			placeholder.add_child(error_label)
			
			print("❌ 未找到纹理: %s (%s)" % [tile_label, tile_name])
		
		# 添加标签
		var label = Label.new()
		label.text = tile_label
		label.add_theme_font_size_override("font_size", 14)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", Color.WHITE)
		vbox.add_child(label)
		
		cards_container.add_child(vbox)

func _show_instructions() -> void:
	"""显示说明信息"""
	var info_text = """
	📝 使用说明：
	
	✅ 如果看到真实的麻将牌图案 = 纹理系统工作正常
	❌ 如果看到灰色方块 = 纹理提取失败
	
	纹理来源：
	- 贵州弈乐麻将原版素材
	- 高质量 PNG 纹理 (85x85)
	- 自动从 atlas 提取
	
	按 ESC 退出测试
	"""
	
	var info_label = RichTextLabel.new()
	info_label.bbcode_enabled = true
	info_label.text = info_text
	info_label.add_theme_font_size_override("normal_font_size", 16)
	info_label.position = Vector2(50, 400)
	info_label.size = Vector2(1000, 200)
	info_label.add_theme_color_override("default_color", Color.WHITE)
	add_child(info_label)
	
	# 显示统计信息
	var stats = Label.new()
	stats.text = "📊 提取统计: %d / 34 个麻将牌" % texture_extractor.extracted_tiles.size()
	stats.add_theme_font_size_override("font_size", 20)
	stats.position = Vector2(50, 100)
	stats.add_theme_color_override("font_color", Color.YELLOW)
	add_child(stats)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().quit()
