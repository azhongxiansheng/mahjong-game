class_name TurnEngine

# 状态机最小骨架（plan 0e）+ E2-02 / #232 实体 instance_id 权威变更 API。
# 公开动作一律走 instance_id；先完整预检，失败零修改；不接受客户端 Tile 对象。
# 本引擎不发出任何事件 / 信号 — EventBus 接入留里程碑 1。

var state: TableState

func _init(p_state: TableState) -> void:
	state = p_state

# 当前 seat 摸 1 张 live wall；phase → DISCARD。返 null 表示牌墙耗尽。
func draw_for_current() -> Tile:
	var t := state.wall.draw()
	if t == null:
		return null
	var seat: Seat = state.seats[state.current_seat]
	seat.add_to_hand(t)
	# 标记刚摸的实体：权威 last_drawn_instance_id
	seat.last_drawn_instance_id = t.instance_id
	# 普通摸:清岭上标记(若上一动作是岭上摸到现在,中间会经过 _step_discard 已自己 clear,
	# 这里再做一道兜底)。
	seat.last_draw_is_rinshan = false
	# 日麻 §5 同巡振听清除:当事人下一次自摸时,temporary 振听解除。
	seat.furiten.clear_temporary()
	state.phase = BattlePhase.Kind.DISCARD
	return t

# 当前 seat 弃指定实体；从 hand 移到本席牌河；phase → CLAIM。
# 注意：此方法不推进 current_seat（等鸣牌窗口）；调用方在窗口结束后调 advance。
# instance_id: Variant — 比较/查找前严格 is_valid_instance_id（无 int 静默强转）。
func discard(instance_id: Variant) -> bool:
	if state.phase != BattlePhase.Kind.DISCARD:
		return false
	if not Tile.is_valid_instance_id(instance_id):
		return false
	var iid: int = instance_id
	var seat: Seat = state.seats[state.current_seat]
	var found_tile: Tile = seat.hand.find_by_instance_id(iid)
	if found_tile == null:
		return false
	# 提交
	var hand_before: Array[Tile] = seat.hand.tiles()
	var taken: Tile = seat.hand.take_by_instance_id(iid)
	if taken == null:
		return false
	if not seat.river.append_discard(taken):
		seat.hand.restore_tiles(hand_before)
		return false
	seat.last_drawn_instance_id = Tile.INVALID_INSTANCE_ID
	# 日麻 §5 振听规则:每次自家弃牌后,(1)重算 waits;(2)若任一 wait tile
	# 已在自家弃牌堆 → permanent furiten(不能荣胡)。立直振听同样走这条
	# (立直锁牌后听张固定,只要打过 wait 自动落入永久振听)。
	# temporary 振听(同巡见逃)由 BattleController._try_auto_ron 维护。
	_recompute_self_furiten(seat)
	state.phase = BattlePhase.Kind.CLAIM
	return true


# 自家振听检查:13 张听牌张里有任何一张已落进自家弃牌堆 → 永久振听。
# 鸣牌(seat.melds 非空)同样适用,只是 closed-hand 条件由别处控制。
func _recompute_self_furiten(seat: Seat) -> void:
	if seat.hand.size() != 13:
		return
	# 向听数大于 0 时不可能存在听张；先走一次计数 DP，避免普通巡目仍枚举
	# 34 种和牌候选。真正听牌时继续由 WaitCalculator 给出权威 waits。
	if ShantenCalculator.calc(seat.hand, seat.melds.all()) > 0:
		seat.furiten.update_waits([])
		seat.furiten.permanent = false
		return
	var waits: Array = WaitCalculator.wait_tiles(seat.hand, seat.melds.all())
	seat.furiten.update_waits(waits)
	# 判断自家弃牌中是否含任一 wait
	var hit: bool = false
	if not waits.is_empty():
		for tile in seat.river.tiles():
			if tile != null and waits.has(tile.id):
				hit = true
				break
	seat.furiten.permanent = hit

# 推 current_seat 到下家；phase → DRAW；维护 turn_count + first_round_active。
# 仅在 CLAIM 窗口无人鸣牌时调用；鸣牌成立时由 apply_xxx 自行设 current_seat。
func advance_to_next_seat() -> void:
	state.current_seat = (state.current_seat + 1) % 4
	state.phase = BattlePhase.Kind.DRAW
	if state.current_seat == state.dealer_seat:
		state.turn_count += 1
		if state.turn_count > 1:
			state.first_round_active = false

