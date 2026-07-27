class_name BattleController extends IAuthoritativeBattleController

const RIICHI_STICK_COST: int = 1000

# 里程碑 2 + E2-02 — 端到端本地权威编排器。
# 唯一行动入口：apply_action(Action, ActionSource) -> ActionResolution
# journal = 已接受 Action；load_replay_journal = 期望队列（与 journal 分离）

const MAX_LOOP_STEPS := 2000  # 一局上限，防死循环；正常一局 < 200 步
const DEFAULT_ROOM_ID := "local"
const _ACTION_CMD_UUID_PREFIX := "550e8400-e29b-41d4-a716-"

# 领域执行 tri-state：成功应用 / 技能取消（保留事件）/ 规则失败
const DOMAIN_APPLIED: int = 0
const DOMAIN_CANCELLED: int = 1
const DOMAIN_FAILED: int = 2

# state / engine / registry / scheduler / ai / events 在 IAuthoritativeBattleController
var _settled: bool = false
var _last_event_type: StringName = &""
var _battle_seed: int = 0
var _action_cmd_seq: int = 0
var _window_seq: int = 0
var _last_discarded_tile: Tile = null
var _last_discarder_seat: int = -1
# 已接受 Action journal（元素级深拷贝对外）
var _action_journal: Array = []
# 期望回放队列（与 journal 分离）
var _expected_replay: Array = []
var _expected_replay_idx: int = 0
var _replay_status: StringName = &"IDLE"
var _active_window: DecisionWindow = null
var _active_window_phase: int = -1
var _pending_added_kan: Dictionary = {}

func _init(seed: int = 0, dealer_seat: int = 0, use_heuristic_ai: bool = false, round_wind: int = TileId.E, hand_seq: int = 0) -> void:
	# round_wind: M8 半庄战支持。默认东兼容 M7；GameDriver 在南场调用时
	# 传 TileId.S_WIND 以激活场风南牌役（南、南家自风南）。
	# hand_seq: E2-02 实体 id 命名空间（默认 0，兼容旧 4 参调用）。
	# 非法 / for_east_round 失败 → fail-closed：state/engine/registry/scheduler/ai 保持 null。
	_battle_seed = seed
	if hand_seq < 0 or hand_seq > Wall.MAX_HAND_SEQ:
		return
	state = BattleState.for_east_round(seed, dealer_seat, 1, 0, 0, round_wind, hand_seq)
	if state == null:
		return
	engine = TurnEngine.new(state)
	registry = SkillRegistry.new()
	scheduler = SkillScheduler.new(registry, state)
	# AI 用不同 seed，与洗牌 seed 解耦
	if use_heuristic_ai:
		ai = HeuristicAi.new(seed + 1)
	else:
		ai = SimpleAi.new(seed + 1)
	# E2-04：无 mode_modules 时 legacy 保留 Momentum
	_apply_momentum_for_mode()


## E2-04：注入会话模式模块并按模式装配 Momentum / 门控。
func bind_mode_modules(modules: ModeModuleBundle) -> void:
	mode_modules = modules
	_apply_momentum_for_mode()


func _apply_momentum_for_mode() -> void:
	if state == null:
		return
	if mode_modules != null and mode_modules.is_standard():
		state.momentum = null
	elif mode_modules != null and mode_modules.is_trash_talk():
		if mode_modules.momentum != null:
			state.momentum = mode_modules.momentum
		elif state.momentum == null:
			state.momentum = Momentum.new()
	else:
		# legacy：mode_modules == null
		if state.momentum == null:
			state.momentum = Momentum.new()

# ---- 主入口 ----

# 跑到流局或胡牌；返 {last_event: StringName, events: Array[BattleEvent]}
# 状态机：DRAW 只摸牌/事件；TURN(DISCARD) 选 Action→apply_action；
# CLAIM / ROB_KAN 收齐 intent 后由 BattleActionResolver 裁决。
func _impl_run_to_end() -> Dictionary:
	_emit(&"GAME_BEGIN", state.dealer_seat, null, {})

	var steps := 0
	while not _settled and steps < MAX_LOOP_STEPS:
		steps += 1
		if not _pending_added_kan.is_empty():
			_step_rob_kan_collect()
		elif state.phase == BattlePhase.Kind.DRAW:
			_step_draw()
		elif state.phase == BattlePhase.Kind.DISCARD:
			_step_turn()
		elif state.phase == BattlePhase.Kind.CLAIM:
			_step_claim_collect()
		elif state.phase == BattlePhase.Kind.SETTLE:
			break
		if not _settled:
			_check_and_emit_abortive_draws()

	_finalize_replay_lifecycle_status()
	return {
		"last_event": _last_event_type,
		"events": events,
	}

# ---- 步骤 ----

func _step_draw() -> void:
	# DRAW 只允许 server draw/事件；TSUMO/KAN 等由 TURN Action 选择。
	var t: Tile = engine.draw_for_current()
	if t == null:
		_emit(&"EXHAUSTIVE_DRAW", -1, null, {})
		var nm_winner: int = NagashiMangan.detect_winner_seat(state)
		if nm_winner >= 0:
			_emit(&"NAGASHI_MANGAN", nm_winner, null,
				{"winner_seat": nm_winner})
		_settled = true
		return
	_emit(&"TILE_DRAWN", state.current_seat, _wrap_tile(t), {})


func _step_turn() -> void:
	var seat: Seat = state.seats[state.current_seat]
	var actor: int = state.current_seat
	_close_ippatsu_if_lap_passed(seat)
	# 岭上标记仅供 TURN 的 TSUMO 役判定；不在此旁路 settle
	if seat.last_draw_is_rinshan and seat.last_drawn_instance_id == Tile.INVALID_INSTANCE_ID:
		seat.last_draw_is_rinshan = false

	var source: StringName = ActionSource.AI
	var act: Action = null
	if _replay_status == &"LOADED" or _replay_status == &"RUNNING":
		source = ActionSource.REPLAY
		act = _peek_expected_replay()
		if act == null:
			_replay_status = &"MISMATCH"
			_settled = true
			return
	else:
		act = _select_ai_turn_action(seat, actor)
		if act == null:
			_settled = true
			return
	var resp: ActionResolution = apply_action(act, source)
	if resp == null or not resp.accepted:
		_settled = true
		return


func _step_claim_collect() -> void:
	var discarded: Tile = _get_last_discarded()
	var discarder: int = _get_last_discarder()
	if discarded == null or discarder < 0:
		engine.advance_to_next_seat()
		_invalidate_window()
		return
	_ensure_active_window()
	if _active_window == null or _active_window.kind != DecisionWindow.KIND_CLAIM:
		engine.advance_to_next_seat()
		_invalidate_window()
		return
	var source: StringName = ActionSource.AI
	if _replay_status == &"LOADED" or _replay_status == &"RUNNING":
		source = ActionSource.REPLAY
	for offset in range(1, 4):
		var candidate: int = (discarder + offset) % 4
		if _active_window.has_responded(candidate):
			continue
		var act: Action = null
		if source == ActionSource.REPLAY:
			act = _peek_expected_replay()
			if act == null or act.seat != candidate:
				act = _build_pass_action(candidate)
		else:
			act = _build_ai_claim_action(candidate, discarded, discarder)
		if act == null:
			act = _build_pass_action(candidate)
		if act == null:
			continue
		var resp: ActionResolution = apply_action(act, source)
		if resp == null:
			continue
		if not resp.accepted and source == ActionSource.REPLAY:
			_settled = true
			return
		if _settled:
			return
	if state.phase == BattlePhase.Kind.CLAIM and _active_window != null \
			and not _active_window.is_complete():
		# 异常兜底
		engine.advance_to_next_seat()
		_invalidate_window()


func _step_rob_kan_collect() -> void:
	_ensure_active_window()
	if _active_window == null or _active_window.kind != DecisionWindow.KIND_ROB_KAN:
		# 无窗则按全 PASS 升级
		_finalize_pending_added_kan_all_pass()
		return
	var kan_seat: int = int(_pending_added_kan.get("seat", -1))
	var source: StringName = ActionSource.AI
	if _replay_status == &"LOADED" or _replay_status == &"RUNNING":
		source = ActionSource.REPLAY
	for offset in range(1, 4):
		var candidate: int = (kan_seat + offset) % 4
		if _active_window.has_responded(candidate):
			continue
		var act: Action = null
		if source == ActionSource.REPLAY:
			act = _peek_expected_replay()
			if act == null or act.seat != candidate:
				act = _build_pass_action(candidate)
		else:
			act = _build_ai_rob_kan_action(candidate)
		if act == null:
			act = _build_pass_action(candidate)
		if act == null:
			continue
		var resp: ActionResolution = apply_action(act, source)
		if resp == null:
			continue
		if not resp.accepted and source == ActionSource.REPLAY:
			_settled = true
			return
		if _settled or _pending_added_kan.is_empty():
			return

# ---- 事件 emit ----

# 把一次 emit 集中到此 helper：登记 log + 调 scheduler。
func _emit(type: StringName, actor_seat: int, ti: TileSkillAnchor, extra: Dictionary) -> SkillCtx:
	var ev := BattleEvent.make(type, actor_seat, ti, extra)
	events.append(ev)
	_last_event_type = type
	var ctx := scheduler.emit_event(ev)
	_append_skill_triggered_events(ctx, type)
	return ctx


