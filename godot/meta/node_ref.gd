class_name NodeRef extends RefCounted

# 麻将王 — 里程碑 4 第 1 步：单节点引用
#
# `floor_index` 命名故意避开 GDScript 内置 floor() 函数 shadow（PR #15 教训）。

var index: int = -1
var floor_index: int = 0
var kind: int = NodeKind.Kind.NORMAL
var meta: Dictionary = {}

func _init(p_index: int = -1, p_floor: int = 0, p_kind: int = NodeKind.Kind.NORMAL, p_meta: Dictionary = {}) -> void:
	index = p_index
	floor_index = p_floor
	kind = p_kind
	meta = p_meta

func display_name() -> String:
	return NodeKind.display_name(kind)
