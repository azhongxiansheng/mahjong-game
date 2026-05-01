class_name MeldFu

# 日麻面子符表：
#                中张   幺九/字
#   顺子          0       0
#   明刻          2       4
#   暗刻          4       8
#   明杠          8      16
#   暗杠         16      32

# 来自 StandardDecomposer 输出的 meld 数组（[a,a,a] 或 [a,a+1,a+2]）
# is_concealed: 该刻子是否暗刻。顺子忽略此参数（恒 0）
static func fu_for_decomp_meld(meld_ids: Array, is_concealed: bool) -> int:
	if meld_ids.size() != 3:
		return 0
	# 顺子：3 张连续不同
	if meld_ids[0] != meld_ids[1]:
		return 0
	# 刻子
	var is_yaochu := TileId.is_yaochu(meld_ids[0])
	return _triplet_fu(is_yaochu, is_concealed, false)

# 来自副露 Meld 对象（CHI/PON/MINKAN/ANKAN/ADDED_KAN）
static func fu_for_called_meld(meld: Meld) -> int:
	match meld.kind:
		Meld.Kind.CHI:
			return 0
		Meld.Kind.PON:
			return _triplet_fu(_meld_is_yaochu(meld), false, false)
		Meld.Kind.MINKAN, Meld.Kind.ADDED_KAN:
			# 加杠按明杠计（标准日麻）
			return _triplet_fu(_meld_is_yaochu(meld), false, true)
		Meld.Kind.ANKAN:
			return _triplet_fu(_meld_is_yaochu(meld), true, true)
	return 0

static func _triplet_fu(is_yaochu: bool, is_concealed: bool, is_kan: bool) -> int:
	# 基础矩阵：明刻 2、暗刻 4、明杠 8、暗杠 16；幺九 ×2
	var base := 2
	if is_concealed:
		base *= 2
	if is_kan:
		base *= 4  # 杠相对于刻子 ×4（明杠 8、暗杠 16）
	if is_yaochu:
		base *= 2
	return base

static func _meld_is_yaochu(meld: Meld) -> bool:
	if meld.tiles.size() == 0:
		return false
	return TileId.is_yaochu(meld.tiles[0].id)
