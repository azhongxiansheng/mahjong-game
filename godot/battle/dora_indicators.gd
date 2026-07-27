class_name DoraIndicators

# Dora 指示牌容器（spec §5）。
# - visible: 已翻开的指示牌（开局 1 + 每杠 +1）
# - hidden_uradora: 立直胡牌时翻
# 综合 dora 数 = 普通 dora + 赤 dora + (可选) 裏 dora

const MAX_INDICATORS := 5

var _visible: Array[Tile] = []
var _hidden_uradora: Array[Tile] = []

func reveal_pair(visible_tile: Tile, hidden_tile: Tile) -> bool:
	if visible_tile == null or hidden_tile == null \
			or not visible_tile.is_valid() or not hidden_tile.is_valid() \
			or _visible.size() >= MAX_INDICATORS:
		return false
	if visible_tile == hidden_tile:
		return false
	var incoming_ids: Array[int] = []
	for tile in [visible_tile, hidden_tile]:
		if Tile.is_valid_instance_id(tile.instance_id):
			if incoming_ids.has(tile.instance_id) or _contains_instance_id(tile.instance_id):
				return false
			incoming_ids.append(tile.instance_id)
	_visible.append(visible_tile)
	_hidden_uradora.append(hidden_tile)
	return true

func visible_count() -> int:
	return _visible.size()

func visible_tiles() -> Array[Tile]:
	return _visible.duplicate()

func uradora_tiles() -> Array[Tile]:
	return _hidden_uradora.duplicate()

func visible_indicator_ids() -> Array:
	var ids: Array = []
	for t in _visible:
		ids.append(t.id)
	return ids

func uradora_indicator_ids() -> Array:
	var ids: Array = []
	for t in _hidden_uradora:
		ids.append(t.id)
	return ids

func count_total_dora(hand: Hand, called_melds: Array, include_uradora: bool) -> int:
	var total := DoraIndicator.count_normal_dora(hand, called_melds, visible_indicator_ids())
	total += DoraIndicator.count_red_dora(hand, called_melds)
	if include_uradora:
		total += DoraIndicator.count_normal_dora(hand, called_melds, uradora_indicator_ids())
	return total

func restore_pairs(visible_arg: Array[Tile], hidden_arg: Array[Tile]) -> bool:
	if visible_arg.size() != hidden_arg.size() or visible_arg.size() > MAX_INDICATORS:
		return false
	var staged := DoraIndicators.new()
	for i in range(visible_arg.size()):
		if not staged.reveal_pair(visible_arg[i], hidden_arg[i]):
			return false
	_visible = staged._visible
	_hidden_uradora = staged._hidden_uradora
	return true

func _contains_instance_id(instance_id: int) -> bool:
	for tile in _visible:
		if tile.instance_id == instance_id:
			return true
	for tile in _hidden_uradora:
		if tile.instance_id == instance_id:
			return true
	return false
