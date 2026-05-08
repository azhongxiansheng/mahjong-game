class_name MeldLayout

# 麻将王 — 副露日麻风格视觉化算法层
#
# 给定 Meld + 副露者 seat id（claimant），返每张牌的渲染 Slot：
#   { tile_id: int, rotated: bool, face_down: bool, stacked_above: bool }
#
# 旋转规则（spec §10 通行日麻）：
#   from_seat 是 claimant 的上家 (claimant-1)%4 → 第 0 张 rotated
#   from_seat 是 claimant 的对家 (claimant+2)%4 → 第 1 张 rotated
#   from_seat 是 claimant 的下家 (claimant+1)%4 → 第 2 张 rotated
#
# Chi 仅允许从上家 → 旋转牌恒第 0 张。
# Ankan 首尾 2 张盖牌（D1 流派），无旋转牌。
# Added-kan 在原 pon 旋转牌正上方叠 1 张同 id 旋转牌。
#
# 纯算法层：无 Godot scene tree 依赖，GUT 单测全覆盖。

# 计算 Meld 的渲染 Slot 列表
static func compute(meld: Meld, claimant_seat: int) -> Array:
	match meld.kind:
		Meld.Kind.CHI:
			return _compute_chi(meld)
		Meld.Kind.PON:
			return _compute_pon_or_minkan(meld, claimant_seat, 3)
		Meld.Kind.MINKAN:
			return _compute_pon_or_minkan(meld, claimant_seat, 4)
		Meld.Kind.ANKAN:
			return _compute_ankan(meld)
		Meld.Kind.ADDED_KAN:
			return _compute_added_kan(meld, claimant_seat)
	return []

# Chi: 3 张升序，旋转牌恒第 0 张（仅上家来）
static func _compute_chi(meld: Meld) -> Array:
	var slots: Array = []
	for i in range(meld.tiles.size()):
		slots.append({
			"tile_id": meld.tiles[i].id,
			"rotated": i == 0,
			"face_down": false,
			"stacked_above": false,
			"is_red_dora": meld.tiles[i].is_red_dora,
		})
	return slots

# Pon/Minkan: 3 或 4 张同 id，按 from_seat 旋转
static func _compute_pon_or_minkan(meld: Meld, claimant_seat: int, count: int) -> Array:
	var rotated_idx: int = _rotated_index_from_source(meld.from_seat, claimant_seat)
	var slots: Array = []
	for i in range(count):
		slots.append({
			"tile_id": meld.tiles[i].id,
			"rotated": i == rotated_idx,
			"face_down": false,
			"stacked_above": false,
			"is_red_dora": meld.tiles[i].is_red_dora,
		})
	return slots

# 来源 → 旋转索引（基于 3 张视角）
# 上家 (claimant-1)%4 → 0；对家 (claimant+2)%4 → 1；下家 (claimant+1)%4 → 2
# 4 张 minkan 同样规则（多出的第 4 张靠最右）
static func _rotated_index_from_source(from_seat: int, claimant_seat: int) -> int:
	var diff: int = (from_seat - claimant_seat + 4) % 4
	match diff:
		3: return 0  # 上家
		2: return 1  # 对家
		1: return 2  # 下家
	return 0  # fallback（不该到达；防御性返第 0 张）

# Ankan: 4 张同 id，第 0 / 第 3 张 face_down，无旋转牌
static func _compute_ankan(meld: Meld) -> Array:
	var slots: Array = []
	for i in range(4):
		slots.append({
			"tile_id": meld.tiles[i].id,
			"rotated": false,
			"face_down": (i == 0 or i == 3),
			"stacked_above": false,
			"is_red_dora": meld.tiles[i].is_red_dora,
		})
	return slots

# Added-kan: 4 张同 id；先按原 pon 布局（3 张），再在原 rotated 位置正上方叠 1 张
static func _compute_added_kan(meld: Meld, claimant_seat: int) -> Array:
	var rotated_idx: int = _rotated_index_from_source(meld.from_seat, claimant_seat)
	var slots: Array = []
	# 原 pon 3 张
	for i in range(3):
		slots.append({
			"tile_id": meld.tiles[i].id,
			"rotated": i == rotated_idx,
			"face_down": false,
			"stacked_above": false,
			"is_red_dora": meld.tiles[i].is_red_dora,
		})
	# 第 4 张：叠在原 rotated 位置上方
	slots.append({
		"tile_id": meld.tiles[3].id,
		"rotated": true,
		"face_down": false,
		"stacked_above": true,
		"is_red_dora": meld.tiles[3].is_red_dora,
	})
	return slots
