class_name AbilityCard extends RefCounted

# 麻将王 — 里程碑 5 第 1 步：角色能力卡（spec §3.1 角色能力 + §10）
#
# v1 占位；M6 内容生产时填具体 hook + 立绘等。

var id: StringName
var display_name: String
var description: String
var rarity: int = Rarity.Kind.COMMON
var hook_resource_path: String = ""  # M6 改为 SkillHook 子类路径
var icon_path: String = ""  # 可选；多数能力暂无独立图标

func _init(p_id: StringName = &"", p_rarity: int = Rarity.Kind.COMMON) -> void:
	id = p_id
	rarity = p_rarity

func summary() -> String:
	var rarity_str := Rarity.display_name(rarity)
	return "[%s 角色能力] %s" % [rarity_str, display_name if display_name != "" else String(id)]

func resolved_icon_path() -> String:
	if icon_path != "" and ResourceLoader.exists(icon_path):
		return icon_path
	return ""

# ---- 序列化 ----

func to_dict() -> Dictionary:
	return {
		"id": String(id),
		"display_name": display_name,
		"description": description,
		"rarity": rarity,
		"hook_resource_path": hook_resource_path,
		"icon_path": icon_path,
	}

static func from_dict(d: Dictionary) -> AbilityCard:
	if d == null or d.is_empty():
		return null
	var a := AbilityCard.new(StringName(d.get("id", "")), int(d.get("rarity", Rarity.Kind.COMMON)))
	a.display_name = d.get("display_name", "")
	a.description = d.get("description", "")
	a.hook_resource_path = d.get("hook_resource_path", "")
	a.icon_path = d.get("icon_path", "")
	return a
