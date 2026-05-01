class_name FuritenState

# 一座位的振听状态（spec §5）。
# permanent / temporary 标志由调用方根据上下文设置（FuritenChecker 提供判定基元）。

var permanent: bool = false
var temporary: bool = false
var waits: Array = []

func is_furiten() -> bool:
	return permanent or temporary

func clear_temporary() -> void:
	temporary = false

func update_waits(new_waits: Array) -> void:
	waits = new_waits
