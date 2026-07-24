class_name PlayableBattleController extends BattleController

# 麻将王 — 战斗节点真实可玩。
# async 决策：context → Action → apply_action。无 apply_ron / consumable / tile_id fallback。

const PLAYER_SEAT: int = 0

var _decision_port: PlayerDecisionPort = null
var _ai_think_delay_sec: float = 0.4
var _scene_tree: SceneTree = null


func _init(
	seed: int = 0,
	dealer_seat: int = 0,
	use_heuristic_ai: bool = false,
	round_wind: int = TileId.E,
	hand_seq: int = 0
) -> void:
	super(seed, dealer_seat, use_heuristic_ai, round_wind, hand_seq)


func bind_decision_port(port: PlayerDecisionPort, tree: SceneTree = null) -> void:
	_decision_port = port
	_scene_tree = tree


func set_ai_think_delay(seconds: float) -> void:
	_ai_think_delay_sec = max(0.0, seconds)


func _is_human_turn_source() -> bool:
	return _decision_port != null


func _select_turn_action_async(seat: Seat, actor: int) -> Action:
	if actor != PLAYER_SEAT or _decision_port == null:
		await _ai_think_pause()
		return _select_ai_turn_action(seat, actor)
	return await _player_select_turn_action(seat, actor)


func _select_claim_action_async(candidate: int, discarded: Tile, discarder: int) -> Action:
	if candidate != PLAYER_SEAT or _decision_port == null:
		await _ai_think_pause()
		return _build_ai_claim_action(candidate, discarded, discarder)
	return await _player_select_claim_action(candidate, discarded, discarder)


func _select_rob_kan_action_async(candidate: int) -> Action:
	if candidate != PLAYER_SEAT or _decision_port == null:
		await _ai_think_pause()
		return _build_ai_rob_kan_action(candidate)
	return await _player_select_rob_kan_action(candidate)


func _player_select_turn_action(seat: Seat, actor: int) -> Action:
	var ctx: DecisionContext = decision_context_for_seat(actor)
	if ctx == null:
		return null
	# 立直锁牌：只能 tsumogiri / TSUMO / 合法 KAN
	if should_auto_tsumogiri(seat):
		if ctx.has_kind("TSUMO"):
			# 仍允许玩家选 TSUMO
			pass
		elif ctx.has_kind("DISCARD"):
			var forced_iid: int = seat.last_drawn_instance_id
			if ctx.allows("DISCARD", {"tile_instance_id": forced_iid}):
				_decision_port.present(&"idle", {"text": "立直中（自动切刚摸的牌）"})
				await _ai_think_pause()
				return Action.discard(
					actor, forced_iid, DEFAULT_ROOM_ID, _next_action_command_id(),
					ctx.decision_id, state.hand_seq, _action_cmd_seq
				)

	var validation_message: String = ""
	while true:
		var choice: Dictionary = await _decision_port.request(&"discard", {
			"can_tsumo": ctx.has_kind("TSUMO"),
			"can_ankan": _ctx_has_kan_kind(ctx, "ANKAN"),
			"can_added_kan": _ctx_has_kan_kind(ctx, "ADDED_KAN"),
			"can_kyuusyu": ctx.has_kind("DECLARE_ABORTIVE_DRAW"),
			"has_consumable": false,
			"message": validation_message,
		})
		validation_message = ""
		var action: String = String(choice.get("action", ""))
		if action == "tsumo" and ctx.has_kind("TSUMO"):
			_decision_port.present(&"idle", {"text": "自摸！"})
			return Action.tsumo(
				actor, DEFAULT_ROOM_ID, _next_action_command_id(),
				ctx.decision_id, state.hand_seq, _action_cmd_seq
			)
		if action == "kyuusyu_yes" and ctx.has_kind("DECLARE_ABORTIVE_DRAW"):
			_decision_port.present(&"idle", {"text": "九種九牌！本局流局"})
			return Action.declare_abortive_draw(
				actor, "KYUUSYU_KYUUHAI", DEFAULT_ROOM_ID, _next_action_command_id(),
				ctx.decision_id, state.hand_seq, _action_cmd_seq
			)
		if action == "ankan" and _ctx_has_kan_kind(ctx, "ANKAN"):
			var pay_a: Dictionary = _first_kan_payload(ctx, "ANKAN")
			if not pay_a.is_empty():
				return Action.kan(
					actor, pay_a, DEFAULT_ROOM_ID, _next_action_command_id(),
					ctx.decision_id, state.hand_seq, _action_cmd_seq
				)
			continue
		if action == "added_kan" and _ctx_has_kan_kind(ctx, "ADDED_KAN"):
			var pay_b: Dictionary = _first_kan_payload(ctx, "ADDED_KAN")
			if not pay_b.is_empty():
				return Action.kan(
					actor, pay_b, DEFAULT_ROOM_ID, _next_action_command_id(),
					ctx.decision_id, state.hand_seq, _action_cmd_seq
				)
			continue
		if action == "discard":
			var iid: int = int(choice.get("tile_instance_id", Tile.INVALID_INSTANCE_ID))
			if iid == Tile.INVALID_INSTANCE_ID:
				validation_message = "请点选手牌实体"
				continue
			if should_auto_tsumogiri(seat) and iid != seat.last_drawn_instance_id:
				validation_message = "立直中只能切刚摸的牌"
				continue
			if state.kuikae_restricted[actor].has(
				_tile_id_of_iid(seat, iid)
			):
				validation_message = "喰い替え禁止 — 这张不能打，换一张"
				continue
			# 可选 RIICHI
			if ctx.allows("RIICHI", {"tile_instance_id": iid}):
				var want: bool = await _get_riichi_decision(actor)
				if want:
					_decision_port.present(&"idle", {"text": "立直！"})
					return Action.riichi(
						actor, iid, DEFAULT_ROOM_ID, _next_action_command_id(),
						ctx.decision_id, state.hand_seq, _action_cmd_seq
					)
			if not ctx.allows("DISCARD", {"tile_instance_id": iid}):
				validation_message = "该牌不可切"
				continue
			_decision_port.present(&"idle", {"text": "AI 出牌中…"})
			return Action.discard(
				actor, iid, DEFAULT_ROOM_ID, _next_action_command_id(),
				ctx.decision_id, state.hand_seq, _action_cmd_seq
			)
	return null


