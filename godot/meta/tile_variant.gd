class_name TileVariant extends RefCounted

# 麻将王 — 里程碑 5 第 1 步：单张麻将牌变体（spec §3.1 Variant）
#
# v1 占位结构。M6 内容生产时改为加载 .tres SkillResource 资源。
# skill_resource_path 留空 = 普通无技能牌。

var id: StringName
var display_name: String
var description: String
var tile_id: int = -1            # TileId 枚举值（0..33）
var rarity: int = Rarity.Kind.COMMON
var skill_resource_path: String = ""
var level: int = 0
var upgraded_skill_resource_path: String = ""  # M6 改为 SkillResource

func _init(p_id: StringName = &"", p_tile_id: int = -1, p_rarity: int = Rarity.Kind.COMMON) -> void:
	id = p_id
	tile_id = p_tile_id
	rarity = p_rarity

# 是否带技能（v1：看 skill_resource_path 非空；M6 改为看 .tres 是否存在）
func has_skill() -> bool:
	return skill_resource_path != ""

func is_upgraded() -> bool:
	return level >= 1

func active_hook_path() -> String:
	if level >= 1 and upgraded_skill_resource_path != "":
		return upgraded_skill_resource_path
	return skill_resource_path

func upgrade() -> bool:
	if level >= 1:
		return false
	level = 1
	return true

func summary() -> String:
	var rarity_str := Rarity.display_name(rarity)
	return "[%s] %s" % [rarity_str, display_name if display_name != "" else String(id)]

# ---- 序列化 ----

func to_dict() -> Dictionary:
	return {
		"id": String(id),
		"display_name": display_name,
		"description": description,
		"tile_id": tile_id,
		"rarity": rarity,
		"skill_resource_path": skill_resource_path,
		"level": level,
		"upgraded_skill_resource_path": upgraded_skill_resource_path,
	}

static func from_dict(d: Dictionary) -> TileVariant:
	if d == null or d.is_empty():
		return null
	var v := TileVariant.new(StringName(d.get("id", "")), int(d.get("tile_id", -1)), int(d.get("rarity", Rarity.Kind.COMMON)))
	v.display_name = d.get("display_name", "")
	v.description = d.get("description", "")
	v.skill_resource_path = d.get("skill_resource_path", "")
	v.level = int(d.get("level", 0))
	v.upgraded_skill_resource_path = d.get("upgraded_skill_resource_path", "")
	return v
