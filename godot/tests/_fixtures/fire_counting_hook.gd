class_name FireCountingHook extends SkillHook

# 麻将王 — M8.5 假设 O 验证 fixture：纯计数 hook。
# 每次 on_event 触发 → fire_count += 1。用来给 sim 验证某 trigger 类型在
# 真实对局中实际 fire 次数（vs 设计期望）。

var fire_count: int = 0
var fired_event_types: Array[StringName] = []

func on_event(_skill: SkillResource, event: BattleEvent, _ctx: SkillCtx) -> void:
	fire_count += 1
	fired_event_types.append(event.type)
