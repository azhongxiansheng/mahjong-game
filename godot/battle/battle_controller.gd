class_name BattleController extends IBattleController

const RIICHI_STICK_COST: int = 1000

# 里程碑 2 — 端到端编排器（v1 单机权威实现）。
# 职责：
#   1. 自建 BattleState / TurnEngine / SkillRegistry / SkillScheduler / SimpleAi
#   2. 编排「摸→弃→（鸣牌窗口暂略）→下家」整局循环
#   3. 在 TurnEngine apply_xxx 调用前后向 SkillScheduler emit BattleEvent
#   4. 流局 / 自摸 / 荣胡时退出循环
# spec §13 第 2 项 — 不接 UI、不接交互、4 家全 AI。
#
# M11 Path C：本类已 extends IBattleController，作为 v1 单机实现；M12 加 server
# 权威 NetworkedBattleController 时也走 IBattleController 抽象。
# 后续 M11 第 2 步会把外部 caller 的类型签名从 BattleController 改 IBattleController；
# 本 PR 只建立 extends 关系，不强制 caller migrate（向后兼容）。

# 里程碑 2 完成 YakuEvaluator → ScoreCalc 串接：YakuEvaluator 用 yaku/yaku_list.gd
# （class_name YakuEntries，含 entries: Array[YakuEntry] / apply_exclusions / is_yakuman()），
# ScoreCalc 用 rules_japanese/yaku_list.gd（class_name YakuList，含 yaku: Array[Dict]
# / is_yakuman: bool / yakuman_multiplier）—— 两份语义不同；PR #12 已修 class_name 重名
# （旧 WinContext → 拆为 ScoreContext + WinContext，旧 YakuList → 拆为 YakuList + YakuEntries）。
# _adapt_yaku_list() 在 YakuEntries → YakuList 之间桥接。

const MAX_LOOP_STEPS := 2000  # 一局上限，防死循环；正常一局 < 200 步

# state / engine / registry / scheduler / ai / events 字段已在 IBattleController 声明；
# 本类继承得到。构造函数初始化这些字段。
var _settled: bool = false
var _last_event_type: StringName = &""
# M11 replay (net foundation): 决策回放队列（来自 extract_player_actions）。
# 非空时 BC 用回放决策替代 ai.decide_*；为空（默认）走 v1 AI 决策路径。
# 配合同事 PR #124 IBattleController + #127 NetworkedEvent 协议，server
# 推 NetworkedEvent[Action] → client BC 用本字段重放。
var _replay_decisions: Array = []
var _replay_idx: int = 0

func _init(seed: int = 0, dealer_seat: int = 0, use_heuristic_ai: bool = false, round_wind: int = TileId.E) -> void:
	# round_wind: M8 半庄战支持。默认东兼容 M7；GameDriver 在南场调用时
	# 传 TileId.S_WIND 以激活场风南牌役（南、南家自风南）。
	state = BattleState.for_east_round(seed, dealer_seat, 1, 0, 0, round_wind)
	engine = TurnEngine.new(state)
	registry = SkillRegistry.new()
	scheduler = SkillScheduler.new(registry, state)
	# AI 用不同 seed，与洗牌 seed 解耦
	if use_heuristic_ai:
		ai = HeuristicAi.new(seed + 1)
	else:
		ai = SimpleAi.new(seed + 1)

# ---- 主入口 ----

# 跑到流局或胡牌；返 {last_event: StringName, events: Array[BattleEvent]}
func run_to_end() -> Dictionary:
	_emit(&"GAME_BEGIN", state.dealer_seat, null, {})

	var steps := 0
	while not _settled and steps < MAX_LOOP_STEPS:
		steps += 1
		if state.phase == BattlePhase.Kind.DRAW:
			_step_draw()
		elif state.phase == BattlePhase.Kind.DISCARD:
			_step_discard()
		elif state.phase == BattlePhase.Kind.CLAIM:
			var last_discard: Tile = _get_last_discarded()
			var last_discarder: int = _get_last_discarder()
			if last_discard != null and last_discarder >= 0:
				_resolve_claims(last_discard, last_discarder)
			else:
				engine.advance_to_next_seat()
		elif state.phase == BattlePhase.Kind.SETTLE:
			# 已被 _step_xxx 内部处理；保险起见强制退出
			break

	return {
		"last_event": _last_event_type,
		"events": events,
	}

# ---- 步骤 ----

func _step_draw() -> void:
	var t: Tile = engine.draw_for_current()
	if t == null:
		# 牌墙耗尽 — 流局
		_emit(&"EXHAUSTIVE_DRAW", -1, null, {})
		# 流し満貫(nagashi mangan)检測:命中则额外 emit NAGASHI_MANGAN 让 UI 反馈
		var nm_winner: int = NagashiMangan.detect_winner_seat(state)
		if nm_winner >= 0:
			_emit(&"NAGASHI_MANGAN", nm_winner, null,
				{"winner_seat": nm_winner})
		_settled = true
		return
	_emit(&"TILE_DRAWN", state.current_seat, _wrap_tile(t), {})
	# M7：摸到此牌后牌墙是否空 → 海底捞月（自摸路径）
	var is_haitei: bool = (state.wall.live_wall_size() == 0)
	# 天和/地和(tenhou/chiihou):第一巡每家首摸,前提 first_round_active +
	# 该 seat 还没弃过牌。Yaku evaluator 通过 GameContext.is_dealer_first_hand /
	# is_non_dealer_first_draw 检测;修复前这两 dead code,役満永不命中。
	var first_draw: bool = state.first_round_active \
		and state.discards_per_seat[state.current_seat].is_empty()
	var is_tenhou: bool = first_draw \
		and state.current_seat == state.dealer_seat
	var is_chiihou: bool = first_draw \
		and state.current_seat != state.dealer_seat
	# 自摸检测（无役不胡;本里程碑 SimpleAi 不会主动宣告，这里 BC 自动判定）
	var win := _check_tsumo(t, is_haitei, false, is_tenhou, is_chiihou)
	if win.is_winning and _should_accept_tsumo(state.current_seat, t, win):
		_settle_tsumo(t, win.wp, win.yaku_list, is_haitei)
	# Task 3: AI self-kan (ankan / added_kan) after draw, only if not settled
	if not _settled:
		_try_ai_self_kan()

