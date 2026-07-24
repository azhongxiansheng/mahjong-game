class_name SnapshotModuleProvider
extends RefCounted

# #241：快照模块 provider 稳定接口。
# serialize 仅 Worker/权威侧；can_restore / stage_restore / commit_restore 仅客户端投影侧。
# 组合器不得读取、推导或改写模块业务 payload。
# 两阶段：stage 无副作用 → 全部成功后 commit；commit 失败由 registry 回滚 target。


func module_key() -> String:
	return ""


func schema_version() -> int:
	return 1


func is_required() -> bool:
	return false


## 权威侧：按座位裁剪序列化。成功返回 payload（Dictionary 或 JSON-safe 值）；失败返回 null。
func serialize(_ctx: Dictionary, _seat: int) -> Variant:
	return null


## 客户端：预检，不得产生副作用。false → 整份快照拒绝。
func can_restore(_payload: Variant, _seat: int) -> bool:
	return false


## 阶段 1：纯 staging，不得写 target。成功返回 staged 值；失败 null。
func stage_restore(payload: Variant, seat: int) -> Variant:
	if not can_restore(payload, seat):
		return null
	if typeof(payload) == TYPE_DICTIONARY:
		return (payload as Dictionary).duplicate(true)
	return payload


## 阶段 2：把 staged 写入 target。false → registry 回滚 target。
func commit_restore(staged: Variant, seat: int, target: Object) -> bool:
	return restore(staged, seat, target)


## 兼容入口：默认等同 stage+commit 单步（registry 优先走两阶段）。
func restore(_payload: Variant, _seat: int, _target: Object) -> bool:
	return false
