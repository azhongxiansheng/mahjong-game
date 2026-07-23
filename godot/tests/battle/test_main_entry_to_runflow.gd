extends GutTest

# 历史名保留：原「主入口 → RunFlow」断言。
# E1-01 (#225) 后生产入口改为大厅壳；RunFlow 仅作 legacy 可实例化场景保留。
#
# loading_screen / main_scene 导航契约以 tests/ui/test_lobby_shell.gd 为准。

func test_loading_screen_does_not_target_run_flow():
	var script: GDScript = load("res://scripts/loading_screen.gd")
	assert_not_null(script, "loading_screen.gd 应存在")
	var source: String = script.source_code
	assert_false(
		source.contains("run_flow.tscn"),
		"loading_screen 不得再跳转到 run_flow.tscn（生产入口是大厅壳）"
	)
	assert_false(
		source.contains("main_simple_new.tscn"),
		"loading_screen 不应跳转到遗留 main_simple_new.tscn"
	)

func test_run_flow_scene_exists():
	var scene: PackedScene = load("res://ui/run/run_flow.tscn")
	assert_not_null(scene, "run_flow.tscn 场景文件应存在（legacy / GUT 显式实例化）")

func test_run_flow_scene_instantiates():
	var scene: PackedScene = load("res://ui/run/run_flow.tscn")
	assert_not_null(scene)
	var node: Node = scene.instantiate()
	assert_not_null(node, "run_flow.tscn 应能实例化")
	assert_true(node is RunFlow, "根节点应是 RunFlow 类")
	node.queue_free()
