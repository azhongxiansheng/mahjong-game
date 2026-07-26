extends SceneTree

# #257：编辑器 / 带 --script 能力的入口。导出 release app 无 -s，走 GameManager 环境变量门闩。


func _initialize() -> void:
	var runner: Node = load("res://tools/e7_257_model_smoke_runner.gd").new()
	root.add_child(runner)
