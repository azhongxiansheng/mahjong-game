class_name PlayableBattleController extends BattleController

# 麻将王 — 战斗节点真实可玩（plan Step 5）。
#
# 继承 BattleController，覆写 4 个决策钩子让 seat 0 的决策走玩家点击：
#   _get_discard_decision     — 玩家点手牌切的哪张
#   _get_riichi_decision      — 玩家是否立直（discard 后弹按钮）
#   _should_accept_ron        — 玩家是否接受这次荣和
#   _should_accept_tsumo      — 玩家是否接受这次自摸
#
# 玩家"自摸 vs 切牌"流程：
#   _step_draw_async 摸到牌 → _check_tsumo 命中 → _should_accept_tsumo 弹按钮
#   ├─ 玩家点"自摸" → return true → BC 调 _settle_tsumo 结束本局
#   └─ 玩家点切牌  → 把切牌选择缓存到 _pending_discard_choice，return false
#                    → BC 进入 _step_discard_async → _get_discard_decision
#                    → 直接读缓存返出，不再让玩家点 2 次
#
# AI seat 直接走父类同步路径（默认 ai.decide_discard 等）+ 思考延时。

const PLAYER_SEAT: int = 0

var _action_panel: PlayerActionPanel = null
var _seat_panel_player: SeatPanel = null
var _ai_think_delay_sec: float = 0.4
var _scene_tree: SceneTree = null  # 用于 await create_timer

# 自摸窗口里玩家选了切牌时缓存的选择，给下一步 _get_discard_decision 用。
# 用 -1 表示"无缓存"，因为 tile_id 0 是合法的（W1）。
var _pending_discard_tile_id: int = -1

func _init(seed: int = 0, dealer_seat: int = 0, use_heuristic_ai: bool = false, round_wind: int = TileId.E) -> void:
	super(seed, dealer_seat, use_heuristic_ai, round_wind)

# 上层（PlayableTable）注入 UI 引用。必须在 run_to_end_async 之前调。
func bind_ui(action_panel: PlayerActionPanel, seat_panel_player: SeatPanel, tree: SceneTree) -> void:
	_action_panel = action_panel
	_seat_panel_player = seat_panel_player
	_scene_tree = tree

func set_ai_think_delay(seconds: float) -> void:
	_ai_think_delay_sec = max(0.0, seconds)

# ---- 覆写 _step_discard_async（GDScript 4 quirk workaround） ----
#
# BC 父类 _step_discard_async 末尾调 `await _try_player_claim_async(...)`，
# 但直接 await self.method() 在 GDScript 4 + method override 链路上 dispatch
# 不可靠（首次正确分派到子类，后续静默 cache 父类 — 见 commit f86b375 debug log）。
# Workaround：子类覆写整个 _step_discard_async，复制父类逻辑，最末尾的 claim 钩子
# 调用在子类内部完成 — 子类 self.method() dispatch 一直正确。
func _step_discard_async() -> void:
	var seat: Seat = state.seats[state.current_seat]
	var actor: int = state.current_seat
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
	_emit(&"PLAYER_ACTION", actor, null, {"kind": "discard", "tile_id": to_discard.id})
	var ok: bool = engine.discard(to_discard.id)
	if not ok:
		_settled = true
		return
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
	# 鸣牌响应（v1 仅 ron）— 父类版本，子类不重写 ron 决策（_should_accept_ron 钩子里覆写）
	if not _settled:
		await _try_ron_async(to_discard, actor)
	# 玩家鸣牌窗口（吃/碰/杠）— 子类调用子类版本（dispatch 正常）
	if not _settled:
		await _try_player_claim_async(to_discard, actor)

# ---- 钩子覆写 ----

