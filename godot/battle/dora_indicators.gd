class_name DoraIndicators

# Dora 指示牌容器（spec §5）。
# - visible: 已翻开的指示牌（开局 1 + 每杠 +1）
# - hidden_uradora: 立直胡牌时翻
# 综合 dora 数 = 普通 dora + 赤 dora + (可选) 裏 dora

var visible: Array = []
var hidden_uradora: Array = []

func add_visible(tile: Tile) -> void:
	visible.append(tile)

func add_hidden_uradora(tile: Tile) -> void:
	hidden_uradora.append(tile)

func visible_indicator_ids() -> Array:
	var ids: Array = []
	for t in visible:
		ids.append(t.id)
	return ids

func uradora_indicator_ids() -> Array:
	var ids: Array = []
	for t in hidden_uradora:
		ids.append(t.id)
	return ids

func count_total_dora(hand: Hand, called_melds: Array, include_uradora: bool) -> int:
	var total := DoraIndicator.count_normal_dora(hand, called_melds, visible_indicator_ids())
	total += DoraIndicator.count_red_dora(hand, called_melds)
	if include_uradora:
		total += DoraIndicator.count_normal_dora(hand, called_melds, uradora_indicator_ids())
	return total
