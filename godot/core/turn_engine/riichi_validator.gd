class_name RiichiValidator

# 立直触发条件（标准日麻）：门清 + 听牌 + 点数 ≥1000 + 牌墙剩余 ≥4 + 未立直。
# 输入：Seat（13 张听牌期）+ wall_remaining；此函数纯函数不修改 state。

const MIN_POINTS_TO_RIICHI: int = 1000
const MIN_WALL_REMAINING: int = 4

static func can_declare_riichi(seat: Seat, wall_remaining: int) -> bool:
	if seat.riichi.declared:
		return false
	if not seat.is_concealed_hand():
		return false
	if seat.points < MIN_POINTS_TO_RIICHI:
		return false
	if wall_remaining < MIN_WALL_REMAINING:
		return false
	return WaitCalculator.wait_tiles(seat.hand, seat.melds).size() > 0


# 批量：返回弃后听牌的 physical instance_id（与 oracle 集合等价）。
# 不检查 points / wall / 已立直 / 门清。
# 一次构建 34 counts；按 distinct tile type 扣 1 算 shanten==0；
# 同 type 的全部 physical iid 一并纳入；调用内共享 memo，不跨状态缓存。
static func tenpai_discard_instance_ids(hand: Hand, called_melds: Array = []) -> Array:
	var counts: Array[int] = []
	counts.resize(34)
	counts.fill(0)
	var ordered: Array = []
	for t in hand._tiles:
		if t == null:
			continue
		counts[t.id] += 1
		ordered.append(t)

	var called: int = called_melds.size()
	var type_tenpai: Dictionary = {}
	var cache: Dictionary = {}
	# 14 张形若仍在一向听以上，弃掉任意一张都不可能变成 13 张听牌。
	# 绝大多数普通巡目在这里一次判定后返回，避免对每种牌重复递归。
	if ShantenCalculator.calc_from_counts(counts, called, cache) > 0:
		return []
	for tid in range(34):
		if counts[tid] <= 0:
			continue
		counts[tid] -= 1
		type_tenpai[tid] = (ShantenCalculator.calc_from_counts(counts, called, cache) == 0)
		counts[tid] += 1

	var out: Array = []
	for t in ordered:
		if bool(type_tenpai.get(t.id, false)):
			out.append(t.instance_id)
	return out


# 完整 RIICHI discard options：含门清 / 点数 / 墙 / 已立直门槛。
# 返回 Array[{"tile_instance_id": int}]，与 BattleController offers 同形。
# 顺序与 hand._tiles 物理顺序一致（仅保留可立直切牌）。
static func riichi_discard_options(seat: Seat, wall_remaining: int) -> Array:
	if seat.riichi.declared:
		return []
	if not seat.is_concealed_hand():
		return []
	if seat.points < MIN_POINTS_TO_RIICHI:
		return []
	if wall_remaining < MIN_WALL_REMAINING:
		return []
	var out: Array = []
	for iid in tenpai_discard_instance_ids(seat.hand, seat.melds):
		out.append({"tile_instance_id": iid})
	return out