func _get_discard_decision(seat: Seat, actor: int) -> Tile:
	if actor != PLAYER_SEAT or _action_panel == null or _seat_panel_player == null:
		await _ai_think_pause()
		return ai.decide_discard(seat)
	# 立直后强制 tsumogiri（弃刚摸的牌；spec 2026-05-08 bug 1 fix）。
	# 注意：本判断在自摸窗口（_should_accept_tsumo）之后执行；若玩家已点了
	# 自摸，不会进到这里。落到这里说明玩家选了"切牌"或者根本没自摸窗口。
	# 立直锁定后只能 tsumogiri，跳过 UI 直接返出刚摸的牌。
	if should_auto_tsumogiri(seat):
		var auto_discard: Tile = _find_tile_by_id(seat, seat.last_drawn_tile_id)
		if auto_discard != null:
			_pending_discard_tile_id = -1  # 清缓存防意外复用
			_action_panel.enter_idle("立直中（自动切刚摸的牌）")
			await _ai_think_pause()  # 给玩家视觉延迟看清楚摸了什么
			return auto_discard
		# 异常 fallback：last_drawn 找不到则落到正常流程（不应到达）
	# 缓存命中：玩家在 _should_accept_tsumo 阶段已经点了切牌，直接用
	if _pending_discard_tile_id >= 0:
		var picked_cached: Tile = _find_tile_by_id(seat, _pending_discard_tile_id)
		_pending_discard_tile_id = -1
		if picked_cached != null:
			return picked_cached
		# 缓存的 tile_id 不在手牌（异常）— 落到正常流程让玩家再选
	# 正常流程：玩家点切（自摸已处理过或本次摸的牌不构成自摸）
	_action_panel.enter_waiting_discard(false)
	_seat_panel_player.set_hand_clickable(true)
	while true:
		var choice: Dictionary = await _action_panel.player_action_chosen
		var action: String = String(choice.get("action", ""))
		if action == "discard":
			var tid: int = int(choice.get("tile_id", -1))
			var picked: Tile = _find_tile_by_id(seat, tid)
			if picked == null:
				continue
			_seat_panel_player.set_hand_clickable(false)
			_action_panel.enter_idle("AI 出牌中…")
			return picked
		# 其它 action 在此状态被忽略，继续等
	return null  # unreachable

func _get_riichi_decision(actor: int) -> bool:
	if actor != PLAYER_SEAT or _action_panel == null:
		await _ai_think_pause()
		return super(actor)
	# 玩家路径：先看是否真的可立直，否则直接返 false
	var seat: Seat = state.seats[actor]
	if not RiichiValidator.can_declare_riichi(seat, state.wall.live_wall_size()):
		return false
	_action_panel.enter_waiting_riichi_confirm()
	while true:
		var choice: Dictionary = await _action_panel.player_action_chosen
		var action: String = String(choice.get("action", ""))
		match action:
			"riichi_yes":
				_action_panel.enter_idle("立直！")
				return true
			"riichi_no":
				_action_panel.enter_idle("AI 出牌中…")
				return false
	return false

func _should_accept_ron(candidate: int, _discarded: Tile, discarder: int, _ron_check: Dictionary, _is_houtei: bool) -> bool:
	if candidate != PLAYER_SEAT or _action_panel == null:
		return true
	# v1：仅 ron 单选；吃/碰/杠 在 _try_player_claim_async 二段窗口处理
	_action_panel.enter_waiting_claim(true, false, false, false, discarder)
	while true:
		var choice: Dictionary = await _action_panel.player_action_chosen
		var action: String = String(choice.get("action", ""))
		if action == "ron":
			_action_panel.enter_idle("荣和！")
			return true
		elif action == "skip":
			_action_panel.enter_idle("AI 出牌中…")
			return false
	return true  # unreachable

