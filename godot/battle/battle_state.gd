class_name BattleState
extends TableState

# 一局对战快照（spec §5）。
# 合并自 plan 0e（含 seats/wall/phase 等完整对战字段）与 main PR #8 里程碑 1（技能框架字段）。
# 两条路线共存：
#   - 0e 字段：seats / wall / dora_indicators / phase / current/dealer 等
#     —— 已下沉到 core/turn_engine/table_state.gd（ARCH-CORE #399），TurnEngine 与 ScoreCalc 用
#   - 里程碑 1 字段：scores / furiten_flags / ron_cancelled / revealed_tiles / haitei_forced_seat
#     —— SkillScheduler 与 SkillCtx 用，仍由本类持有
# 注：scores 与 seats[i].points 在概念上重复；当前两个分支独立维护各自的来源，后续 plan
# 应将一者改为派生（避免漂移）。0e 已加 turn_count 维护巡数。

const MAX_EVENT_CHAIN_DEPTH := 16
const STARTING_SCORE := 25000

const _SEAT_WINDS: Array = [TileId.E, TileId.S_WIND, TileId.W_WIND, TileId.N]

# 共享
var event_chain_depth: int = 0

# 里程碑 1 技能框架字段（SkillScheduler/SkillCtx 用）
var scores: Array[int] = [STARTING_SCORE, STARTING_SCORE, STARTING_SCORE, STARTING_SCORE]
var furiten_flags: Array[bool] = [false, false, false, false]
var ron_cancelled: Array[bool] = [false, false, false, false]
var revealed_tiles: Array = []
# #346：稳定 13 张形态下的权威听牌跃迁，以及按 viewer→subject 授权的等待牌。
# TENPAI_ENTERED 只公开跃迁事实；等待牌仅经 recipient optional module 投影。
var tenpai_flags: Array[bool] = [false, false, false, false]
var tenpai_wait_reveals: Dictionary = {}
var haitei_forced_seat: int = -1
# M7 ctx B2 — Dora 系：per-seat 额外 dora / red dora 计数（hook 通过
# mark_extra_dora_for_seat / mark_red_dora_for_seat 累加，BattleController
# 在 ScoreCalc 之前把对应 seat 的额外 count 加到 yaku_list.dora_count 上）
var extra_dora_count: Array[int] = [0, 0, 0, 0]
var extra_red_dora_count: Array[int] = [0, 0, 0, 0]
var kuikae_restricted: Array = [[], [], [], []]
# E2-04：默认可 null；STANDARD 会话保持 null，legacy/TRASH_TALK 由控制器装配
var momentum: Momentum = null

static func for_east_round(rng_seed: int, p_dealer: int, hand_number_arg: int, honba_arg: int, riichi_sticks_arg: int, round_wind_arg: int = TileId.E, hand_seq_arg: int = 0) -> BattleState:
	# round_wind_arg: M8 半庄战支持。默认东（兼容 M7）；半庄战南场由 GameDriver
	# 在 hand_index >= hands_per_round 时传 TileId.S_WIND。函数名仍叫 for_east_round
	# 是历史命名（实际是"为某局风圈实例化 state"），保持名字避免大改 API surface。
	# hand_seq_arg: E2-02 实体 id 命名空间（默认 0）。负数 / 溢出 → null。
	if hand_seq_arg < 0 or hand_seq_arg > Wall.MAX_HAND_SEQ:
		return null
	var s := BattleState.new()
	s.hand_number = hand_number_arg
	s.honba = honba_arg
	s.riichi_sticks = riichi_sticks_arg
	s.dealer_seat = p_dealer
	s.current_seat = p_dealer
	s.round_wind = round_wind_arg
	s.hand_seq = hand_seq_arg

	# 4 seat：自风按 dealer 旋转（dealer 是 E）
	for i in range(4):
		var relative: int = (i - p_dealer + 4) % 4
		var seat_wind: int = _SEAT_WINDS[relative]
		s.seats.append(Seat.new(i, seat_wind))

	# 牌墙：按 hand_seq 分配 instance_id → 洗 + 切 dead wall
	s.wall = Wall.new_full_set(hand_seq_arg)
	if s.wall == null:
		return null
	s.wall.shuffle(rng_seed)
	s.wall.reserve_dead_wall(14)

	# 翻初始 dora 指示牌 + 预置裏 dora(立直胡时翻出来)。
	# 缺裏 dora 之前是 dead code:立直胡牌时 count_total_dora(include_uradora=true)
	# 但 hidden_uradora 列表为空,实际 uradora 永不计入 — 立直收益被低估。
	s.dora_indicators = DoraIndicators.new()
	var visible_first := s.wall.peek_dora_indicator(0)
	var ura_first := s.wall.peek_uradora_indicator(0)
	if visible_first == null or ura_first == null \
			or not s.dora_indicators.reveal_pair(visible_first, ura_first):
		return null

	# 发 13 张 × 4
	for _i in range(13):
		for seat_id in range(4):
			s.seats[seat_id].add_to_hand(s.wall.draw())

	return s

# E2-02 / #232：snapshot_dict / snapshot_hash 已移除。
# 未来 snapshot 归属 AuthorityReplaySnapshot sibling 范围。
