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

# ---- 钩子覆写 ----

func _get_discard_decision(seat: Seat, actor: int) -> Tile:
	if actor != PLAYER_SEAT or _action_panel == null or _seat_panel_player == null:
		await _ai_think_pause()
		return ai.decide_discard(seat)
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
	_action_panel.enter_waiting_claim(true, discarder)
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
