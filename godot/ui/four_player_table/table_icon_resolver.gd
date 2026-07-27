extends RefCounted

# Issue #326：牌桌 HUD 唯一稳定 ID → 原创图标映射。

const UNKNOWN_ICON := "res://assets/ui/table_hud/chrome/icon_unknown_seal.png"
const INVENTORY_ICON := "res://assets/ui/table_hud/chrome/icon_inventory_omamori.png"

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
	var definition := ItemCatalog.definition(StringName(item_id))
	if definition == null or definition.table_icon_path.is_empty():
		push_warning("未知牌桌道具图标 ID：%s" % item_id)
		return UNKNOWN_ICON
	return definition.table_icon_path


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
