class_name Gacha

# 麻将王 — 里程碑 5 第 1 步：抽卡核心（spec §9.2 三渠道 + plan-5 D2/D3）
#
# 三个 v1 静态 API：
#   draw_node_single(pity, seed) → GachaResult
#     节点单抽：1 张牌或角色能力（90% 牌 / 10% ability v1 简化）；保底激活时
#     强制走 EPIC+ 池子。
#   open_pack(theme, seed) → Array[GachaResult] (size = PACK_SIZE)
#     卡包：5 张牌；最后 1 张强制 UNCOMMON+（包内保底）。
#   refresh_shop(seed) → Array[GachaResult] (size = SHOP_SLOT_COUNT)
#     商店刷新：4 槽明牌；3 张牌 + 1 张 ability（v1 简化）；无保底。

const SHOP_SLOT_COUNT: int = 5
const NODE_SINGLE_ABILITY_PROBABILITY: float = 0.10
const SHOP_ABILITY_SLOT_COUNT: int = 1
const SHOP_CONSUMABLE_SLOT_COUNT: int = 1

# ---- 节点单抽 ----

# pity 是 PityState 实例；调用方负责在调用前后维护。
# 内部会读 pity.node_single_pity_active() 决定是否走 EPIC+ 池子。
static func draw_node_single(pity: PityState, seed: int) -> GachaResult:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	# 90% 牌 / 10% ability
	var is_ability: bool = rng.randf() < NODE_SINGLE_ABILITY_PROBABILITY
	var rarity: int

	if pity.node_single_pity_active():
		# 强制 EPIC+：用卡包保底权重（仅 UNCOMMON 以上）但只取 EPIC/LEG
		rarity = _pick_epic_or_above(rng)
	else:
		rarity = Rarity.pick_weighted(Rarity.NODE_SINGLE_WEIGHTS, rng)

	var result: GachaResult
	if is_ability:
		result = _draw_ability(rarity, rng)
	else:
		result = _draw_tile(rarity, rng)
	return result

# ---- 卡包 ----

static func open_pack(theme: int, seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var results: Array = []
	var theme_weights := CardPack.rarity_weights_for_theme(theme)
	for i in range(CardPack.PACK_SIZE):
		var rarity: int
		if i == CardPack.GUARANTEE_INDEX:
			# 包内保底：最后 1 张强制 UNCOMMON+
			rarity = Rarity.pick_weighted(Rarity.PACK_GUARANTEE_WEIGHTS, rng)
		else:
			rarity = Rarity.pick_weighted(theme_weights, rng)
		results.append(_draw_tile(rarity, rng))
	return results

# ---- 商店 4 槽 ----

static func refresh_shop(seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var results: Array = []
	var tile_slots: int = SHOP_SLOT_COUNT - SHOP_ABILITY_SLOT_COUNT - SHOP_CONSUMABLE_SLOT_COUNT
	for i in range(tile_slots):
		var rarity: int = Rarity.pick_weighted(Rarity.NODE_SINGLE_WEIGHTS, rng)
		results.append(_draw_tile(rarity, rng))
	for i in range(SHOP_ABILITY_SLOT_COUNT):
		var rarity_a: int = Rarity.pick_weighted(Rarity.NODE_SINGLE_WEIGHTS, rng)
		results.append(_draw_ability(rarity_a, rng))
	for i in range(SHOP_CONSUMABLE_SLOT_COUNT):
		results.append(_draw_consumable(rng))
	return results

# ---- internal helpers ----

static func _pick_epic_or_above(rng: RandomNumberGenerator) -> int:
	# 仅在 EPIC / LEGENDARY 之间分配（NODE_SINGLE_WEIGHTS 比例 10:2 = 5:1）
	var roll := rng.randf()
	# 史诗 vs 神话 = 10/(10+2) = 0.833
	if roll < 10.0 / 12.0:
		return Rarity.Kind.EPIC
	return Rarity.Kind.LEGENDARY

static func _draw_tile(rarity: int, rng: RandomNumberGenerator) -> GachaResult:
	var pool: Array = CardPool.tile_variants_by_rarity(rarity)
	if pool.size() == 0:
		# 兜底：该 rarity 池子空 → 降到 COMMON（v1 占位池子保证至少 COMMON 有内容）
		pool = CardPool.tile_variants_by_rarity(Rarity.Kind.COMMON)
	if pool.size() == 0:
		return GachaResult.new()
	var idx: int = rng.randi_range(0, pool.size() - 1)
	return GachaResult.make_tile(pool[idx])

static func _draw_consumable(rng: RandomNumberGenerator) -> GachaResult:
	var pool: Array = CardPool.all_consumables()
	if pool.size() == 0:
		return GachaResult.new()
	var idx: int = rng.randi_range(0, pool.size() - 1)
	return GachaResult.make_consumable(pool[idx])

static func _draw_ability(rarity: int, rng: RandomNumberGenerator) -> GachaResult:
	var pool: Array = CardPool.abilities_by_rarity(rarity)
	if pool.size() == 0:
		# 兜底降级
		for r in [Rarity.Kind.COMMON, Rarity.Kind.UNCOMMON, Rarity.Kind.EPIC, Rarity.Kind.LEGENDARY]:
			pool = CardPool.abilities_by_rarity(r)
			if pool.size() > 0:
				break
	if pool.size() == 0:
		return GachaResult.new()
	var idx: int = rng.randi_range(0, pool.size() - 1)
	return GachaResult.make_ability(pool[idx])
