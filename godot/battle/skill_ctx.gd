class_name SkillCtx

var _state: BattleState
var _event: BattleEvent
var han_deltas: Dictionary = {}
# M7 ctx B3-mini：per-seat 番数倍率（Dictionary[int → float]，缺省视为 1.0）。
# hook 通过 multiply_han_for_seat 累乘；BattleController 在 ScoreCalc 之前读取
# 以"补偿合成 yaku entry"形式作用到 yaku_list。
var han_multipliers: Dictionary = {}
# M7 ctx B3-mini：mangan 下限标记（Dictionary[int → bool]，true 时 winner
# 该胡牌至少 5 番 = 满贯）。BattleController 在 ScoreCalc 之前补差。
var mangan_floor_seats: Dictionary = {}
# M9 ctx B3：yakuman 强制标记。true 时 BattleController 在 ScoreCalc 之前
# 把 yaku_list.is_yakuman = true、yakuman_multiplier = max(1, current)。
# 用于 boss3_kanmon "任意胡牌升级为役满" 等 spec 原效果。
var yakuman_force_seats: Dictionary = {}
var beneficiary_seat: int = -1  # 由 scheduler 在每个 candidate 派发前设置
var current_skill: SkillResource = null  # 由 scheduler 在每个 candidate 派发前设置；M7 ctx.consume_self 用
# scheduler 在每个真实 mutation 后记录稳定身份；Dora mutation 额外携带 delta，
# is_ability 仅供结算层区分角色/能力反馈与普通牌技能。
var triggered_skills: Array = []

func _init(p_state: BattleState, p_event: BattleEvent) -> void:
	_state = p_state
	_event = p_event

# ---- Mutations (spec §6.3 + 本里程碑追加) ----

func add_han(seat: int, n: int) -> void:
	han_deltas[seat] = int(han_deltas.get(seat, 0)) + n

func cancel_ron(seat: int) -> void:
	_state.ron_cancelled[seat] = true

func steal_score(from_seat: int, to_seat: int, fraction: float) -> void:
	var amount := int(_state.scores[from_seat] * fraction)
	_state.scores[from_seat] -= amount
	_state.scores[to_seat] += amount

func transfer_points(from_seat: int, to_seat: int, amount: int) -> void:
	_state.scores[from_seat] -= amount
	_state.scores[to_seat] += amount

func reveal_tile_to(tile: TileSkillAnchor, target_seat: int) -> void:
	_state.revealed_tiles.append({"tile": tile, "visible_to": [target_seat]})

# ---- 信息系 reveal API ----

# 从 target_seat 手牌随机抽 1 张，标记为对 viewer_seat 可见。
# 用 _state 的 RNG 决定（保证决定性 sim）。target 手牌空时返 false。
# 用途：xray_1w（看下家手牌 1 张）等。
func reveal_random_from_seat(
	target_seat: int,
	viewer_seat: int,
	only_unseen: bool = false
) -> bool:
	if target_seat < 0 or target_seat >= _state.seats.size():
		return false
	var seat: Seat = _state.seats[target_seat]
	if seat == null or seat.hand == null or seat.hand.size() == 0:
		return false
	var candidates: Array[Tile] = []
	for tile in seat.hand.tiles():
		if not only_unseen or not _is_revealed_to(tile, target_seat, viewer_seat):
			candidates.append(tile)
	if candidates.is_empty():
		return false
	# 用 event_chain_depth + 既有 turn_count 作 deterministic seed —— 不引入新
	# RNG state，保证 sim 决定性
	var rng := RandomNumberGenerator.new()
	rng.seed = _state.turn_count * 17 + _state.event_chain_depth * 31 + target_seat
	var idx: int = rng.randi_range(0, candidates.size() - 1)
	var picked: Tile = candidates[idx]
	var ti: TileSkillAnchor = TileSkillAnchor.make(picked, target_seat)
	ti.holder_seat = target_seat
	_state.revealed_tiles.append({"tile": ti, "visible_to": [viewer_seat]})
	return true


func _is_revealed_to(tile: Tile, holder_seat: int, viewer_seat: int) -> bool:
	for value in _state.revealed_tiles:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = value
		var visible_to: Variant = record.get("visible_to", null)
		if typeof(visible_to) != TYPE_ARRAY or not (visible_to as Array).has(viewer_seat):
			continue
		var instance_value: Variant = record.get("tile", null)
		if not (instance_value is TileSkillAnchor):
			continue
		var instance := instance_value as TileSkillAnchor
		if instance.holder_seat == holder_seat and instance.tile != null \
				and instance.tile.instance_id == tile.instance_id:
			return true
	return false

# 牌墙顶 n 张 reveal 给 viewer_seat。
# 用途：yamagan（GAME_BEGIN reveal 顶 10 张顺序）。
# 牌墙剩余不足时 reveal 实际剩余，返 reveal 张数。
func reveal_wall_top_to(viewer_seat: int, n: int) -> int:
	if _state.wall == null or n <= 0:
		return 0
	var tiles: Array[Tile] = _state.wall.peek_top_n(n)
	for t in tiles:
		var ti: TileSkillAnchor = TileSkillAnchor.make(t, -1)
		ti.holder_seat = -1
		_state.revealed_tiles.append({"tile": ti, "visible_to": [viewer_seat]})
	return tiles.size()


# 从 live wall 顶部确定性移除至多 n 张，返回实际移除数。
func discard_wall_top(n: int) -> int:
	if _state.wall == null or n <= 0:
		return 0
	var removed := 0
	for _i in range(mini(n, _state.wall.live_wall_size())):
		if _state.wall.draw() == null:
			break
		removed += 1
	return removed

