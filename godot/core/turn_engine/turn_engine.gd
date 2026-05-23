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
	var seat: Seat = state.seats[state.current_seat]
	seat.add_to_hand(t)
	# 标记刚摸的牌：UI 用于"摸切"显示与立直后强制 tsumogiri（spec 2026-05-08 bug fix）
	seat.last_drawn_tile_id = t.id
	# 普通摸:清岭上标记(若上一动作是岭上摸到现在,中间会经过 _step_discard 已自己 clear,
	# 这里再做一道兜底)。
	seat.last_draw_is_rinshan = false
	# 日麻 §5 同巡振听清除:当事人下一次自摸时,temporary 振听解除。
	seat.furiten.clear_temporary()
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
	# 弃牌后清掉"刚摸的牌"标记（不再 post-draw）
	seat.last_drawn_tile_id = -1
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
	var waits: Array = WaitCalculator.wait_tiles(seat.hand, seat.melds)
	seat.furiten.update_waits(waits)
	# 判断自家弃牌中是否含任一 wait
	var hit: bool = false
	if not waits.is_empty():
		for tile in state.discards_per_seat[seat.seat_id]:
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

# 立直宣告：调 RiichiValidator + RiichiState.declare + 扣 1000 点 + 桌面 stick +1。
# 返 false 表示不满足条件，state 不动。
func declare_riichi(seat_id: int) -> bool:
	var seat: Seat = state.seats[seat_id]
	if not RiichiValidator.can_declare_riichi(seat, state.wall.live_wall_size()):
		return false
	var is_double: bool = state.first_round_active and state.turn_count == 0
	seat.riichi.declare(state.turn_count, is_double)
	# 立直在 discard 之后调用 → 该 seat 的 discards 末尾就是立直牌。
	# DiscardRiver 渲染时按此索引把那一张旋转 90°(日麻标志记号)。
	seat.riichi.riichi_discard_index = state.discards_per_seat[seat_id].size() - 1
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
	_pop_discard_clearing_riichi_index(discarder_seat)
	_after_claim(claimant_seat)
	_clear_all_ippatsu_windows()  # 日麻 §6.4 一発:任何鸣牌(含暗杠)立刻关窗
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
	_pop_discard_clearing_riichi_index(discarder_seat)
	_after_claim(claimant_seat)
	_clear_all_ippatsu_windows()
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
	_pop_discard_clearing_riichi_index(discarder_seat)
	_reveal_new_dora()
	_take_rinshan_to(claimant)
	state.current_seat = claimant_seat
	state.phase = BattlePhase.Kind.DISCARD
	state.first_round_active = false
	_clear_all_ippatsu_windows()
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
	_clear_all_ippatsu_windows()  # 暗杠也关一発窗(国际标准日麻 §6.4)
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
	_clear_all_ippatsu_windows()
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
	# chi/pon 后 claimant 没真摸牌，不显示"刚摸"分隔
	state.seats[claimant_seat].last_drawn_tile_id = -1

func _reveal_new_dora() -> void:
	var n: int = state.dora_indicators.visible.size()
	var indicator: Tile = state.wall.peek_dora_indicator(n)
	if indicator != null:
		state.dora_indicators.add_visible(indicator)
	# 加杠/暗杠时同时预置对应裏 dora 指示牌(立直胡时翻出)。日麻规则:
	# 每翻 1 张明 dora,对应位置的裏 dora 同步存在 — 等立直胡牌时一起亮。
	var ura: Tile = state.wall.peek_uradora_indicator(n)
	if ura != null:
		state.dora_indicators.add_hidden_uradora(ura)

func _take_rinshan_to(seat: Seat) -> void:
	var t: Tile = state.wall.take_rinshan()
	if t != null:
		seat.add_to_hand(t)
		# 杠后岭上摸 = 新的"刚摸的牌"
		seat.last_drawn_tile_id = t.id
		# 标记 last_draw_is_rinshan,让 BC._step_discard 检 tsumo 时识别为岭上开花
		seat.last_draw_is_rinshan = true


# 日麻 §6.4 一発:任何鸣牌(吃/碰/明杠/暗杠/加杠)都立刻关闭所有座位
# 一発窗。BattleController._step_discard 在 riichi 玩家下一巡自家弃牌前
# 也会自己关窗 — 两层 cover 保险。
func _clear_all_ippatsu_windows() -> void:
	for seat in state.seats:
		if seat.riichi.ippatsu_window:
			seat.riichi.consume_ippatsu()


# pop discarder 最后一张弃牌;若它是 riichi 宣告牌(== riichi_discard_index 末位)
# 则同步把 riichi_discard_index 清 -1。否则 DiscardRiver 渲染时会把
# discarder 的"新位置末位"错旋转 — 因为索引固定但底层 Array 元素已替换。
func _pop_discard_clearing_riichi_index(discarder_seat: int) -> void:
	var seat: Seat = state.seats[discarder_seat]
	var last_idx: int = state.discards_per_seat[discarder_seat].size() - 1
	state.discards_per_seat[discarder_seat].pop_back()
	# 立直牌被鸣 → riichi 旋转标记丢弃(牌已不在弃牌堆)
	if seat.riichi.declared and seat.riichi.riichi_discard_index == last_idx:
		seat.riichi.riichi_discard_index = -1
