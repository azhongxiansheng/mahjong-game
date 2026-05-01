class_name AbilityCard extends RefCounted

# 麻将王 — 里程碑 5 第 1 步：角色能力卡（spec §3.1 角色能力 + §10）
#
# v1 占位；M6 内容生产时填具体 hook + 立绘等。

var id: StringName
var display_name: String
var description: String
var rarity: int = Rarity.Kind.COMMON
var hook_resource_path: String = ""  # M6 改为 SkillHook 子类路径

func _init(p_id: StringName = &"", p_rarity: int = Rarity.Kind.COMMON) -> void:
	id = p_id
	rarity = p_rarity

func summary() -> String:
	var rarity_str := Rarity.display_name(rarity)
	return "[%s 角色能力] %s" % [rarity_str, display_name if display_name != "" else String(id)]
