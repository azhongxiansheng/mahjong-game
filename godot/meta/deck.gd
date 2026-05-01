class_name Deck extends RefCounted

# 麻将王 — 里程碑 5 第 1 步：玩家整 Run 卡组
#
# 持 Run 内累积的所有牌变体 + 角色能力。起始包注入 + 节点抽卡 + 卡包 + 商店
# 共同填充。
#
# spec §9.3：未填槽位用普通无技能牌补满；abilities 上限 5（spec §10/§14）。

const MAX_ABILITIES: int = 5

var tile_variants: Dictionary = {}  # TileId(int) → TileVariant
var abilities: Array = []           # Array[AbilityCard]

# ---- tile_variants ----

func add_tile_variant(variant: TileVariant) -> bool:
	if variant == null or variant.tile_id < 0:
		return false
	# 同 tile_id 已有变体时覆盖（v1 简化：玩家选择哪个 variant 留 M6）
	tile_variants[variant.tile_id] = variant
	return true

func remove_tile_variant(tile_id: int) -> bool:
	if not tile_variants.has(tile_id):
		return false
	tile_variants.erase(tile_id)
	return true

func has_tile_variant(tile_id: int) -> bool:
	return tile_variants.has(tile_id)

func get_tile_variant(tile_id: int) -> TileVariant:
	return tile_variants.get(tile_id)

func tile_variant_count() -> int:
	return tile_variants.size()

# ---- abilities ----

func add_ability(card: AbilityCard) -> bool:
	if card == null:
		return false
	if abilities.size() >= MAX_ABILITIES:
		return false  # 满槽拒绝；UI 应提示玩家先丢一张
	abilities.append(card)
	return true

func remove_ability(card_id: StringName) -> bool:
	for i in range(abilities.size()):
		if abilities[i].id == card_id:
			abilities.remove_at(i)
			return true
	return false

func has_ability(card_id: StringName) -> bool:
	for c in abilities:
		if c.id == card_id:
			return true
	return false

func ability_count() -> int:
	return abilities.size()

func ability_slots_remaining() -> int:
	return MAX_ABILITIES - abilities.size()