# 第 n 张未翻 dora 指示牌 reveal 给 viewer_seat（n=0..4）。
# 用途：white_oracle（每巡看 1 张未翻 dora）。
# n 超界返 false。
func reveal_dora_indicator_to(viewer_seat: int, n: int) -> bool:
	if _state.wall == null or n < 0 or n >= 5:
		return false
	var t: Tile = _state.wall.peek_dora_indicator(n)
	if t == null:
		return false
	var ti: TileSkillAnchor = TileSkillAnchor.make(t, -1)
	ti.holder_seat = -1
	_state.revealed_tiles.append({"tile": ti, "visible_to": [viewer_seat]})
	return true

# target_seat 下次摸的牌 reveal 给 viewer_seat。
# 用途：isshun_senken（看下次摸牌）。target 下个摸的就是牌墙顶 next_draw —
# 因为 turn engine 在每个 seat 摸前都从 wall.draw() 取。语义上"下次摸"=
# 当前 _draw_index 处的牌。返是否 reveal 成功（牌墙空返 false）。
# 注：v1 简化 — 不区分 target 下次摸 vs 任意人下次摸；都是同一个 next_draw。
func reveal_next_draw_for_seat(target_seat: int, viewer_seat: int) -> bool:
	if _state.wall == null:
		return false
	var t: Tile = _state.wall.peek_next_draw()
	if t == null:
		return false
	var ti: TileSkillAnchor = TileSkillAnchor.make(t, -1)
	ti.holder_seat = -1
	_state.revealed_tiles.append({"tile": ti, "visible_to": [viewer_seat]})
	return true

func clear_furiten(seat: int) -> void:
	if seat < 0 or seat >= _state.furiten_flags.size():
		return
	_state.furiten_flags[seat] = false
	if seat < _state.seats.size():
		var seat_state := _state.seats[seat] as Seat
		if seat_state != null and seat_state.furiten != null:
			seat_state.furiten.permanent = false
			seat_state.furiten.temporary = false

# M7 ctx 扩展 B1：set_furiten — 主动切换兼容技能状态；clear_furiten 另行
# 同步真实 Seat.furiten，供权威荣和判定消费。
# 真"振听 N 巡倒计时"需 furiten_turns_remaining 状态字段（M7 后续 PR）；
# 当前版本只切 bool 标记，配合 turn_engine 在 turn 结束清振听做一巡过期。
func set_furiten(seat: int, value: bool = true) -> void:
	_state.furiten_flags[seat] = value

# M7 ctx 扩展 B2：Dora 系。
# mark_extra_dora_for_seat：给指定 seat 额外 +N 张普通 Dora（私有可见，
# 仅该 seat 自胡时计入 yaku_list.dora_count）。man6_treasure / boss2_fortune_runner
# 等 hook 用。
# mark_red_dora_for_seat：同理，给 seat 额外 +N 张赤 Dora。语义与普通
# Dora 相同（每张 +1 番），但分桶以便未来 spec §14 红 dora 上限调整时
# 独立审计。
# BattleController 在 ScoreCalc 之前把对应 seat 的累计加到 yaku_list.dora_count。
func mark_extra_dora_for_seat(seat: int, count: int = 1) -> void:
	if seat < 0 or seat >= _state.extra_dora_count.size():
		return
	_state.extra_dora_count[seat] += count

func mark_red_dora_for_seat(seat: int, count: int = 1) -> void:
	if seat < 0 or seat >= _state.extra_red_dora_count.size():
		return
	_state.extra_red_dora_count[seat] += count

# M7 ctx B3-mini：番数倍率。多次调用累乘（如两个 ×2 effect → ×4）。
# 用于 pin9_haitei_double（spec "海底/河底役 ×2"）等 multiplicative 效果。
# 注：本 PR 只暴露 ctx API + BattleController 读取；首批落地 hook 是
# pin9_haitei_double 升级到真 ×2（替代 v1 +1 番桩）。
func multiply_han_for_seat(seat: int, factor: float) -> void:
	if seat < 0 or seat >= 4:
		return
	var current: float = float(han_multipliers.get(seat, 1.0))
	han_multipliers[seat] = current * factor

# M7 ctx B3-mini：ensure_mangan_for_seat。
# 标记指定 seat 的胡牌至少满贯（≥ 5 番 → ScoreFormula 钳到满贯下限）。
# 用于 white_mangan_floor 等"满贯保底"消耗品（spec §8.9：任意胡牌至少满贯）。
# BattleController 在 ScoreCalc 之前读 mangan_floor_seats，若包含 winner 且
# 当前 yaku_list.total_han < 5 则补差 → 5 番。
func ensure_mangan_for_seat(seat: int) -> void:
	if seat < 0 or seat >= 4:
		return
	mangan_floor_seats[seat] = true

# M9 ctx B3：force_yakuman_for_seat。
# 标记指定 seat 的胡牌升级为役满（≥ yakuman base，BattleController 会在
# ScoreCalc 之前把 yaku_list.is_yakuman = true，yakuman_multiplier 至少为 1）。
# 用于 boss3_kanmon spec 原效果"任意胡牌升级为役满"等。
func force_yakuman_for_seat(seat: int) -> void:
	if seat < 0 or seat >= 4:
		return
	yakuman_force_seats[seat] = true

func force_tsumo(seat: int) -> void:
	_state.haitei_forced_seat = seat

# 一次性消耗品：把当前正在派发的 skill 标记为 consumed。
# current_skill 由 SkillScheduler._dispatch 注入。
func consume_self() -> void:
	if current_skill != null:
		current_skill.consumed = true

# ---- Read-only accessors ----

func get_score(seat: int) -> int:
	return _state.scores[seat]

func is_furiten(seat: int) -> bool:
	return _state.furiten_flags[seat]

func get_event() -> BattleEvent:
	return _event
