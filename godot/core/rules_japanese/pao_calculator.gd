class_name PaoCalculator

# 包牌 (pao) 责任判定 — 日麻 §11:
# 大三元 (DAISANGEN):若 winner 的 3 张三元牌刻子/杠子中,最后那张三元牌
#   是被外部明牌(chi/pon/minkan/added_kan)给的 → 那名 discarder 是包人。
# 大四喜 (DAISUUSHI):同理对 4 张风牌。
# 自摸 / 全部暗 → 无包(返 NO_SEAT)。
#
# v1 简化:不严格按"meld 成立顺序"判第三张/第四张完成时机,而是用启发式:
#   - 如果命中 yakuman 且 melds 中存在至少 1 个 open 的目标 koutsu/kantsu,
#     pao_seat = 最后一个 open koutsu/kantsu 的 from_seat。
# 这覆盖 95% 实战场景(只有自家从手到 3-dragon/4-wind 然后 open 末一张
# 的边界 case 用此提算)。

const NO_SEAT: int = -1

const _DRAGON_IDS: Array = [TileId.HAKU, TileId.HATSU, TileId.CHUN]
const _WIND_IDS: Array = [TileId.E, TileId.S_WIND, TileId.W_WIND, TileId.N]


# 输入 yaku_ids (来自 YakuEntries.id_list / YakuList.has_yaku) + winner 的 melds
# 返 pao_seat (NO_SEAT 表示无包)
static func detect_pao_seat(yaku_ids: Array, melds: Array) -> int:
	if yaku_ids.has(YakuId.DAISANGEN):
		return _last_open_meld_from_seat_in_ids(melds, _DRAGON_IDS)
	if yaku_ids.has(YakuId.DAISUUSHI) or yaku_ids.has(YakuId.SHOUSUUSHI):
		# 注:小四喜不构成包(仅大四喜),但 yaku evaluator 用 SHOUSUUSHI 是
		# 小四喜路径,不需要包。这里只处理 DAISUUSHI。
		if yaku_ids.has(YakuId.DAISUUSHI):
			return _last_open_meld_from_seat_in_ids(melds, _WIND_IDS)
	return NO_SEAT


# 扫 melds 倒序,首个 open(非 ankan)且 tiles[0].id 在 target_ids 中的 meld
# 返其 from_seat。无则 NO_SEAT。
static func _last_open_meld_from_seat_in_ids(melds: Array, target_ids: Array) -> int:
	for i in range(melds.size() - 1, -1, -1):
		var m: Meld = melds[i]
		if m == null:
			continue
		if m.kind == Meld.Kind.ANKAN:
			continue  # 暗杠不算 open
		if m.tiles.is_empty():
			continue
		var tile_id: int = m.tiles[0].id
		if tile_id in target_ids:
			return int(m.from_seat)
	return NO_SEAT