func _step_discard() -> void:
	var seat: Seat = state.seats[state.current_seat]
	var actor: int = state.current_seat
	# 日麻 §6.4 一発窗:玩家立直后下一巡再轮到自家弃牌时关窗
	# (此时距离 declared_turn 已过 ≥1 巡且未鸣牌 — 一発自然过期)
	_close_ippatsu_if_lap_passed(seat)
	# 岭上开花(rinshan kaihou):杠后岭上摸到的牌若胡 → +1 han 役。
	# 仅在 _step_discard 入口检 — 因为杠后 phase=DISCARD 直接进这里,
	# 而 _step_draw 是正常摸牌的入口(那条路 last_draw_is_rinshan=false)。
	if seat.last_draw_is_rinshan and seat.last_drawn_tile_id >= 0:
		if _try_rinshan_tsumo(seat):
			return
		# 不胡 → 清掉岭上标记让本回合走正常切牌
		seat.last_draw_is_rinshan = false
	# M11 net foundation: 优先回放决策；否则走 AI 决策路径
	var to_discard: Tile = null
	var replayed: Dictionary = _consume_replay_decision_if_match(actor, "discard")
	if not replayed.is_empty():
		var tid: int = int(replayed.get("tile_id", -1))
		for t in seat.hand._tiles:
			if t.id == tid:
				to_discard = t
				break
	else:
		to_discard = _get_discard_decision(seat, actor)
	if to_discard == null:
		_settled = true
		return
	# M11 net foundation: emit PLAYER_ACTION 让事件日志自包含决策。
	# 这是 spec §4.3 联机权威化的前置：未来 server 会把 player click 包成
	# 同样的 PlayerAction event 推给 client。本 emit 在 engine.discard 之前
	# 让 cause-effect 顺序明确：决策 → 引擎应用 → TILE_DISCARDED 事件
	_emit(&"PLAYER_ACTION", actor, null, {
		"kind": "discard",
		"tile_id": to_discard.id,
	})
	var ok: bool = engine.discard(to_discard.id)
	if not ok:
		_settled = true
		return
	state.kuikae_restricted[actor] = []
	_emit(&"TILE_DISCARDED", actor, _wrap_tile(to_discard), {})
	# M7：discard 后 hand=13 张，AI 可决定立直（HeuristicAi.decide_riichi 走
	# RiichiValidator）。declare_riichi 成功 → state.scores[seat] -= 1000 让
	# GameDriver._apply_in_hand_skill_deltas 同步到 cumulative，避免守恒被破。
	# M11 replay: 立直决策也支持回放
	var should_riichi: bool = false
	var riichi_replayed: Dictionary = _consume_replay_decision_if_match(actor, "riichi")
	if not riichi_replayed.is_empty():
		should_riichi = true
	elif _replay_decisions.is_empty():
		should_riichi = _get_riichi_decision(actor)
	if should_riichi:
		# M11: 立直决策同样包成 PlayerAction
		_emit(&"PLAYER_ACTION", actor, null, {"kind": "riichi"})
		if engine.declare_riichi(actor):
			state.scores[actor] -= RIICHI_STICK_COST
			_emit(&"RIICHI_DECLARED", actor, null, {})
	# M7：自动 RON 检测。在每次 TILE_DISCARDED 后按 atama-hane 顺序遍历对家。
	# v1：任一对家若可胡（非振听 + 听牌 + 有役）→ 自动 apply_ron。
	# 真实玩家 UI 路径下（M8+）会替换为玩家选择窗口；当前 SimpleAi-only 阶段
	# 自动接受所有可胡机会以让 sim 看见 RON 路径。
	if not _settled:
		_try_auto_ron(to_discard, actor)

# ---- 事件 emit ----

# 把一次 emit 集中到此 helper：登记 log + 调 scheduler。
func _emit(type: StringName, actor_seat: int, ti: TileInstance, extra: Dictionary) -> SkillCtx:
	var ev := BattleEvent.make(type, actor_seat, ti, extra)
	events.append(ev)
	_last_event_type = type
	var ctx := scheduler.emit_event(ev)
	for entry in ctx.triggered_skills:
		var skill_ev := BattleEvent.make(&"SKILL_TRIGGERED", int(entry.beneficiary_seat), null, {
			"skill_id": entry.skill_id,
			"skill_name": entry.skill_name,
			"source_event": type,
		})
		events.append(skill_ev)
	return ctx

# 把 Tile 包成 TileInstance 以喂事件 payload。
# Tile 当前没有 owner_seat 字段（main 合并冲突里 commit 2b87929 的字段被丢掉，是 main 旧债，
# 不在里程碑 2 修复范围）。本里程碑 owner_seat 默认 -1；路径 C/D 涉及 owner 归属时由
# BattleController 在专用 fixture 入口（_register_skill_for_tile）显式塞 TileInstance 到映射表。
func _wrap_tile(t: Tile) -> TileInstance:
	if t == null:
		return null
	return TileInstance.make(t, -1, null)

# ---- 胡牌结算 ----
#
# 调用顺序（spec §6.1 + §12.1）：
#   WaitCalculator 隐式（WinPattern.detect 内部即跑分解）
#   → WinPattern.detect → YakuEvaluator.evaluate（apply_exclusions 内置）
#   → 无役校验 → ScoreCalc.calculate → emit WIN_DECLARED

# 把 14 张手（含刚摸到的 drawn）拆成 13 张暗牌 + 和牌张，然后跑 WinPattern + YakuEvaluator。
# is_rinshan: 是否岭上开花 tsumo(杠后岭上摸到的牌胡)。修复前 dead code,所有岭上摸胡
# 都丢了 +1 han 役。BC._step_discard 在 seat.last_draw_is_rinshan=true 时传 true。
# 返 {is_winning: bool, wp?: Dict, yaku_list?: YakuList, hand_13?: Hand, melds?: Array}
func _check_tsumo(drawn: Tile, is_haitei: bool = false, is_rinshan: bool = false, is_tenhou: bool = false, is_chiihou: bool = false) -> Dictionary:
	var seat: Seat = state.seats[state.current_seat]
	var hand_13 := _hand_minus_first(seat.hand, drawn.id)
	if hand_13 == null:
		return {"is_winning": false}
	# Seat.melds 是 untyped Array，转成 Array[Meld] 喂规则引擎
	var typed_melds: Array[Meld] = []
	for m in seat.melds:
		typed_melds.append(m)
	var wp: Dictionary = WinPattern.detect(hand_13, typed_melds, drawn)
	if not wp.is_winning:
		return {"is_winning": false}
	var game_ctx := _build_game_ctx(seat, true, is_haitei, false, is_rinshan, is_tenhou, is_chiihou)
	var yaku_wc := WinContext.new(hand_13, typed_melds, drawn, wp, game_ctx)
	var yaku_list = YakuEvaluator.evaluate(yaku_wc)
	# 无役不能胡（dora 不构成役）；yaku/yaku_list.gd 的 is_yakuman 是函数
	var has_yaku: bool = yaku_list.is_yakuman() or yaku_list.size() > 0
	if not has_yaku:
		return {"is_winning": false}
	return {
		"is_winning": true,
		"wp": wp,
		"yaku_list": yaku_list,
		"hand_13": hand_13,
		"melds": typed_melds,
	}

# 检查 winner_seat 用 ron_tile 荣胡是否合法。
# winner.hand 是 13 张听牌期手（不含 ron_tile）；ron_tile 由对家弃牌补上。
func _check_ron(ron_tile: Tile, winner_seat: int, is_houtei: bool = false, is_chankan: bool = false) -> Dictionary:
	var winner: Seat = state.seats[winner_seat]
	var typed_melds: Array[Meld] = []
	for m in winner.melds:
		typed_melds.append(m)
	var wp: Dictionary = WinPattern.detect(winner.hand, typed_melds, ron_tile)
	if not wp.is_winning:
		return {"is_winning": false}
	var game_ctx := _build_game_ctx(winner, false, false, is_houtei)
	game_ctx.is_chankan = is_chankan
	var yaku_wc := WinContext.new(winner.hand, typed_melds, ron_tile, wp, game_ctx)
	var yaku_list = YakuEvaluator.evaluate(yaku_wc)
	var has_yaku: bool = yaku_list.is_yakuman() or yaku_list.size() > 0
	if not has_yaku:
		return {"is_winning": false}
	return {
		"is_winning": true,
		"wp": wp,
		"yaku_list": yaku_list,
		"melds": typed_melds,
	}

