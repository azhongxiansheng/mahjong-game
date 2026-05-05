class_name ObjectPool
extends Node  # ✓ 改为继承 Node

# 对象池系统
# 用于高效地复用对象，减少频繁的创建和销毁

# 存储各类对象的池
var button_pool: Array = []
var label_pool: Array = []
var panel_pool: Array = []

# ✓ 添加池的父节点，用于容纳所有池对象
var pool_parent: Node = null

# 池配置
var initial_button_count: int = 10
var initial_label_count: int = 20
var initial_panel_count: int = 5

func _init() -> void:
	"""初始化对象池"""
	# ✓ 创建一个父节点来容纳所有池节点
	pool_parent = Node.new()
	pool_parent.name = "ObjectPoolParent"

	_initialize_pools()
	print("ObjectPool: 已初始化")

func _initialize_pools() -> void:
	"""初始化所有对象池"""
	# 预创建按钮
	for i in range(initial_button_count):
		var btn = Button.new()
		pool_parent.add_child(btn)  # ✓ 添加到池父节点
		btn.visible = false
		button_pool.append(btn)

	# 预创建标签
	for i in range(initial_label_count):
		var lbl = Label.new()
		pool_parent.add_child(lbl)  # ✓ 添加到池父节点
		lbl.visible = false
		label_pool.append(lbl)

	# 预创建面板
	for i in range(initial_panel_count):
		var pnl = PanelContainer.new()
		pool_parent.add_child(pnl)  # ✓ 添加到池父节点
		pnl.visible = false
		panel_pool.append(pnl)

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
		pool_parent.add_child(button)  # ✓ 添加到场景树
		print("ObjectPool: 创建新按钮 (池已耗尽)")
	else:
		# 从池中取出
		button = button_pool.pop_back()

	# 安全检查：确保button不为null
	if button == null:
		button = Button.new()
		pool_parent.add_child(button)  # ✓ 添加到场景树
		print("ObjectPool: 池中按钮为null，创建新按钮")

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
	# 不能直接清空信号连接，只重置状态
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
		pool_parent.add_child(label)  # ✓ 添加到场景树
		print("ObjectPool: 创建新标签 (池已耗尽)")
	else:
		# 从池中取出
		label = label_pool.pop_back()

	# 安全检查：确保label不为null
	if label == null:
		label = Label.new()
		pool_parent.add_child(label)  # ✓ 添加到场景树
		print("ObjectPool: 池中标签为null，创建新标签")

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
		pool_parent.add_child(panel)  # ✓ 添加到场景树
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
