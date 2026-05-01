class_name WinPattern

# detect: 综合三种和牌型识别
# hand: 暗牌（不含副露）
# melds: 已副露面子（吃/碰/杠）
# winning_tile: 自摸或荣胡的那张（必加入计算）
#
# 总张数公式：
#   暗牌张 + 副露贡献 = 13 张听牌期 + 1 张和牌张 = 14 张等价手
#   副露贡献：CHI/PON 各 3 张，KAN（任意）3 张（实际 4 张但杠子作为 1 个面子计 3 张算暗牌等价）
# 简化：要求 hand.size() + 3 * melds.size() + 1 == 14
#   即 hand.size() == 13 - 3 * melds.size()
static func detect(hand: Hand, melds: Array[Meld], winning_tile: Tile) -> Dictionary:
	var result := {
		"is_winning": false,
		"is_chiitoi": false,
		"is_kokushi": false,
		"is_thirteen_wait": false,
		"standard_decompositions": [],
	}

	# 张数校验
	var expected_hand_size := 13 - 3 * melds.size()
	if hand.size() != expected_hand_size:
		return result

	# 全部 14 张 id 列表（含和牌张 + 副露中的牌）
	var combined_ids: Array = hand.to_id_array()
	combined_ids.append(winning_tile.id)
	combined_ids.sort()

	# 七対子（无副露才有效）
	if melds.size() == 0:
		if ChiitoiDetector.is_chiitoi(combined_ids):
			result.is_chiitoi = true
			result.is_winning = true

	# 国士無双（无副露才有效）
	if melds.size() == 0:
		var hand_ids := hand.to_id_array()
		var k := KokushiDetector.detect_with_winning(hand_ids, winning_tile.id)
		if k.is_kokushi:
			result.is_kokushi = true
			result.is_thirteen_wait = k.is_thirteen_wait
			result.is_winning = true

	# 标准 4 面子+1 雀头
	var standard_input: Array = combined_ids
	var decomps := StandardDecomposer.decompose(standard_input)
	if decomps.size() > 0:
		result.standard_decompositions = decomps
		result.is_winning = true

	return result
