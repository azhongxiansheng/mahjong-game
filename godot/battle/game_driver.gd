class_name GameDriver

# 麻将王 — 里程碑 3 第 1 步：东风战跨局驱动器（plan-3 D1/D6）
#
# 职责：
#   - 持东风战层状态：hand_index / honba / riichi_sticks / cumulative_scores / dealer_seat
#   - 每局开始：用 seed + hand_index 实例化 BattleController，注入当前累计分
#   - 每局结束：解析 BattleController.run_to_end() 返回的 events，把最末
#     WIN_DECLARED.extra.payout 应用到 cumulative_scores（M2 BC 不自动应用）
#   - advance_or_finish: 决定连庄/流转/整场结束（spec §3.2 + §10）
#
# 不在本类范围：
#   - 听牌检测（由调用方提供 tenpai_array 给 advance_or_finish；UI 层调 WaitCalculator）
#   - UI 渲染（→ 第 2-4 步）
#   - 鸣牌窗口（M2 留给后续 plan）

const STARTING_SCORE: int = 25000
const NUM_HANDS_EAST_ROUND: int = 4  # 历史默认；M8 改为 total_hands 实例字段
const RIICHI_STICK_VALUE: int = 1000

var seed: int = 0
# hand_index: 线性递增（0..total_hands-1）。半庄战不在 E4→S1 处重置；
# round_wind 由 _compute_current_round_wind() 函数式计算（不同于
# 重置 hand_index 的方案 — 让连庄计数不被风圈切换干扰）
var hand_index: int = 0
var honba: int = 0
var riichi_sticks: int = 0
var dealer_seat: int = 0
var cumulative_scores: Array[int] = []
var battle: BattleController = null
var finished: bool = false
# M7 平衡：是否用 HeuristicAi（默认 false 保持向后兼容）
var use_heuristic_ai: bool = false
# M10 Path A：HeuristicAi 启用 ShantenCalculator-aware 弃牌（仅 use_heuristic_ai 时有效）
var use_shanten_ai: bool = false
# M8 半庄战参数化：
# - total_hands=4, hands_per_round=4 → 东风战（M7 默认）
# - total_hands=8, hands_per_round=4 → 半庄战（前 4 局东、后 4 局南）
var total_hands: int = NUM_HANDS_EAST_ROUND
var hands_per_round: int = NUM_HANDS_EAST_ROUND
# M7：start_hand 时拍照 battle.state.scores，apply_result 时算"in-hand skill
# 转分增量"（由 ctx.transfer_points / steal_score 写入 state.scores），把
# 这部分 delta 应用到 cumulative_scores 让玩家技能（如 soul_drain_hatsu）真生效
var _pre_hand_state_scores: Array[int] = [0, 0, 0, 0]

func _init(p_seed: int = 0, p_total_hands: int = NUM_HANDS_EAST_ROUND, p_hands_per_round: int = NUM_HANDS_EAST_ROUND) -> void:
	seed = p_seed
	total_hands = p_total_hands
	hands_per_round = p_hands_per_round
	cumulative_scores = [STARTING_SCORE, STARTING_SCORE, STARTING_SCORE, STARTING_SCORE]

# M8: 当前局对应的场风。东风战恒东；半庄战 hand_index>=4 切到南。
# 调用方需保证 hand_index < total_hands 时调用（连庄超出 total_hands 例外，
# 见 advance_or_finish 终局判定）。
func _compute_current_round_wind() -> int:
	if hand_index < hands_per_round:
		return TileId.E
	return TileId.S_WIND

# 创建当前 hand 的 BattleController；把累计分 + honba + riichi_sticks 注入
# 到 battle.state，便于 ScoreFormula 在结算时引用本场起点。
func start_hand() -> BattleController:
	battle = BattleController.new(seed + hand_index, dealer_seat, use_heuristic_ai, _compute_current_round_wind())
	for i in range(4):
		battle.state.scores[i] = cumulative_scores[i]
	battle.state.honba = honba
	battle.state.riichi_sticks = riichi_sticks
	# 拍照供 apply_result 算 skill 转分增量
	for i in range(4):
		_pre_hand_state_scores[i] = battle.state.scores[i]
	# M8.5：注入 strategic context 给 HeuristicAi（终局策略：领先时不立直）
	if use_heuristic_ai and battle.ai is HeuristicAi:
		var hai := battle.ai as HeuristicAi
		hai.set_strategic_context(cumulative_scores, hand_index, total_hands)
		# M10 Path A：可选启用 shanten-aware 弃牌
		if use_shanten_ai:
			hai.use_shanten_aware_discard = true
	return battle

