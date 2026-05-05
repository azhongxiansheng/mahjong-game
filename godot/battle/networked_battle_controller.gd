class_name NetworkedBattleController extends BattleController

# 麻将王 — M11 net foundation: NetworkedBattleController stub
#
# spec §4.3 Phase 2 联机的 BattleController 实现。当前是 v1 stub —
# **真服务端推流路径（M12+）尚未连接**。本类的存在是为了：
#
# 1. 把 BattleControllerInterface 的契约从"文档"升级到"有第二个实现"
#    (LocalBC + NetworkedBC stub)，保证契约真起作用
# 2. 提供 ingest_event_stream / desync_check 两个 API，未来接 server stream
#    时只是"input source 换成 socket"，BC 内部逻辑不变
# 3. 让端到端测试有"另一种实现 = 同结果"的证据，巩固 spec §4 day-1 承诺
#    （所有副作用走 event bus）
#
# v1 实现策略：从录制的事件流抽 PlayerAction → 用父类 set_replay_decisions
# 注入 → run_to_end 重跑。**等价于 LocalBC 跑同 seed + 同决策**，因此终态
# snapshot_hash 必须 byte-identical（端到端测试锁住）。
#
# Phase 2 真实装时 ingest_event_stream 会换成 ingest_event_realtime：每收
# 到 server 一个 event 就 from_dict + 喂 SkillScheduler，不重新跑决策路径。
# 当前 stub 走"重放"路径是简化 — 等 server 协议定下来再切换。

# ---- 公共 API ----

# 接收完整事件流（dict 形式 = JSON 友好），提取决策后重放整局。
# events_dicts 来自 LocalBattleController.events 经 to_dict() 序列化。
# 返与父类 run_to_end 一致：{last_event, events}。
#
# v1 stub 限制：不支持流式（一次性接整局）。M12+ 实装时改为 push-driven。
func ingest_event_stream(events_dicts: Array) -> Dictionary:
	# 1) 反序列化事件
	var rebuilt: Array = []
	for d in events_dicts:
		var ev: BattleEvent = BattleEvent.from_dict(d)
		if ev != null:
			rebuilt.append(ev)
	# 2) 抽决策（PLAYER_ACTION 序列）
	var actions: Array = BattleController.extract_player_actions(rebuilt)
	# 3) 注入回放队列后跑
	set_replay_decisions(actions)
	return run_to_end()

# Desync detect：与 server 推送的状态 hash 比对。
# 不一致 = 本地状态与 server 权威状态分叉，应立即 disconnect + dump
# snapshot_dict 给运维诊断。
func desync_check(remote_state_hash: int) -> bool:
	return state.snapshot_hash() == remote_state_hash
