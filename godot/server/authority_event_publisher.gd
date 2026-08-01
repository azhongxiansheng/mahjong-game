class_name AuthorityEventPublisher extends RefCounted

# ARCH-02 #392（spec 2026-07-29 §5.3）：权威事件发布组件。
# 唯一职责：server_seq 与四席 NetworkedEvent journal 的所有权、recipient
# 事件构造（严格 wire roundtrip）与事件克隆。禁止承担：修改领域状态。
# 原子提交编排（预构造 → 抢占 seq → 逐席 append）仍由 façade 执行，
# journals 暴露为活引用以保持既有提交模式逐字不变。

var server_seq: int = 0
# 每席独立 NetworkedEvent 日志（同逻辑 seq 可有不同 view_hash）
var journals: Array = [[], [], [], []]


## 构造 recipient 事件：make 后强制 from_dict(to_dict()) 严格 wire roundtrip，
## 非法 kind / payload / hash 一律 null（与拆分前 LLS._build_recipient_event 一致）。
func build_recipient_event(
	kind: String, seq: int, room_id: String, payload: Dictionary, view_hash: String
) -> NetworkedEvent:
	var ne: NetworkedEvent = NetworkedEvent.make(kind, seq, room_id, payload, view_hash)
	if ne == null:
		return null
	return NetworkedEvent.from_dict(ne.to_dict())


## 深克隆 wire 事件数组：仅保留合法 NetworkedEvent（journal 冻结/恢复用）。
static func clone_events(src: Array) -> Array:
	var out: Array = []
	for ne in src:
		if ne is NetworkedEvent:
			var c: NetworkedEvent = NetworkedEvent.from_dict((ne as NetworkedEvent).to_dict())
			if c != null:
				out.append(c)
	return out