# 立直 + 弃牌原子：14 张手中弃 instance_id 后须听牌；失败零修改。
func declare_riichi_and_discard(seat_id: Variant, instance_id: Variant) -> bool:
	if state.phase != BattlePhase.Kind.DISCARD:
		return false
	if not _is_valid_seat(seat_id):
		return false
	var sid: int = seat_id
	if sid != state.current_seat:
		return false
	if not Tile.is_valid_instance_id(instance_id):
		return false
	var iid: int = instance_id
	var seat: Seat = state.seats[sid]
	if seat.riichi.declared:
		return false
	if not seat.is_concealed_hand():
		return false
	if seat.points < RiichiValidator.MIN_POINTS_TO_RIICHI:
		return false
	if state.wall.live_wall_size() < RiichiValidator.MIN_WALL_REMAINING:
		return false
	var target: Tile = seat.hand.find_by_instance_id(iid)
	if target == null:
		return false
	# 预检听牌：模拟弃后 13 张
	var sim := seat.hand.clone()
	if sim.take_by_instance_id(iid) == null:
		return false
	if WaitCalculator.wait_tiles(sim, seat.melds.all()).is_empty():
		return false
	# 提交：先弃再立直（riichi_discard_index = 河末位）
	var hand_before: Array[Tile] = seat.hand.tiles()
	var taken: Tile = seat.hand.take_by_instance_id(iid)
	if taken == null:
		return false
	if not seat.river.append_discard(taken, true):
		seat.hand.restore_tiles(hand_before)
		return false
	seat.last_drawn_instance_id = Tile.INVALID_INSTANCE_ID
	_recompute_self_furiten(seat)
	state.phase = BattlePhase.Kind.CLAIM
	var is_double: bool = state.first_round_active and state.turn_count == 0
	seat.riichi.declare(state.turn_count, is_double)
	seat.adjust_points(-1000)
	seat.riichi.pay_stick()
	state.riichi_sticks += 1
	return true

# ---- 鸣牌应用（实体 API）----

# 吃顺子：companion_instance_ids 长度 2。
func apply_chi(claimant_seat: Variant, claimed_instance_id: Variant,
		companion_instance_ids: Array) -> bool:
	if state.phase != BattlePhase.Kind.CLAIM:
		return false
	if not _is_valid_seat(claimant_seat):
		return false
	var cs: int = claimant_seat
	if not Tile.is_valid_instance_id(claimed_instance_id):
		return false
	var claimed_iid: int = claimed_instance_id
	if companion_instance_ids.size() != 2:
		return false
	if _ids_invalid_or_duplicate(companion_instance_ids):
		return false
	var discarder_seat: int = state.current_seat
	if cs == discarder_seat:
		return false
	var claimed: Tile = _last_discard_tile()
	if claimed == null or claimed.instance_id != claimed_iid:
		return false
	var claimant: Seat = state.seats[cs]
	if not ClaimValidator.can_chi(cs, discarder_seat, claimant.hand, claimed.id):
		return false
	# 预检 companion 均在手且牌种构成合法顺子
	var companion_tiles: Array[Tile] = []
	for raw in companion_instance_ids:
		var ct: Tile = claimant.hand.find_by_instance_id(raw)
		if ct == null:
			return false
		companion_tiles.append(ct)
	if not _companions_form_valid_chi(claimed.id, companion_tiles):
		return false
	# 提交：先取牌 → 再分配 meld_id → 再构造 Meld（不直接写 identity 字段）
	var hand_before: Array[Tile] = claimant.hand.tiles()
	var taken: Variant = claimant.hand.take_many_by_instance_ids(companion_instance_ids)
	if taken == null:
		return false
	var meld_tiles: Array[Tile] = [claimed]
	for t in taken:
		meld_tiles.append(t)
	meld_tiles.sort_custom(func(a, b): return a.id < b.id)
	var meld: Meld = claimant.melds.add_chi(meld_tiles, discarder_seat, claimed)
	if meld == null:
		claimant.hand.restore_tiles(hand_before)
		return false
	_pop_discard_clearing_riichi_index(discarder_seat)
	_after_claim(cs)
	_clear_all_ippatsu_windows()
	return true

