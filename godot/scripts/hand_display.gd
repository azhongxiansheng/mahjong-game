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

func add_card_display(card: CardData, index: int = -1) -> void:
	"""添加单张卡牌显示"""
	var tile: CardTile = card_tile_scene.instantiate()
	tile.set_card(card)
	add_child(tile)
	
	# 设置位置
	var x_pos = 20 + (card_tiles.size() * 85)
	var y_pos = 35
	tile.position = Vector2(x_pos, y_pos)
	
	# 连接信号
	tile.card_pressed.connect(_on_card_pressed.bind(tile))
	tile.card_selected.connect(_on_card_selected.bind(tile))
	
	card_tiles.append(tile)
	print("添加卡牌显示: %s (位置: %d)" % [card.get_card_name(), x_pos])

func remove_card_display(card: CardData) -> bool:
	"""移除指定卡牌的显示"""
	for i in range(card_tiles.size()):
		if card_tiles[i].card_data == card:
			card_tiles[i].queue_free()
			card_tiles.remove_at(i)
			
			# 如果移除的是选中的卡牌
			if selected_tile == card_tiles[i] if i < card_tiles.size() else null:
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

func _on_card_pressed(tile: CardTile) -> void:
	"""卡牌被点击"""
	select_card(tile)
	card_pressed.emit(tile.card_data)

func _on_card_selected(tile: CardTile) -> void:
	"""卡牌被选中信号"""
	card_selected.emit(tile.card_data)