# 只激活指定技能，不把等价 source event 广播给 registry 中其他技能。
func activate_single_skill_for_event(
	skill: SkillResource,
	beneficiary_seat: int,
	source_type: StringName
) -> SkillCtx:
	var ev := BattleEvent.make(source_type, beneficiary_seat, null, {})
	var ctx := scheduler.emit_single_skill_event(ev, skill, beneficiary_seat)
	_append_skill_triggered_events(ctx, source_type)
	return ctx


func _append_skill_triggered_events(ctx: SkillCtx, source_type: StringName) -> void:
	for entry in ctx.triggered_skills:
		var skill_extra := {
			"skill_id": String(entry.skill_id),
			"skill_name": entry.skill_name,
			"source_event": String(source_type),
		}
		if entry.has("extra_dora_delta"):
			skill_extra["extra_dora_delta"] = int(entry.extra_dora_delta)
		if entry.has("extra_red_dora_delta"):
			skill_extra["extra_red_dora_delta"] = int(entry.extra_red_dora_delta)
		var skill_ev := BattleEvent.make(
			&"SKILL_TRIGGERED", int(entry.beneficiary_seat), null, skill_extra)
		events.append(skill_ev)

# 把 Tile 包成 TileSkillAnchor 以喂事件 payload。
# Tile 当前没有 owner_seat 字段（main 合并冲突里 commit 2b87929 的字段被丢掉，是 main 旧债，
# 不在里程碑 2 修复范围）。本里程碑 owner_seat 默认 -1；路径 C/D 涉及 owner 归属时由
# BattleController 在专用 fixture 入口（_register_skill_for_tile）显式塞 TileSkillAnchor 到映射表。
func _wrap_tile(t: Tile) -> TileSkillAnchor:
	if t == null:
		return null
	return TileSkillAnchor.make(t, -1, null)

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
# 从 hand 拷一份并移除指定 instance_id 的牌；返新 Hand；找不到返 null。
func _hand_minus_instance(hand: Hand, instance_id: int) -> Hand:
	var copy := Hand.new()
	var skipped := false
	for t in hand.tiles():
		if not skipped and t.instance_id == instance_id:
			skipped = true
			continue
		copy.add(t)
	if not skipped:
		return null
	return copy


func _check_tsumo(drawn: Tile, is_haitei: bool = false, is_rinshan: bool = false, is_tenhou: bool = false, is_chiihou: bool = false) -> Dictionary:
	var seat: Seat = state.seats[state.current_seat]
	var hand_13: Hand = _hand_minus_instance(seat.hand, drawn.instance_id)
	if hand_13 == null:
		return {"is_winning": false}
	var typed_melds: Array[Meld] = seat.melds.all()
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
	var typed_melds: Array[Meld] = winner.melds.all()
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

# 旧 _try_auto_ron / _count_ron_candidates 旁路已删除。
# RON / sancha 仅由 CLAIM DecisionWindow 实际 intent + BattleActionResolver 裁决。

# ---- 决策钩子（subclass 覆写以接入玩家输入或网络权威） ----
#
# 这些钩子是同步默认实现：返当前 AI / RiichiValidator 计算的决策，与原来直
# 接 inline 调用 ai.decide_* 的行为完全一致。PlayableBattleController 子类
# 覆写这些钩子改成 await PlayerDecisionPort，配合 run_to_end_async()。
# 默认 sync 路径下 await 一个非 coroutine 值是 no-op，所以两条路径可共用。

# 决定 actor 切哪张牌；默认 = ai.decide_discard(seat)。
# 日麻 §5 立直锁牌:已立直 + 有刚摸的牌 → 强制 tsumogiri,不再让 AI 决策
# (AI 决策不知 riichi 状态,会非法换牌)。
func _get_discard_decision(seat: Seat, actor: int) -> Tile:
	if seat.riichi.declared and seat.last_drawn_instance_id != Tile.INVALID_INSTANCE_ID:
		var forced: Tile = seat.hand.find_by_instance_id(seat.last_drawn_instance_id)
		if forced != null:
			return forced
	if ai.has_method("set_defense_context"):
		var riichi_seats: Array = []
		var discards_flat: Array = []
		for i in range(4):
			if i == actor:
				continue
			if state.seats[i].riichi.declared:
				riichi_seats.append(i)
			for d in state.seats[i].river.tiles():
				if d != null:
					discards_flat.append(d.id)
		ai.set_defense_context(riichi_seats, discards_flat)
	var pick: Tile = ai.decide_discard(seat)
	if pick != null and not state.kuikae_restricted[actor].is_empty():
		var restricted: Array = state.kuikae_restricted[actor]
		if restricted.has(pick.id):
			for t in seat.hand.tiles():
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

# ---- run_to_end 的 async 镜像：与 sync 同一状态机，仅 TURN/CLAIM/ROB 决策可 await ----
func run_to_end_async() -> Dictionary:
	_emit(&"GAME_BEGIN", state.dealer_seat, null, {})

	var steps := 0
	while not _settled and steps < MAX_LOOP_STEPS:
		steps += 1
		if not _pending_added_kan.is_empty():
			await _step_rob_kan_collect_async()
		elif state.phase == BattlePhase.Kind.DRAW:
			await _step_draw_async()
		elif state.phase == BattlePhase.Kind.DISCARD:
			await _step_turn_async()
		elif state.phase == BattlePhase.Kind.CLAIM:
			await _step_claim_collect_async()
		elif state.phase == BattlePhase.Kind.SETTLE:
			break
		if not _settled:
			_check_and_emit_abortive_draws()

	_finalize_replay_lifecycle_status()
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
	# 与 sync 相同：仅 server draw/事件
	_step_draw()


func _step_turn_async() -> void:
	var seat: Seat = state.seats[state.current_seat]
	var actor: int = state.current_seat
	_close_ippatsu_if_lap_passed(seat)
	var source: StringName = ActionSource.AI
	var act: Action = null
	if _replay_status == &"LOADED" or _replay_status == &"RUNNING":
		source = ActionSource.REPLAY
		act = _peek_expected_replay()
		if act == null:
			_replay_status = &"MISMATCH"
			_settled = true
			return
	else:
		act = await _select_turn_action_async(seat, actor)
		if act == null:
			_settled = true
			return
		if actor == 0 and _is_human_turn_source():
			source = ActionSource.HUMAN
	var resp: ActionResolution = apply_action(act, source)
	if resp == null or not resp.accepted:
		_settled = true
		return


func _step_claim_collect_async() -> void:
	var discarded: Tile = _get_last_discarded()
	var discarder: int = _get_last_discarder()
	if discarded == null or discarder < 0:
		engine.advance_to_next_seat()
		_invalidate_window()
		return
	_ensure_active_window()
	if _active_window == null or _active_window.kind != DecisionWindow.KIND_CLAIM:
		engine.advance_to_next_seat()
		_invalidate_window()
		return
	var source: StringName = ActionSource.AI
	if _replay_status == &"LOADED" or _replay_status == &"RUNNING":
		source = ActionSource.REPLAY
	for offset in range(1, 4):
		var candidate: int = (discarder + offset) % 4
		if _active_window.has_responded(candidate):
			continue
		var act: Action = null
		if source == ActionSource.REPLAY:
			act = _peek_expected_replay()
			if act == null or act.seat != candidate:
				act = _build_pass_action(candidate)
		else:
			act = await _select_claim_action_async(candidate, discarded, discarder)
		if act == null:
			act = _build_pass_action(candidate)
		var use_src: StringName = source
		if candidate == 0 and _is_human_turn_source() and source != ActionSource.REPLAY:
			use_src = ActionSource.HUMAN
		var resp: ActionResolution = apply_action(act, use_src)
		if resp == null:
			continue
		if not resp.accepted and use_src == ActionSource.REPLAY:
			_settled = true
			return
		if _settled:
			return


func _step_rob_kan_collect_async() -> void:
	_ensure_active_window()
	if _active_window == null or _active_window.kind != DecisionWindow.KIND_ROB_KAN:
		_finalize_pending_added_kan_all_pass()
		return
	var kan_seat: int = int(_pending_added_kan.get("seat", -1))
	var source: StringName = ActionSource.AI
	if _replay_status == &"LOADED" or _replay_status == &"RUNNING":
		source = ActionSource.REPLAY
	for offset in range(1, 4):
		var candidate: int = (kan_seat + offset) % 4
		if _active_window.has_responded(candidate):
			continue
		var act: Action = null
		if source == ActionSource.REPLAY:
			act = _peek_expected_replay()
			if act == null or act.seat != candidate:
				act = _build_pass_action(candidate)
		else:
			act = await _select_rob_kan_action_async(candidate)
		if act == null:
			act = _build_pass_action(candidate)
		var use_src: StringName = source
		if candidate == 0 and _is_human_turn_source() and source != ActionSource.REPLAY:
			use_src = ActionSource.HUMAN
		var resp: ActionResolution = apply_action(act, use_src)
		if resp == null:
			continue
		if not resp.accepted and use_src == ActionSource.REPLAY:
			_settled = true
			return
		if _settled or _pending_added_kan.is_empty():
			return


func _is_human_turn_source() -> bool:
	# Playable 子类覆写为 true；默认 AI-only
	return false


