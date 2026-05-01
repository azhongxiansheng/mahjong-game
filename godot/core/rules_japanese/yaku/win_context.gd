class_name WinContext

var hand: Hand
var melds: Array[Meld]
var winning_tile: Tile
var win_result: Dictionary
var game_context: GameContext

func _init(p_hand: Hand, p_melds: Array[Meld], p_winning: Tile, p_win_result: Dictionary, p_ctx: GameContext) -> void:
	hand = p_hand
	melds = p_melds
	winning_tile = p_winning
	win_result = p_win_result
	game_context = p_ctx

func is_menzen() -> bool:
	return MenzenHelper.is_menzen(melds)

func all_tile_ids() -> Array:
	var ids: Array = hand.to_id_array()
	ids.append(winning_tile.id)
	for m in melds:
		for tid in m.to_id_array():
			ids.append(tid)
	ids.sort()
	return ids
