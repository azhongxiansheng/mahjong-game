class_name ChapterMap extends RefCounted

# 麻将王 — 里程碑 4 第 1 步：每章节点图（plan-4 D2）
#
# 7-8 层 DAG：entry_node → ... → boss_node。
# edges[i] = Array[int]：node[i] 可达的下层节点索引。

var nodes: Array = []        # Array[NodeRef]
var edges: Array = []        # Array[Array[int]]
var entry_node: int = 0
var boss_node: int = -1
var current_node: int = -1   # -1 = 入口前；choose_next_node 后 = 实际节点 index

func node_count() -> int:
	return nodes.size()

func neighbors(node_index: int) -> Array:
	if node_index < 0 or node_index >= edges.size():
		return []
	return edges[node_index].duplicate()

# 当前可达的下层节点 index 列表。
# Run 起点（current_node=-1）返回 [entry_node]。
func next_options() -> Array:
	if current_node == -1:
		return [entry_node]
	return neighbors(current_node)

# 推进到 node_index；非法则返 false 不改 state。
func advance_to(node_index: int) -> bool:
	var allowed: Array = next_options()
	if node_index in allowed:
		current_node = node_index
		return true
	return false

func is_at_boss() -> bool:
	return current_node == boss_node

# 连通性自检：从 entry 起 BFS 能否到达 boss
# 注：方法名故意避开 Object.is_connected(signal_name, callable) 的 shadow
# （Godot 4 把这种 override warning 当 error 让脚本编译失败）。
func has_path_to_boss() -> bool:
	if entry_node < 0 or boss_node < 0:
		return false
	if entry_node == boss_node:
		return true
	var visited: Dictionary = {entry_node: true}
	var stack: Array = [entry_node]
	while stack.size() > 0:
		var n: int = stack.pop_back()
		for nb in neighbors(n):
			if nb == boss_node:
				return true
			if not visited.has(nb):
				visited[nb] = true
				stack.append(nb)
	return false

# 每个 non-entry 节点是否都有入边（避免孤儿节点）
func all_nodes_reachable_from_entry() -> bool:
	if entry_node < 0:
		return false
	var visited: Dictionary = {entry_node: true}
	var stack: Array = [entry_node]
	while stack.size() > 0:
		var n: int = stack.pop_back()
		for nb in neighbors(n):
			if not visited.has(nb):
				visited[nb] = true
				stack.append(nb)
	return visited.size() == nodes.size()

# ---- 序列化（M5 SaveSystem） ----

func to_dict() -> Dictionary:
	var node_dicts: Array = []
	for n in nodes:
		node_dicts.append(n.to_dict())
	return {
		"nodes": node_dicts,
		"edges": edges.duplicate(true),
		"entry_node": entry_node,
		"boss_node": boss_node,
		"current_node": current_node,
	}

static func from_dict(d: Dictionary) -> ChapterMap:
	if d == null or d.is_empty():
		return null
	var m := ChapterMap.new()
	for nd in d.get("nodes", []):
		var n := NodeRef.from_dict(nd)
		if n:
			m.nodes.append(n)
	# JSON 反序列化把数字统一变 float;edges 是 Array[Array[int]] 必须
	# 显式 int() 回去,否则 BFS 里 dict key 类型 int/float 不一致导致
	# "Out of bounds get index 'N' (on base: 'Dictionary')"。
	var raw_edges: Array = d.get("edges", [])
	m.edges = []
	for row in raw_edges:
		var int_row: Array = []
		for v in row:
			int_row.append(int(v))
		m.edges.append(int_row)
	m.entry_node = int(d.get("entry_node", 0))
	m.boss_node = int(d.get("boss_node", -1))
	m.current_node = int(d.get("current_node", -1))
	return m
