class_name NodeRef extends RefCounted

# 麻将王 — 里程碑 4 第 1 步：单节点引用
#
# `floor_index` 命名故意避开 GDScript 内置 floor() 函数 shadow（PR #15 教训）。

var index: int = -1
var floor_index: int = 0
var kind: int = NodeKind.Kind.NORMAL
var meta: Dictionary = {}
# M8 半庄战：节点 session 模式（"east_round" / "hanchan"）。
# 与 NodeKind 正交：BOSS+hanchan 表示半庄 Boss 战，NORMAL+east_round 表示
# 标准 4 局战。默认 east_round 兼容 M7，旧存档加载时缺字段也回这值。
var session_kind: String = "east_round"

func _init(p_index: int = -1, p_floor: int = 0, p_kind: int = NodeKind.Kind.NORMAL, p_meta: Dictionary = {}, p_session_kind: String = "east_round") -> void:
	index = p_index
	floor_index = p_floor
	kind = p_kind
	meta = p_meta
	session_kind = p_session_kind

func display_name() -> String:
	return NodeKind.display_name(kind)

# ---- 序列化（M5 SaveSystem） ----

func to_dict() -> Dictionary:
	return {
		"index": index,
		"floor_index": floor_index,
		"kind": kind,
		"meta": meta.duplicate(true),
		"session_kind": session_kind,
	}

static func from_dict(d: Dictionary) -> NodeRef:
	if d == null or d.is_empty():
		return null
	var n := NodeRef.new()
	n.index = int(d.get("index", -1))
	n.floor_index = int(d.get("floor_index", 0))
	n.kind = int(d.get("kind", NodeKind.Kind.NORMAL))
	n.meta = d.get("meta", {}).duplicate(true) if d.has("meta") else {}
	# M7 旧档无 session_kind 字段；默认 east_round 兼容（migration 路径之一）
	n.session_kind = String(d.get("session_kind", "east_round"))
	return n