func _player_select_claim_action(candidate: int, discarded: Tile, discarder: int) -> Action:
	var ctx: DecisionContext = decision_context_for_seat(candidate)
	if ctx == null:
		return null
	while true:
		var choice: Dictionary = await _decision_port.request(&"claim", {
			"can_ron": ctx.has_kind("RON"),
			"can_chi": ctx.has_kind("CHI"),
			"can_pon": ctx.has_kind("PON"),
			"can_minkan": ctx.has_kind("KAN"),
			"discarder_seat": discarder,
		})
		var action: String = String(choice.get("action", ""))
		if action == "ron" and ctx.has_kind("RON"):
			_decision_port.present(&"idle", {"text": "荣和！"})
			return Action.ron(
				candidate, DEFAULT_ROOM_ID, _next_action_command_id(),
				ctx.decision_id, state.hand_seq, _action_cmd_seq
			)
		if action == "pon" and ctx.has_kind("PON"):
			var comps_p: Array = await _pick_claim_companion_iids(ctx, "PON", discarded)
			if not comps_p.is_empty() \
					and ctx.allows("PON", {"companion_tile_instance_ids": comps_p}):
				return Action.pon(
					candidate, comps_p,
					DEFAULT_ROOM_ID, _next_action_command_id(),
					ctx.decision_id, state.hand_seq, _action_cmd_seq
				)
			continue
		if action == "minkan" and ctx.has_kind("KAN"):
			var pay_k: Dictionary = _first_payload(ctx, "KAN")
			if not pay_k.is_empty():
				return Action.kan(
					candidate, pay_k, DEFAULT_ROOM_ID, _next_action_command_id(),
					ctx.decision_id, state.hand_seq, _action_cmd_seq
				)
			continue
		if action == "chi" and ctx.has_kind("CHI"):
			var comps: Array = await _pick_claim_companion_iids(ctx, "CHI", discarded)
			if comps.is_empty():
				continue
			if ctx.allows("CHI", {"companion_tile_instance_ids": comps}):
				return Action.chi(
					candidate, comps, DEFAULT_ROOM_ID, _next_action_command_id(),
					ctx.decision_id, state.hand_seq, _action_cmd_seq
				)
			continue
		if action == "skip" or action == "pass" or action == "":
			_decision_port.present(&"idle", {"text": "AI 出牌中…"})
			return Action.make_pass(
				candidate, DEFAULT_ROOM_ID, _next_action_command_id(),
				ctx.decision_id, state.hand_seq, _action_cmd_seq
			)
	return null


func _player_select_rob_kan_action(candidate: int) -> Action:
	var ctx: DecisionContext = decision_context_for_seat(candidate)
	if ctx == null:
		return null
	while true:
		var choice: Dictionary = await _decision_port.request(&"claim", {
			"can_ron": ctx.has_kind("RON"),
			"can_chi": false,
			"can_pon": false,
			"can_minkan": false,
			"discarder_seat": int(_pending_added_kan.get("seat", -1)),
		})
		var action: String = String(choice.get("action", ""))
		if action == "ron" and ctx.has_kind("RON"):
			_decision_port.present(&"idle", {"text": "抢杠荣和！"})
			return Action.ron(
				candidate, DEFAULT_ROOM_ID, _next_action_command_id(),
				ctx.decision_id, state.hand_seq, _action_cmd_seq
			)
		if action == "skip" or action == "pass" or action == "":
			return Action.make_pass(
				candidate, DEFAULT_ROOM_ID, _next_action_command_id(),
				ctx.decision_id, state.hand_seq, _action_cmd_seq
			)
	return null


