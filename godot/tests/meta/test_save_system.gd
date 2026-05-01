extends GutTest

# 麻将王 — M4 第 2 步：SaveSystem autoload 占位单测
#
# 仅验证 4 个 API 不抛错且返回值符合占位契约。M5 实装真持久化时这些
# 测试会被替换为实际行为验证。

# 注：SaveSystem 是 autoload，全局可访问；这里通过 /root 节点拿
func _save_system() -> Node:
	return get_tree().root.get_node_or_null("SaveSystem")

func test_save_system_is_autoload():
	assert_not_null(_save_system(), "SaveSystem 应注册为 autoload (在 project.godot)")

func test_has_save_returns_false_in_v1():
	assert_false(_save_system().has_save(), "v1 总是没存档")

func test_save_run_returns_ok_without_throwing():
	# 占位：调用不抛错，返回 OK
	var result: int = _save_system().save_run(null)
	assert_eq(result, OK)

func test_load_run_returns_null_in_v1():
	assert_null(_save_system().load_run())

func test_clear_run_does_not_throw():
	# 占位：调用不抛错
	_save_system().clear_run()
	assert_true(true, "clear_run 不抛错")
