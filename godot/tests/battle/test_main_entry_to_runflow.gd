extends GutTest

# 麻将王 — 验证主入口通往 RunFlow（不走遗留 main_simple）
#
# loading_screen.gd 应 change_scene 到 run_flow.tscn。
# 这里验证脚本源码中的跳转路径（静态解析，不需要实际跑场景）。

func test_loading_screen_targets_run_flow():
	var script: GDScript = load("res://scripts/loading_screen.gd")
	assert_not_null(script, "loading_screen.gd 应存在")
	var source: String = script.source_code
	assert_true(
		source.contains("run_flow.tscn"),
		"loading_screen 应跳转到 run_flow.tscn"
	)
	assert_false(
		source.contains("main_simple_new.tscn"),
		"loading_screen 不应跳转到遗留 main_simple_new.tscn"
	)

func test_run_flow_scene_exists():
	var scene: PackedScene = load("res://ui/run/run_flow.tscn")
	assert_not_null(scene, "run_flow.tscn 场景文件应存在")

func test_run_flow_scene_instantiates():
	var scene: PackedScene = load("res://ui/run/run_flow.tscn")
	assert_not_null(scene)
	var node: Node = scene.instantiate()
	assert_not_null(node, "run_flow.tscn 应能实例化")
	assert_true(node is RunFlow, "根节点应是 RunFlow 类")
	node.queue_free()
