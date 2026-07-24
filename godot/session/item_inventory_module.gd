class_name ItemInventoryModule extends RefCounted

# E2-04：欢乐场道具库存生产模块（最小对象）。
# 不实现 E5 发奖 / 消耗 / 使用业务；仅占构造期隔离位。

var _instances: Array = []


func instance_count() -> int:
	return _instances.size()


func all_instances() -> Array:
	return _instances.duplicate()
