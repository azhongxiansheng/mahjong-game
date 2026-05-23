class_name Rarity

# 麻将王 — 里程碑 5 第 1 步：稀有度（spec §9.1）
#
# 4 档 + 单抽概率分布。其它渠道（卡包 / 商店）按各自规则覆盖。

enum Kind {
	COMMON = 0,    # 普通 60%
	UNCOMMON = 1,  # 精良 28%
	EPIC = 2,      # 史诗 10%
	LEGENDARY = 3, # 神话 2%
}

const COUNT: int = 4

# 单抽概率（spec §9.1）。索引对应 Kind 值。
const NODE_SINGLE_WEIGHTS: Array = [60.0, 28.0, 10.0, 2.0]

# 卡包"精良+ 池子"权重（保底用）：仅取 UNCOMMON 以上
const PACK_GUARANTEE_WEIGHTS: Array = [0.0, 70.0, 25.0, 5.0]

static func display_name(rarity: int) -> String:
	match rarity:
		Kind.COMMON: return "普通"
		Kind.UNCOMMON: return "精良"
		Kind.EPIC: return "史诗"
		Kind.LEGENDARY: return "神话"
	return "?"

# 稀有度色(卡框/印章 共用,spec §9.1):灰/蓝/紫/金。
# UI(TileStamp / ShopView / PackOpenView 等)统一调此入口避免颜色漂移。
static func color(rarity: int) -> Color:
	match rarity:
		Kind.COMMON:    return Color(0.55, 0.55, 0.55)
		Kind.UNCOMMON:  return Color(0.30, 0.55, 0.85)
		Kind.EPIC:      return Color(0.65, 0.30, 0.85)
		Kind.LEGENDARY: return Color(1.00, 0.80, 0.20)
	return Color(0.40, 0.40, 0.40)

static func is_epic_or_above(rarity: int) -> bool:
	return rarity >= Kind.EPIC

# 按权重在 [Kind.COMMON .. Kind.LEGENDARY] 之间随机一档。
# weights 数组长度必须 == COUNT；否则用默认 NODE_SINGLE_WEIGHTS。
static func pick_weighted(weights: Array, rng: RandomNumberGenerator) -> int:
	var w: Array = weights if weights.size() == COUNT else NODE_SINGLE_WEIGHTS
	var total := 0.0
	for v in w:
		total += float(v)
	if total <= 0:
		return Kind.COMMON
	var roll: float = rng.randf() * total
	var acc := 0.0
	for i in range(w.size()):
		acc += float(w[i])
		if roll <= acc:
			return i
	return Kind.LEGENDARY