# M7：在 TILE_DISCARDED 后自动尝试 ron。按 atama-hane 顺序（discarder + 1
# 优先），首个可胡的对家直接 apply_ron。被 cancel_ron 跳过该候选试下一个
# （v1 简化：spec 严格 atama-hane 是"被取消即不再考虑"；本 v1 让其它候选
# 也有机会 fire 以让 sim 看到更多 RON 数据点）。
# is_houtei = (wall.live_wall_size() == 0) — 当前 discard 来自最后一张 live 牌。
#
# 日麻 §3.2 三家和了(sancha houra):若 3 家同时可荣胡此弃牌 → 途中流局
# (而非首个 atama-hane 收胡)。本函数先扫一遍 candidates 计数,≥3 → abort。
func _try_auto_ron(discarded: Tile, discarder: int) -> void:
	var is_houtei: bool = (state.wall.live_wall_size() == 0)
	# 三家和了 pre-check:计可胡候选数,≥3 → abortive draw
	if _count_ron_candidates(discarded, discarder, is_houtei) >= 3:
		_emit(&"ABORTIVE_DRAW", -1, null, {"reason": "sancha_houra"})
		_settled = true
		return
	for offset in range(1, 4):
		var candidate: int = (discarder + offset) % 4
		var candidate_seat: Seat = state.seats[candidate]
		# 1) 振听 + 听牌检查（ClaimValidator 已封装）
		if not ClaimValidator.can_ron(candidate_seat.hand, candidate_seat.melds, discarded, candidate_seat.furiten):
			continue
		# 2) 有役检查（_check_ron 内部跑 YakuEvaluator + 无役拒绝）
		var ron_check: Dictionary = _check_ron(discarded, candidate, is_houtei)
		if not ron_check.is_winning:
			continue
		# 3) 是否接受 ron 由钩子决定（默认子类不重写则总是接受；玩家子类可弹按钮等待选择）
		if not _should_accept_ron(candidate, discarded, discarder, ron_check, is_houtei):
			# 见逃 — 日麻 §5:同巡振听 temporary;立直见逃 → 永久振听
			# (立直锁牌后只能 tsumogiri,不能再调整待牌,所以一次见逃就锁死)
			candidate_seat.furiten.temporary = true
			if candidate_seat.riichi.declared:
				candidate_seat.furiten.permanent = true
			continue
		# 4) 试结算（apply_ron emit RON_DECLARED 给技能 cancel 机会）
		if apply_ron(candidate, discarded, discarder, is_houtei):
			return  # 已 settle


# 计算给定 discarded 牌的可荣胡候选数(只看规则可行性 + 有役,不调
# _should_accept_ron 避免 async 路径污染)。
func _count_ron_candidates(discarded: Tile, discarder: int, is_houtei: bool) -> int:
	var count: int = 0
	for offset in range(1, 4):
		var candidate: int = (discarder + offset) % 4
		var candidate_seat: Seat = state.seats[candidate]
		if not ClaimValidator.can_ron(candidate_seat.hand, candidate_seat.melds, discarded, candidate_seat.furiten):
			continue
		var ron_check: Dictionary = _check_ron(discarded, candidate, is_houtei)
		if not ron_check.is_winning:
			continue
		count += 1
	return count

# ---- 决策钩子（subclass 覆写以接入玩家输入或网络权威） ----
#
# 这些钩子是同步默认实现：返当前 AI / RiichiValidator 计算的决策，与原来直
# 接 inline 调用 ai.decide_* 的行为完全一致。PlayableBattleController 子类
# 覆写这些钩子改成 await PlayerActionPanel signal，配合 run_to_end_async()。
# 默认 sync 路径下 await 一个非 coroutine 值是 no-op，所以两条路径可共用。

# 决定 actor 切哪张牌；默认 = ai.decide_discard(seat)。
# 日麻 §5 立直锁牌:已立直 + 有刚摸的牌 → 强制 tsumogiri,不再让 AI 决策
# (AI 决策不知 riichi 状态,会非法换牌)。
func _get_discard_decision(seat: Seat, actor: int) -> Tile:
	if seat.riichi.declared and seat.last_drawn_tile_id >= 0:
		var forced: Tile = _find_tile_in_hand(seat.hand, seat.last_drawn_tile_id)
		if forced != null:
			return forced
	var pick: Tile = ai.decide_discard(seat)
	if pick != null and not state.kuikae_restricted[actor].is_empty():
		var restricted: Array = state.kuikae_restricted[actor]
		if restricted.has(pick.id):
			for t in seat.hand._tiles:
				if not restricted.has(t.id):
					return t
	return pick

# 决定 actor 是否立直；默认 = HeuristicAi.decide_riichi（如有），否则 false。
func _get_riichi_decision(actor: int) -> bool:
	if ai.has_method("decide_riichi"):
		var seat_after: Seat = state.seats[actor]
		return ai.decide_riichi(seat_after, state.wall.live_wall_size())
	return false

# 决定 candidate 是否接受这次荣和；默认 = 总是接受（auto ron）。
# PlayableBattleController 子类覆写：candidate==0 时弹"荣和/见逃" 按钮 await 玩家选择。
func _should_accept_ron(_candidate: int, _discarded: Tile, _discarder: int, _ron_check: Dictionary, _is_houtei: bool) -> bool:
	return true

# 决定 actor 是否接受这次自摸；默认 = 总是接受（auto tsumo）。
# PlayableBattleController 子类覆写：actor==0 时弹"自摸"按钮 await 玩家选择。
func _should_accept_tsumo(_actor: int, _drawn: Tile, _win_check: Dictionary) -> bool:
	return true

# 玩家鸣牌响应（吃/碰/杠）窗口；默认 no-op（v1 AI 不主动鸣牌）。
# PlayableBattleController 覆写：玩家可吃/碰/杠时弹按钮 await 玩家选择。
func _try_player_claim_async(_discarded: Tile, _discarder: int) -> void:
	pass


# 九種九牌(日麻 §3.2):第一巡 14 张含 ≥9 种幺九 → 玩家可宣告途中流局。
# 默认:AI 永不主动宣告(continue playing)。PlayableBattleController 在
# seat==0 时覆写 → 弹按钮等玩家选。
func _should_declare_kyuusyu_kyuuhai(_actor: int) -> bool:
	return false


# 日麻 §6.4 一発:玩家立直后,若再轮到自家弃牌(=已过了 ≥1 巡且无人鸣牌)
# 则一発过期。注意 declare 当巡的弃牌不该关 — 此时 declared_turn==turn_count
# 直接 return。鸣牌打断由 TurnEngine.apply_xxx 自己 cover(关所有 seats 窗)。
func _close_ippatsu_if_lap_passed(seat: Seat) -> void:
	if not seat.riichi.declared:
		return
	if not seat.riichi.ippatsu_window:
		return
	# 同一巡 declare 后的本家弃牌还在 declared_turn,不关窗
	if seat.riichi.declared_turn == state.turn_count:
		return
	seat.riichi.consume_ippatsu()