# 碰：companion_instance_ids 长度 2，牌种须与 claimed 相同。
func apply_pon(claimant_seat: Variant, claimed_instance_id: Variant,
		companion_instance_ids: Array) -> bool:
	if state.phase != BattlePhase.Kind.CLAIM:
		return false
	if not _is_valid_seat(claimant_seat):
		return false
	var cs: int = claimant_seat
	if not Tile.is_valid_instance_id(claimed_instance_id):
		return false
	var claimed_iid: int = claimed_instance_id
	if companion_instance_ids.size() != 2:
		return false
	if _ids_invalid_or_duplicate(companion_instance_ids):
		return false
	var discarder_seat: int = state.current_seat
	if cs == discarder_seat:
		return false
	var claimed: Tile = _last_discard_tile()
	if claimed == null or claimed.instance_id != claimed_iid:
		return false
	var claimant: Seat = state.seats[cs]
	if not ClaimValidator.can_pon(cs, discarder_seat, claimant.hand, claimed.id):
		return false
	for raw in companion_instance_ids:
		var ct: Tile = claimant.hand.find_by_instance_id(raw)
		if ct == null or ct.id != claimed.id:
			return false
	var hand_before: Array[Tile] = claimant.hand.tiles()
	var taken: Variant = claimant.hand.take_many_by_instance_ids(companion_instance_ids)
	if taken == null:
		return false
	var meld_tiles: Array[Tile] = [claimed]
	for t in taken:
		meld_tiles.append(t)
	var meld: Meld = claimant.melds.add_pon(meld_tiles, discarder_seat, claimed)
	if meld == null:
		claimant.hand.restore_tiles(hand_before)
		return false
	_pop_discard_clearing_riichi_index(discarder_seat)
	_after_claim(cs)
	_clear_all_ippatsu_windows()
	return true

# 明杠：companion_instance_ids 长度 3；翻 dora；摸岭上。
func apply_minkan(claimant_seat: Variant, claimed_instance_id: Variant,
		companion_instance_ids: Array) -> bool:
	if state.phase != BattlePhase.Kind.CLAIM:
		return false
	if not _is_valid_seat(claimant_seat):
		return false
	var cs: int = claimant_seat
	if not Tile.is_valid_instance_id(claimed_instance_id):
		return false
	var claimed_iid: int = claimed_instance_id
	if companion_instance_ids.size() != 3:
		return false
	if _ids_invalid_or_duplicate(companion_instance_ids):
		return false
	var discarder_seat: int = state.current_seat
	if cs == discarder_seat:
		return false
	var claimed: Tile = _last_discard_tile()
	if claimed == null or claimed.instance_id != claimed_iid:
		return false
	var claimant: Seat = state.seats[cs]
	if not ClaimValidator.can_minkan(cs, discarder_seat, claimant.hand, claimed.id):
		return false
	for raw in companion_instance_ids:
		var ct: Tile = claimant.hand.find_by_instance_id(raw)
		if ct == null or ct.id != claimed.id:
			return false
	var hand_before: Array[Tile] = claimant.hand.tiles()
	var taken: Variant = claimant.hand.take_many_by_instance_ids(companion_instance_ids)
	if taken == null:
		return false
	var meld_tiles: Array[Tile] = [claimed]
	for t in taken:
		meld_tiles.append(t)
	var meld: Meld = claimant.melds.add_minkan(meld_tiles, discarder_seat, claimed)
	if meld == null:
		claimant.hand.restore_tiles(hand_before)
		return false
	_pop_discard_clearing_riichi_index(discarder_seat)
	_reveal_new_dora()
	_take_rinshan_to(claimant)
	state.current_seat = cs
	state.phase = BattlePhase.Kind.DISCARD
	state.first_round_active = false
	_clear_all_ippatsu_windows()
	return true

