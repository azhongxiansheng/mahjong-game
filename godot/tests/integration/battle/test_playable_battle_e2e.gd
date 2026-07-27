extends GutTest

# 玩家决策端口对战端到端测试。
#
# 用脚本化 PlayerDecisionPort 驱动 PlayableBattleController.run_to_end_async()，
# 不加载具体 UI 控件；UI 映射由 test_table_decision_adapter 单独覆盖。
#
# 覆盖：玩家切牌路径、立直确认、鸣牌响应、自摸/荣和决策，
# 以及一局结束后的点数守恒。

const SCRIPTED_DECISION_PORT := preload("res://tests/_fixtures/scripted_decision_port.gd")


# 脚本化玩家：策略 = 永远切手牌第一张、从不立直、从不鸣牌、不抢自摸 —— 一个
# 最朴素但完全合法的玩家，能把任意一局推到自然终局（自摸/荣和/流局）。
#
func _respond(kind: StringName, _context: Dictionary, bc: PlayableBattleController) -> Dictionary:
	match kind:
		&"discard":
			var hand_tiles: Array[Tile] = bc.state.seats[0].hand.tiles()
			if not hand_tiles.is_empty():
				return {
					"action": "discard",
					"tile_instance_id": int(hand_tiles[0].instance_id),
				}
		&"riichi":
			return {"action": "riichi_no"}
		&"claim", &"claim_companions":
			return {"action": "skip"}
		&"kyuusyu":
			# 默认不申请九種九牌(让测试跑到自然终局,而非途中流局)
			return {"action": "kyuusyu_no"}
	return {}


func _play_one_hand(seed: int) -> PlayableBattleController:
	var bc := PlayableBattleController.new(seed, 0, false, TileId.E)
	var port = SCRIPTED_DECISION_PORT.new()
	port.responder = func(kind: StringName, context: Dictionary):
		return _respond(kind, context, bc)
	bc.bind_decision_port(port, get_tree())
	bc.set_ai_think_delay(0.0)
	await bc.run_to_end_async()
	# 断开 responder 捕获 bc 形成的 RefCounted 环，避免测试结束遗留 orphan。
	port.responder = Callable()
	bc.bind_decision_port(null)
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