# 岭上开花 sync 路径:检 tsumo;胡且默认 accept → settle 并返 true。
# is_rinshan=true 被透传到 _build_game_ctx → Yaku 评 +1 han 役。
func _try_rinshan_tsumo(seat: Seat) -> bool:
	var rinshan_tile: Tile = _find_tile_in_hand(seat.hand, seat.last_drawn_tile_id)
	if rinshan_tile == null:
		return false
	var win: Dictionary = _check_tsumo(rinshan_tile, false, true)  # is_rinshan=true
	if not win.is_winning:
		return false
	if not _should_accept_tsumo(state.current_seat, rinshan_tile, win):
		return false
	_settle_tsumo(rinshan_tile, win.wp, win.yaku_list, false, true)
	return true


# 岭上开花 async 路径:_should_accept_tsumo 在 PlayableBC 是 coroutine,要 await
func _try_rinshan_tsumo_async(seat: Seat) -> bool:
	var rinshan_tile: Tile = _find_tile_in_hand(seat.hand, seat.last_drawn_tile_id)
	if rinshan_tile == null:
		return false
	var win: Dictionary = _check_tsumo(rinshan_tile, false, true)
	if not win.is_winning:
		return false
	var accept = await _should_accept_tsumo(state.current_seat, rinshan_tile, win)
	if not accept:
		return false
	_settle_tsumo(rinshan_tile, win.wp, win.yaku_list, false, true)
	return true


# 按 id 找手牌中的实际 Tile 引用(保留 owner_seat / is_red_dora 等)
func _find_tile_in_hand(hand: Hand, tile_id: int) -> Tile:
	for t in hand._tiles:
		if t.id == tile_id:
			return t
	return null

# ---- run_to_end 的 async 镜像（plan: 战斗节点真实可玩 / Step 5） ----
#
# 跟 run_to_end() 行为完全一样，只是把 _step_draw / _step_discard / _try_auto_ron
# 路径上的决策钩子调用都包成 await，让 PlayableBattleController 可以在那 3 个钩子
# 里 await 玩家 signal。默认 sync 钩子被 await 时是 no-op（GDScript 4 规则：
# await 一个非 Signal/coroutine 值 → 立刻返回该值），所以 sync 默认行为下 async
# 路径与 sync 路径输出一致。
#
# 现存 GUT 测试继续走 run_to_end()（sync）；新写 PlayableTable + RunFlow 走
# run_to_end_async()。两路径共享 _settle_tsumo / _settle_ron / 状态机。
func run_to_end_async() -> Dictionary:
	_emit(&"GAME_BEGIN", state.dealer_seat, null, {})

	var steps := 0
	while not _settled and steps < MAX_LOOP_STEPS:
		steps += 1
		if state.phase == BattlePhase.Kind.DRAW:
			await _step_draw_async()
		elif state.phase == BattlePhase.Kind.DISCARD:
			await _step_discard_async()
		elif state.phase == BattlePhase.Kind.CLAIM:
			var last_discard: Tile = _get_last_discarded()
			var last_discarder: int = _get_last_discarder()
			if last_discard != null and last_discarder >= 0:
				_resolve_claims(last_discard, last_discarder)
			else:
				engine.advance_to_next_seat()
		elif state.phase == BattlePhase.Kind.SETTLE:
			break
		# 日麻 §3.2 途中流局自动判定(四风连打 / 四家立直 / 四杠散了 / 三家和了)。
		# 任一命中 → 立刻 settle 为 abortive_draw,GameDriver 路径同 kyuusyu。
		if not _settled:
			_check_and_emit_abortive_draws()

	return {
		"last_event": _last_event_type,
		"events": events,
	}


# 检测 4 种途中流局条件(九種九牌走 _step_draw_async 单独路径,不在此)。
# 命中 → emit ABORTIVE_DRAW + _settled = true。
func _check_and_emit_abortive_draws() -> void:
	if DrawDetector.is_suufon_renda(state):
		_emit(&"ABORTIVE_DRAW", -1, null, {"reason": "suufon_renda"})
		_settled = true
		return
	if DrawDetector.is_suucha_riichi(state):
		_emit(&"ABORTIVE_DRAW", -1, null, {"reason": "suucha_riichi"})
		_settled = true
		return
	if DrawDetector.is_suukantsu_sanra(state):
		_emit(&"ABORTIVE_DRAW", -1, null, {"reason": "suukantsu_sanra"})
		_settled = true
		return

func _step_draw_async() -> void:
	var t: Tile = engine.draw_for_current()
	if t == null:
		_emit(&"EXHAUSTIVE_DRAW", -1, null, {})
		# 流し満貫 检测(同 sync 路径)
		var nm_winner: int = NagashiMangan.detect_winner_seat(state)
		if nm_winner >= 0:
			_emit(&"NAGASHI_MANGAN", nm_winner, null,
				{"winner_seat": nm_winner})
		_settled = true
		return
	_emit(&"TILE_DRAWN", state.current_seat, _wrap_tile(t), {})
	# 日麻 §3.2 九種九牌:第一巡(state.first_round_active + turn_count == 0)
	# 摸完牌后,若本家 14 张含 ≥ 9 种 distinct 幺九 → 玩家可选途中流局。
	# 默认 hook 返 false(AI 永不主动 abort);PlayableBattleController 覆写
	# 让 seat 0 弹按钮等玩家决定。
	if state.first_round_active and state.turn_count == 0:
		var seat: Seat = state.seats[state.current_seat]
		if AbortiveDraw.is_kyuusyu_kyuuhai(seat.hand.to_id_array()):
			var declare_kyuusyu: bool = await _should_declare_kyuusyu_kyuuhai(state.current_seat)
			if declare_kyuusyu:
				_emit(&"ABORTIVE_DRAW", state.current_seat, null,
					{"reason": "kyuusyu_kyuuhai"})
				_settled = true
				return
	var is_haitei: bool = (state.wall.live_wall_size() == 0)
	# 天和/地和(同 sync 路径)
	var first_draw: bool = state.first_round_active \
		and state.discards_per_seat[state.current_seat].is_empty()
	var is_tenhou: bool = first_draw \
		and state.current_seat == state.dealer_seat
	var is_chiihou: bool = first_draw \
		and state.current_seat != state.dealer_seat
	var win := _check_tsumo(t, is_haitei, false, is_tenhou, is_chiihou)
	if win.is_winning:
		var accept: bool = await _should_accept_tsumo(state.current_seat, t, win)
		if accept:
			_settle_tsumo(t, win.wp, win.yaku_list, is_haitei)
	# Task 3: AI self-kan (ankan / added_kan) after draw, only if not settled
	if not _settled:
		_try_ai_self_kan()

