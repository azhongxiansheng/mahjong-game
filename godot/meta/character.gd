class_name Character extends RefCounted

# 可选角色：生产契约保留 id / 显示名 / 人设 / ability 映射 / 立绘 / Momentum affinity。
# starting_hp / gold / pack / unlock_renown 仍可由 legacy Run 读取，不进新生产契约。

var id: StringName
var display_name: String
var description: String
var ability_id: StringName = &""
var starting_hp: int = 5
var starting_gold: int = 0
var recommended_pack: StringName = &""
var unlock_renown: int = 0
var portrait_path: String = ""
var affinity_primary: StringName = &""
var affinity_secondary: StringName = &""

func _init(p_id: StringName = &"") -> void:
	id = p_id

func is_unlocked(renown: int) -> bool:
	return renown >= unlock_renown

# 五类 affinity 唯一真源：Momentum.Attribute.keys()（定义顺序即序列化键顺序）
static func affinity_keys() -> Array[StringName]:
	var keys: Array[StringName] = []
	for name in Momentum.Attribute.keys():
		keys.append(StringName(name))
	return keys

static func is_valid_affinity(raw: StringName) -> bool:
	if raw == &"":
		return false
	return affinity_keys().has(raw)

# 归一化：接受 Momentum.Attribute 枚举 int、大小写字符串；非法 → 空
static func normalize_affinity(raw: Variant) -> StringName:
	if raw == null:
		return &""
	var keys: Array[StringName] = affinity_keys()
	if typeof(raw) == TYPE_INT:
		var idx: int = int(raw)
		if idx >= 0 and idx < keys.size():
			return keys[idx]
		return &""
	var s := String(raw).strip_edges().to_upper()
	if s.is_empty():
		return &""
	var key := StringName(s)
	if keys.has(key):
		return key
	return &""

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
		"portrait_path": portrait_path,
		"affinity_primary": String(normalize_affinity(affinity_primary)),
		"affinity_secondary": String(normalize_affinity(affinity_secondary)),
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
	c.portrait_path = String(d.get("portrait_path", ""))
	c.affinity_primary = normalize_affinity(d.get("affinity_primary", ""))
	c.affinity_secondary = normalize_affinity(d.get("affinity_secondary", ""))
	return c