# 暗杠：instance_ids 长度 4，同牌种；翻 dora；摸岭上。
func apply_ankan(seat_id: Variant, instance_ids: Array) -> bool:
	if state.phase != BattlePhase.Kind.DISCARD:
		return false
	if not _is_valid_seat(seat_id):
		return false
	var sid: int = seat_id
	if sid != state.current_seat:
		return false
	if instance_ids.size() != 4:
		return false
	if _ids_invalid_or_duplicate(instance_ids):
		return false
	var seat: Seat = state.seats[sid]
	var tiles_found: Array[Tile] = []
	var tile_id: int = -1
	for raw in instance_ids:
		var t: Tile = seat.hand.find_by_instance_id(raw)
		if t == null:
			return false
		if tile_id < 0:
			tile_id = t.id
		elif t.id != tile_id:
			return false
		tiles_found.append(t)
	if seat.hand.count_of(tile_id) < 4:
		return false
	var hand_before: Array[Tile] = seat.hand.tiles()
	var taken: Variant = seat.hand.take_many_by_instance_ids(instance_ids)
	if taken == null:
		return false
	var meld_tiles: Array[Tile] = []
	for t in taken:
		meld_tiles.append(t)
	var meld: Meld = seat.melds.add_ankan(meld_tiles)
	if meld == null:
		seat.hand.restore_tiles(hand_before)
		return false
	_reveal_new_dora()
	_take_rinshan_to(seat)
	state.phase = BattlePhase.Kind.DISCARD
	state.first_round_active = false
	_clear_all_ippatsu_windows()
	return true

# 加杠：按 meld_id 升级原 PON，保留 meld_id / called / source，只追加指定实体。
# 经 Meld.promote_to_added_kan 一次性写入 added identity；不直接写 Meld identity 字段。
func apply_added_kan(seat_id: Variant, meld_id: Variant, added_instance_id: Variant) -> bool:
	if state.phase != BattlePhase.Kind.DISCARD:
		return false
	if not _is_valid_seat(seat_id):
		return false
	var sid: int = seat_id
	if sid != state.current_seat:
		return false
	if not Tile.is_valid_instance_id(added_instance_id):
		return false
	var added_iid: int = added_instance_id
	if not Meld.is_valid_meld_id(meld_id):
		return false
	var mid: int = meld_id
	var seat: Seat = state.seats[sid]
	var target: Meld = null
	target = seat.melds.find_by_id(mid)
	if target == null or target.kind != Meld.Kind.PON:
		return false
	var fourth: Tile = seat.hand.find_by_instance_id(added_iid)
	if fourth == null:
		return false
	if target.tiles.is_empty() or fourth.id != target.tiles[0].id:
		return false
	if not ClaimValidator.can_added_kan(seat.melds.all(), seat.hand, fourth.id):
		return false
	var hand_before: Array[Tile] = seat.hand.tiles()
	var taken: Tile = seat.hand.take_by_instance_id(added_iid)
	if taken == null:
		return false
	if not seat.melds.promote_pon(mid, taken):
		# 理论预检后不应失败；失败时回滚手牌保证零修改语义
		seat.hand.restore_tiles(hand_before)
		return false
	_reveal_new_dora()
	_take_rinshan_to(seat)
	state.phase = BattlePhase.Kind.DISCARD
	state.first_round_active = false
	_clear_all_ippatsu_windows()
	return true

# 荣胡：claimed 必须是当前河末实体；经 ClaimValidator.can_ron 真校验。
# ClaimValidator.can_ron 不含 seat 关系 → 本函数拒绝 self-ron（claimant == discarder）。
func apply_ron(claimant_seat: Variant, claimed_instance_id: Variant) -> bool:
	if state.phase != BattlePhase.Kind.CLAIM:
		return false
	if not _is_valid_seat(claimant_seat):
		return false
	var cs: int = claimant_seat
	if cs == state.current_seat:
		return false
	if not Tile.is_valid_instance_id(claimed_instance_id):
		return false
	var claimed_iid: int = claimed_instance_id
	var claimed: Tile = _last_discard_tile()
	if claimed == null or claimed.instance_id != claimed_iid:
		return false
	var claimant: Seat = state.seats[cs]
	# 真实签名：can_ron(hand, melds, discarded_tile, furiten_state)
	if not ClaimValidator.can_ron(claimant.hand, claimant.melds.all(), claimed, claimant.furiten):
		return false
	state.current_seat = cs
	state.phase = BattlePhase.Kind.SETTLE
	return true

