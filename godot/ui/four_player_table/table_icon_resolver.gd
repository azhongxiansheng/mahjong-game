extends RefCounted

# Issue #326：牌桌 HUD 唯一稳定 ID → 原创图标映射。

const UNKNOWN_ICON := "res://assets/ui/table_hud/chrome/icon_unknown_seal.png"
const INVENTORY_ICON := "res://assets/ui/table_hud/chrome/icon_inventory_omamori.png"

const ITEM_ICONS := {
	"iron_shield_v1": "item_iron_shield.png",
	"wall_peek_v1": "item_wall_peek.png",
	"dora_charm_v1": "item_dora_charm.png",
	"furiten_bomb_v1": "item_furiten_bomb.png",
	"double_payout_v1": "item_double_payout.png",
	"wall_collapse_v1": "item_wall_collapse.png",
	"dora_flip_v1": "item_dora_flip.png",
	"seat_swap_v1": "item_seat_swap.png",
	"point_shield_v1": "item_point_shield.png",
	"tsubame_v1": "item_tsubame.png",
	"relic_lucky_cat_v1": "item_relic_lucky_cat.png",
	"relic_iron_will_v1": "item_relic_iron_will.png",
	"relic_soul_mirror_v1": "item_relic_soul_mirror.png",
	"relic_wall_eye_v1": "item_relic_wall_eye.png",
	"relic_red_string_v1": "item_relic_red_string.png",
	"relic_dragon_seal_v1": "item_relic_dragon_seal.png",
	"relic_wind_charm_v1": "item_relic_wind_charm.png",
	"relic_speed_demon_v1": "item_relic_speed_demon.png",
	"relic_patience_stone_v1": "item_relic_patience_stone.png",
	"relic_han_crystal_v1": "item_relic_han_crystal.png",
	"relic_comeback_crown_v1": "item_relic_comeback_crown.png",
}

const ABILITY_ICONS := {
	"char_akagi_passive_v1": "ability_char_akagi_passive.png",
	"char_kaiji_passive_v1": "ability_char_kaiji_passive.png",
	"char_washizu_passive_v1": "ability_char_washizu_passive.png",
	"char_saki_passive_v1": "ability_char_saki_passive.png",
	"char_teru_passive_v1": "ability_char_teru_passive.png",
	"char_awai_passive_v1": "ability_char_awai_passive.png",
	"char_koromo_passive_v1": "ability_char_koromo_passive.png",
	"char_nodoka_passive_v1": "ability_char_nodoka_passive.png",
	"char_toki_passive_v1": "ability_char_toki_passive.png",
	"char_kuro_passive_v1": "ability_char_kuro_passive.png",
	"char_momoko_passive_v1": "ability_char_momoko_passive.png",
	"char_tetsuya_passive_v1": "ability_char_tetsuya_passive.png",
}

const AFFINITY_ICONS := {
	"CALM": "icon_affinity_calm.png",
	"CUNNING": "icon_affinity_cunning.png",
	"DOMINATION": "icon_affinity_domination.png",
	"MYSTIC": "icon_affinity_mystic.png",
	"PASSION": "icon_affinity_passion.png",
}


static func item_icon_path(item_id: String) -> String:
	var file_name := String(ITEM_ICONS.get(item_id, ""))
	if file_name.is_empty():
		push_warning("未知牌桌道具图标 ID：%s" % item_id)
		return UNKNOWN_ICON
	return "res://assets/ui/table_hud/items/%s" % file_name


static func ability_icon_path(ability_id: String) -> String:
	var file_name := String(ABILITY_ICONS.get(ability_id, ""))
	if file_name.is_empty():
		push_warning("未知牌桌技能图标 ID：%s" % ability_id)
		return UNKNOWN_ICON
	return "res://assets/ui/table_hud/abilities/%s" % file_name


static func affinity_icon_path(affinity: String) -> String:
	var file_name := String(AFFINITY_ICONS.get(affinity.to_upper(), ""))
	if file_name.is_empty():
		return UNKNOWN_ICON
	return "res://assets/ui/table_hud/chrome/%s" % file_name


static func texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	push_error("牌桌 HUD 图标不可加载：%s" % path)
	return load(UNKNOWN_ICON) as Texture2D
