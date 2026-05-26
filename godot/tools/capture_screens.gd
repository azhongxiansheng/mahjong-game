extends SceneTree

# 一次性视觉验证工具：实例化 run-flow / 战斗桌场景，渲染若干帧后把视口
# 截图存到 /tmp，供人工核对新资产 + Akagi 主题的实际渲染效果。
#
# 跑法（必须带窗口渲染，不能 --headless）：
#   godot --path godot -s tools/capture_screens.gd

const SHOTS := [
	["res://ui/run/starter_pack_picker.tscn", "starter_picker"],
	["res://ui/run/character_picker.tscn", "character_picker"],
	["res://ui/run/continue_prompt.tscn", "continue_prompt"],
	["res://ui/run/chapter_map_view.tscn", "chapter_map"],
	["res://ui/run/pack_open_view.tscn", "pack_open_view"],
	["res://ui/run/shop_view.tscn", "shop_view"],
	["res://ui/run/event_node.tscn", "event_node"],
	["res://ui/run/camp_node.tscn", "camp_node"],
	["res://ui/run/placeholder_node.tscn", "placeholder_node"],
	["res://ui/run/run_summary.tscn", "run_summary"],
	["res://ui/run/run_hud.tscn", "run_hud"],
	["res://ui/four_player_table/four_player_table.tscn", "four_player_table"],
]


func _initialize() -> void:
	_run()


func _run() -> void:
	# 1280x800 让截图够大看清 UI (默认 1152x648 太挤)
	root.content_scale_size = Vector2i(1280, 800)
	DisplayServer.window_set_size(Vector2i(1280, 800))
	await process_frame
	await process_frame
	for entry in SHOTS:
		var scene_path: String = entry[0]
		var tag: String = entry[1]
		var packed := load(scene_path) as PackedScene
		if packed == null:
			print("[capture] cannot load ", scene_path)
			continue
		var inst := packed.instantiate()
		root.add_child(inst)
		for _i in range(40):
			await process_frame
		var img := root.get_texture().get_image()
		var out := "/tmp/shot_%s.png" % tag
		img.save_png(out)
		print("[capture] saved ", out)
		inst.queue_free()
		await process_frame
	# 额外:一张「带牌局的战斗桌」截图,真实绑定 BattleState 让 38 张麻将牌、
	# dealer 标记、当前回合金边、座位分数都一起亮相,证明对战可玩。
	await _capture_battle_with_state()
	print("[capture] done")
	quit()


func _capture_battle_with_state() -> void:
	var packed := load("res://ui/four_player_table/four_player_table.tscn") as PackedScene
	if packed == null:
		return
	var table = packed.instantiate()
	root.add_child(table)
	# BattleController 跑一个确定 seed 起手,state 立刻有 4 家 13 张手牌 + 庄家
	var bc := BattleController.new(42, 0, false, TileId.E)
	# bind 桌面到这个 state,seat 0 可见手牌、dora 指示牌、立直棒 0、当前 seat 高亮
	table.bind_battle_state(bc.state, 0, 4)
	for _i in range(40):
		await process_frame
	var img := root.get_texture().get_image()
	var out := "/tmp/shot_battle_live.png"
	img.save_png(out)
	print("[capture] saved ", out)
	table.queue_free()
	await process_frame