# 自摸：仅与权威 last_drawn_instance_id 比较；clone 14 张后移除和牌实体再 can_tsumo。
func apply_tsumo(seat_id: Variant, claimed_last_drawn_instance_id: Variant) -> bool:
	if state.phase != BattlePhase.Kind.DISCARD:
		return false
	if not _is_valid_seat(seat_id):
		return false
	var sid: int = seat_id
	if sid != state.current_seat:
		return false
	if not Tile.is_valid_instance_id(claimed_last_drawn_instance_id):
		return false
	var claimed_iid: int = claimed_last_drawn_instance_id
	var seat: Seat = state.seats[sid]
	if seat.last_drawn_instance_id != claimed_iid:
		return false
	var drawn: Tile = seat.hand.find_by_instance_id(claimed_iid)
	if drawn == null:
		return false
	# clone 当前 14 张，精确移除 last_drawn，以剩余 13 张 + winning tile 校验
	var without: Hand = seat.hand.clone()
	if without.take_by_instance_id(claimed_iid) == null:
		return false
	if not ClaimValidator.can_tsumo(without, seat.melds.all(), drawn):
		return false
	state.current_seat = sid
	state.phase = BattlePhase.Kind.SETTLE
	return true

# ---- 内部 helper ----

# seat 索引 fail-closed：精确 TYPE_INT 且 0..state.seats.size()-1。
func _is_valid_seat(seat: Variant) -> bool:
	if typeof(seat) != TYPE_INT:
		return false
	var s: int = seat
	return s >= 0 and s < state.seats.size()

func _last_discard_tile() -> Tile:
	return state.seats[state.current_seat].river.last_tile()

# fail-closed：禁止 int(raw) 静默强转。
func _ids_invalid_or_duplicate(ids: Array) -> bool:
	var seen: Dictionary = {}
	for raw in ids:
		if not Tile.is_valid_instance_id(raw):
			return true
		var iid: int = raw
		if seen.has(iid):
			return true
		seen[iid] = true
	return false

func _companions_form_valid_chi(claimed_id: int, companions: Array[Tile]) -> bool:
	if companions.size() != 2:
		return false
	if TileId.is_honor(claimed_id):
		return false
	var pair: Array = [companions[0].id, companions[1].id]
	pair.sort()
	var a: int = pair[0]
	var b: int = pair[1]
	var d: int = claimed_id
	var n: int = TileId.number(d)
	# [d-2, d-1, d] / [d-1, d, d+1] / [d, d+1, d+2]
	if a == d - 2 and b == d - 1:
		return n >= 3
	if a == d - 1 and b == d + 1:
		return n >= 2 and n <= 8
	if a == d + 1 and b == d + 2:
		return n <= 7
	return false

func _after_claim(claimant_seat: int) -> void:
	state.current_seat = claimant_seat
	state.phase = BattlePhase.Kind.DISCARD
	state.first_round_active = false
	# chi/pon 后 claimant 没真摸牌，不显示"刚摸"分隔
	state.seats[claimant_seat].last_drawn_instance_id = Tile.INVALID_INSTANCE_ID

func _reveal_new_dora() -> void:
	var n: int = state.dora_indicators.visible_count()
	var indicator: Tile = state.wall.peek_dora_indicator(n)
	# 加杠/暗杠时同时预置对应裏 dora 指示牌(立直胡时翻出)。日麻规则:
	# 每翻 1 张明 dora,对应位置的裏 dora 同步存在 — 等立直胡牌时一起亮。
	var ura: Tile = state.wall.peek_uradora_indicator(n)
	if indicator != null and ura != null:
		state.dora_indicators.reveal_pair(indicator, ura)

func _take_rinshan_to(seat: Seat) -> void:
	var t: Tile = state.wall.take_rinshan()
	if t != null:
		seat.add_to_hand(t)
		seat.last_drawn_instance_id = t.instance_id
		# 标记 last_draw_is_rinshan,让 BC._step_discard 检 tsumo 时识别为岭上开花
		seat.last_draw_is_rinshan = true


# 日麻 §6.4 一発:任何鸣牌(吃/碰/明杠/暗杠/加杠)都立刻关闭所有座位
# 一発窗。BattleController._step_discard 在 riichi 玩家下一巡自家弃牌前
# 也会自己关窗 — 两层 cover 保险。
func _clear_all_ippatsu_windows() -> void:
	for seat in state.seats:
		if seat.riichi.ippatsu_window:
			seat.riichi.consume_ippatsu()


# 移除 discarder 河末实体；DiscardRiver 同步维护立直牌索引。
func _pop_discard_clearing_riichi_index(discarder_seat: int) -> void:
	var river: DiscardRiver = state.seats[discarder_seat].river
	var last: Tile = river.last_tile()
	if last != null:
		river.claim_last(last.instance_id)