func _select_turn_action_async(seat: Seat, actor: int) -> Action:
	return _select_ai_turn_action(seat, actor)


func _select_claim_action_async(candidate: int, discarded: Tile, discarder: int) -> Action:
	return _build_ai_claim_action(candidate, discarded, discarder)


func _select_rob_kan_action_async(candidate: int) -> Action:
	return _build_ai_rob_kan_action(candidate)


# 私有：荣和结算 helper（外部一律 Action.ron → apply_action）。
# 返 DOMAIN_APPLIED / DOMAIN_CANCELLED / DOMAIN_FAILED。
func _apply_ron_private(winner_seat: int, ron_tile: Tile, discarder_seat: int, is_houtei: bool = false, is_chankan: bool = false) -> int:
	var ron_ti := TileSkillAnchor.make(ron_tile, discarder_seat, null)
	# 每次尝试前 reset，避免同 hand 多次 ron 时旧 cancel 粘连
	state.ron_cancelled[winner_seat] = false
	# 规则先判：不成立则 FAILED，且不 emit（技能无机会 consume）
	var win := _check_ron(ron_tile, winner_seat, is_houtei, is_chankan)
	if not win.is_winning:
		return DOMAIN_FAILED
	# 规则成立后再 emit，技能可 cancel；CANCELLED 保留事件与 cancel/consume 状态
	_emit(&"RON_DECLARED", winner_seat, ron_ti, {
		"discarder_seat": discarder_seat,
		"is_tsumo": false,
		"is_chankan": is_chankan,
	})
	if state.ron_cancelled[winner_seat]:
		return DOMAIN_CANCELLED
	# 权威状态提交在 settle 之前：普通 ron 走 engine.apply_ron；chankan 不经河末校验
	if is_chankan:
		state.current_seat = winner_seat
		state.phase = BattlePhase.Kind.SETTLE
	else:
		if not engine.apply_ron(winner_seat, ron_tile.instance_id):
			return DOMAIN_FAILED
	_settle_ron(ron_tile, ron_ti, winner_seat, discarder_seat,
		win.wp, win.yaku_list, is_houtei, is_chankan)
	return DOMAIN_APPLIED

# 不可失败：调用方已完成 engine/state 权威提交，此处仅计分与事件结算。
func _settle_ron(ron_tile: Tile, ron_ti: TileSkillAnchor, winner_seat: int,
		discarder_seat: int, wp: Dictionary, yaku_list,
		is_houtei: bool = false, is_chankan: bool = false) -> void:
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

	var melds_arr: Array = winner.melds.all()
	# Ron 路径:winner.hand 是 13 张,胡牌手需含 ron_tile → 拼 14 张 Hand
	var win_hand_ron := Hand.new()
	for t in winner.hand.tiles():
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
	var pre_extra: Dictionary = {
		"discarder_seat": discarder_seat,
		"is_tsumo": false,
		"is_houtei": is_houtei,
		"is_chankan": is_chankan,
	}
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
	result["is_tsumo"] = false
	result["is_chankan"] = is_chankan
	result["points_won"] = int(result.get("winner_total", 0))
	result["dora_count"] = int(score_yaku_list.dora_count)
	result["ability_extra_dora_count"] = _sum_ability_extra_dora(
		winner_seat, pre_ctxs)
	result["ability_extra_red_dora_count"] = _sum_ability_extra_red_dora(
		winner_seat, pre_ctxs)
	# 给 UI 结算 overlay 用：抽出本次胡牌命中的役名 + han（已含 evaluator
	# 的役満/普通飜判定;skill_han/extra_dora 等修正不在此列表内）。
	result["yaku_names"] = _extract_yaku_names(yaku_list)

	_emit(&"WIN_DECLARED", winner_seat, ron_ti, result)
	_settled = true

func _settle_tsumo(drawn: Tile, wp: Dictionary, yaku_list, is_haitei: bool = false, _is_rinshan: bool = false) -> void:
	# 纯结算：TSUMO_DECLARED + engine.apply_tsumo 由 _apply_tsumo_action 在成功路径先完成
	var seat: Seat = state.seats[state.current_seat]
	var ti := _wrap_tile(drawn)

	var score_ctx := ScoreContext.new()
	score_ctx.is_tsumo = true
	score_ctx.winning_tile = drawn
	score_ctx.round_wind = state.round_wind
	score_ctx.seat_wind = seat.seat_wind
	score_ctx.dealer_seat = state.dealer_seat
	score_ctx.winner_seat = state.current_seat
	score_ctx.honba = state.honba
	score_ctx.riichi_sticks = state.riichi_sticks

	var melds_arr: Array = seat.melds.all()

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
	result["is_tsumo"] = true
	result["is_chankan"] = false
	result["points_won"] = int(result.get("winner_total", 0))
	result["dora_count"] = int(score_yaku_list.dora_count)
	result["ability_extra_dora_count"] = _sum_ability_extra_dora(
		state.current_seat, pre_ctxs)
	result["ability_extra_red_dora_count"] = _sum_ability_extra_red_dora(
		state.current_seat, pre_ctxs)
	result["yaku_names"] = _extract_yaku_names(yaku_list)

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
		sc.dora_count = state.dora_indicators.visible_count()
	# YakuEntry.yaku_id 是 int (YakuId 常量)，但 YakuList.is_pinfu / is_chiitoi
	# 走 has_yaku(&"pinfu") / has_yaku(&"chiitoitsu") StringName 比较。
	# 这里把 PINFU / CHIITOITSU 转 StringName，让 FuCalculator 正确识别特殊符。
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


static func _sum_ability_extra_dora(winner_seat: int, ctxs: Array) -> int:
	var total := 0
	for ctx in ctxs:
		if ctx == null:
			continue
		for entry_value in ctx.triggered_skills:
			if not (entry_value is Dictionary):
				continue
			var entry: Dictionary = entry_value
			if int(entry.get("beneficiary_seat", -1)) != winner_seat \
					or not bool(entry.get("is_ability", false)):
				continue
			total += int(entry.get("extra_dora_delta", 0))
	return total


static func _sum_ability_extra_red_dora(winner_seat: int, ctxs: Array) -> int:
	var total := 0
	for ctx in ctxs:
		if ctx == null:
			continue
		for entry_value in ctx.triggered_skills:
			if not (entry_value is Dictionary):
				continue
			var entry: Dictionary = entry_value
			if int(entry.get("beneficiary_seat", -1)) != winner_seat \
					or not bool(entry.get("is_ability", false)):
				continue
			total += int(entry.get("extra_red_dora_delta", 0))
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

func _get_last_discarded() -> Tile:
	return _last_discarded_tile


func _get_last_discarder() -> int:
	return _last_discarder_seat


func _build_pass_action(seat_id: int) -> Action:
	var ctx: DecisionContext = _decision_context_ref_for_seat(seat_id)
	if ctx == null:
		return null
	return Action.make_pass(
		seat_id, DEFAULT_ROOM_ID, _next_action_command_id(),
		ctx.decision_id, state.hand_seq, _action_cmd_seq
	)


func _build_ai_claim_action(candidate: int, discarded: Tile, discarder: int) -> Action:
	var ctx: DecisionContext = _decision_context_ref_for_seat(candidate)
	if ctx == null:
		return null
	var cmd: String = _next_action_command_id()
	var did: String = ctx.decision_id
	var hs: int = state.hand_seq
	# AI 有 RON offer 时必须提交 Action.ron（不再走自动荣和旁路）
	if ctx.has_kind("RON"):
		return Action.ron(candidate, DEFAULT_ROOM_ID, cmd, did, hs, _action_cmd_seq)
	if not ai.has_method("decide_claim_for_seat"):
		return _build_pass_action(candidate)
	var seat: Seat = state.seats[candidate]
	var decision: Dictionary = ai.decide_claim_for_seat(seat, discarded.id, discarder)
	if decision.is_empty():
		return _build_pass_action(candidate)
	var kind: String = String(decision.get("kind", ""))
	if kind == "pon" and ctx.has_kind("PON"):
		var comps: Array = _match_type_iids(seat.hand, [discarded.id, discarded.id])
		if comps.size() == 2 and ctx.allows("PON", {"companion_tile_instance_ids": comps}):
			return Action.pon(candidate, comps, DEFAULT_ROOM_ID, cmd, did, hs, _action_cmd_seq)
	if kind == "minkan" and ctx.has_kind("KAN"):
		var comps3: Array = _match_type_iids(seat.hand, [discarded.id, discarded.id, discarded.id])
		if comps3.size() == 3:
			var pay := {"kan_kind": "MINKAN", "companion_tile_instance_ids": comps3}
			if ctx.allows("KAN", pay):
				return Action.kan(candidate, pay, DEFAULT_ROOM_ID, cmd, did, hs, _action_cmd_seq)
	if kind == "chi" and ctx.has_kind("CHI"):
		var type_ids: Array = decision.get("companion_tile_ids", []) as Array
		var comps_c: Array = _match_type_iids(seat.hand, type_ids)
		if comps_c.size() == 2 and ctx.allows("CHI", {"companion_tile_instance_ids": comps_c}):
			return Action.chi(candidate, comps_c, DEFAULT_ROOM_ID, cmd, did, hs, _action_cmd_seq)
	return _build_pass_action(candidate)