func _step_discard_async() -> void:
	var seat: Seat = state.seats[state.current_seat]
	var actor: int = state.current_seat
	# 日麻 §6.4 一発窗:玩家立直后下一巡再轮到自家弃牌时关窗
	_close_ippatsu_if_lap_passed(seat)
	# 岭上开花(rinshan kaihou)tsumo 检测 — 杠后岭上摸 + 胡 → +1 han 役
	if seat.last_draw_is_rinshan and seat.last_drawn_tile_id >= 0:
		var rinshan_settled: bool = await _try_rinshan_tsumo_async(seat)
		if rinshan_settled:
			return
		seat.last_draw_is_rinshan = false
	var to_discard: Tile = null
	var replayed: Dictionary = _consume_replay_decision_if_match(actor, "discard")
	if not replayed.is_empty():
		var tid: int = int(replayed.get("tile_id", -1))
		for t in seat.hand._tiles:
			if t.id == tid:
				to_discard = t
				break
	else:
		to_discard = await _get_discard_decision(seat, actor)
	if to_discard == null:
		_settled = true
		return
	_emit(&"PLAYER_ACTION", actor, null, {
		"kind": "discard",
		"tile_id": to_discard.id,
	})
	var ok: bool = engine.discard(to_discard.id)
	if not ok:
		_settled = true
		return
	state.kuikae_restricted[actor] = []
	_emit(&"TILE_DISCARDED", actor, _wrap_tile(to_discard), {})
	# 立直决策（discard 后 hand=13）
	var should_riichi: bool = false
	var riichi_replayed: Dictionary = _consume_replay_decision_if_match(actor, "riichi")
	if not riichi_replayed.is_empty():
		should_riichi = true
	elif _replay_decisions.is_empty():
		should_riichi = await _get_riichi_decision(actor)
	if should_riichi:
		_emit(&"PLAYER_ACTION", actor, null, {"kind": "riichi"})
		if engine.declare_riichi(actor):
			state.scores[actor] -= RIICHI_STICK_COST
			_emit(&"RIICHI_DECLARED", actor, null, {})
	# 鸣牌响应（v1 仅 ron）
	if not _settled:
		await _try_ron_async(to_discard, actor)
	# 玩家鸣牌窗口（吃/碰/杠）— 默认 no-op；PlayableBattleController 覆写
	# 注意：直接 await self._try_player_claim_async() 在 GDScript 4 中 dispatch
	# 不可靠（首次后 cache 父类版本）。子类应覆写 _step_discard_async 自己调，
	# 不要在父类调用 self.method() 期望子类版本生效。
	if not _settled:
		await _try_player_claim_async(to_discard, actor)

func _try_ron_async(discarded: Tile, discarder: int) -> void:
	var is_houtei: bool = (state.wall.live_wall_size() == 0)
	# 三家和了 pre-check
	if _count_ron_candidates(discarded, discarder, is_houtei) >= 3:
		_emit(&"ABORTIVE_DRAW", -1, null, {"reason": "sancha_houra"})
		_settled = true
		return
	for offset in range(1, 4):
		var candidate: int = (discarder + offset) % 4
		var candidate_seat: Seat = state.seats[candidate]
		if not ClaimValidator.can_ron(candidate_seat.hand, candidate_seat.melds, discarded, candidate_seat.furiten):
			continue
		var ron_check: Dictionary = _check_ron(discarded, candidate, is_houtei)
		if not ron_check.is_winning:
			continue
		var accept: bool = await _should_accept_ron(candidate, discarded, discarder, ron_check, is_houtei)
		if not accept:
			continue
		if apply_ron(candidate, discarded, discarder, is_houtei):
			return

# 公共入口：荣胡（外部 driver 调用，不走 run_to_end 主循环）。
# discarder_seat: 弃牌人座（决定 ron_tile 的 owner_seat 与 score_ctx.loser_seat）。
# 返 false 表示和牌不成立（无役 / 听牌不命中 / 技能取消）。
func apply_ron(winner_seat: int, ron_tile: Tile, discarder_seat: int, is_houtei: bool = false, is_chankan: bool = false) -> bool:
	var ron_ti := TileInstance.make(ron_tile, discarder_seat, null)
	# M7：reset 上一次 emit 留下的 cancel 标记，避免同 hand 多次 ron 尝试时
	# 旧值粘连（例：先 seat 1 的 ron 被 cancel；再 seat 2 试 ron 时 ron_cancelled[2]
	# 默认 false，但若上次 emit 不小心也触发了 seat 2 的 cancel 就会粘连）
	state.ron_cancelled[winner_seat] = false
	# M11 net foundation: ron 接受决策（v1 自动接受 — Phase 2 玩家可"放弃和牌"
	# 等情景需要日志化）。本 emit 在 RON_DECLARED 之前以记录"决定 → 引擎应用"顺序
	_emit(&"PLAYER_ACTION", winner_seat, null, {
		"kind": "ron_accept",
		"tile_id": ron_tile.id,
		"discarder_seat": discarder_seat,
	})
	# 先 emit RON_DECLARED 让技能（如「中·封印」）有机会取消
	_emit(&"RON_DECLARED", winner_seat, ron_ti, {"discarder_seat": discarder_seat})
	if state.ron_cancelled[winner_seat]:
		return false
	var win := _check_ron(ron_tile, winner_seat, is_houtei, is_chankan)
	if not win.is_winning:
		return false
	_settle_ron(ron_tile, ron_ti, winner_seat, discarder_seat, win.wp, win.yaku_list, is_houtei)
	return true

func _settle_ron(ron_tile: Tile, ron_ti: TileInstance, winner_seat: int, discarder_seat: int, wp: Dictionary, yaku_list, is_houtei: bool = false) -> void:
	var winner: Seat = state.seats[winner_seat]

	var score_ctx := ScoreContext.new()
	score_ctx.is_tsumo = false
	score_ctx.winning_tile = ron_tile
	score_ctx.round_wind = state.round_wind
	score_ctx.seat_wind = winner.seat_wind
	score_ctx.dealer_seat = state.dealer_seat
	score_ctx.winner_seat = winner_seat
	score_ctx.loser_seat = discarder_seat
	score_ctx.honba = state.honba
	score_ctx.riichi_sticks = state.riichi_sticks

	var melds_arr: Array = []
	for m in winner.melds:
		melds_arr.append(m)
	# Ron 路径:winner.hand 是 13 张,胡牌手需含 ron_tile → 拼 14 张 Hand
	var win_hand_ron := Hand.new()
	for t in winner.hand._tiles:
		win_hand_ron.add(t)
	win_hand_ron.add(ron_tile)
	var score_yaku_list := _adapt_yaku_list(
		yaku_list, win_hand_ron, melds_arr, winner.riichi.declared)
	# 包牌(大三元/大四喜)— 检 yaku evaluator 命中 + melds 含 open dragon/wind 刻
	score_ctx.pao_seat = PaoCalculator.detect_pao_seat(
		yaku_list.id_list(), melds_arr)

	# M7：在 ScoreCalc 之前 emit pre-score 事件（HOUTEI? + WIN_DECLARED_PRE），
	# hooks 此时可通过 ctx.add_han / mark_extra_dora / multiply_han_for_seat
	# 真正影响计分。所有 pre-score ctx 收集到 pre_ctxs 数组里以便统一应用。
	var pre_ctxs: Array = []
	if is_houtei:
		pre_ctxs.append(_emit(&"HOUTEI", winner_seat, ron_ti, {}))
	var pre_extra: Dictionary = {"discarder_seat": discarder_seat, "is_tsumo": false, "is_houtei": is_houtei}
	pre_ctxs.append(_emit(&"WIN_DECLARED_PRE", winner_seat, ron_ti, pre_extra))
	_apply_skill_han_delta(score_yaku_list, _sum_skill_han(winner_seat, pre_ctxs))
	_apply_extra_dora(score_yaku_list, winner_seat)
	# M7 B3-mini：把 multiplicative effect（任一 pre ctx）应用到番数
	_apply_han_multiplier(score_yaku_list, _composite_multiplier(winner_seat, pre_ctxs))
	# M7 B3-mini：满贯下限保底（white_mangan_floor 等消耗品）
	if _has_mangan_floor(winner_seat, pre_ctxs):
		_apply_mangan_floor(score_yaku_list)
	# M9 B3：force_yakuman（boss3_kanmon spec 原效果"任意胡牌升级为役满"等）
	if _has_yakuman_force(winner_seat, pre_ctxs):
		_apply_yakuman_force(score_yaku_list)

	var result: Dictionary = ScoreCalc.calculate(wp, melds_arr, score_yaku_list, score_ctx)

	# M7：把 discarder_seat / points_won 注入 WIN_DECLARED.extra，让 post-score
	# hooks（soul_drain_hatsu / east_mirror_chambo 等用 transfer_points）能读到
	result["discarder_seat"] = discarder_seat
	result["points_won"] = int(result.get("winner_total", 0))
	# 给 UI 结算 overlay 用：抽出本次胡牌命中的役名 + han（已含 evaluator
	# 的役満/普通飜判定;skill_han/extra_dora 等修正不在此列表内）。
	result["yaku_names"] = _extract_yaku_names(yaku_list)

	engine.apply_ron(winner_seat, ron_tile)
	_emit(&"WIN_DECLARED", winner_seat, ron_ti, result)
	_settled = true

