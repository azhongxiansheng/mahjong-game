class_name GachaResult extends RefCounted

# 麻将王 — 里程碑 5 第 1 步：单次抽卡结果

const KIND_TILE: StringName = &"tile"
const KIND_ABILITY: StringName = &"ability"
const KIND_CONSUMABLE: StringName = &"consumable"

var kind: StringName = KIND_TILE
var tile_variant: TileVariant = null
var ability: AbilityCard = null
var consumable: ConsumableItem = null
var rarity: int = Rarity.Kind.COMMON

static func make_tile(variant: TileVariant) -> GachaResult:
	var r := GachaResult.new()
	r.kind = KIND_TILE
	r.tile_variant = variant
	r.rarity = variant.rarity if variant else Rarity.Kind.COMMON
	return r

static func make_ability(card: AbilityCard) -> GachaResult:
	var r := GachaResult.new()
	r.kind = KIND_ABILITY
	r.ability = card
	r.rarity = card.rarity if card else Rarity.Kind.COMMON
	return r

static func make_consumable(item: ConsumableItem) -> GachaResult:
	var r := GachaResult.new()
	r.kind = KIND_CONSUMABLE
	r.consumable = item
	r.rarity = item.rarity if item else Rarity.Kind.COMMON
	return r

func summary() -> String:
	if kind == KIND_TILE and tile_variant:
		return tile_variant.summary()
	if kind == KIND_ABILITY and ability:
		return ability.summary()
	if kind == KIND_CONSUMABLE and consumable:
		return consumable.summary()
	return "(空 GachaResult)"
