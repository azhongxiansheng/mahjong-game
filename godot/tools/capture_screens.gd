extends SceneTree

# 一次性视觉验证工具：实例化 run-flow / 战斗桌场景，渲染若干帧后把视口
# 截图存到 /tmp，供人工核对新资产与牌桌渲染效果。
#
# 跑法（必须带窗口渲染，不能 --headless）：
#   godot --path godot -s tools/capture_screens.gd

const SHOTS := [
	["res://ui/lobby/lobby_shell.tscn", "lobby_shell"],
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
const CAPTURE_SIZE := Vector2i(1600, 900)


func _initialize() -> void:
	_run()


func _run() -> void:
	# 与参考站固定 stage 同尺寸，截图直接核对设计基准。
	root.content_scale_size = CAPTURE_SIZE
	DisplayServer.window_set_size(CAPTURE_SIZE)
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
	# 走 PlayableTable（真实游戏视图，默认 2D 伪 3D 渲染），
	# 不再裸实例化 FourPlayerTable（那会绕过生产入口的渲染模式选择）。
	# 注意:必须运行时 load — -s 脚本的编译闭包先于 autoload 注册,
	# 静态引用 PlayableTable 会把 Anima(依赖 ANIMA autoload)拖进早期编译。
	var table = load("res://ui/four_player_table/playable_table.gd").new()
	root.add_child(table)
	table.set_player_persona("林夜彻",
		"res://assets/roguelike/characters/char_lin_yeche.png")
	# BattleController 跑一个确定 seed 起手,state 立刻有 4 家 13 张手牌 + 庄家
	var bc := BattleController.new(42, 0, false, TileId.E)
	# bind 桌面到这个 state,seat 0 可见手牌、dora 指示牌、立直棒 0、当前 seat 高亮
	table._table.bind_battle_state(bc.state, 0, 4)
	for _i in range(40):
		await process_frame
	var img := root.get_texture().get_image()
	var out := "/tmp/shot_battle_live.png"
	img.save_png(out)
	print("[capture] saved ", out)
	# 确认态特殊役横幅：只调用公开 bundle 的 MomentBand 翻译入口，避免同时
	# 挂 3 秒 win-announce 干扰后续终局截图。
	table._play_confirmed_moment_band([{"name": "海底捞月", "han": 1}])
	for _i in range(24):
		await process_frame
	var moment_img := root.get_texture().get_image()
	moment_img.save_png("/tmp/shot_battle_moment.png")
	print("[capture] saved /tmp/shot_battle_moment.png")
	var moment_band: Node = table.get_node_or_null("MomentBand")
	if moment_band != null:
		moment_band.queue_free()
	await process_frame
	# 再来一张终局状态:跑完整局后 rebind,河牌满 / 副露 / 立直棒全亮,
	# 验证 3D 倾斜视图下的中盘景观密度。
	bc.run_to_end()
	table._table.bind_battle_state(bc.state, 0, 4)
	for _i in range(20):
		await process_frame
	var img2 := root.get_texture().get_image()
	img2.save_png("/tmp/shot_battle_end.png")
	print("[capture] saved /tmp/shot_battle_end.png")
	table.queue_free()
	await process_frame