func _settle_tsumo(drawn: Tile, wp: Dictionary, yaku_list, is_haitei: bool = false, _is_rinshan: bool = false) -> void:
	var seat: Seat = state.seats[state.current_seat]
	var ti := _wrap_tile(drawn)
	# M11 net foundation: tsumo 接受是隐含决策（v1 自动接受）。本 emit 让事件
	# 流自包含 — 未来玩家"放弃自摸"或网络重放都能用
	_emit(&"PLAYER_ACTION", state.current_seat, null, {
		"kind": "tsumo_accept",
		"tile_id": drawn.id,
	})
	_emit(&"TSUMO_DECLARED", state.current_seat, ti, {})

	var score_ctx := ScoreContext.new()
	score_ctx.is_tsumo = true
	score_ctx.winning_tile = drawn
	score_ctx.round_wind = state.round_wind
	score_ctx.seat_wind = seat.seat_wind
	score_ctx.dealer_seat = state.dealer_seat
	score_ctx.winner_seat = state.current_seat
	score_ctx.honba = state.honba
	score_ctx.riichi_sticks = state.riichi_sticks

	var melds_arr: Array = []
	for m in seat.melds:
		melds_arr.append(m)

	# Tsumo 路径:engine.draw_for_current 已把摸的牌加进 seat.hand,所以
	# seat.hand 此时就是 14 张胡牌手,直接传给 _adapt_yaku_list 数 dora。
	var score_yaku_list := _adapt_yaku_list(
		yaku_list, seat.hand, melds_arr, seat.riichi.declared)
	# 包牌(自摸路径):大三元/大四喜由外鸣完成 → 包人付全额
	score_ctx.pao_seat = PaoCalculator.detect_pao_seat(
		yaku_list.id_list(), melds_arr)

	# M7：HAITEI? + WIN_DECLARED_PRE，accumulate hook 影响（han_deltas / dora /
	# multiplier）。pre_ctxs 持所有 pre-score ctx 引用。
	var pre_ctxs: Array = []
	if is_haitei:
		pre_ctxs.append(_emit(&"HAITEI", state.current_seat, ti, {}))
	var pre_extra: Dictionary = {"is_tsumo": true, "is_haitei": is_haitei}
	pre_ctxs.append(_emit(&"WIN_DECLARED_PRE", state.current_seat, ti, pre_extra))
	_apply_skill_han_delta(score_yaku_list, _sum_skill_han(state.current_seat, pre_ctxs))
	_apply_extra_dora(score_yaku_list, state.current_seat)
	_apply_han_multiplier(score_yaku_list, _composite_multiplier(state.current_seat, pre_ctxs))
	if _has_mangan_floor(state.current_seat, pre_ctxs):
		_apply_mangan_floor(score_yaku_list)
	# M9 B3：force_yakuman 自摸路径
	if _has_yakuman_force(state.current_seat, pre_ctxs):
		_apply_yakuman_force(score_yaku_list)

	var result: Dictionary = ScoreCalc.calculate(wp, melds_arr, score_yaku_list, score_ctx)

	# M7：tsumo 无 discarder_seat（自摸无放铳人），仅设 points_won
	result["points_won"] = int(result.get("winner_total", 0))
	result["yaku_names"] = _extract_yaku_names(yaku_list)

	engine.apply_tsumo(state.current_seat, drawn)
	_emit(&"WIN_DECLARED", state.current_seat, ti, result)
	_settled = true


# 把 YakuEntries 转成 UI 结算 overlay 用的 [{name, han}] 数组。
# 役満条目 han=0 → 显示为 "役満 (Nx)"。
static func _extract_yaku_names(eval_list) -> Array:
	var out: Array = []
	if eval_list == null:
		return out
	for entry in eval_list.entries:
		var meta: Dictionary = YakuId.metadata(int(entry.yaku_id))
		var name_zh: String = String(meta.get("name_zh", "?"))
		var item: Dictionary = {"name": name_zh, "han": int(entry.han)}
		if bool(entry.is_yakuman):
			item["yakuman_multiplier"] = int(entry.yakuman_multiplier)
		out.append(item)
	return out

# 把 YakuEntries（YakuEvaluator 出口）转成 YakuList（ScoreCalc 入口）。
# dora_count 修正(2026):原来用 visible_indicator_count 是 bug —— 实际 dora 数
# 应数胡牌手 14 张 + 副露里有几张匹配 dora 指示牌翻出来的那张 +1 牌(以及
# 赤宝牌 0m/0p/0s,立直胡时还要加裏 dora)。
# 调用方负责构造完整 14 张胡牌手(_settle_tsumo 已 14 / _settle_ron 在外
# 拼上 ron_tile),并传 include_uradora=seat.riichi.declared。
func _adapt_yaku_list(eval_list: YakuEntries, win_hand: Hand = null, win_melds: Array = [], include_uradora: bool = false) -> YakuList:
	var sc := YakuList.new()
	sc.is_yakuman = eval_list.is_yakuman()
	sc.yakuman_multiplier = eval_list.yakuman_total_multiplier()
	if win_hand != null:
		sc.dora_count = state.dora_indicators.count_total_dora(win_hand, win_melds, include_uradora)
	else:
		# 旧 API 兼容(其它 caller 临时):仍按 indicator 张数估,虽然不准。
		sc.dora_count = state.dora_indicators.visible.size()
	# YakuEntry.yaku_id 是 int (YakuId 常量)，但 YakuList.is_pinfu / is_chiitoi
	# 走 has_yaku(&"pinfu") / has_yaku(&"chiitoitsu") StringName 比较。
	# 这里把 PINFU / CHIITOITSU 转 StringName 让 FuCalculator 特殊符识别正确（M4
	# BattleNodeRunner 跑大量随机牌局触发了这个 M2 留下的类型不匹配 bug）。
	for entry in eval_list.entries:
		sc.yaku.append({"id": _yaku_id_to_string_name(entry.yaku_id), "han": entry.han})
	return sc