func _build_ai_rob_kan_action(candidate: int) -> Action:
	var ctx: DecisionContext = _decision_context_ref_for_seat(candidate)
	if ctx == null:
		return null
	if ctx.has_kind("RON"):
		return Action.ron(
			candidate, DEFAULT_ROOM_ID, _next_action_command_id(),
			ctx.decision_id, state.hand_seq, _action_cmd_seq
		)
	return _build_pass_action(candidate)


func _select_ai_turn_action(seat: Seat, actor: int) -> Action:
	var ctx: DecisionContext = _decision_context_ref_for_seat(actor)
	if ctx == null:
		return null
	var cmd: String = _next_action_command_id()
	var did: String = ctx.decision_id
	var hs: int = state.hand_seq
	# TSUMO 优先（对齐旧 auto-accept）
	if ctx.has_kind("TSUMO"):
		return Action.tsumo(actor, DEFAULT_ROOM_ID, cmd, did, hs, _action_cmd_seq)
	# 自摸杠：AI decide_self_kan
	if ctx.has_kind("KAN") and ai != null and ai.has_method("decide_self_kan"):
		var decision: Dictionary = ai.decide_self_kan(seat)
		if not decision.is_empty():
			var k: String = String(decision.get("kind", ""))
			var tid: int = int(decision.get("tile_id", -1))
			if k == "ankan":
				var iids: Array = _hand_iids_of_type(seat.hand, tid)
				if iids.size() >= 4:
					var pay_a := {"kan_kind": "ANKAN", "tile_instance_ids": iids.slice(0, 4)}
					if ctx.allows("KAN", pay_a):
						return Action.kan(actor, pay_a, DEFAULT_ROOM_ID, cmd, did, hs, _action_cmd_seq)
			elif k == "added_kan":
				for offer in ctx.allowed_actions:
					if str(offer.get("kind", "")) != "KAN":
						continue
					for opt in offer.get("payload_options", []):
						if str(opt.get("kan_kind", "")) != "ADDED_KAN":
							continue
						var added_iid: int = int(opt.get("added_tile_instance_id", -1))
						var at: Tile = seat.hand.find_by_instance_id(added_iid)
						if at != null and at.id == tid and ctx.allows("KAN", opt):
							return Action.kan(actor, opt, DEFAULT_ROOM_ID, cmd, did, hs, _action_cmd_seq)
	# DISCARD / RIICHI
	return _build_action_for_tile(seat, actor, _get_discard_decision(seat, actor))


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
	ctx.is_rinshan = is_rinshan and is_tsumo
	ctx.is_dealer_first_hand = is_tenhou and is_tsumo
	ctx.is_non_dealer_first_draw = is_chiihou and is_tsumo
	ctx.dora_count = state.dora_indicators.visible_count()
	return ctx


# ---- E2-02：统一 Action 入口 / DecisionWindow / journal / replay ----

func _impl_apply_action(action: Action, source: StringName = ActionSource.HUMAN) -> ActionResolution:
	if action == null:
		return ActionResolution.rejected(ActionResolution.INVALID_ACTION)
	if not ActionSource.is_valid(source):
		return ActionResolution.rejected(ActionResolution.INVALID_ACTION)
	# #253：练习 TT 生产入口 — 路由到共享 LocalLoopback（与 Worker 同事务）
	var auth = _get_practice_authority()
	if auth != null and not bool(auth.call("is_processing_internal")):
		if not bool(auth.get("_started")):
			if not bool(auth.call("start")):
				return ActionResolution.rejected(ActionResolution.INVALID_ACTION)
		# PBC 生产 Action 使用 DEFAULT_ROOM_ID("local")；仅该默认值可转为 session room。
		# 任意错误 room 不得静默修正（返回 null → WRONG_ROOM）。
		action = _align_action_room_for_practice_authority(action, auth)
		if action == null:
			return ActionResolution.rejected(ActionResolution.WRONG_ROOM)
		if source == ActionSource.HUMAN:
			var cr: CommandResult = auth.call("submit_action", action) as CommandResult
			return _command_result_to_resolution(cr)
		# AI / REPLAY：传入原始 source，禁止在 Loopback 内降级为 HUMAN
		return auth.call("process_internal_action", action, source) as ActionResolution
	# E2-04：模式硬隔离门控（可区分 MODE_FORBIDDEN；先于 E5 NOT_ENABLED）
	if mode_modules != null and not mode_modules.accepts_command_kind(action.kind):
		return ActionResolution.rejected(ActionResolution.MODE_FORBIDDEN)
	# #253：ITEM_USE 仅经 LocalLoopback（PBC meta local_authority）统一事务。
	# 裸 BC（含 TT modules 但无权威）fail-closed，禁止无事件侧写库存。
	if action.kind == "ITEM_USE":
		if mode_modules == null or not mode_modules.is_trash_talk():
			return ActionResolution.rejected(ActionResolution.NOT_ENABLED)
		return ActionResolution.rejected(ActionResolution.RULE_REJECTED)

	# REPLAY：先对齐期望队列（不得被 WRONG_* 抢走）
	if source == ActionSource.REPLAY:
		var expected: Action = _peek_expected_replay()
		if expected == null or expected.to_dict() != action.to_dict():
			_replay_status = &"MISMATCH"
			return ActionResolution.rejected(ActionResolution.REPLAY_MISMATCH)

	var reject: ActionResolution = _prevalidate_action(action)
	if reject != null:
		return reject

	var result: ActionResolution = null
	match action.kind:
		"DISCARD":
			result = _apply_discard_action(action)
		"RIICHI":
			result = _apply_riichi_action(action)
		"TSUMO":
			result = _apply_tsumo_action(action)
		"RON":
			result = _apply_window_intent_action(action)
		"PASS":
			result = _apply_window_intent_action(action)
		"CHI", "PON":
			result = _apply_window_intent_action(action)
		"KAN":
			result = _apply_kan_action(action)
		"DECLARE_ABORTIVE_DRAW":
			result = _apply_abortive_draw_action(action)
		_:
			result = ActionResolution.rejected(ActionResolution.NOT_OFFERED)

	if result != null and result.accepted:
		_append_journal(action)
		if source == ActionSource.REPLAY:
			_consume_expected_replay()
	return result


func _impl_decision_context_for_seat(seat: int) -> DecisionContext:
	if state == null:
		return null
	if seat < 0 or seat > 3:
		return null
	_ensure_active_window()
	if _active_window == null:
		return null
	return _active_window.context_for_seat(seat)


## 权威 controller 内部只读借用；公开 facade 仍走 _impl_decision_context_for_seat 深拷贝。
func _decision_context_ref_for_seat(seat: int) -> DecisionContext:
	if state == null or seat < 0 or seat > 3:
		return null
	_ensure_active_window()
	if _active_window == null:
		return null
	return _active_window._context_ref_for_seat(seat)


func _impl_action_journal() -> Array:
	var out: Array = []
	for item in _action_journal:
		if item is Action:
			out.append(Action.from_dict((item as Action).to_dict()))
	return out


func _impl_load_replay_journal(raw: Variant) -> bool:
	if typeof(raw) != TYPE_ARRAY:
		return false
	var loaded: Array = []
	for item in raw:
		if not (item is Action):
			return false
		var cloned: Action = Action.from_dict((item as Action).to_dict())
		if cloned == null:
			return false
		loaded.append(cloned)
	_expected_replay = loaded
	_expected_replay_idx = 0
	_replay_status = &"LOADED"
	return true


func _impl_replay_status() -> StringName:
	return _replay_status


## 合法 DRAW 且未 settle 时调用唯一 _step_draw；正常摸牌与荒牌 settle 均 true。
func _impl_progress_server_draw() -> bool:
	if _settled:
		return false
	if state == null or engine == null:
		return false
	if state.phase != BattlePhase.Kind.DRAW:
		return false
	_step_draw()
	return true


func _get_practice_authority():
	# 仅本局 PBC meta；禁止 ModeModuleBundle 双权威跨 hand 错路由
	if has_meta("local_authority"):
		return get_meta("local_authority")
	return null


## 练习共享 Loopback room 契约：
## - 已是权威 session room → 保持
## - 生产默认 DEFAULT_ROOM_ID("local") → 转换为 session
## - 其它任意非空错误 room → 返回 null，由调用方稳定拒绝 WRONG_ROOM
func _align_action_room_for_practice_authority(action: Action, auth) -> Action:
	if action == null or auth == null:
		return action
	var rid := str(auth.get("_room_id"))
	if rid.is_empty():
		return null
	if action.room_id == rid:
		return action
	if action.room_id == DEFAULT_ROOM_ID:
		var d: Dictionary = action.to_dict()
		d["room_id"] = rid
		return Action.from_dict(d)
	return null


func _command_result_to_resolution(cr: CommandResult) -> ActionResolution:
	if cr == null:
		return ActionResolution.rejected(ActionResolution.INVALID_ACTION)
	if cr.status == "ACCEPTED":
		return ActionResolution.success([])
	var code := StringName(cr.error_code)
	var mapped: ActionResolution = ActionResolution.rejected(code)
	if mapped == null:
		return ActionResolution.rejected(ActionResolution.RULE_REJECTED)
	return mapped


