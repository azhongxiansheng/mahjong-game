class_name ChapterConfig

# 麻将王 — 里程碑 4 第 1 步：3 章 hardcoded 配置（plan-4 D2）
#
# v1 用 GDScript 字典；M6 内容生产时改为 Resource (.tres) + 美术 / Boss 配置。
# 节点权重比例与每层节点数范围按 spec §14 数值近似（v1 拍板，平衡留 M7）。
#
# Boss 之前 1 floor 由 ChapterMapGenerator._pick_kind_for_floor 强制设为 CAMP，
# 这里的 node_weights 不会被用在 Boss 之前的 floor。

# 用 static func 而不是 const，避开 const Dictionary 在 GDScript 4 里
# 引用其他 class_name enum 的静态初始化顺序问题。

static func chapter_1() -> Dictionary:
	return {
		"chapter_index": 1,
		"floor_count": 5,
		"nodes_per_floor": Vector2i(1, 3),
		"node_weights": {
			NodeKind.Kind.NORMAL: 0.6,
			NodeKind.Kind.ELITE: 0.15,
			NodeKind.Kind.SHOP: 0.10,
			NodeKind.Kind.EVENT: 0.15,
		},
		"boss_id": &"boss1_iron_curtain_v1",
		# GAP-4: 普通/精英节点 speed (2 局)；Boss 保留 east_round (4 局)
		"default_session_kind": "speed",
		"boss_session_kind": "east_round",
	}

static func chapter_2() -> Dictionary:
	return {
		"chapter_index": 2,
		"floor_count": 5,
		"nodes_per_floor": Vector2i(1, 3),
		"node_weights": {
			NodeKind.Kind.NORMAL: 0.5,
			NodeKind.Kind.ELITE: 0.2,
			NodeKind.Kind.SHOP: 0.1,
			NodeKind.Kind.EVENT: 0.2,
		},
		"boss_id": &"boss2_fortune_runner_v1",
		# GAP-4: 普通/精英节点 speed (2 局)；Boss 保留 east_round (4 局)
		"default_session_kind": "speed",
		"boss_session_kind": "east_round",
	}

static func chapter_3() -> Dictionary:
	return {
		"chapter_index": 3,
		"floor_count": 6,
		"nodes_per_floor": Vector2i(2, 3),
		"node_weights": {
			NodeKind.Kind.NORMAL: 0.4,
			NodeKind.Kind.ELITE: 0.3,
			NodeKind.Kind.SHOP: 0.1,
			NodeKind.Kind.EVENT: 0.2,
		},
		"boss_id": &"boss3_kanmon_v1",
		# GAP-4: 普通/精英节点 speed (2 局)；Boss 保留 hanchan (8 局)
		"default_session_kind": "speed",
		"boss_session_kind": "hanchan",
	}

static func get_chapter(chapter_index: int) -> Dictionary:
	match chapter_index:
		1: return chapter_1()
		2: return chapter_2()
		3: return chapter_3()
	return {}

# 取章节 Boss 能力 id（CardPool 中注册的 ability id）。
# chapter_index 越界返 &""（调用方应当 fallback 到不 inject Boss）。
static func get_boss_id(chapter_index: int) -> StringName:
	var c: Dictionary = get_chapter(chapter_index)
	return c.get("boss_id", &"") as StringName

static func chapter_count() -> int:
	return 3
