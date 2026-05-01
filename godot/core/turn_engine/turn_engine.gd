class_name TurnEngine

# 状态机最小骨架（plan 0e）。
# 范围：draw_for_current / discard / advance_to_next_seat / declare_riichi。
# 鸣牌 (chi/pon/kan) 与胡牌 (ron/tsumo) 的"应用"操作留下一计划（plan 0f）。
# 本引擎不发出任何事件 / 信号 — EventBus 接入留里程碑 1。

var state: BattleState

func _init(p_state: BattleState) -> void:
	state = p_state

# 当前 seat 摸 1 张 live wall；phase → DISCARD。返 null 表示牌墙耗尽。
func draw_for_current() -> Tile:
	var t := state.wall.draw()
	if t == null:
		return null
	state.seats[state.current_seat].add_to_hand(t)
	state.phase = BattlePhase.Kind.DISCARD
	return t

# 当前 seat 弃指定 id；从 hand 移到 discards_per_seat；phase → CLAIM。
# 注意：此方法不推进 current_seat（等鸣牌窗口）；调用方在窗口结束后调 advance。
func discard(tile_id: int) -> bool:
	var seat: Seat = state.seats[state.current_seat]
	# 找到要弃的物理 Tile（保留 owner_seat / is_red_dora 等元数据）
	var found_tile: Tile = null
	for t in seat.hand._tiles:
		if t.id == tile_id:
			found_tile = t
			break
	if found_tile == null:
		return false
	seat.hand.remove_by_id(tile_id)
	state.discards_per_seat[state.current_seat].append(found_tile)
	state.phase = BattlePhase.Kind.CLAIM
	return true

# 推 current_seat 到下家；phase → DRAW；维护 turn_count + first_round_active。
# 仅在 CLAIM 窗口无人鸣牌时调用；鸣牌成立时由 apply_xxx 自行设 current_seat。
func advance_to_next_seat() -> void:
	state.current_seat = (state.current_seat + 1) % 4
	state.phase = BattlePhase.Kind.DRAW
	if state.current_seat == state.dealer_seat:
		state.turn_count += 1
		if state.turn_count > 1:
			state.first_round_active = false

# 立直宣告：调 RiichiValidator + RiichiState.declare + 扣 1000 点 + 桌面 stick +1。
# 返 false 表示不满足条件，state 不动。
func declare_riichi(seat_id: int) -> bool:
	var seat: Seat = state.seats[seat_id]
	if not RiichiValidator.can_declare_riichi(seat, state.wall.live_wall_size()):
		return false
	var is_double: bool = state.first_round_active and state.turn_count == 0
	seat.riichi.declare(state.turn_count, is_double)
	seat.adjust_points(-1000)
	seat.riichi.pay_stick()
	state.riichi_sticks += 1
	return true

# ---- 鸣牌应用 ----

# 吃顺子：claimant_seat 接管 discarder 弃牌；hand 移出 companion_ids 两张。
# 推进 current_seat=claimant，phase=DISCARD（claimant 直接弃）。鸣牌打破第一巡。
func apply_chi(claimant_seat: int, claimed_tile: Tile, companion_ids: Array) -> bool:
	var discarder_seat: int = state.current_seat
	var claimant: Seat = state.seats[claimant_seat]
	if not ClaimValidator.can_chi(claimant_seat, discarder_seat, claimant.hand, claimed_tile.id):
		return false
	if companion_ids.size() != 2:
		return false
	# hand 移出两张构成牌，组合成 meld
	var meld_tiles: Array[Tile] = [claimed_tile]
	for cid in companion_ids:
		var found: Tile = _take_from_hand(claimant.hand, cid)
		if found == null:
			# 回滚：companion 缺
			return false
		meld_tiles.append(found)
	meld_tiles.sort_custom(func(a, b): return a.id < b.id)
	claimant.melds.append(Meld.make_chi(meld_tiles, discarder_seat))
	state.discards_per_seat[discarder_seat].pop_back()
	_after_claim(claimant_seat)
	return true

