class_name ConsumableItem extends RefCounted

enum Kind {
	BATTLE,
	RUN,
}

var id: StringName
var display_name: String
var description: String
var rarity: int = Rarity.Kind.COMMON
var kind: int = Kind.BATTLE
var hook_resource_path: String = ""
var icon_path: String = ""  # 可选；空则 UI 走 default_icon_path

func _init(p_id: StringName = &"", p_kind: int = Kind.BATTLE, p_rarity: int = Rarity.Kind.COMMON) -> void:
	id = p_id
	kind = p_kind
	rarity = p_rarity

func is_battle() -> bool:
	return kind == Kind.BATTLE

func is_run() -> bool:
	return kind == Kind.RUN

func summary() -> String:
	var rarity_str := Rarity.display_name(rarity)
	var kind_str := "战斗" if kind == Kind.BATTLE else "旅途"
	return "[%s %s道具] %s" % [rarity_str, kind_str, display_name if display_name != "" else String(id)]

func resolved_icon_path() -> String:
	if icon_path != "" and ResourceLoader.exists(icon_path):
		return icon_path
	return default_icon_path(id)

func to_dict() -> Dictionary:
	return {
		"id": String(id),
		"display_name": display_name,
		"description": description,
		"rarity": rarity,
		"kind": kind,
		"hook_resource_path": hook_resource_path,
		"icon_path": icon_path,
	}

static func from_dict(d: Dictionary) -> ConsumableItem:
	if d == null or d.is_empty():
		return null
	var c := ConsumableItem.new(
		StringName(d.get("id", "")),
		int(d.get("kind", Kind.BATTLE)),
		int(d.get("rarity", Rarity.Kind.COMMON))
	)
	c.display_name = d.get("display_name", "")
	c.description = d.get("description", "")
	c.hook_resource_path = d.get("hook_resource_path", "")
	c.icon_path = d.get("icon_path", "")
	return c

# 池 id 常为 wall_peek_v1，磁盘文件为 consumable_wall_peek.png
static func default_icon_path(item_id: StringName) -> String:
	var base := String(item_id)
	if base.ends_with("_v1"):
		base = base.substr(0, base.length() - 3)
	var candidates: Array[String] = [
		"res://assets/roguelike/consumables/%s.png" % base,
		"res://assets/roguelike/consumables/consumable_%s.png" % base,
	]
	for path in candidates:
		if ResourceLoader.exists(path):
			return path
	return ""
