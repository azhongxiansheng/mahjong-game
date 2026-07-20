class_name MeldLayout

# 麻将王 — 副露日麻风格视觉化算法层
#
# 给定 Meld + 副露者 seat id（claimant），返每张牌的渲染 Slot：
#   { tile_id: int, rotated: bool, face_down: bool, stacked_above: bool }
#
# 公开 bundle nV 的顺序：先从 tiles 移除真正的 called_tile，再按
# relativeSource=(claimant-from+4)%4 插回：1→0、2→1、其余→末尾；
# chi 固定插到 0。Ankan index 1/2 盖牌。Added-kan 在 called tile 上叠牌。
#
# 纯算法层：无 Godot scene tree 依赖，GUT 单测全覆盖。

# 计算 Meld 的渲染 Slot 列表
static func compute(meld: Meld, claimant_seat: int) -> Array:
	match meld.kind:
		Meld.Kind.CHI:
			return _compute_open_meld(meld, claimant_seat)
		Meld.Kind.PON:
			return _compute_open_meld(meld, claimant_seat)
		Meld.Kind.MINKAN:
			return _compute_open_meld(meld, claimant_seat)
		Meld.Kind.ANKAN:
			return _compute_ankan(meld)
		Meld.Kind.ADDED_KAN:
			return _compute_open_meld(meld, claimant_seat)
	return []


static func _slot(tile: Tile, rotated: bool, stacked_above: bool = false) -> Dictionary:
	return {
		"tile_id": tile.id,
		"rotated": rotated,
		"face_down": false,
		"stacked_above": stacked_above,
		"is_red_dora": tile.is_red_dora,
	}


# nV 等价翻译。生产路径由 TurnEngine 写入精确 called_tile；null 仅兼容历史手工
# 构造的 Meld，沿用旧的 tiles[0] 约定，但不把该兼容分支视作参考等价。
static func _compute_open_meld(meld: Meld, claimant_seat: int) -> Array:
	if meld.tiles.is_empty():
		return []
	var called: Tile = meld.called_tile
	if called == null:
		called = meld.tiles[0]
	var called_index: int = meld.tiles.find(called)
	if called_index < 0:
		called_index = 0
		called = meld.tiles[0]
	var remaining: Array[Tile] = []
	for i in range(meld.tiles.size()):
		if i != called_index:
			remaining.append(meld.tiles[i])
	if meld.kind == Meld.Kind.ADDED_KAN and not remaining.is_empty():
		remaining.resize(remaining.size() - 1)
	var relative_source: int = (claimant_seat - meld.from_seat + 4) % 4
	var called_position: int
	if meld.kind == Meld.Kind.CHI or relative_source == 1:
		called_position = 0
	elif relative_source == 2:
		called_position = 1
	else:
		called_position = remaining.size()
	var slots: Array = []
	for tile in remaining:
		slots.append(_slot(tile, false))
	slots.insert(called_position, _slot(called, true))
	if meld.kind == Meld.Kind.ADDED_KAN:
		# rV 在 meld__stack 内再次渲染同一个 called tile。
		slots.append(_slot(called, true, true))
	return slots

# Ankan: bundle nV 固定第 1 / 第 2 张 face_down，无旋转牌。
static func _compute_ankan(meld: Meld) -> Array:
	var slots: Array = []
	for i in range(4):
		slots.append({
			"tile_id": meld.tiles[i].id,
			"rotated": false,
			"face_down": (i == 1 or i == 2),
			"stacked_above": false,
			"is_red_dora": meld.tiles[i].is_red_dora,
		})
	return slots