# v1 玩家鸣牌（吃/碰/杠）窗口 — 在 _try_ron_async 之后调用，玩家可吃/碰/杠
# 时弹按钮，玩家选 → 直接调 engine.apply_*；玩家 skip → BC 主循环 advance。
# 注意：玩家选 chi 时 v1 自动选第一组合法 companion（不让玩家手选）。
func _try_player_claim_async(discarded: Tile, discarder: int) -> void:
	if _action_panel == null or _seat_panel_player == null:
		return
	if discarder == PLAYER_SEAT:
		return  # 自己刚切的，不可鸣自己
	var hand: Hand = state.seats[PLAYER_SEAT].hand
	var can_chi := ClaimValidator.can_chi(PLAYER_SEAT, discarder, hand, discarded.id)
	var can_pon := ClaimValidator.can_pon(PLAYER_SEAT, discarder, hand, discarded.id)
	var can_minkan := ClaimValidator.can_minkan(PLAYER_SEAT, discarder, hand, discarded.id)
	if not (can_chi or can_pon or can_minkan):
		return
	_action_panel.enter_waiting_claim(false, can_chi, can_pon, can_minkan, discarder)
	while true:
		var choice: Dictionary = await _action_panel.player_action_chosen
		var action: String = String(choice.get("action", ""))
		match action:
			"pon":
				if engine.apply_pon(PLAYER_SEAT, discarded):
					_emit(&"PLAYER_ACTION", PLAYER_SEAT, null, {"kind": "pon", "tile_id": discarded.id})
					_action_panel.enter_idle("碰！")
				return
			"minkan":
				if engine.apply_minkan(PLAYER_SEAT, discarded):
					_emit(&"PLAYER_ACTION", PLAYER_SEAT, null, {"kind": "minkan", "tile_id": discarded.id})
					_action_panel.enter_idle("杠！")
				return
			"chi":
				# v1 自动选第一个合法 companion 组合
				var companions: Array = _pick_chi_companions(hand, discarded.id)
				if companions.size() == 2 and engine.apply_chi(PLAYER_SEAT, discarded, companions):
					_emit(&"PLAYER_ACTION", PLAYER_SEAT, null, {"kind": "chi", "tile_id": discarded.id})
					_action_panel.enter_idle("吃！")
				return
			"skip", "":
				_action_panel.enter_idle("AI 出牌中…")
				return
			_:
				continue

# 立直后是否强制 tsumogiri（弃刚摸的牌）。spec 2026-05-08 bug 1 fix。
# 日麻规则：立直锁定手牌；玩家不能选切别的牌。条件：
#   (a) seat.riichi.declared = true
#   (b) seat.last_drawn_tile_id >= 0（处于 post-draw / post-rinshan 状态）
# 提取为静态 predicate 方便 GUT 单测（不依赖 UI / async）。
static func should_auto_tsumogiri(seat: Seat) -> bool:
	if not seat.riichi.declared:
		return false
	return seat.last_drawn_tile_id >= 0

# 选第一组合法 chi companion（[d-2,d-1] / [d-1,d+1] / [d+1,d+2]）。
# v1 自动取首组；当玩家 companion 选择 UI 落地后改成传 picked 参数。
# 算法委托给 ClaimValidator.chi_companion_options，避免重复实现。
static func _pick_chi_companions(hand: Hand, discarded_id: int) -> Array:
	var options: Array = ClaimValidator.chi_companion_options(hand, discarded_id)
	if options.is_empty():
		return []
	return options[0]

func _should_accept_tsumo(actor: int, _drawn: Tile, _win_check: Dictionary) -> bool:
	if actor != PLAYER_SEAT or _action_panel == null or _seat_panel_player == null:
		return true
	# 玩家路径：可自摸 + 可切牌都开放，等玩家选
	_action_panel.enter_waiting_discard(true)
	_seat_panel_player.set_hand_clickable(true)
	while true:
		var choice: Dictionary = await _action_panel.player_action_chosen
		var action: String = String(choice.get("action", ""))
		if action == "tsumo":
			_seat_panel_player.set_hand_clickable(false)
			_action_panel.enter_idle("自摸！")
			return true
		elif action == "discard":
			var tid: int = int(choice.get("tile_id", -1))
			# 缓存切牌选择，让 _step_discard_async / _get_discard_decision 直接用
			_pending_discard_tile_id = tid
			_seat_panel_player.set_hand_clickable(false)
			_action_panel.enter_idle("出牌中…")
			return false
		# 其它 action 忽略
	return true  # unreachable

# ---- helpers ----

func _ai_think_pause() -> void:
	if _scene_tree == null or _ai_think_delay_sec <= 0.0:
		return
	await _scene_tree.create_timer(_ai_think_delay_sec).timeout

func _find_tile_by_id(seat: Seat, tile_id: int) -> Tile:
	for t in seat.hand._tiles:
		if t.id == tile_id:
			return t
	return null
