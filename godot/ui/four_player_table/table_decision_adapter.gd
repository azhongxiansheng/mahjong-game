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
		&"chi_companions":
			_seat_panel.set_hand_clickable(true)
			_seat_panel.dim_hand_except(context.get("allowed_tile_ids", []))
	var message: String = String(context.get("message", ""))
	if kind == &"chi_companions" and message == "":
		var options_text: Array[String] = []
		for option in context.get("options", []):
			options_text.append("%s+%s" % [
				CardTileBack.tile_short_name(int(option[0])),
				CardTileBack.tile_short_name(int(option[1]))])
		message = "吃 %s — 点手牌选搭子（%s）或跳过" % [
			CardTileBack.tile_short_name(int(context.get("discarded_tile_id", -1))),
			" / ".join(options_text)]
	if message != "":
		_action_panel.set_status_text(message)
	return await _action_panel.player_action_chosen


func present(state_name: StringName, context: Dictionary = {}) -> void:
	match state_name:
		&"idle":
			_seat_panel.set_hand_clickable(false)
			_seat_panel.clear_hand_dim()
			_action_panel.enter_idle(String(context.get("text", "等待 AI…")))
		&"status":
			_action_panel.set_status_text(String(context.get("text", "")))
		&"clear_hand_selection":
			_seat_panel.set_hand_clickable(false)
			_seat_panel.clear_hand_dim()


func on_hand_tile_clicked(tile_id: int) -> void:
	_action_panel.on_hand_tile_clicked(tile_id)


func submit_action(choice: Dictionary) -> void:
	_action_panel.player_action_chosen.emit(choice)