# 碰：claimant_seat 接管弃牌，hand 出 2 张同 id
func apply_pon(claimant_seat: int, claimed_tile: Tile) -> bool:
	var discarder_seat: int = state.current_seat
	var claimant: Seat = state.seats[claimant_seat]
	if not ClaimValidator.can_pon(claimant_seat, discarder_seat, claimant.hand, claimed_tile.id):
		return false
	var meld_tiles: Array[Tile] = [claimed_tile]
	for _i in range(2):
		meld_tiles.append(_take_from_hand(claimant.hand, claimed_tile.id))
	claimant.melds.append(Meld.make_pon(meld_tiles, discarder_seat))
	state.discards_per_seat[discarder_seat].pop_back()
	_after_claim(claimant_seat)
	return true

# 明杠：hand 出 3 张同 id；翻新 dora；摸岭上
func apply_minkan(claimant_seat: int, claimed_tile: Tile) -> bool:
	var discarder_seat: int = state.current_seat
	var claimant: Seat = state.seats[claimant_seat]
	if not ClaimValidator.can_minkan(claimant_seat, discarder_seat, claimant.hand, claimed_tile.id):
		return false
	var meld_tiles: Array[Tile] = [claimed_tile]
	for _i in range(3):
		meld_tiles.append(_take_from_hand(claimant.hand, claimed_tile.id))
	claimant.melds.append(Meld.make_minkan(meld_tiles, discarder_seat))
	state.discards_per_seat[discarder_seat].pop_back()
	_reveal_new_dora()
	_take_rinshan_to(claimant)
	state.current_seat = claimant_seat
	state.phase = BattlePhase.Kind.DISCARD
	state.first_round_active = false
	return true

# 暗杠（自家回合）：hand 出 4 张同 id；翻新 dora；摸岭上
func apply_ankan(seat_id: int, tile_id: int) -> bool:
	var seat: Seat = state.seats[seat_id]
	if seat.hand.count_of(tile_id) < 4:
		return false
	var meld_tiles: Array[Tile] = []
	for _i in range(4):
		meld_tiles.append(_take_from_hand(seat.hand, tile_id))
	seat.melds.append(Meld.make_ankan(meld_tiles))
	_reveal_new_dora()
	_take_rinshan_to(seat)
	state.phase = BattlePhase.Kind.DISCARD
	state.first_round_active = false
	return true

# 加杠：hand 出 1 张匹配 PON 的 id；替换 PON → ADDED_KAN；翻 dora；摸岭上
func apply_added_kan(seat_id: int, tile_id: int) -> bool:
	var seat: Seat = state.seats[seat_id]
	if not ClaimValidator.can_added_kan(seat.melds, seat.hand, tile_id):
		return false
	var fourth: Tile = _take_from_hand(seat.hand, tile_id)
	# 找到对应 PON 并替换
	for i in range(seat.melds.size()):
		var m: Meld = seat.melds[i]
		if m.kind == Meld.Kind.PON and m.tiles[0].id == tile_id:
			var combined: Array[Tile] = []
			for t in m.tiles:
				combined.append(t)
			combined.append(fourth)
			seat.melds[i] = Meld.make_added_kan(combined, m.from_seat)
			break
	_reveal_new_dora()
	_take_rinshan_to(seat)
	state.phase = BattlePhase.Kind.DISCARD
	state.first_round_active = false
	return true

# 荣胡：进入结算 phase（实际分数计算由 ScoreCalc 在 SETTLE 期完成）
func apply_ron(claimant_seat: int, _claimed_tile: Tile) -> bool:
	state.current_seat = claimant_seat
	state.phase = BattlePhase.Kind.SETTLE
	return true

# 自摸：进入结算 phase
func apply_tsumo(seat_id: int, _drawn_tile: Tile) -> bool:
	state.current_seat = seat_id
	state.phase = BattlePhase.Kind.SETTLE
	return true

# ---- 内部 helper ----

func _take_from_hand(hand: Hand, tile_id: int) -> Tile:
	for t in hand._tiles:
		if t.id == tile_id:
			hand.remove_by_id(tile_id)
			return t
	return null

func _after_claim(claimant_seat: int) -> void:
	state.current_seat = claimant_seat
	state.phase = BattlePhase.Kind.DISCARD
	state.first_round_active = false

func _reveal_new_dora() -> void:
	var n: int = state.dora_indicators.visible.size()
	var indicator: Tile = state.wall.peek_dora_indicator(n)
	if indicator != null:
		state.dora_indicators.add_visible(indicator)

func _take_rinshan_to(seat: Seat) -> void:
	var t: Tile = state.wall.take_rinshan()
	if t != null:
		seat.add_to_hand(t)
