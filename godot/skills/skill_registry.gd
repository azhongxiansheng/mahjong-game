class_name SkillRegistry

# 内部 entry: {skill, anchor, hook, reg_order}
# anchor:
#   - is_ability=false 时:  TileInstance(scheduler 通过 anchor.owner_seat / anchor.holder_seat 派发)
#   - is_ability=true  时:  int(座位号 0..3,owner==holder==此座位)
var _entries: Array = []
var _next_order: int = 0

func register(skill: SkillResource, anchor: Variant) -> void:
	var hook = null
	if skill.hook_script != null:
		hook = skill.hook_script.new()
		if hook is SkillHook:
			hook.on_register(skill, self)
	_entries.append({
		"skill": skill,
		"anchor": anchor,
		"hook": hook,
		"reg_order": _next_order,
	})
	_next_order += 1

func unregister(skill: SkillResource, anchor: Variant) -> void:
	for i in range(_entries.size()):
		var e = _entries[i]
		if e.skill == skill and e.anchor == anchor:
			_entries.remove_at(i)
			return

func get_all_entries() -> Array:
	return _entries.duplicate()
