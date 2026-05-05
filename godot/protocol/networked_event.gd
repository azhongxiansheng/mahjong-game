class_name NetworkedEvent extends RefCounted

# 麻将王 — M12 Path C 第 1 步：联机协议 NetworkedEvent 数据类型
#
# server 仲裁后回 client 的事件信封；包装现有 BattleEvent + 加 server_seq
# 让 client 可以确认事件顺序、检测丢失、重连后从最后已知 seq 继续拉。
#
# 设计原则：
# - server_seq 单调递增，每个 BattleEvent 命中即赋一个；server 重启后从 0 起
# - causing_action_id 可选：standalone 事件（如 server 注入的随机牌摸事件）为 0；
#   client 发的 Action 仲裁后产生的事件复制 client_seq 让 client 端 echo
# - event payload 复用 BattleEvent.to_dict —— 不重复造轮子
#
# 网络层后续（M13）会在 NetworkedEvent 外再包一层 transport frame
# (length prefix / msgpack / 鉴权 token)；本类只做"语义层" event。

# 服务端递增序号（>=1；0 表示未赋）
var server_seq: int = 0

# 关联的 client Action.client_seq（0 表示无关联）
var causing_action_id: int = 0

# 实际事件数据
var event: BattleEvent = null

# 时间戳（server 端 ms unix timestamp，可选；M14 反作弊 / 录像用）
var server_ts_ms: int = 0

# ---- 构造 helpers ----

static func wrap(battle_event: BattleEvent, seq: int, causing_action: int = 0, ts_ms: int = 0) -> NetworkedEvent:
	var ne := NetworkedEvent.new()
	ne.event = battle_event
	ne.server_seq = seq
	ne.causing_action_id = causing_action
	ne.server_ts_ms = ts_ms
	return ne

# ---- 序列化 ----

func to_dict() -> Dictionary:
	return {
		"server_seq": server_seq,
		"causing_action_id": causing_action_id,
		"server_ts_ms": server_ts_ms,
		"event": event.to_dict() if event != null else {},
	}

static func from_dict(d: Dictionary) -> NetworkedEvent:
	if d == null or d.is_empty():
		return null
	var ne := NetworkedEvent.new()
	ne.server_seq = int(d.get("server_seq", 0))
	ne.causing_action_id = int(d.get("causing_action_id", 0))
	ne.server_ts_ms = int(d.get("server_ts_ms", 0))
	var ev_dict: Dictionary = d.get("event", {})
	if not ev_dict.is_empty():
		ne.event = BattleEvent.from_dict(ev_dict)
	return ne

# 用作 debug / log
func describe() -> String:
	var ev_type: String = String(event.type) if event != null else "<null>"
	return "NetEv[seq=%d ev=%s actor=%d cause=%d]" % [
		server_seq, ev_type,
		event.actor_seat if event != null else -1,
		causing_action_id,
	]
