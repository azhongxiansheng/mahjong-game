class_name TableDecisionAdapter extends PlayerDecisionPort

# PlayerDecisionPort 的牌桌 UI 实现。
#
# 这里是唯一知道 PlayerActionPanel / SeatPanel 具体 API 的边界；战斗控制器只
# 发送语义化 request/present，不直接操作按钮、手牌点击或高亮。

var _action_panel: PlayerActionPanel
# SeatPanel 或 MahjongTable3D（duck：set_hand_clickable / dim_hand_except）
var _seat_panel: Node


func _init(action_panel: PlayerActionPanel, seat_panel: Node) -> void:
	_action_panel = action_panel
	_seat_panel = seat_panel


func request(kind: StringName, context: Dictionary = {}) -> Dictionary:
	match kind:
		&"discard":
			_set_selected_instances([])
			_action_panel.enter_waiting_discard(
				bool(context.get("can_tsumo", false)),
				bool(context.get("can_ankan", false)),
				bool(context.get("can_added_kan", false)),
				bool(context.get("has_consumable", false)))
			_seat_panel.set_hand_clickable(true)
		&"riichi":
			_action_panel.enter_waiting_riichi_confirm()
		&"claim":
			_action_panel.enter_waiting_claim(
				bool(context.get("can_ron", false)),
				bool(context.get("can_chi", false)),
				bool(context.get("can_pon", false)),
				bool(context.get("can_minkan", false)),
				int(context.get("discarder_seat", -1)))
		&"kyuusyu":
			_action_panel.enter_waiting_kyuusyu()
		&"claim_companions":
			# 从吃/碰按钮进入实体选择：切 WAITING_CLAIM + 仅 skip，清掉鸣牌按钮残留
			_action_panel.enter_waiting_claim_pick()
			_seat_panel.set_hand_clickable(true)
			# 已选实体保持高亮；其余仅保留当前可作为下一张的实体候选。
			var highlighted: Array = (
				context.get("allowed_tile_instance_ids", []) as Array
			).duplicate()
			for iid in context.get("selected_tile_instance_ids", []) as Array:
				if not highlighted.has(iid):
					highlighted.append(iid)
			_seat_panel.dim_hand_except(highlighted)
			_set_selected_instances(
				context.get("selected_tile_instance_ids", []) as Array)
	var message: String = String(context.get("message", ""))
	if kind == &"claim_companions" and message == "":
		var claim_kind: String = String(context.get("claim_kind", ""))
		var claim_label := "吃" if claim_kind == "CHI" else "碰"
		var selected_count: int = (
			context.get("selected_tile_instance_ids", []) as Array
		).size()
		message = "%s — 已选 %d/2，点选实体牌；跳过取消" % [
			claim_label, selected_count]
	if message != "":
		_action_panel.set_status_text(message)
	return await _action_panel.player_action_chosen


func present(state_name: StringName, context: Dictionary = {}) -> void:
	match state_name:
		&"idle":
			_seat_panel.set_hand_clickable(false)
			_seat_panel.clear_hand_dim()
			_set_selected_instances([])
			_action_panel.enter_idle(String(context.get("text", "等待 AI…")))
		&"status":
			_action_panel.set_status_text(String(context.get("text", "")))
		&"clear_hand_selection":
			_seat_panel.set_hand_clickable(false)
			_seat_panel.clear_hand_dim()
			_set_selected_instances([])


func _set_selected_instances(instance_ids: Array) -> void:
	if _seat_panel != null and _seat_panel.has_method("set_selected_instances"):
		_seat_panel.call("set_selected_instances", instance_ids)


func on_hand_tile_clicked(tile_instance_id: int) -> void:
	_action_panel.on_hand_tile_clicked(tile_instance_id)


func submit_action(choice: Dictionary) -> void:
	_action_panel.player_action_chosen.emit(choice)