# M7：把 pre-score hook 累积的 han 增量注入到 ScoreCalc 输入的 yaku_list。
# 调用方负责把多个 ctx（HAITEI/HOUTEI + WIN_DECLARED_PRE）的 han_deltas
# 求和后传 delta 进来。delta = 0 不注入，避免污染 yaku_list；
# delta != 0 追加 &"skill_bonus" entry 由 ScoreCalc 累加。
static func _apply_skill_han_delta(yaku_list: YakuList, delta: int) -> void:
	if delta == 0:
		return
	yaku_list.add_yaku(&"skill_bonus", delta)

# M7 B2：把 BattleState.extra_dora_count[winner] + extra_red_dora_count[winner]
# 加到 yaku_list.dora_count（hooks 通过 ctx.mark_extra_dora_for_seat /
# ctx.mark_red_dora_for_seat 累积）。
func _apply_extra_dora(yaku_list: YakuList, winner_seat: int) -> void:
	yaku_list.dora_count += int(state.extra_dora_count[winner_seat])
	yaku_list.dora_count += int(state.extra_red_dora_count[winner_seat])

# M7 B3-mini：把 ctx.han_multipliers[winner] 应用到 yaku_list。
# 用合成"&\"skill_multiplier\""yaku entry 表达：(factor - 1) * total_han 番。
# 例如 factor=2.0、当前 total_han=5 → 加 +5 番（合 10 番）。
# factor <= 1.0 不操作（避免 ScoreFormula 钳制 < 0 番时混乱）。
static func _apply_han_multiplier(yaku_list: YakuList, factor: float) -> void:
	if factor <= 1.0:
		return
	var current_total: int = yaku_list.total_han()
	var added: int = int(current_total * (factor - 1.0))
	if added != 0:
		yaku_list.add_yaku(&"skill_multiplier", added)

# 累加多个 ctx 中 winner_seat 的 han_deltas（用于 HAITEI/HOUTEI + WIN_DECLARED_PRE）
static func _sum_skill_han(winner_seat: int, ctxs: Array) -> int:
	var total: int = 0
	for c in ctxs:
		if c == null:
			continue
		total += int(c.han_deltas.get(winner_seat, 0))
	return total

# 多个 ctx 的 han_multipliers 累乘（×2 + ×1.5 = ×3 复合）
static func _composite_multiplier(winner_seat: int, ctxs: Array) -> float:
	var product: float = 1.0
	for c in ctxs:
		if c == null:
			continue
		product *= float(c.han_multipliers.get(winner_seat, 1.0))
	return product

# M7 B3-mini：ensure_mangan — winner 在任一 ctx 标了 mangan_floor 时，
# 若当前 total_han < 5（满贯阈值）补差到 5（合成 &"skill_mangan_floor" yaku）。
const MANGAN_HAN_THRESHOLD: int = 5

static func _has_mangan_floor(winner_seat: int, ctxs: Array) -> bool:
	for c in ctxs:
		if c == null:
			continue
		if bool(c.mangan_floor_seats.get(winner_seat, false)):
			return true
	return false

static func _apply_mangan_floor(yaku_list: YakuList) -> void:
	var current: int = yaku_list.total_han()
	if current >= MANGAN_HAN_THRESHOLD:
		return  # 已满贯，无需补差
	yaku_list.add_yaku(&"skill_mangan_floor", MANGAN_HAN_THRESHOLD - current)

# M9 ctx B3：force_yakuman 检测 + 应用。
# winner 在任一 pre_ctx 标了 yakuman_force → yaku_list.is_yakuman=true,
# yakuman_multiplier=max(1, current)。已是役满则不变。
static func _has_yakuman_force(winner_seat: int, ctxs: Array) -> bool:
	for c in ctxs:
		if c == null:
			continue
		if bool(c.yakuman_force_seats.get(winner_seat, false)):
			return true
	return false

static func _apply_yakuman_force(yaku_list: YakuList) -> void:
	yaku_list.is_yakuman = true
	if yaku_list.yakuman_multiplier < 1:
		yaku_list.yakuman_multiplier = 1

# 兼容性 wrapper：从单个 ctx 取 han_deltas[winner_seat] 调 _apply_skill_han_delta。
# 现存测试 / 后续 PR 还会调用，保留。
static func _apply_skill_han(yaku_list: YakuList, ctx: SkillCtx, winner_seat: int) -> void:
	if ctx == null:
		return
	var delta: int = int(ctx.han_deltas.get(winner_seat, 0))
	_apply_skill_han_delta(yaku_list, delta)

# YakuId int → StringName 映射。仅覆盖 YakuList.has_yaku 实际查询的 id；
# 其它 id 用 str(int) 占位（不影响 ScoreCalc 累加 han 的正确性）。
static func _yaku_id_to_string_name(yaku_id: int) -> StringName:
	match yaku_id:
		YakuId.PINFU: return &"pinfu"
		YakuId.CHIITOITSU: return &"chiitoitsu"
	return StringName(str(yaku_id))

# ---- Task 3: Self-kan after draw ----
#
# After AI draws and tsumo is not accepted, check if ankan/added_kan is possible.
# Calls ai.decide_self_kan(seat) if available. For added_kan, first checks chankan
# (Task 5) before applying.

func _try_ai_self_kan() -> void:
	if not ai.has_method("decide_self_kan"):
		return
	var actor: int = state.current_seat
	var seat: Seat = state.seats[actor]
	var decision: Dictionary = ai.decide_self_kan(seat)
	if decision.is_empty():
		return
	var kind: String = String(decision.get("kind", ""))
	var tid: int = int(decision.get("tile_id", -1))
	if kind == "ankan":
		_emit(&"PLAYER_ACTION", actor, null, {"kind": "ankan", "tile_id": tid})
		engine.apply_ankan(actor, tid)
	elif kind == "added_kan":
		# Task 5: chankan check before applying added_kan
		if _try_chankan_ron(tid, actor):
			return  # someone ronned the kan tile
		_emit(&"PLAYER_ACTION", actor, null, {"kind": "added_kan", "tile_id": tid})
		engine.apply_added_kan(actor, tid)

# ---- Task 4: Claim resolution ----
#
# After discard, check if any AI seat wants to pon/minkan the discarded tile.
# Priority: pon/minkan (priority 2) > chi (priority 1).
# Ron is handled separately by _try_auto_ron before this.

func _get_last_discarded() -> Tile:
	for i in range(events.size() - 1, -1, -1):
		if events[i].type == &"TILE_DISCARDED" and events[i].tile_instance != null:
			return Tile.new(events[i].tile_instance.tile.id, events[i].tile_instance.tile.is_red_dora)
	return null

func _get_last_discarder() -> int:
	for i in range(events.size() - 1, -1, -1):
		if events[i].type == &"TILE_DISCARDED":
			return events[i].actor_seat
	return -1

