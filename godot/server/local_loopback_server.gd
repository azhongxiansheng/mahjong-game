class_name LocalLoopbackServer extends RefCounted

# 麻将王 — M12 Path C 第 2 步：本地 loopback server 骨架（spec §4.3 PvP 雏形）
#
# v1 同 process 跑的"假 server"：
# - 单一 BattleController 作权威 state（authoritative）
# - 提供 broadcast 层：把 BC.events 包装成 NetworkedEvent 序列（server_seq 单调）
# - submit_action() 入口：v1 仅接 PASS_CLAIM 作 no-op 占位；完整 action 路由在 p3+ 加
# - events_since(seq) 入口：client 重连后从最后已知 seq 拉补
#
# 设计原则：
# - 不接真网络（M13 才上 WebSocket）；本类是"网络无关的仲裁器"，把 spec §4.3
#   "事件总线 = 单一事实源"在本地 loopback 跑通
# - 不替换 BattleController：BC 仍跑现有 AI；server 在 BC.run_to_end() 后吸事件
#   并广播；为 p3 NetworkedBattleController（client 半边）铺接口
# - server_seq 从 0 起；run_to_end / submit_action 调用过程中递增
#
# 不在本 PR 范围（留 M12/p3+）：
# - 真 client → server 路由（NetworkedBattleController 实例化）
# - DISCARD / RIICHI / RON / TSUMO 等 action 的合法性校验 + 状态转移
# - server 端独立 BC 镜像（v1 用同一个 BC）
# - 牌墙 reveal gating（M14 反作弊）

# 权威 BC（authoritative state）
var bc: IBattleController = null

# 事件序号（≥1 起递增；0 = 未赋）
var _seq: int = 0

# 已广播事件列表（按 server_seq 升序）
var _events: Array = []  # Array[NetworkedEvent]

func _init(seed: int = 0, dealer_seat: int = 0, use_heuristic_ai: bool = false) -> void:
	# v1: 用 BattleController（concrete v1 实现）；M12+ 可换 NetworkedBattleController
	bc = BattleController.new(seed, dealer_seat, use_heuristic_ai)

# 跑完整一局；server 吸 BC.events 并包装成 NetworkedEvent 序列广播。
# 返广播 events 副本（按 server_seq 升序）。
func run_to_end() -> Array:
	bc.run_to_end()
	# 把 BC 内部 emit 的每个 BattleEvent 提升为 NetworkedEvent
	for be in bc.events:
		_seq += 1
		var ne: NetworkedEvent = NetworkedEvent.wrap(be, _seq, 0, _server_ts())
		_events.append(ne)
	return _events.duplicate()

# 接收 client Action；v1 仅识别 PASS_CLAIM 作 no-op 占位；其余 kind 返
# kind_not_yet_implemented（p3 加完整路由）。
# 返 {accepted: bool, reason: String, events: Array[NetworkedEvent]}.
func submit_action(action: Action) -> Dictionary:
	if action == null:
		return {"accepted": false, "reason": "null_action", "events": []}
	if action.seat < 0 or action.seat > 3:
		return {"accepted": false, "reason": "invalid_seat", "events": []}
	# v1: 仅接 PASS_CLAIM 作 no-op；ack 后无 events 产生
	if action.kind == Action.Kind.PASS_CLAIM:
		return {"accepted": true, "reason": "ok", "events": []}
	return {
		"accepted": false,
		"reason": "kind_not_yet_implemented",
		"events": [],
	}

# 当前 server_seq（≥0；0 = 还没 emit 过）
func current_seq() -> int:
	return _seq

# Client 重连用：拉 server_seq > since_seq 的所有 events 副本。
# since_seq=0 表示拉全部历史。
func events_since(since_seq: int) -> Array:
	var result: Array = []
	for ne in _events:
		if ne.server_seq > since_seq:
			result.append(ne)
	return result

# 全部已广播 events 的副本快照
func get_all_events() -> Array:
	return _events.duplicate()

# v1：占位 timestamp（client 不依赖；M14 反作弊用真 unix ms）
func _server_ts() -> int:
	return Time.get_ticks_msec()
