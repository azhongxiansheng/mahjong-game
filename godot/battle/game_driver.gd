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
const NUM_HANDS_EAST_ROUND: int = 4
const RIICHI_STICK_VALUE: int = 1000

var seed: int = 0
var hand_index: int = 0  # 0..3 表东 1..东 4
var honba: int = 0
var riichi_sticks: int = 0
var dealer_seat: int = 0
var cumulative_scores: Array[int] = []
var battle: BattleController = null
var finished: bool = false
# M7 平衡：是否用 HeuristicAi（默认 false 保持向后兼容）
var use_heuristic_ai: bool = false

func _init(p_seed: int = 0) -> void:
	seed = p_seed
	cumulative_scores = [STARTING_SCORE, STARTING_SCORE, STARTING_SCORE, STARTING_SCORE]

# 创建当前 hand 的 BattleController；把累计分 + honba + riichi_sticks 注入
# 到 battle.state，便于 ScoreFormula 在结算时引用本场起点。
func start_hand() -> BattleController:
	battle = BattleController.new(seed + hand_index, dealer_seat, use_heuristic_ai)
	for i in range(4):
		battle.state.scores[i] = cumulative_scores[i]
	battle.state.honba = honba
	battle.state.riichi_sticks = riichi_sticks
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
	return {"kind": "exhaustive_draw"}

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

	if not renchan and hand_index >= NUM_HANDS_EAST_ROUND:
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