func _prevalidate_action(action: Action) -> ActionResolution:
	if action.hand_seq != state.hand_seq:
		return ActionResolution.rejected(ActionResolution.WRONG_HAND)
	# DRAW/SETTLE 下任何业务行动均为 WRONG_PHASE（在 WRONG_DECISION 之前）
	if state.phase == BattlePhase.Kind.DRAW or state.phase == BattlePhase.Kind.SETTLE:
		return ActionResolution.rejected(ActionResolution.WRONG_PHASE)

	var ctx: DecisionContext = _decision_context_ref_for_seat(action.seat)
	if ctx == null:
		if action.kind in ["DISCARD", "RIICHI", "TSUMO", "DECLARE_ABORTIVE_DRAW"]:
			if action.seat != state.current_seat:
				return ActionResolution.rejected(ActionResolution.WRONG_SEAT)
		return ActionResolution.rejected(ActionResolution.WRONG_DECISION)
	if action.decision_id != ctx.decision_id:
		return ActionResolution.rejected(ActionResolution.WRONG_DECISION)
	if action.seat != ctx.seat:
		return ActionResolution.rejected(ActionResolution.WRONG_SEAT)
	if _active_window != null and _active_window.has_responded(action.seat):
		return ActionResolution.rejected(ActionResolution.ALREADY_RESPONDED)
	# entity / offered（NOT_OFFERED 优先于“kind 与 phase 不完全匹配”）
	if action.kind == "DISCARD" or action.kind == "RIICHI":
		var iid: int = int(action.payload.get("tile_instance_id", -1))
		var tile: Tile = state.seats[action.seat].hand.find_by_instance_id(iid)
		if tile == null:
			return ActionResolution.rejected(ActionResolution.ENTITY_NOT_FOUND)
	if not ctx.allows(action.kind, action.payload):
		return ActionResolution.rejected(ActionResolution.NOT_OFFERED)
	return null


func _apply_discard_action(action: Action) -> ActionResolution:
	var iid: int = int(action.payload.get("tile_instance_id", -1))
	var seat: Seat = state.seats[action.seat]
	var tile: Tile = seat.hand.find_by_instance_id(iid)
	if tile == null:
		return ActionResolution.rejected(ActionResolution.ENTITY_NOT_FOUND)
	var events_before: int = events.size()
	if not engine.discard(iid):
		return ActionResolution.rejected(ActionResolution.RULE_REJECTED)
	state.kuikae_restricted[action.seat] = []
	_last_discarded_tile = tile
	_last_discarder_seat = action.seat
	_invalidate_window()
	_emit(&"PLAYER_ACTION", action.seat, null, {
		"kind": "discard",
		"tile_id": tile.id,
		"tile_instance_id": tile.instance_id,
	})
	var applied_ev: BattleEvent = _append_action_applied(action)
	_emit(&"TILE_DISCARDED", action.seat, _wrap_tile(tile), {})
	return _finish_resolution(events_before, applied_ev)


func _apply_riichi_action(action: Action) -> ActionResolution:
	var iid: int = int(action.payload.get("tile_instance_id", -1))
	var seat: Seat = state.seats[action.seat]
	var tile: Tile = seat.hand.find_by_instance_id(iid)
	if tile == null:
		return ActionResolution.rejected(ActionResolution.ENTITY_NOT_FOUND)
	var events_before: int = events.size()
	if not engine.declare_riichi_and_discard(action.seat, iid):
		return ActionResolution.rejected(ActionResolution.RULE_REJECTED)
	state.scores[action.seat] -= RIICHI_STICK_COST
	state.kuikae_restricted[action.seat] = []
	_last_discarded_tile = tile
	_last_discarder_seat = action.seat
	_invalidate_window()
	_emit(&"PLAYER_ACTION", action.seat, null, {
		"kind": "discard",
		"tile_id": tile.id,
		"tile_instance_id": tile.instance_id,
	})
	_emit(&"TILE_DISCARDED", action.seat, _wrap_tile(tile), {})
	_emit(&"PLAYER_ACTION", action.seat, null, {"kind": "riichi"})
	_emit(&"RIICHI_DECLARED", action.seat, null, {})
	var applied_ev: BattleEvent = _append_action_applied(action)
	return _finish_resolution(events_before, applied_ev)


func _apply_tsumo_action(action: Action) -> ActionResolution:
	var seat: Seat = state.seats[action.seat]
	var drawn: Tile = seat.hand.find_by_instance_id(seat.last_drawn_instance_id)
	if drawn == null:
		return ActionResolution.rejected(ActionResolution.ENTITY_NOT_FOUND)
	var is_haitei: bool = (state.wall.live_wall_size() == 0)
	var win: Dictionary = _check_tsumo(drawn, is_haitei, seat.last_draw_is_rinshan)
	if not win.is_winning:
		return ActionResolution.rejected(ActionResolution.RULE_REJECTED)

	# 快照：领域失败时整段回滚（含 hook 副作用），成功时 ACTION_APPLIED 插到段首
	var events_before: int = events.size()
	var phase_before: int = int(state.phase)
	var seat_before: int = state.current_seat
	var settled_before: bool = _settled
	var last_event_before: StringName = _last_event_type
	var chain_id_before: int = int(scheduler._next_chain_id)

	_emit(&"TSUMO_DECLARED", action.seat, _wrap_tile(drawn), {})
	if not engine.apply_tsumo(action.seat, drawn.instance_id):
		while events.size() > events_before:
			events.pop_back()
		state.phase = phase_before
		state.current_seat = seat_before
		_settled = settled_before
		_last_event_type = last_event_before
		scheduler._next_chain_id = chain_id_before
		return ActionResolution.rejected(ActionResolution.RULE_REJECTED)

	_settle_tsumo(drawn, win.wp, win.yaku_list, is_haitei, seat.last_draw_is_rinshan)
	_invalidate_window()
	var applied_ev: BattleEvent = _make_action_applied_event(action)
	events.insert(events_before, applied_ev)
	return _finish_resolution(events_before, applied_ev)


func _apply_abortive_draw_action(action: Action) -> ActionResolution:
	var events_before: int = events.size()
	_emit(&"ABORTIVE_DRAW", action.seat, null, {
		"reason": str(action.payload.get("reason", "")),
	})
	_settled = true
	_invalidate_window()
	var applied_ev: BattleEvent = _append_action_applied(action)
	return _finish_resolution(events_before, applied_ev)


func _apply_kan_action(action: Action) -> ActionResolution:
	var p: Dictionary = action.payload
	var kan_kind: String = str(p.get("kan_kind", ""))
	if kan_kind == "MINKAN":
		return _apply_window_intent_action(action)
	# ANKAN / ADDED_KAN：TURN 窗
	var events_before: int = events.size()
	var actor: int = action.seat
	if kan_kind == "ANKAN":
		var ids: Array = p.get("tile_instance_ids", []) as Array
		if not engine.apply_ankan(actor, ids):
			return ActionResolution.rejected(ActionResolution.RULE_REJECTED)
		_invalidate_window()
		_emit(&"PLAYER_ACTION", actor, null, {"kind": "ankan", "tile_instance_ids": ids.duplicate()})
		var applied_a: BattleEvent = _append_action_applied(action)
		return _finish_resolution(events_before, applied_a)
	if kan_kind == "ADDED_KAN":
		# 两阶段：accepted 只登记 pending + ACTION_APPLIED + 开 ROB_KAN；domain 零升级
		var meld_id: int = int(p.get("meld_id", -1))
		var added_iid: int = int(p.get("added_tile_instance_id", -1))
		var seat_ak: Seat = state.seats[actor]
		var added_tile: Tile = seat_ak.hand.find_by_instance_id(added_iid)
		if added_tile == null:
			return ActionResolution.rejected(ActionResolution.ENTITY_NOT_FOUND)
		var target: Meld = seat_ak.melds.find_by_id(meld_id)
		if target == null or target.kind != Meld.Kind.PON:
			return ActionResolution.rejected(ActionResolution.RULE_REJECTED)
		if not ClaimValidator.can_added_kan(seat_ak.melds.all(), seat_ak.hand, added_tile.id):
			return ActionResolution.rejected(ActionResolution.RULE_REJECTED)
		_pending_added_kan = {
			"seat": actor,
			"meld_id": meld_id,
			"added_iid": added_iid,
		}
		_invalidate_window()
		_emit(&"PLAYER_ACTION", actor, null, {
			"kind": "added_kan_declare",
			"meld_id": meld_id,
			"added_tile_instance_id": added_iid,
		})
		var applied_b: BattleEvent = _append_action_applied(action)
		_open_rob_kan_window()
		return _finish_resolution(events_before, applied_b)
	return ActionResolution.rejected(ActionResolution.NOT_OFFERED)


