class_name FuCalculator

# 综合符算入口。流程：
#   1. 七対子 → 25 固定
#   2. 役满 → 0（不参与，由 ScoreFormula 直接走役满档）
#   3. 平和自摸 → 20；平和荣胡 → 30
#   4. 否则：副底 20 + 自摸 +2 + 门清荣胡 +10 + 雀头符 + 待牌符 + 面子符
#   5. 向上取整到 10
#
# 门清判定：called_melds 中只允许 ANKAN（暗杠不破坏门清）
# 荣胡完成的刻子（含 winning_tile 的刻子）算明刻

static func calculate(decomposition: Dictionary, called_melds: Array, win_ctx: ScoreContext, yaku_list: YakuList) -> int:
	return int(breakdown(decomposition, called_melds, win_ctx, yaku_list).get("rounded_fu", 0))


# UI 与回放消费的权威符组成。每项只记录实际产生的符，避免展示层重算规则。
static func breakdown(decomposition: Dictionary, called_melds: Array,
		win_ctx: ScoreContext, yaku_list: YakuList) -> Dictionary:
	if yaku_list.is_yakuman:
		return _fixed_breakdown("yakuman", "役满不计符", 0)
	if yaku_list.is_chiitoi():
		return _fixed_breakdown("chiitoi", "七对子固定", 25)

	var is_concealed_hand := _is_concealed(called_melds)

	if yaku_list.is_pinfu():
		var pinfu := 20 if win_ctx.is_tsumo else 30
		return _fixed_breakdown("pinfu", "平和%s固定" % (
			"自摸" if win_ctx.is_tsumo else "荣和"), pinfu)

	var items: Array = []
	_append_item(items, "base", "副底", 20)

	if win_ctx.is_tsumo:
		_append_item(items, "tsumo", "自摸", 2)
	elif is_concealed_hand:
		_append_item(items, "menzen_ron", "门清荣和", 10)

	_append_item(items, "pair", "役牌雀头",
		PairFu.fu_for_pair(decomposition.pair, win_ctx.round_wind, win_ctx.seat_wind))
	_append_item(items, "wait", "边张／嵌张／单骑听牌",
		WaitFu.fu_for_wait(decomposition, win_ctx.winning_tile.id))

	# decomposition 内的面子（暗牌分解）
	for meld_ids in decomposition.melds:
		var is_concealed_meld := true
		# 荣胡 + 含 winning 的刻子 → 明刻
		if not win_ctx.is_tsumo and meld_ids[0] == meld_ids[1] and (win_ctx.winning_tile.id in meld_ids):
			is_concealed_meld = false
		var meld_fu := MeldFu.fu_for_decomp_meld(meld_ids, is_concealed_meld)
		_append_item(items, "meld", _decomp_meld_label(meld_ids, is_concealed_meld), meld_fu)

	# 副露面子
	for meld in called_melds:
		_append_item(items, "meld", _called_meld_label(meld),
			MeldFu.fu_for_called_meld(meld))

	var raw_fu := 0
	for item in items:
		raw_fu += int(item.get("fu", 0))
	return {
		"kind": "standard",
		"items": items,
		"raw_fu": raw_fu,
		"rounded_fu": _ceil_to_10(raw_fu),
	}


static func _fixed_breakdown(kind: String, label: String, fu: int) -> Dictionary:
	return {
		"kind": kind,
		"items": [{"key": kind, "label": label, "fu": fu}],
		"raw_fu": fu,
		"rounded_fu": fu,
	}


static func _append_item(items: Array, key: String, label: String, fu: int) -> void:
	if fu <= 0:
		return
	items.append({"key": key, "label": label, "fu": fu})


static func _decomp_meld_label(meld_ids: Array, concealed: bool) -> String:
	if meld_ids.size() < 3 or meld_ids[0] != meld_ids[1]:
		return "顺子"
	var group := "幺九牌" if TileId.is_yaochu(int(meld_ids[0])) else "中张牌"
	return "%s刻·%s" % ["暗" if concealed else "明", group]


static func _called_meld_label(meld: Meld) -> String:
	var group := "幺九牌" if meld.tiles.size() > 0 \
		and TileId.is_yaochu(int(meld.tiles[0].id)) else "中张牌"
	match meld.kind:
		Meld.Kind.PON:
			return "明刻·%s" % group
		Meld.Kind.ANKAN:
			return "暗杠·%s" % group
		Meld.Kind.MINKAN, Meld.Kind.ADDED_KAN:
			return "明杠·%s" % group
	return "顺子"

static func _is_concealed(called_melds: Array) -> bool:
	for m in called_melds:
		if m.kind != Meld.Kind.ANKAN:
			return false
	return true

static func _ceil_to_10(fu: int) -> int:
	@warning_ignore("integer_division")
	var rounded: int = ((fu + 9) / 10) * 10
	return rounded
