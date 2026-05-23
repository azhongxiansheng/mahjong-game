class_name RelicItem extends RefCounted

# 遗物 — 整个 Run 持续生效的被动道具（不消耗）。
# 区别于 ConsumableItem（一次性）和 AbilityCard（角色能力）。

var id: StringName
var display_name: String
var description: String
var rarity: int = Rarity.Kind.UNCOMMON
var hook_resource_path: String = ""

func _init(p_id: StringName = &"", p_rarity: int = Rarity.Kind.UNCOMMON) -> void:
	id = p_id
	rarity = p_rarity

func summary() -> String:
	return "[%s 遗物] %s" % [Rarity.display_name(rarity), display_name if display_name != "" else String(id)]

func to_dict() -> Dictionary:
	return {
		"id": String(id),
		"display_name": display_name,
		"description": description,
		"rarity": rarity,
		"hook_resource_path": hook_resource_path,
	}

static func from_dict(d: Dictionary) -> RelicItem:
	if d == null or d.is_empty():
		return null
	var r := RelicItem.new(StringName(d.get("id", "")), int(d.get("rarity", Rarity.Kind.UNCOMMON)))
	r.display_name = d.get("display_name", "")
	r.description = d.get("description", "")
	r.hook_resource_path = d.get("hook_resource_path", "")
	return r