func _apply_window_intent_action(action: Action) -> ActionResolution:
	_ensure_active_window()
	if _active_window == null:
		return ActionResolution.rejected(ActionResolution.WRONG_PHASE)
	# intent 先登记在当前权威窗；最后一个 intent 若领域事务失败，只回滚该 seat，
	# 其余已确认响应保持不变。避免每次响应复制整窗和全部历史 intent。
	var candidate: DecisionWindow = _active_window
	if candidate == null:
		return ActionResolution.rejected(ActionResolution.RULE_REJECTED)
	if not candidate.register_intent(action):
		return ActionResolution.rejected(ActionResolution.RULE_REJECTED)

	var events_before: int = events.size()
	if not candidate.is_complete():
		_active_window = candidate
		_commit_pass_furiten_if_needed(action, candidate)
		var applied_partial: BattleEvent = _append_action_applied(action)
		return _finish_resolution(events_before, applied_partial)

	# 收窗：用候选纯裁决 + 领域；失败则截断 events 并保留原窗（不登记最后 intent）
	var pending_before: Dictionary = _pending_added_kan.duplicate(true)
	var seat_before: int = state.current_seat
	var phase_before: int = int(state.phase)
	var settled_before: bool = _settled
	var last_event_before: StringName = _last_event_type
	var chain_id_before: int = int(scheduler._next_chain_id)
	var ok: bool = _resolve_completed_window(candidate)
	if not ok:
		while events.size() > events_before:
			events.pop_back()
		_pending_added_kan = pending_before
		state.current_seat = seat_before
		state.phase = phase_before
		_settled = settled_before
		_last_event_type = last_event_before
		scheduler._next_chain_id = chain_id_before
		candidate._rollback_intent(action.seat)
		_active_window = candidate
		return ActionResolution.rejected(ActionResolution.RULE_REJECTED)

	# 关窗后仍用候选查 offer；仅成功路径提交 PASS 振听
	_commit_pass_furiten_if_needed(action, candidate)
	# 领域成功后才建 ACTION_APPLIED，并插到本次事件段首（对外顺序：先 APPLIED 后领域）
	var applied_ev: BattleEvent = _make_action_applied_event(action)
	events.insert(events_before, applied_ev)
	return _finish_resolution(events_before, applied_ev)


func _commit_pass_furiten_if_needed(action: Action, win: DecisionWindow) -> void:
	# 仅在 intent 已确认接受后提交 PASS 振听，拒绝路径不得污染
	if action == null or action.kind != "PASS" or win == null:
		return
	var ctx_pass: DecisionContext = win._context_ref_for_seat(action.seat)
	if ctx_pass == null or not ctx_pass.has_kind("RON"):
		return
	var seat_p: Seat = state.seats[action.seat]
	seat_p.furiten.temporary = true
	if seat_p.riichi.declared:
		seat_p.furiten.permanent = true


func _resolve_completed_window(win: DecisionWindow) -> bool:
	if win == null:
		return false
	var intents: Array = win.intents()
	if win.kind == DecisionWindow.KIND_CLAIM:
		# 本地 remaining 循环：CANCELLED 去掉该 winner 再裁决，不得当 RULE_REJECTED
		var remaining: Array = intents.duplicate()
		while true:
			var outcome: Dictionary = BattleActionResolver.resolve(remaining, win.discarder_seat)
			match str(outcome.get("outcome", "")):
				BattleActionResolver.OUTCOME_SANCHA_HOURA:
					_invalidate_window()
					_emit(&"ABORTIVE_DRAW", -1, null, {"reason": "sancha_houra"})
					_settled = true
					return true
				BattleActionResolver.OUTCOME_WINNER:
					var winner: Action = outcome.get("winner", null) as Action
					if winner == null:
						_invalidate_window()
						engine.advance_to_next_seat()
						return true
					var domain_r: int = _execute_winning_claim(winner)
					if domain_r == DOMAIN_APPLIED:
						_invalidate_window()
						return true
					if domain_r == DOMAIN_FAILED:
						# 规则失败：保留事务窗，由上层 RULE_REJECTED + 回滚事件
						return false
					# DOMAIN_CANCELLED：移除该 intent，继续下一候选人；不重跑同 intent
					remaining = _remove_cancelled_winner_intent(remaining, winner)
					continue
				_:
					_invalidate_window()
					engine.advance_to_next_seat()
					return true
	if win.kind == DecisionWindow.KIND_ROB_KAN:
		# 与 CLAIM 同构：CANCELLED 去掉该 winner 再裁决，不得当 RULE_REJECTED
		var remaining_rk: Array = intents.duplicate()
		var kan_seat: int = int(_pending_added_kan.get("seat", win.discarder_seat))
		while true:
			var outcome_r: Dictionary = BattleActionResolver.resolve(remaining_rk, kan_seat)
			match str(outcome_r.get("outcome", "")):
				BattleActionResolver.OUTCOME_SANCHA_HOURA:
					_pending_added_kan = {}
					_invalidate_window()
					_emit(&"ABORTIVE_DRAW", -1, null, {"reason": "sancha_houra"})
					_settled = true
					return true
				BattleActionResolver.OUTCOME_WINNER:
					var w_ron: Action = outcome_r.get("winner", null) as Action
					if w_ron != null and w_ron.kind == "RON":
						var added_iid: int = int(_pending_added_kan.get("added_iid", -1))
						var added_tile: Tile = state.seats[kan_seat].hand.find_by_instance_id(added_iid)
						if added_tile == null:
							return false
						var domain_rk: int = _apply_ron_private(
							w_ron.seat, added_tile, kan_seat, false, true)
						if domain_rk == DOMAIN_APPLIED:
							_pending_added_kan = {}
							_invalidate_window()
							return true
						if domain_rk == DOMAIN_FAILED:
							return false
						# DOMAIN_CANCELLED：移除该 intent，继续下一 RON / ALL_PASS
						remaining_rk = _remove_cancelled_winner_intent(remaining_rk, w_ron)
						continue
					# 非 RON 赢家：按全 PASS 完成加杠
					if not _finalize_pending_added_kan_all_pass():
						return false
					_invalidate_window()
					return true
				_:
					# ALL_PASS（含 cancel 后无剩余 RON）
					if not _finalize_pending_added_kan_all_pass():
						return false
					_invalidate_window()
					return true
	_invalidate_window()
	return true


func _remove_cancelled_winner_intent(remaining: Array, winner: Action) -> Array:
	# 从本地 remaining 去掉已 CANCELLED 的 winner（按 seat+kind，只去一条）
	if winner == null:
		return remaining
	var out: Array = []
	var removed: bool = false
	for raw in remaining:
		var a: Action = raw as Action
		if a == null:
			continue
		if not removed and a.seat == winner.seat and a.kind == winner.kind:
			removed = true
			continue
		out.append(a)
	return out


func _finalize_pending_added_kan_all_pass() -> bool:
	if _pending_added_kan.is_empty():
		return true
	var actor: int = int(_pending_added_kan.get("seat", -1))
	var meld_id: int = int(_pending_added_kan.get("meld_id", -1))
	var added_iid: int = int(_pending_added_kan.get("added_iid", -1))
	if actor < 0:
		return false
	var seat_before: int = state.current_seat
	# 确保 current_seat 是杠家
	state.current_seat = actor
	if not engine.apply_added_kan(actor, meld_id, added_iid):
		state.current_seat = seat_before
		return false
	_pending_added_kan = {}
	_emit(&"PLAYER_ACTION", actor, null, {
		"kind": "added_kan",
		"meld_id": meld_id,
		"added_tile_instance_id": added_iid,
	})
	return true


func _execute_winning_claim(action: Action) -> int:
	var discarded: Tile = _get_last_discarded()
	var discarder: int = _get_last_discarder()
	if discarded == null:
		return DOMAIN_FAILED
	var actor: int = action.seat
	match action.kind:
		"RON":
			var is_houtei: bool = (state.wall.live_wall_size() == 0)
			return _apply_ron_private(actor, discarded, discarder, is_houtei, false)
		"PON":
			var comps: Array = action.payload.get("companion_tile_instance_ids", []) as Array
			if not engine.apply_pon(actor, discarded.instance_id, comps):
				return DOMAIN_FAILED
			state.kuikae_restricted[actor] = ClaimValidator.kuikae_restricted_ids(
				discarded.id, [], false)
			_emit(&"PLAYER_ACTION", actor, null, {
				"kind": "pon",
				"tile_instance_id": discarded.instance_id,
				"discarder_seat": discarder,
			})
			_emit(&"TILE_CLAIMED", actor, _wrap_tile(discarded), {
				"kind": "pon",
				"discarder_seat": discarder,
			})
			return DOMAIN_APPLIED
		"CHI":
			var comps_c: Array = action.payload.get("companion_tile_instance_ids", []) as Array
			if not engine.apply_chi(actor, discarded.instance_id, comps_c):
				return DOMAIN_FAILED
			_emit(&"PLAYER_ACTION", actor, null, {
				"kind": "chi",
				"tile_instance_id": discarded.instance_id,
				"discarder_seat": discarder,
			})
			_emit(&"TILE_CLAIMED", actor, _wrap_tile(discarded), {
				"kind": "chi",
				"discarder_seat": discarder,
			})
			return DOMAIN_APPLIED
		"KAN":
			var comps_k: Array = action.payload.get("companion_tile_instance_ids", []) as Array
			if not engine.apply_minkan(actor, discarded.instance_id, comps_k):
				return DOMAIN_FAILED
			_emit(&"PLAYER_ACTION", actor, null, {
				"kind": "minkan",
				"tile_instance_id": discarded.instance_id,
				"discarder_seat": discarder,
			})
			_emit(&"TILE_CLAIMED", actor, _wrap_tile(discarded), {
				"kind": "minkan",
				"discarder_seat": discarder,
			})
			return DOMAIN_APPLIED
	return DOMAIN_FAILED


