class_name AuthorityCommandProcessor extends RefCounted

# ARCH-02 #392（spec 2026-07-29 §5.3）：权威命令处理组件。
# 唯一职责：command 业务指纹、幂等命中/冲突判定、首次结果缓存与事务
# capture/restore。禁止承担：推进牌局、渲染、网络连接。
# LocalLoopbackServer 迁移期间保留公开行为（façade characterization 不变）。

const STATUS_MISS := "MISS"
const STATUS_HIT := "HIT"
const STATUS_CONFLICT := "CONFLICT"

# command_id → { "fingerprint": String, "result": CommandResult }
var _cache: Dictionary = {}


## 业务指纹：仅 Action v1 exact-schema + 可规范化 payload 后形成；失败返 ""（不缓存）。
## bound_session_id 优先；为空时使用 fallback_session_id（原 LLS._config.session_id）。
static func business_fingerprint(
	action: Action, fallback_session_id: String, bound_session_id: String = ""
) -> String:
	if action == null:
		return ""
	var sid: String = bound_session_id.strip_edges()
	if sid.is_empty():
		sid = fallback_session_id.strip_edges()
	if sid.is_empty():
		return ""
	var kind_str: String = str(action.kind)
	var raw_payload: Dictionary = action.payload if typeof(action.payload) == TYPE_DICTIONARY else {}
	var canon_pl: Variant = Action.normalize_payload(kind_str, raw_payload)
	if canon_pl == null or typeof(canon_pl) != TYPE_DICTIONARY:
		return ""
	var payload_sha: String = ProtocolViewCodec.compute_view_hash(canon_pl)
	if payload_sha.is_empty() or payload_sha.length() != 64:
		return ""
	var material := {
		"session_id": sid,
		"room_id": str(action.room_id),
		"seat": int(action.seat),
		"hand_seq": int(action.hand_seq),
		"decision_id": str(action.decision_id),
		"kind": kind_str,
		"payload_sha256": payload_sha,
	}
	var fp: String = ProtocolViewCodec.compute_view_hash(material)
	if fp.is_empty() or fp.length() != 64:
		return ""
	return fp


## 幂等判定：MISS / HIT（携原缓存结果）/ CONFLICT（同 command_id 异指纹）。
func lookup(command_id: String, fingerprint_value: String) -> Dictionary:
	if not _cache.has(command_id):
		return {"status": STATUS_MISS}
	var entry: Dictionary = _cache[command_id] as Dictionary
	if str(entry.get("fingerprint", "")) == fingerprint_value:
		return {"status": STATUS_HIT, "result": entry.get("result") as CommandResult}
	return {"status": STATUS_CONFLICT}


func store(command_id: String, fingerprint_value: String, cr: CommandResult) -> void:
	_cache[command_id] = {
		"fingerprint": fingerprint_value,
		"result": cr,
	}


func size() -> int:
	return _cache.size()


func clear() -> void:
	_cache = {}


## 事务快照：与原 LLS `_command_cache.duplicate(true)` 语义一致
## （嵌套 Dictionary 深拷、CommandResult 引用共享）。
func capture() -> Dictionary:
	return _cache.duplicate(true)


func restore(snapshot: Dictionary) -> void:
	_cache = snapshot


## 只读内省（characterization 测试兼容）：返回浅拷贝，写入不影响权威缓存。
func entries() -> Dictionary:
	return _cache.duplicate()
