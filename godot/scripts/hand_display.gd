class_name HandDisplay
extends Control

# 属性
var hand: CardHand
var card_tiles: Array[CardTile] = []
var selected_tile: CardTile = null

# 预加载场景
var card_tile_scene: PackedScene = preload("res://scenes/card_tile.tscn")

# 信号
signal card_selected(card: CardData)
signal card_pressed(card: CardData)

func _ready() -> void:
	print("HandDisplay初始化完成")
	print("[DEBUG] HandDisplay 位置: ", position, " 全局位置: ", global_position)
	print("[DEBUG] HandDisplay 大小: ", size)

	# 设置背景
	var panel = Panel.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.2, 0.2, 1.0)
	panel.add_theme_stylebox_override("panel", style)
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	add_child(panel)
	move_child(panel, 0)

func set_hand(h: CardHand) -> void:
	"""设置并显示手牌"""
	hand = h
	refresh_display()

func refresh_display() -> void:
	"""刷新卡牌显示"""
	# 清空旧的卡牌显示
	for tile in card_tiles:
		tile.queue_free()
	card_tiles.clear()
	selected_tile = null

	# 如果没有手牌，返回
	if not hand:
		print("⚠ 没有手牌数据")
		return

	# 创建新的卡牌显示
	print("显示 %d 张卡牌" % hand.cards.size())
	for i in range(hand.cards.size()):
		add_card_display(hand.cards[i], i)

func add_card_display(card: CardData, _index: int = -1) -> void:
	"""添加单张卡牌显示"""
	var tile = card_tile_scene.instantiate()

	# 验证是否是CardTile类型
	if not tile is CardTile:
		print("⚠ 场景未能正确实例化为CardTile类型")
		tile.queue_free()
		return

	# 转换为CardTile类型
	var card_tile: CardTile = tile as CardTile

	# 先添加到场景树，让_ready()执行
	add_child(card_tile)

	# ✅ 改进: 动态计算卡牌间距，让所有13张卡牌都能显示在屏幕内
	var card_count = hand.cards.size() if hand else 1
	var available_width = size.x - 40  # 留出左右各20像素边距
	var card_width = 80
	var spacing = max(10, (available_width - card_width) / float(card_count))  # 动态计算间距

	var x_pos = 20 + (card_tiles.size() * spacing)
	var y_pos = 35
	card_tile.position = Vector2(x_pos, y_pos)
	print("[DEBUG] 卡牌位置: ", card_tile.position, " 全局位置: ", card_tile.global_position)
	print("[DEBUG] 卡牌大小: ", card_tile.size)

	# 现在设置卡牌数据（在add_child之后）
	card_tile.set_card(card)

	# 连接信号 - 使用更安全的方式
	if card_tile.has_signal("card_pressed"):
		card_tile.card_pressed.connect(_on_card_pressed)
	else:
		print("⚠ CardTile没有card_pressed信号")

	if card_tile.has_signal("card_selected"):
		card_tile.card_selected.connect(_on_card_selected)
	else:
		print("⚠ CardTile没有card_selected信号")

	card_tiles.append(card_tile)
	print("添加卡牌显示: %s (位置: %.1f, 间距: %.1f)" % [card.get_card_name(), x_pos, spacing])

func remove_card_display(card: CardData) -> bool:
	"""移除指定卡牌的显示"""
	for i in range(card_tiles.size()):
		if card_tiles[i].card_data == card:
			# ✓ 先保存要移除的卡牌引用
			var removed_tile = card_tiles[i]

			# 从场景树中移除
			removed_tile.queue_free()

			# 从数组中移除
			card_tiles.remove_at(i)

			# ✓ 检查是否移除的是选中卡牌
			if selected_tile == removed_tile:
				selected_tile = null

			print("移除卡牌显示: %s" % card.get_card_name())
			return true
	return false

func select_card(tile: CardTile) -> void:
	"""选中指定卡牌"""
	# 取消之前的选择
	if selected_tile and selected_tile != tile:
		selected_tile.deselect()

	# 选择新卡牌
	selected_tile = tile
	tile.select()
	print("选中卡牌: %s" % tile.card_data.get_card_name())

func get_selected_card() -> CardData:
	"""获取当前选中的卡牌"""
	if selected_tile:
		return selected_tile.card_data
	return null

func get_card_count() -> int:
	"""获取手牌数量"""
	if hand:
		return hand.get_card_count()
	return 0

func clear_hand() -> void:
	"""清空所有手牌显示"""
	for tile in card_tiles:
		tile.queue_free()
	card_tiles.clear()
	selected_tile = null
	print("已清空手牌")

func deselect_all() -> void:
	"""取消所有选中状态"""
	if selected_tile:
		selected_tile.deselect()
		selected_tile = null

func _on_card_pressed(_card_data: CardData) -> void:
	"""卡牌被点击"""
	for tile in card_tiles:
		if tile.card_data == _card_data:
			select_card(tile)
			break
	card_pressed.emit(_card_data)

func _on_card_selected(_card_data: CardData) -> void:
	"""卡牌被选中信号"""
	card_selected.emit(_card_data)