func _make_action_applied_event(action: Action) -> BattleEvent:
	var rp: Dictionary = action.payload.duplicate(true)
	rp["seat"] = action.seat
	rp["hand_seq"] = action.hand_seq
	rp["decision_id"] = action.decision_id
	var extra := {
		"resolved_payload": rp,
	}
	return BattleEvent.make(&"ACTION_APPLIED", action.seat, null, extra)


func _append_action_applied(action: Action) -> BattleEvent:
	var ev: BattleEvent = _make_action_applied_event(action)
	events.append(ev)
	return ev



## 统一 accepted 事件段：无论领域动作内部何时确认成功，公开结果与 journal 中
## ACTION_APPLIED 都必须位于本次事件段首，供回放/网络层稳定消费。
func _finish_resolution(events_before: int, applied_ev: BattleEvent) -> ActionResolution:
	var applied_index: int = events.find(applied_ev, events_before)
	if applied_index < 0:
		return ActionResolution.rejected(ActionResolution.RULE_REJECTED)
	if applied_index != events_before:
		events.remove_at(applied_index)
		events.insert(events_before, applied_ev)
	var new_events: Array = []
	for i in range(events_before, events.size()):
		new_events.append(events[i])
	return ActionResolution.success(new_events)


func _append_journal(action: Action) -> void:
	var cloned: Action = Action.from_dict(action.to_dict())
	if cloned != null:
		_action_journal.append(cloned)


func _peek_expected_replay() -> Action:
	if _expected_replay_idx >= _expected_replay.size():
		return null
	return _expected_replay[_expected_replay_idx] as Action


func _consume_expected_replay() -> void:
	_expected_replay_idx += 1
	if _expected_replay_idx >= _expected_replay.size():
		_replay_status = &"COMPLETED"
	else:
		_replay_status = &"RUNNING"


func _finalize_replay_lifecycle_status() -> void:
	if _replay_status == &"IDLE" or _replay_status == &"MISMATCH":
		return
	if _replay_status == &"COMPLETED":
		return
	if _expected_replay_idx < _expected_replay.size():
		_replay_status = &"UNCONSUMED"


func _invalidate_window() -> void:
	_active_window = null
	_active_window_phase = -1


func _ensure_active_window() -> void:
	if state == null:
		_active_window = null
		return
	if not _pending_added_kan.is_empty():
		if _active_window != null and _active_window.kind == DecisionWindow.KIND_ROB_KAN \
				and _active_window.hand_seq == state.hand_seq \
				and int(_pending_added_kan.get("seat", -2)) == _active_window.discarder_seat:
			return
		_open_rob_kan_window()
		return
	if state.phase == BattlePhase.Kind.DISCARD:
		if _active_window != null and _active_window.kind == DecisionWindow.KIND_TURN \
				and _active_window.subject_seat == state.current_seat \
				and _active_window.hand_seq == state.hand_seq \
				and _active_window_phase == state.phase:
			return
		_open_turn_window()
	elif state.phase == BattlePhase.Kind.CLAIM:
		if _active_window != null and _active_window.kind == DecisionWindow.KIND_CLAIM \
				and _active_window.hand_seq == state.hand_seq \
				and _active_window_phase == state.phase \
				and _active_window.discarder_seat == _last_discarder_seat:
			return
		_open_claim_window()
	else:
		_active_window = null
		_active_window_phase = -1


func _open_turn_window() -> void:
	var seat_id: int = state.current_seat
	var seat: Seat = state.seats[seat_id]
	var did: String = _make_decision_id("TURN", seat_id)
	var subject_tile: int = seat.last_drawn_instance_id
	var win: DecisionWindow = DecisionWindow.make(
		DecisionWindow.KIND_TURN, state.hand_seq, did, seat_id, subject_tile, -1
	)
	if win == null:
		_active_window = null
		return
	var actions: Array = _build_turn_offers(seat)
	var ctx: DecisionContext = DecisionContext.make(
		DecisionContext.KIND_TURN, state.hand_seq, did, seat_id, actions, -1, -1
	)
	if ctx == null:
		_active_window = null
		return
	win.add_context(ctx)
	_active_window = win
	_active_window_phase = state.phase


func _open_claim_window() -> void:
	var discarded: Tile = _get_last_discarded()
	var discarder: int = _get_last_discarder()
	if discarded == null or discarder < 0:
		_active_window = null
		return
	var did: String = _make_decision_id("CLAIM", discarder)
	var win: DecisionWindow = DecisionWindow.make(
		DecisionWindow.KIND_CLAIM, state.hand_seq, did, discarder,
		discarded.instance_id, discarder
	)
	if win == null:
		_active_window = null
		return
	for s in range(4):
		if s == discarder:
			continue
		var offers: Array = _build_claim_offers(s, discarded, discarder)
		var ctx: DecisionContext = DecisionContext.make(
			DecisionContext.KIND_CLAIM, state.hand_seq, did, s, offers,
			discarded.instance_id, discarder
		)
		if ctx != null:
			win.add_context(ctx)
	_active_window = win
	_active_window_phase = state.phase


func _open_rob_kan_window() -> void:
	if _pending_added_kan.is_empty():
		_active_window = null
		return
	var kan_seat: int = int(_pending_added_kan.get("seat", -1))
	var added_iid: int = int(_pending_added_kan.get("added_iid", -1))
	var added_tile: Tile = state.seats[kan_seat].hand.find_by_instance_id(added_iid)
	if added_tile == null or kan_seat < 0:
		_active_window = null
		return
	var did: String = _make_decision_id("ROB_KAN", kan_seat)
	var win: DecisionWindow = DecisionWindow.make(
		DecisionWindow.KIND_ROB_KAN, state.hand_seq, did, kan_seat, added_iid, kan_seat
	)
	if win == null:
		_active_window = null
		return
	for s in range(4):
		if s == kan_seat:
			continue
		var offers: Array = _build_rob_kan_offers(s, added_tile)
		var ctx: DecisionContext = DecisionContext.make(
			DecisionContext.KIND_ROB_KAN, state.hand_seq, did, s, offers,
			added_iid, kan_seat
		)
		if ctx != null:
			win.add_context(ctx)
	_active_window = win
	_active_window_phase = state.phase


func _build_rob_kan_offers(seat_id: int, kan_tile: Tile) -> Array:
	var offers: Array = []
	var seat: Seat = state.seats[seat_id]
	if ClaimValidator.can_ron(seat.hand, seat.melds.all(), kan_tile, seat.furiten):
		var ron_check: Dictionary = _check_ron(kan_tile, seat_id, false, true)
		if bool(ron_check.get("is_winning", false)):
			offers.append({"kind": "RON", "payload_options": [{}]})
	offers.append({"kind": "PASS", "payload_options": [{}]})
	return offers


func _build_turn_offers(seat: Seat) -> Array:
	var offers: Array = []
	var disc_opts: Array = []
	# 立直锁牌必须由权威 offer 保证，不能只依赖本地 UI/AI 自动摸切。
	if seat.riichi.declared:
		var drawn: Tile = seat.hand.find_by_instance_id(seat.last_drawn_instance_id)
		if drawn != null:
			disc_opts.append({"tile_instance_id": drawn.instance_id})
	else:
		for t in seat.hand.tiles():
			if t == null:
				continue
			if not state.kuikae_restricted[seat.seat_id].is_empty():
				if state.kuikae_restricted[seat.seat_id].has(t.id):
					continue
			disc_opts.append({"tile_instance_id": t.instance_id})
		if disc_opts.is_empty():
			for t in seat.hand.tiles():
				if t != null:
					disc_opts.append({"tile_instance_id": t.instance_id})
	if not disc_opts.is_empty():
		offers.append({"kind": "DISCARD", "payload_options": disc_opts})
	# RIICHI：批量 options（门清/点数/墙/听牌门槛在 validator 内）
	var riichi_opts: Array = RiichiValidator.riichi_discard_options(
		seat, state.wall.live_wall_size())
	if not riichi_opts.is_empty():
		offers.append({"kind": "RIICHI", "payload_options": riichi_opts})
	# TSUMO：实际可和
	if seat.last_drawn_instance_id != Tile.INVALID_INSTANCE_ID:
		var drawn: Tile = seat.hand.find_by_instance_id(seat.last_drawn_instance_id)
		if drawn != null:
			var is_haitei: bool = (state.wall.live_wall_size() == 0)
			var first_draw: bool = state.first_round_active \
				and seat.river.is_empty()
			var is_tenhou: bool = first_draw and seat.seat_id == state.dealer_seat
			var is_chiihou: bool = first_draw and seat.seat_id != state.dealer_seat
			var win: Dictionary = _check_tsumo(
				drawn, is_haitei, seat.last_draw_is_rinshan, is_tenhou, is_chiihou)
			if bool(win.get("is_winning", false)):
				offers.append({"kind": "TSUMO", "payload_options": [{}]})
	# ANKAN / ADDED_KAN
	var kan_opts: Array = []
	if not seat.riichi.declared:
		for tid in ClaimValidator.ankan_candidates(seat.hand):
			var iids: Array = _hand_iids_of_type(seat.hand, tid)
			if iids.size() >= 4:
				kan_opts.append({
					"kan_kind": "ANKAN",
					"tile_instance_ids": iids.slice(0, 4),
				})
		for m in seat.melds.all():
			if m.kind != Meld.Kind.PON or m.tiles.is_empty():
				continue
			var tid_p: int = m.tiles[0].id
			if not ClaimValidator.can_added_kan(seat.melds.all(), seat.hand, tid_p):
				continue
			for t in seat.hand.tiles():
				if t.id != tid_p:
					continue
				kan_opts.append({
					"kan_kind": "ADDED_KAN",
					"meld_id": m.meld_id,
					"added_tile_instance_id": t.instance_id,
				})
				break
	if not kan_opts.is_empty():
		offers.append({"kind": "KAN", "payload_options": kan_opts})
	# 九种九牌
	if state.first_round_active and state.turn_count == 0:
		if AbortiveDraw.is_kyuusyu_kyuuhai(seat.hand.to_id_array()):
			offers.append({
				"kind": "DECLARE_ABORTIVE_DRAW",
				"payload_options": [{"reason": "KYUUSYU_KYUUHAI"}],
			})
	if offers.is_empty() and not seat.riichi.declared and not seat.hand.tiles().is_empty():
		offers.append({
			"kind": "DISCARD",
			"payload_options": [{"tile_instance_id": seat.hand.tiles()[0].instance_id}],
		})
	return offers


