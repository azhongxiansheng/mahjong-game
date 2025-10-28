class_name ObjectPool

# 对象池系统
# 用于高效地复用对象，减少频繁的创建和销毁

# 存储各类对象的池
var button_pool: Array = []
var label_pool: Array = []
var panel_pool: Array = []

# 池配置
var initial_button_count: int = 10
var initial_label_count: int = 20
var initial_panel_count: int = 5

func _init() -> void:
	"""初始化对象池"""
	_initialize_pools()
	print("ObjectPool: 已初始化")

func _initialize_pools() -> void:
	"""初始化所有对象池"""
	# 预创建按钮
	for i in range(initial_button_count):
		button_pool.append(Button.new())
	
	# 预创建标签
	for i in range(initial_label_count):
		label_pool.append(Label.new())
	
	# 预创建面板
	for i in range(initial_panel_count):
		panel_pool.append(PanelContainer.new())
	
	print("ObjectPool: 对象池已初始化 (Button:%d, Label:%d, Panel:%d)" % [
		button_pool.size(),
		label_pool.size(),
		panel_pool.size()
	])

# ==================== 按钮池 ====================

func get_button(text: String = "") -> Button:
	"""从池中获取按钮"""
	var button: Button
	
	if button_pool.is_empty():
		# 池为空，创建新按钮
		button = Button.new()
		print("ObjectPool: 创建新按钮 (池已耗尽)")
	else:
		# 从池中取出
		button = button_pool.pop_back()
	
	# 重置按钮状态
	button.text = text
	button.disabled = false
	button.visible = true
	
	return button

func return_button(button: Button) -> void:
	"""归还按钮到池中"""
	if button == null:
		return
	
	# 重置按钮状态
	button.text = ""
	button.pressed.disconnect_all()
	button.visible = false
	
	# 归还到池
	button_pool.append(button)

func get_button_pool_size() -> int:
	"""获取按钮池大小"""
	return button_pool.size()

# ==================== 标签池 ====================

func get_label(text: String = "") -> Label:
	"""从池中获取标签"""
	var label: Label
	
	if label_pool.is_empty():
		# 池为空，创建新标签
		label = Label.new()
		print("ObjectPool: 创建新标签 (池已耗尽)")
	else:
		# 从池中取出
		label = label_pool.pop_back()
	
	# 重置标签状态
	label.text = text
	label.visible = true
	
	return label

func return_label(label: Label) -> void:
	"""归还标签到池中"""
	if label == null:
		return
	
	# 重置标签状态
	label.text = ""
	label.visible = false
	
	# 归还到池
	label_pool.append(label)

func get_label_pool_size() -> int:
	"""获取标签池大小"""
	return label_pool.size()

# ==================== 面板池 ====================

func get_panel() -> PanelContainer:
	"""从池中获取面板"""
	var panel: PanelContainer
	
	if panel_pool.is_empty():
		# 池为空，创建新面板
		panel = PanelContainer.new()
		print("ObjectPool: 创建新面板 (池已耗尽)")
	else:
		# 从池中取出
		panel = panel_pool.pop_back()
	
	# 重置面板状态
	panel.visible = true
	
	return panel

func return_panel(panel: PanelContainer) -> void:
	"""归还面板到池中"""
	if panel == null:
		return
	
	# 清空面板的子节点
	for child in panel.get_children():
		child.queue_free()
	
	panel.visible = false
	
	# 归还到池
	panel_pool.append(panel)

func get_panel_pool_size() -> int:
	"""获取面板池大小"""
	return panel_pool.size()

# ==================== 统计信息 ====================

func get_pool_stats() -> Dictionary:
	"""获取对象池统计信息"""
	return {
		"button_pool_size": button_pool.size(),
		"label_pool_size": label_pool.size(),
		"panel_pool_size": panel_pool.size(),
		"total_objects": button_pool.size() + label_pool.size() + panel_pool.size()
	}

func print_pool_stats() -> void:
	"""打印对象池统计信息"""
	var stats = get_pool_stats()
	print("\n【对象池统计】")
	print("  按钮池: %d" % stats.button_pool_size)
	print("  标签池: %d" % stats.label_pool_size)
	print("  面板池: %d" % stats.panel_pool_size)
	print("  总计: %d" % stats.total_objects)
	print()

func reset_all_pools() -> void:
	"""重置所有对象池"""
	button_pool.clear()
	label_pool.clear()
	panel_pool.clear()
	_initialize_pools()
	print("ObjectPool: 所有对象池已重置")
