## 手牌显示管理器
## 负责显示玩家手牌的UI表现，包括排列、分组和交互
class_name HandDisplayManager
extends Control

## 配置
var card_spacing: float = 5.0
var suit_spacing: float = 15.0
var card_ui_scene: String = "res://scenes/card_ui.tscn"

## 内部数据
var hand: CardHand
var card_ui_nodes: Array[CardUI] = []
var selected_card: CardUI = null

## 信号
signal card_selected(card: CardData)
signal card_deselected(card: CardData)

func _ready() -> void:
	custom_minimum_size = Vector2(400, 120)

## 设置手牌
func set_hand(new_hand: CardHand) -> void:
	hand = new_hand
	refresh_display()

## 刷新显示
func refresh_display() -> void:
	# 清空旧的卡牌UI
	for card_ui in card_ui_nodes:
		card_ui.queue_free()
	card_ui_nodes.clear()

	if not hand or hand.cards.size() == 0:
		return

	# 按花色分组卡牌
	var grouped_cards = _group_cards_by_suit(hand.cards)

	# 创建卡牌UI
	_create_card_uis(grouped_cards)

## 按花色分组卡牌
func _group_cards_by_suit(cards: Array[CardData]) -> Array:
	var grouped: Array = []
	var wan_cards: Array[CardData] = []
	var tong_cards: Array[CardData] = []
	var tiao_cards: Array[CardData] = []
	var letter_cards: Array[CardData] = []

	# 分组
	for card in cards:
		match card.suit:
			CardData.Suit.WAN:
				wan_cards.append(card)
			CardData.Suit.TONG:
				tong_cards.append(card)
			CardData.Suit.TIAO:
				tiao_cards.append(card)
			CardData.Suit.ZI:
				letter_cards.append(card)

	# 排序（按数字）
	wan_cards.sort_custom(func(a, b): return a.number < b.number)
	tong_cards.sort_custom(func(a, b): return a.number < b.number)
	tiao_cards.sort_custom(func(a, b): return a.number < b.number)
	letter_cards.sort_custom(func(a, b): return a.number < b.number)

	# 添加到分组数组
	if wan_cards.size() > 0:
		grouped.append({"suit_name": "万", "cards": wan_cards})
	if tong_cards.size() > 0:
		grouped.append({"suit_name": "筒", "cards": tong_cards})
	if tiao_cards.size() > 0:
		grouped.append({"suit_name": "条", "cards": tiao_cards})
	if letter_cards.size() > 0:
		grouped.append({"suit_name": "字", "cards": letter_cards})

	return grouped

## 创建卡牌UI元素
func _create_card_uis(grouped_cards: Array) -> void:
	var current_pos = Vector2(10, 10)

	for group in grouped_cards:
		var suit_name: String = group["suit_name"]
		var cards: Array[CardData] = group["cards"]

		# 绘制花色标签
		var label = Label.new()
		label.text = suit_name
		label.position = current_pos
		add_child(label)

		current_pos.y += 20

		# 创建卡牌
		for card in cards:
			var card_ui = CardUI.new()
			card_ui.set_card(card)
			card_ui.position = current_pos
			card_ui.card_clicked.connect(_on_card_clicked.bindv([card_ui]))
			card_ui.card_hovered.connect(_on_card_hovered.bindv([card_ui]))
			card_ui.card_unhovered.connect(_on_card_unhovered.bindv([card_ui]))

			add_child(card_ui)
			card_ui_nodes.append(card_ui)

			current_pos.x += card_ui.card_width + card_spacing

		current_pos.x = 10
		current_pos.y += card_ui_nodes.back().card_height + suit_spacing

## 卡牌被点击
func _on_card_clicked(card_ui: CardUI) -> void:
	# 取消之前的选择
	if selected_card and selected_card != card_ui:
		selected_card.set_selected(false)

	# 选择新卡牌
	if card_ui.is_selected:
		selected_card = card_ui
		card_selected.emit(card_ui.card_data)
	else:
		selected_card = null
		card_deselected.emit(card_ui.card_data)

## 卡牌被悬停
func _on_card_hovered(card_ui: CardUI) -> void:
	card_ui.set_highlighted(true)

## 卡牌被取消悬停
func _on_card_unhovered(card_ui: CardUI) -> void:
	card_ui.set_highlighted(false)

## 获取选中的卡牌
func get_selected_card() -> CardData:
	if selected_card:
		return selected_card.card_data
	return null

## 清空选择
func clear_selection() -> void:
	if selected_card:
		selected_card.set_selected(false)
		selected_card = null