func _build_claim_offers(seat_id: int, discarded: Tile, discarder: int) -> Array:
	var seat: Seat = state.seats[seat_id]
	var offers: Array = []
	# CHI（仅下家）
	if ClaimValidator.can_chi(seat_id, discarder, seat.hand, discarded.id):
		var chi_opts: Array = []
		for combo in ClaimValidator.chi_companion_options(seat.hand, discarded.id):
			if not (combo is Array) or (combo as Array).size() != 2:
				continue
			for iids in _match_type_iid_combinations(seat.hand, combo as Array):
				chi_opts.append({"companion_tile_instance_ids": iids})
		if not chi_opts.is_empty():
			offers.append({"kind": "CHI", "payload_options": chi_opts})
	if ClaimValidator.can_pon(seat_id, discarder, seat.hand, discarded.id):
		var pon_opts: Array = []
		for pon_iids in _match_type_iid_combinations(
			seat.hand, [discarded.id, discarded.id]
		):
			pon_opts.append({"companion_tile_instance_ids": pon_iids})
		if not pon_opts.is_empty():
			offers.append({"kind": "PON", "payload_options": pon_opts})
	if ClaimValidator.can_minkan(seat_id, discarder, seat.hand, discarded.id):
		var kan_iids: Array = _match_type_iids(seat.hand, [discarded.id, discarded.id, discarded.id])
		if kan_iids.size() == 3:
			offers.append({"kind": "KAN", "payload_options": [
				{"kan_kind": "MINKAN", "companion_tile_instance_ids": kan_iids},
			]})
	if ClaimValidator.can_ron(seat.hand, seat.melds.all(), discarded, seat.furiten):
		var ron_check: Dictionary = _check_ron(discarded, seat_id, state.wall.live_wall_size() == 0)
		if ron_check.is_winning:
			offers.append({"kind": "RON", "payload_options": [{}]})
	offers.append({"kind": "PASS", "payload_options": [{}]})
	return offers

func _make_decision_id(tag: String, seat_hint: int) -> String:
	_window_seq += 1
	return _deterministic_uuid(_battle_seed, state.hand_seq, _window_seq, "%s:%d" % [tag, seat_hint])


func _deterministic_uuid(seed: int, hand_seq: int, seq: int, tag: String) -> String:
	var h1: int = abs(int(hash("%s|%d|%d|%d" % [tag, seed, hand_seq, seq])))
	var h2: int = abs(int(hash("%d|%s|%d|%d" % [seq, tag, hand_seq, seed])))
	var h3: int = abs(int(hash("%d|%d|%s|x" % [hand_seq, seed, tag])))
	var h4: int = abs(int(hash("%d|%d|%d|%s|y" % [seed, seq, hand_seq, tag])))
	var time_low: int = h1 & 0xffffffff
	var time_mid: int = h2 & 0xffff
	var time_hi: int = 0x4000 | ((h2 >> 16) & 0x0fff)
	var clock: int = 0x8000 | (h3 & 0x3fff)
	var node: int = ((h3 << 16) ^ h4) & 0xffffffffffff
	return "%08x-%04x-%04x-%04x-%012x" % [time_low, time_mid, time_hi, clock, node]


func _next_action_command_id() -> String:
	_action_cmd_seq += 1
	return "%s%012d" % [_ACTION_CMD_UUID_PREFIX, _action_cmd_seq]


## E5-06 / #254：ITEM_USE 薄封装。复用 _next_action_command_id / apply_action → LocalLoopback。
## 不扩权威语义；无 local_authority 时走既有 fail-closed 路径。
func submit_item_use(item_instance_id: String, seat: int = 0) -> ActionResolution:
	var iid := String(item_instance_id).strip_edges()
	if iid.is_empty():
		return ActionResolution.rejected(ActionResolution.INVALID_ACTION)
	if seat < 0 or seat > 3:
		return ActionResolution.rejected(ActionResolution.WRONG_SEAT)
	var ctx: DecisionContext = decision_context_for_seat(seat)
	var decision_id := "00000000-0000-4000-8000-000000000001"
	var hand_seq := 0
	if state != null:
		hand_seq = int(state.hand_seq)
	if ctx != null:
		decision_id = str(ctx.decision_id)
		hand_seq = int(ctx.hand_seq)
	var cmd: String = _next_action_command_id()
	var action: Action = Action.item_use(
		seat, iid, DEFAULT_ROOM_ID, cmd, decision_id, hand_seq, _action_cmd_seq
	)
	return apply_action(action, ActionSource.HUMAN)


func _build_ai_discard_or_riichi_action(seat: Seat, actor: int) -> Action:
	var to_discard: Tile = _get_discard_decision(seat, actor)
	if to_discard == null:
		return null
	return _build_action_for_tile(seat, actor, to_discard)


func _build_action_for_tile(seat: Seat, actor: int, to_discard: Tile) -> Action:
	if to_discard == null:
		return null
	var ctx: DecisionContext = _decision_context_ref_for_seat(actor)
	if ctx == null:
		return null
	# TURN offer 已完成门清、点数、牌墙与弃后听牌判定；AI 只在该物理牌
	# 确实被权威窗口允许立直时构造弃后 13 张视图，避免重复跑两次听牌枚举。
	var should_riichi: bool = ctx.allows(
		"RIICHI", {"tile_instance_id": to_discard.instance_id})
	if should_riichi:
		should_riichi = ai != null and ai.has_method("decide_riichi")
	if should_riichi:
		var sim := seat.hand.clone()
		if sim.take_by_instance_id(to_discard.instance_id) != null:
			# HeuristicAi.decide_riichi 契约是弃后 13 张听牌手。
			# 独立 Seat 规则视图：不改 live seat.hand。
			var seat_after := Seat.new(seat.seat_id, seat.seat_wind, seat.points)
			seat_after.hand = sim
			seat_after.melds = seat.melds.clone()
			seat_after.riichi = seat.riichi
			should_riichi = bool(ai.decide_riichi(
				seat_after, state.wall.live_wall_size()))
		else:
			should_riichi = false
	var cmd: String = _next_action_command_id()
	if should_riichi:
		return Action.riichi(
			actor, to_discard.instance_id, DEFAULT_ROOM_ID, cmd,
			ctx.decision_id, state.hand_seq, _action_cmd_seq
		)
	return Action.discard(
		actor, to_discard.instance_id, DEFAULT_ROOM_ID, cmd,
		ctx.decision_id, state.hand_seq, _action_cmd_seq
	)


func _hand_iids_of_type(hand: Hand, tile_type_id: int) -> Array:
	var out: Array = []
	for t in hand.tiles():
		if t.id == tile_type_id:
			out.append(t.instance_id)
	return out


func _match_type_iids(hand: Hand, type_ids: Array) -> Array:
	var remaining: Array = type_ids.duplicate()
	var iids: Array = []
	for t in hand.tiles():
		for j in range(remaining.size()):
			if int(remaining[j]) == t.id:
				iids.append(t.instance_id)
				remaining.remove_at(j)
				break
	if not remaining.is_empty():
		return []
	return iids


func _match_type_iid_combinations(hand: Hand, type_ids: Array) -> Array:
	if type_ids.is_empty():
		return []
	var partials: Array = [[]]
	for raw_type_id in type_ids:
		var expanded_partials: Array = []
		for partial in partials:
			for tile in hand.tiles():
				if tile == null or tile.id != int(raw_type_id):
					continue
				if (partial as Array).has(tile.instance_id):
					continue
				var expanded: Array = (partial as Array).duplicate()
				expanded.append(tile.instance_id)
				expanded_partials.append(expanded)
		partials = expanded_partials
		if partials.is_empty():
			return []

	# 同牌型会产生 [a,b] / [b,a] 排列；协议把实体数组视为无序集合，
	# 此处按排序后的 key 去重，同时保留手牌顺序生成的首个稳定组合。
	var unique: Array = []
	var seen: Dictionary = {}
	for partial in partials:
		var canonical: Array = (partial as Array).duplicate()
		canonical.sort()
		var key: String = JSON.stringify(canonical)
		if seen.has(key):
			continue
		seen[key] = true
		unique.append((partial as Array).duplicate())
	return unique