# 解析 events，把最末 WIN_DECLARED 的 payout 应用到 cumulative_scores。
# 流局路径：本方法返 {kind: "exhaustive_draw"}；罚符与 dealer 是否连庄
# 由 advance_or_finish 在外部 tenpai_array 帮助下处理。
#
# 返：
#   - 胡牌：{kind: "tsumo"|"ron", winner_seat, payout, han, fu, winner_total}
#   - 流局：{kind: "exhaustive_draw"}
func apply_result(events: Array) -> Dictionary:
	# 倒序找最末 WIN_DECLARED
	for i in range(events.size() - 1, -1, -1):
		var ev: BattleEvent = events[i]
		if ev.type == &"WIN_DECLARED":
			var extra: Dictionary = ev.extra
			var payout: Dictionary = extra.get("payout", {})
			# M7 修：PayoutCalculator 返 {loser: amount_owed_to_winner}（正值 = 输出）。
			# 历史 GameDriver 用 += 把"输出"加到 loser → 等价 winner +X 的同时
			# loser 也 +X，每次胡破坏守恒 +2X。SimpleAi 几乎不胡时偏差小未察；
			# HeuristicAi 让胡频升高后偏差爆发（sim 看到 sum 远超 100000）。
			# 修正：loser 用 -=（输出 → 减分），winner += winner_total（含立直棒）。
			for seat_id in payout:
				cumulative_scores[seat_id] -= int(payout[seat_id])
			var winner_total: int = int(extra.get("winner_total", 0))
			cumulative_scores[ev.actor_seat] += winner_total
			# 立直棒被胜者收走，本驱动器清零
			riichi_sticks = 0
			# M7：把 in-hand skill 转分增量（state.scores 偏离 _pre_hand_state_scores）
			# 应用到 cumulative_scores —— 让 soul_drain_hatsu 等 transfer_points-based
			# 玩家技能在跨局累计中真生效
			_apply_in_hand_skill_deltas()
			# 区分自摸/荣胡：往前找最近的 TSUMO_DECLARED 或 RON_DECLARED
			var kind := "tsumo"
			for j in range(i - 1, -1, -1):
				var earlier: BattleEvent = events[j]
				if earlier.type == &"RON_DECLARED":
					kind = "ron"
					break
				if earlier.type == &"TSUMO_DECLARED":
					break
			return {
				"kind": kind,
				"winner_seat": ev.actor_seat,
				"payout": payout,
				"han": int(extra.get("han", 0)),
				"fu": int(extra.get("fu", 0)),
				"winner_total": winner_total,
			}

	# 没找到 WIN_DECLARED → 流局
	# 流局也要应用 in-hand skill 转分（流局期间也可能 transfer_points）
	_apply_in_hand_skill_deltas()
	# M7：把 in-hand 立直累积的 state.riichi_sticks 同步回 driver，让下一
	# 次胡时 winner 能收走 pool（不然流局后 pool 丢失，scores 守恒被破）
	if battle != null:
		riichi_sticks = battle.state.riichi_sticks
	return {"kind": "exhaustive_draw"}

# M7：把 battle.state.scores 与 _pre_hand_state_scores 之间的 delta 应用到
# cumulative_scores。这部分 delta 来自 skill ctx.transfer_points / steal_score
# 等直接修改 state.scores 的 hooks（payout 不在 state.scores，已由调用方
# 单独 apply）。
func _apply_in_hand_skill_deltas() -> void:
	if battle == null:
		return
	for i in range(4):
		var delta: int = int(battle.state.scores[i]) - int(_pre_hand_state_scores[i])
		cumulative_scores[i] += delta

# 决定连庄 / 流转 / 整场结束。
#
# result 来自 apply_result()，可携带 tenpai_array（流局路径下必需，
# 4-bool 数组表示每 seat 是否听牌）。
#
# - 庄家自摸 / 庄家荣胡 / 流局且庄家听牌 → 连庄：dealer 不变，hand_index 不变，honba+=1
# - 闲家胡 / 流局且庄家不听 → 流转：hand_index+=1，dealer 顺时针旋转，honba=0
# - hand_index 达到 NUM_HANDS_EAST_ROUND 且未连庄 → 整场结束（finished=true）
#
# 流局额外动作：
#   - 应用 ExhaustiveDraw.noten_payout(tenpai_array) 罚符到 cumulative_scores
#   - 立直棒跨局保留（不清零）
#
# 返 {finished, renchan, kind}
func advance_or_finish(result: Dictionary) -> Dictionary:
	var kind: String = result.get("kind", "exhaustive_draw")
	var renchan := false

	match kind:
		"tsumo", "ron":
			renchan = (int(result.get("winner_seat", -1)) == dealer_seat)
		"exhaustive_draw":
			var tenpai_array: Array = result.get("tenpai_array", [false, false, false, false])
			renchan = ExhaustiveDraw.is_dealer_renchan(dealer_seat, tenpai_array)
			var deltas: Dictionary = ExhaustiveDraw.noten_payout(tenpai_array)
			for s in deltas:
				cumulative_scores[s] += int(deltas[s])
			# 流局立直棒留台到下局；这里不动 riichi_sticks

	if renchan:
		honba += 1
	else:
		honba = 0
		hand_index += 1
		dealer_seat = (dealer_seat + 1) % 4

	if not renchan and hand_index >= total_hands:
		finished = true

	battle = null

	return {
		"finished": finished,
		"renchan": renchan,
		"kind": kind,
	}

# 调用方在玩家声明立直时调用：扣 1000 + 把棒加到台上。
# （v1 简化：本方法不校验是否合法立直，由 BattleController 内的 RiichiValidator 把关）
func on_riichi_declared(seat_id: int) -> void:
	cumulative_scores[seat_id] -= RIICHI_STICK_VALUE
	riichi_sticks += 1

# 守恒检查：sum(cumulative_scores) + riichi_sticks * 1000 == 100000
func is_score_conserved() -> bool:
	var total := 0
	for s in cumulative_scores:
		total += s
	return total + riichi_sticks * RIICHI_STICK_VALUE == STARTING_SCORE * 4
