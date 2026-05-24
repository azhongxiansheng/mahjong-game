class_name Character extends RefCounted

# 麻将王 — 可选角色（肉鸽核心重玩性）
#
# 每个角色：
#   - 独特被动能力（ability_id → 每局自动注入 registry）
#   - 起始 HP / gold 差异
#   - 推荐起始包（UI 提示，不强制）
#   - 解锁条件（meta 进度）

var id: StringName
var display_name: String
var description: String
var ability_id: StringName = &""
var starting_hp: int = 5
var starting_gold: int = 0
var recommended_pack: StringName = &""
var unlock_renown: int = 0
var portrait_path: String = ""

func _init(p_id: StringName = &"") -> void:
	id = p_id

func is_unlocked(renown: int) -> bool:
	return renown >= unlock_renown

func to_dict() -> Dictionary:
	return {
		"id": String(id),
		"display_name": display_name,
		"description": description,
		"ability_id": String(ability_id),
		"starting_hp": starting_hp,
		"starting_gold": starting_gold,
		"recommended_pack": String(recommended_pack),
		"unlock_renown": unlock_renown,
	}

static func from_dict(d: Dictionary) -> Character:
	if d == null or d.is_empty():
		return null
	var c := Character.new(StringName(d.get("id", "")))
	c.display_name = d.get("display_name", "")
	c.description = d.get("description", "")
	c.ability_id = StringName(d.get("ability_id", ""))
	c.starting_hp = int(d.get("starting_hp", 5))
	c.starting_gold = int(d.get("starting_gold", 0))
	c.recommended_pack = StringName(d.get("recommended_pack", ""))
	c.unlock_renown = int(d.get("unlock_renown", 0))
	return c
