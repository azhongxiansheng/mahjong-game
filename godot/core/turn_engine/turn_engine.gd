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
