class_name Pinfu

static func detect(wc: WinContext) -> YakuEntry:
	if not wc.win_result.is_winning:
		return null
	if wc.win_result.is_chiitoi or wc.win_result.is_kokushi:
		return null
	if not wc.is_menzen():
		return null
	# Pinfu disallows kans (even ankan): kan = triplet, breaks "all sequences"
	for m in wc.melds:
		if m.is_kan():
			return null
	# Try every standard decomposition; pinfu valid if any qualifies
	for d in wc.win_result.standard_decompositions:
		if _check_decomposition(wc, d):
			return YakuEntry.new(YakuId.PINFU, 1, false, 0)
	return null

static func _check_decomposition(wc: WinContext, decomp: Dictionary) -> bool:
	# Condition 2: all 4 melds are sequences
	for meld_ids in decomp.melds:
		if meld_ids[0] == meld_ids[1]:  # triplet (a == b)
			return false
	# Condition 3: pair is not yakuhai
	if _is_yakuhai_pair(decomp.pair, wc.game_context):
		return false
	# Condition 4: ryanmen wait
	if not _has_ryanmen_wait(decomp, wc.winning_tile.id):
		return false
	return true

static func _is_yakuhai_pair(pair_id: int, ctx: GameContext) -> bool:
	if pair_id == TileId.HAKU or pair_id == TileId.HATSU or pair_id == TileId.CHUN:
		return true
	if pair_id == ctx.bakaze:
		return true
	if pair_id == ctx.jikaze:
		return true
	return false

# Find any sequence containing winning_id where winning is at an end AND the wait is ryanmen
# (not penchan = 1-2-3 won at 3 or 7-8-9 won at 7; not kanchan = winning at middle).
# If winning is the pair (not in any sequence), it's tanki — return false.
# If winning_id is in multiple sequences, ryanmen if ANY is ryanmen.
# Note: if winning is ALSO part of a triplet via shanpon, this never reaches pinfu (condition 2 fails).
static func _has_ryanmen_wait(decomp: Dictionary, winning_id: int) -> bool:
	for meld_ids in decomp.melds:
		# Must be sequence (already verified by caller)
		if meld_ids[0] == meld_ids[1]:
			continue
		var is_in_seq: bool = winning_id == meld_ids[0] or winning_id == meld_ids[1] or winning_id == meld_ids[2]
		if not is_in_seq:
			continue
		var classification := _classify_wait_in_sequence(meld_ids, winning_id)
		if classification == "ryanmen":
			return true
	return false

# Returns one of: "ryanmen", "kanchan", "penchan", "" (winning not in this seq)
static func _classify_wait_in_sequence(meld_ids: Array, winning_id: int) -> String:
	# meld_ids = [a, a+1, a+2] (consecutive within suit)
	if winning_id == meld_ids[1]:
		return "kanchan"  # 嵌张
	if winning_id == meld_ids[0]:
		# Won at left end (a); held b-c, waited a or a+3
		# Penchan iff a+3 > 9 within suit, i.e., (a+2) is 9, i.e., c is 9.
		if TileId.number(meld_ids[2]) == 9:
			return "penchan"
		return "ryanmen"
	if winning_id == meld_ids[2]:
		# Won at right end (c); held a-b, waited c or a-1
		# Penchan iff a-1 < 1, i.e., a is 1 (so meld is 1-2-3)
		if TileId.number(meld_ids[0]) == 1:
			return "penchan"
		return "ryanmen"
	return ""
