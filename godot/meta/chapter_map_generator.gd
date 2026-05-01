class_name ChapterMapGenerator

# 麻将王 — 里程碑 4 第 1 步：节点图生成器（plan-4 D2）
#
# v1 生成约束（plan-4 风险表已说明，不追求 StS 视觉美观）：
#   - floor 0 = entry_node（强制 NORMAL）
#   - floor N-1 = boss_node（强制 BOSS）
#   - floor N-2 = 全部 CAMP（Boss 前营地，给玩家最后休整）
#   - 其余 floor 按 node_weights 抽
#   - 每层 i 的每节点至少 1 条边到层 i+1
#   - 每个非 entry 节点至少 1 条入边（连通性）

const SECOND_EDGE_PROBABILITY: float = 0.4

# 输入：config Dictionary（chapter_index / floor_count / nodes_per_floor / node_weights）+ seed
# 输出：ChapterMap
static func generate(config: Dictionary, seed: int) -> ChapterMap:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var m := ChapterMap.new()

	var floor_count: int = int(config.get("floor_count", 7))
	var nodes_per_floor: Vector2i = config.get("nodes_per_floor", Vector2i(1, 3))
	var weights: Dictionary = config.get("node_weights", {NodeKind.Kind.NORMAL: 1.0})

	var nodes_by_floor: Array = []  # Array[Array[NodeRef]]
	var idx := 0

	for f in range(floor_count):
		var layer: Array = []
		var layer_size: int
		if f == 0 or f == floor_count - 1:
			layer_size = 1  # 入口与 Boss 各 1 节点
		else:
			layer_size = rng.randi_range(nodes_per_floor.x, nodes_per_floor.y)
		for j in range(layer_size):
			var kind := _pick_kind_for_floor(f, floor_count, weights, rng)
			var ref := NodeRef.new(idx, f, kind)
			m.nodes.append(ref)
			m.edges.append([])
			layer.append(ref)
			idx += 1
		nodes_by_floor.append(layer)

	# 入口 / Boss
	m.entry_node = nodes_by_floor[0][0].index
	m.boss_node = nodes_by_floor[floor_count - 1][0].index
	m.current_node = -1

	# 连边：每层每节点 → 下一层至少 1 条；保证 dst 全部至少 1 入边
	for f in range(floor_count - 1):
		var src_layer: Array = nodes_by_floor[f]
		var dst_layer: Array = nodes_by_floor[f + 1]
		# 阶段 1：每个 src 至少 1 条边
		for src in src_layer:
			var dst1: NodeRef = dst_layer[rng.randi_range(0, dst_layer.size() - 1)]
			m.edges[src.index].append(dst1.index)
			# 概率性第二条边（增加路径多样性）
			if dst_layer.size() > 1 and rng.randf() < SECOND_EDGE_PROBABILITY:
				var dst2: NodeRef = dst_layer[rng.randi_range(0, dst_layer.size() - 1)]
				if dst2.index != dst1.index and not (dst2.index in m.edges[src.index]):
					m.edges[src.index].append(dst2.index)
		# 阶段 2：补 dst 缺入边
		for dst in dst_layer:
			var has_inbound := false
			for src in src_layer:
				if dst.index in m.edges[src.index]:
					has_inbound = true
					break
			if not has_inbound:
				m.edges[src_layer[0].index].append(dst.index)

	return m

static func _pick_kind_for_floor(f: int, floor_count: int, weights: Dictionary, rng: RandomNumberGenerator) -> int:
	if f == 0:
		return NodeKind.Kind.NORMAL
	if f == floor_count - 1:
		return NodeKind.Kind.BOSS
	if f == floor_count - 2:
		return NodeKind.Kind.CAMP
	return _weighted_pick(weights, rng)

static func _weighted_pick(weights: Dictionary, rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for k in weights:
		total += float(weights[k])
	if total <= 0:
		return NodeKind.Kind.NORMAL
	var roll: float = rng.randf() * total
	var acc := 0.0
	for k in weights:
		acc += float(weights[k])
		if roll <= acc:
			return int(k)
	return NodeKind.Kind.NORMAL