func _pick_claim_companion_iids(
	ctx: DecisionContext, claim_kind: String, discarded: Tile
) -> Array:
	if ctx == null or (claim_kind != "CHI" and claim_kind != "PON"):
		return []
	# 从冻结 offer 取全部物理组合；唯一组合直接提交，多组合逐张选择实体牌。
	var options: Array = []
	for offer in ctx.allowed_actions:
		if str(offer.get("kind", "")) != claim_kind:
			continue
		for opt in offer.get("payload_options", []):
			if opt is Dictionary and (opt as Dictionary).has("companion_tile_instance_ids"):
				var ids_raw: Variant = (opt as Dictionary)["companion_tile_instance_ids"]
				if typeof(ids_raw) == TYPE_ARRAY and (ids_raw as Array).size() == 2:
					options.append((ids_raw as Array).duplicate())
	if options.is_empty():
		return []
	if options.size() == 1:
		return (options[0] as Array).duplicate()

	var selected: Array = []
	while true:
		var compatible: Array = _compatible_claim_options(options, selected)
		var allowed_iids: Array = _remaining_claim_iids(compatible, selected)
		if compatible.is_empty() or allowed_iids.is_empty():
			_decision_port.present(&"clear_hand_selection")
			return []
		var choice: Dictionary = await _decision_port.request(&"claim_companions", {
			"claim_kind": claim_kind,
			"options": compatible,
			"discarded_tile_id": discarded.id if discarded != null else -1,
			"selected_tile_instance_ids": selected.duplicate(),
			"allowed_tile_instance_ids": allowed_iids,
		})
		var action: String = String(choice.get("action", ""))
		if action == "claim_tile_pick":
			var iid: int = int(choice.get("tile_instance_id", -1))
			if not allowed_iids.has(iid) or selected.has(iid):
				continue
			selected.append(iid)
			if selected.size() < 2:
				continue
			for option in options:
				if _same_iid_set(option as Array, selected):
					_decision_port.present(&"clear_hand_selection")
					return (option as Array).duplicate()
			_decision_port.present(&"clear_hand_selection")
			return []
		if action == "skip":
			_decision_port.present(&"clear_hand_selection")
			return []
	_decision_port.present(&"clear_hand_selection")
	return []


static func _compatible_claim_options(options: Array, selected: Array) -> Array:
	var compatible: Array = []
	for option_raw in options:
		if typeof(option_raw) != TYPE_ARRAY:
			continue
		var option: Array = option_raw as Array
		var contains_all := true
		for iid in selected:
			if not option.has(iid):
				contains_all = false
				break
		if contains_all:
			compatible.append(option.duplicate())
	return compatible


static func _remaining_claim_iids(options: Array, selected: Array) -> Array:
	var remaining: Array = []
	for option_raw in options:
		if typeof(option_raw) != TYPE_ARRAY:
			continue
		for iid_raw in option_raw as Array:
			var iid: int = int(iid_raw)
			if not selected.has(iid) and not remaining.has(iid):
				remaining.append(iid)
	return remaining


static func _same_iid_set(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for iid in a:
		if not b.has(iid):
			return false
	return true


func _get_riichi_decision(actor: int) -> bool:
	if actor != PLAYER_SEAT or _decision_port == null:
		await _ai_think_pause()
		return super(actor)
	# 合法性已由当前 14 张阶段的冻结 DecisionContext / RIICHI offer 判定；
	# 这里仅收集玩家确认，不能再调用要求 13 张听牌形的旧接口二次拒绝。
	while true:
		var choice: Dictionary = await _decision_port.request(&"riichi")
		var action: String = String(choice.get("action", ""))
		match action:
			"riichi_yes":
				return true
			"riichi_no":
				return false
	return false


static func should_auto_tsumogiri(seat: Seat) -> bool:
	if not seat.riichi.declared:
		return false
	return seat.last_drawn_instance_id != Tile.INVALID_INSTANCE_ID


func _ctx_has_kan_kind(ctx: DecisionContext, kan_kind: String) -> bool:
	if ctx == null or not ctx.has_kind("KAN"):
		return false
	for offer in ctx.allowed_actions:
		if str(offer.get("kind", "")) != "KAN":
			continue
		for opt in offer.get("payload_options", []):
			if str(opt.get("kan_kind", "")) == kan_kind:
				return true
	return false


func _first_kan_payload(ctx: DecisionContext, kan_kind: String) -> Dictionary:
	for offer in ctx.allowed_actions:
		if str(offer.get("kind", "")) != "KAN":
			continue
		for opt in offer.get("payload_options", []):
			if str(opt.get("kan_kind", "")) == kan_kind:
				return (opt as Dictionary).duplicate(true)
	return {}


func _first_payload(ctx: DecisionContext, kind: String) -> Dictionary:
	for offer in ctx.allowed_actions:
		if str(offer.get("kind", "")) != kind:
			continue
		var opts: Array = offer.get("payload_options", [])
		if not opts.is_empty() and opts[0] is Dictionary:
			return (opts[0] as Dictionary).duplicate(true)
	return {}


func _tile_id_of_iid(seat: Seat, iid: int) -> int:
	var t: Tile = seat.hand.find_by_instance_id(iid)
	if t == null:
		return -1
	return t.id


func _ai_think_pause() -> void:
	if _ai_think_delay_sec <= 0.0 or _scene_tree == null:
		return
	await _scene_tree.create_timer(_ai_think_delay_sec).timeout