func _resolve_claims(discarded: Tile, discarder: int) -> void:
	if not ai.has_method("decide_claim_for_seat"):
		engine.advance_to_next_seat()
		return
	var best_seat: int = -1
	var best_priority: int = 0
	var best_kind: String = ""
	for offset in range(1, 4):
		var candidate: int = (discarder + offset) % 4
		if candidate == 0:
			continue  # skip player seat — player claims via PlayableBattleController
		var seat: Seat = state.seats[candidate]
		var decision: Dictionary = ai.decide_claim_for_seat(seat, discarded.id, discarder)
		if decision.is_empty():
			continue
		var kind: String = String(decision.get("kind", ""))
		var priority: int = 0
		if kind == "pon" or kind == "minkan":
			priority = 2
		elif kind == "chi":
			priority = 1
		if priority > best_priority:
			best_priority = priority
			best_seat = candidate
			best_kind = kind
	if best_seat < 0:
		engine.advance_to_next_seat()
		return
	# Apply the best claim
	_emit(&"PLAYER_ACTION", best_seat, null, {
		"kind": best_kind,
		"tile_id": discarded.id,
		"discarder_seat": discarder,
	})
	if best_kind == "pon":
		engine.apply_pon(best_seat, discarded)
		state.kuikae_restricted[best_seat] = ClaimValidator.kuikae_restricted_ids(
			discarded.id, [], false)
	elif best_kind == "minkan":
		engine.apply_minkan(best_seat, discarded)
	# Emit TILE_CLAIMED event for UI / replay
	_emit(&"TILE_CLAIMED", best_seat, _wrap_tile(discarded), {
		"kind": best_kind,
		"discarder_seat": discarder,
	})

# ---- Task 5: Chankan (robbing a kan) ----
#
# Before applying added_kan, check if any other seat can ron the tile.
# Sets game_ctx.is_chankan = true for the yaku evaluation.

func _try_chankan_ron(kan_tile_id: int, kan_declarer: int) -> bool:
	var kan_tile := Tile.new(kan_tile_id)
	for offset in range(1, 4):
		var candidate: int = (kan_declarer + offset) % 4
		var candidate_seat: Seat = state.seats[candidate]
		if not ClaimValidator.can_ron(candidate_seat.hand, candidate_seat.melds, kan_tile, candidate_seat.furiten):
			continue
		var ron_check: Dictionary = _check_ron_chankan(kan_tile, candidate)
		if not ron_check.is_winning:
			continue
		if apply_ron(candidate, kan_tile, kan_declarer, false, true):
			return true
	return false

func _check_ron_chankan(ron_tile: Tile, winner_seat: int) -> Dictionary:
	var winner: Seat = state.seats[winner_seat]
	var typed_melds: Array[Meld] = []
	for m in winner.melds:
		typed_melds.append(m)
	var wp: Dictionary = WinPattern.detect(winner.hand, typed_melds, ron_tile)
	if not wp.is_winning:
		return {"is_winning": false}
	var game_ctx := _build_game_ctx(winner, false, false, false)
	game_ctx.is_chankan = true
	var yaku_wc := WinContext.new(winner.hand, typed_melds, ron_tile, wp, game_ctx)
	var yaku_list = YakuEvaluator.evaluate(yaku_wc)
	var has_yaku: bool = yaku_list.is_yakuman() or yaku_list.size() > 0
	if not has_yaku:
		return {"is_winning": false}
	return {
		"is_winning": true,
		"wp": wp,
		"yaku_list": yaku_list,
		"melds": typed_melds,
	}

# ---- 私有 helper ----

# 从 hand 拷一份并移除第一个 id == tile_id 的牌；返新 Hand；找不到返 null。
func _hand_minus_first(hand: Hand, tile_id: int) -> Hand:
	var copy := Hand.new()
	var skipped := false
	for t in hand._tiles:
		if not skipped and t.id == tile_id:
			skipped = true
			continue
		copy.add(t)
	if not skipped:
		return null
	return copy

# 用当前 BattleState + seat 构造 yaku/GameContext。
# is_haitei / is_houtei 由 _check_tsumo / _check_ron 根据牌墙状态传入；
# 之前一直是 false，导致海底捞月 / 河底捞鱼役在真战斗永不被检测。
func _build_game_ctx(seat: Seat, is_tsumo: bool, is_haitei: bool = false, is_houtei: bool = false, is_rinshan: bool = false, is_tenhou: bool = false, is_chiihou: bool = false) -> GameContext:
	var ctx := GameContext.new()
	ctx.bakaze = state.round_wind
	ctx.jikaze = seat.seat_wind
	ctx.is_tsumo = is_tsumo
	ctx.is_riichi = seat.riichi.declared
	ctx.is_double_riichi = seat.riichi.double_riichi
	ctx.is_ippatsu = seat.riichi.ippatsu_window
	ctx.is_haitei = is_haitei
	ctx.is_houtei = is_houtei
	# 岭上开花(rinshan kaihou)只在 tsumo 路径有意义,荣胡时永 false
	ctx.is_rinshan = is_rinshan and is_tsumo
	# 天和/地和:tenhou 仅庄家配牌即和;chiihou 仅闲家首摸即和。两者都要求 tsumo。
	ctx.is_dealer_first_hand = is_tenhou and is_tsumo
	ctx.is_non_dealer_first_draw = is_chiihou and is_tsumo
	ctx.dora_count = state.dora_indicators.visible.size()
	return ctx

# ---- M11 net foundation: replay API ----

# 注入决策回放队列。来自 extract_player_actions(prev_events)。
# 调用顺序：BC.new() → set_replay_decisions(actions) → run_to_end()。
# decisions 期间 BC 用 actions 替代 ai.decide_*，事件流应与原录制一致。
func set_replay_decisions(p_decisions: Array) -> void:
	_replay_decisions = p_decisions
	_replay_idx = 0

# 内部：若下一条决策匹配 (seat, kind)，pop 并返回；否则返 {}。
# 不匹配时不 advance _replay_idx — 下次调用还能 peek 同一条。
func _consume_replay_decision_if_match(p_seat: int, p_kind: String) -> Dictionary:
	if _replay_idx >= _replay_decisions.size():
		return {}
	var dec: Dictionary = _replay_decisions[_replay_idx]
	if int(dec.get("seat", -1)) == p_seat and String(dec.get("kind", "")) == p_kind:
		_replay_idx += 1
		return dec
	return {}

# 从 events 中抽 PlayerAction 序列。
# 用途：录回放 → 重放时把这些 action 注入 BC 替代 AI 决策路径。
# 返：[{seat, kind: "discard"|"riichi"|"tsumo_accept"|"ron_accept",
#       tile_id?: int, discarder_seat?: int}, ...]
static func extract_player_actions(p_events: Array) -> Array:
	# Only extract action kinds that the replay system consumes (discard, riichi,
	# tsumo_accept, ron_accept). AI-deterministic actions (pon, minkan, ankan,
	# added_kan) are re-derived from the AI during replay and must NOT enter the
	# replay queue — otherwise _consume_replay_decision_if_match will stall on
	# unmatched kinds and block subsequent legitimate matches.
	const REPLAY_KINDS: Array = ["discard", "riichi", "tsumo_accept", "ron_accept"]
	var result: Array = []
	for ev in p_events:
		if ev.type != &"PLAYER_ACTION":
			continue
		var kind_str: String = String(ev.extra.get("kind", ""))
		if kind_str not in REPLAY_KINDS:
			continue
		var entry: Dictionary = {
			"seat": ev.actor_seat,
			"kind": kind_str,
		}
		if entry.kind == "discard" or entry.kind == "tsumo_accept" or entry.kind == "ron_accept":
			entry["tile_id"] = int(ev.extra.get("tile_id", -1))
		if entry.kind == "ron_accept":
			entry["discarder_seat"] = int(ev.extra.get("discarder_seat", -1))
		result.append(entry)
	return result
