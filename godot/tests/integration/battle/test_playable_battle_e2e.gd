extends GutTest

# 真实可玩对战端到端测试 — 无 mock。
#
# 实例化真实 PlayerActionPanel + SeatPanel 节点，挂进场景树，跑
# PlayableBattleController.run_to_end_async()，由一个脚本化"玩家"协程读
# 面板状态、向真实的 player_action_chosen 信号发决策，驱动整局走完。
#
# 覆盖：玩家切牌路径、立直确认窗口、鸣牌响应窗口、自摸/荣和窗口的信号接线，
# 以及一局结束后的点数守恒。

const SEAT_PANEL := preload("res://ui/four_player_table/seat_panel.tscn")

var _driving: bool = false


func after_each() -> void:
	_driving = false


# 脚本化玩家：策略 = 永远切手牌第一张、从不立直、从不鸣牌、不抢自摸 —— 一个
# 最朴素但完全合法的玩家，能把任意一局推到自然终局（自摸/荣和/流局）。
#
# BC 在一个 emit() 内会同步链进下一个玩家钩子（如切牌→立直确认），所以这里
# 用内层 while 把所有"链式等待状态"排空，直到面板回到 IDLE（轮到 AI / 局终）。
func _drive_player(panel: PlayerActionPanel, bc: PlayableBattleController) -> void:
	while _driving and is_instance_valid(panel):
		await get_tree().process_frame
		var guard: int = 0
		while _driving and is_instance_valid(panel) and guard < 500:
			var st: int = panel._state
			if st == PlayerActionPanel.State.IDLE:
				break
			guard += 1
			_respond(panel, bc, st)


func _respond(panel: PlayerActionPanel, bc: PlayableBattleController, st: int) -> void:
	match st:
		PlayerActionPanel.State.WAITING_DISCARD:
			var hand_ids: Array = bc.state.seats[0].hand.to_id_array()
			if not hand_ids.is_empty():
				panel.player_action_chosen.emit(
					{"action": "discard", "tile_id": int(hand_ids[0])})
		PlayerActionPanel.State.WAITING_RIICHI_CONFIRM:
			panel.player_action_chosen.emit({"action": "riichi_no"})
		PlayerActionPanel.State.WAITING_CLAIM:
			panel.player_action_chosen.emit({"action": "skip"})
		PlayerActionPanel.State.WAITING_KYUUSYU:
			# 默认不申请九種九牌(让测试跑到自然终局,而非途中流局)
			panel.player_action_chosen.emit({"action": "kyuusyu_no"})


func _play_one_hand(seed: int) -> PlayableBattleController:
	# autoqfree = 延迟 queue_free，不会在 emit() 解栈链上立即 free（避免锁对象）。
	var panel := PlayerActionPanel.new()
	add_child_autoqfree(panel)
	var seat_panel: SeatPanel = SEAT_PANEL.instantiate()
	add_child_autoqfree(seat_panel)
	await get_tree().process_frame  # 让两者的 _ready 跑完

	var bc := PlayableBattleController.new(seed, 0, false, TileId.E)
	bc.bind_ui(panel, seat_panel, get_tree())
	bc.set_ai_think_delay(0.0)

	_driving = true
	_drive_player(panel, bc)  # fire-and-forget 协程
	await bc.run_to_end_async()
	_driving = false
	# 插两帧断开最后一次 emit() 的同步解栈链，让 _drive_player 干净退出，
	# 也让本协程在干净栈上继续断言 / 让 GUT 在干净栈上 teardown。
	await get_tree().process_frame
	await get_tree().process_frame
	return bc


func test_scripted_player_completes_a_hand() -> void:
	var bc: PlayableBattleController = await _play_one_hand(42)

	var last_event: StringName = bc.events[bc.events.size() - 1].type
	assert_true([&"WIN_DECLARED", &"EXHAUSTIVE_DRAW"].has(last_event),
		"一局应以胡牌或流局自然结束，实际：%s" % last_event)
	assert_eq(bc.state.event_chain_depth, 0, "事件链深度退出时应归零")

	# 点数守恒：4 家分数 + 立直棒池 = 100000
	var total: int = 0
	for s in bc.state.scores:
		total += s
	assert_eq(total + bc.state.riichi_sticks * 1000, 100000,
		"点数应守恒（含立直棒池）")


func test_player_input_drives_at_least_one_discard() -> void:
	# 验证玩家切牌信号真的被 BC 消费 —— events 里应出现 seat 0 的
	# PLAYER_ACTION{kind:discard}（脚本化玩家发出的切牌）。
	var bc: PlayableBattleController = await _play_one_hand(7)

	var player_discards: int = 0
	for ev in bc.events:
		if ev.type == &"PLAYER_ACTION" and ev.actor_seat == 0 \
				and String(ev.extra.get("kind", "")) == "discard":
			player_discards += 1
	assert_gt(player_discards, 0,
		"脚本化玩家的切牌应至少被 BC 消费一次")
