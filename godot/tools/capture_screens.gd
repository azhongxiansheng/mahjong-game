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
	# E1-04：规则抽屉展开态（真实打开后再截）。
	await _capture_lobby_rule_drawer()
	# E1-05：资料馆与音量弹层展开态。
	await _capture_lobby_codex()
	await _capture_lobby_audio_popup()
	# 额外:一张「带牌局的战斗桌」截图,真实绑定 BattleState 让 38 张麻将牌、
	# dealer 标记、当前回合金边、座位分数都一起亮相,证明对战可玩。
	await _capture_battle_with_state()
	# E4-01：欢乐场 PTT 空闲 / 按下态截图（不遮挡手牌与行动栏）。
	await _capture_battle_ptt()
	# E4-04 / #246：多语字幕 + partial + AI + 奖励 banner 同屏。
	await _capture_battle_captions()
	print("[capture] done")
	quit()


func _capture_lobby_rule_drawer() -> void:
	var packed := load("res://ui/lobby/lobby_shell.tscn") as PackedScene
	if packed == null:
		print("[capture] cannot load lobby_shell for rule drawer shot")
		return
	var shell := packed.instantiate()
	root.add_child(shell)
	for _i in range(20):
		await process_frame
	if shell.has_method("request_practice"):
		shell.request_practice()
	for _i in range(40):
		await process_frame
	var img := root.get_texture().get_image()
	var out := "/tmp/shot_lobby_rule_drawer.png"
	img.save_png(out)
	print("[capture] saved ", out)
	shell.queue_free()
	await process_frame


func _capture_lobby_codex() -> void:
	var packed := load("res://ui/lobby/lobby_shell.tscn") as PackedScene
	if packed == null:
		print("[capture] cannot load lobby_shell for codex shot")
		return
	var shell := packed.instantiate()
	root.add_child(shell)
	for _i in range(20):
		await process_frame
	var btn := shell.get_node_or_null("%CharacterCodexButton") as Button
	if btn:
		btn.pressed.emit()
	for _i in range(40):
		await process_frame
	var img := root.get_texture().get_image()
	var out := "/tmp/shot_lobby_codex.png"
	img.save_png(out)
	print("[capture] saved ", out)
	shell.queue_free()
	await process_frame


func _capture_lobby_audio_popup() -> void:
	var packed := load("res://ui/lobby/lobby_shell.tscn") as PackedScene
	if packed == null:
		print("[capture] cannot load lobby_shell for audio popup shot")
		return
	var shell := packed.instantiate()
	root.add_child(shell)
	for _i in range(20):
		await process_frame
	var btn := shell.get_node_or_null("%BgmButton") as Button
	if btn:
		btn.pressed.emit()
	for _i in range(40):
		await process_frame
	var img := root.get_texture().get_image()
	var out := "/tmp/shot_lobby_audio_popup.png"
	img.save_png(out)
	print("[capture] saved ", out)
	shell.queue_free()
	await process_frame


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


func _capture_battle_ptt() -> void:
	# 运行时 load，避免 -s 早期编译拖入 Anima autoload 依赖。
	var table = load("res://ui/four_player_table/playable_table.gd").new()
	root.add_child(table)
	table.set_player_persona(
		"林夜彻",
		"res://assets/roguelike/characters/char_lin_yeche.png"
	)
	var intent := SessionIntent.new(&"PRACTICE", &"EAST", &"TRASH_TALK", &"lin_yeche")
	var converted := GameSessionConfig.from_intent(
		intent, 42, "capture-ptt", "e4-01-v1", {}
	)
	if not converted.ok:
		print("[capture] PTT config failed")
		table.queue_free()
		return
	var driver := PracticeSessionLauncher.new().launch(converted.config)
	if driver == null:
		print("[capture] PTT launch failed")
		table.queue_free()
		return
	var bc: PlayableBattleController = driver.bc_factory.call(
		42, 0, false, TileId.E, 0
	)
	table._table.bind_battle_state(bc.state, 0, 4)
	var vp: VoicePortModule = bc.mode_modules.voice_port
	if vp != null:
		vp.set_capture_backend(VoicePortModule.CaptureBackend.FIXTURE)
	table.bind_voice_from_battle(bc)
	for _i in range(30):
		await process_frame
	var idle_img := root.get_texture().get_image()
	idle_img.save_png("/tmp/shot_battle_ptt_idle.png")
	print("[capture] saved /tmp/shot_battle_ptt_idle.png")
	var btn := table.get_node_or_null("PttButton") as BaseButton
	if btn != null:
		btn.button_down.emit()
	for _i in range(20):
		await process_frame
	var pressed_img := root.get_texture().get_image()
	pressed_img.save_png("/tmp/shot_battle_ptt_pressed.png")
	print("[capture] saved /tmp/shot_battle_ptt_pressed.png")
	if btn != null:
		btn.button_up.emit()
	table.queue_free()
	await process_frame


func _capture_battle_captions() -> void:
	# 与 _capture_battle_ptt 同构：PlayableTable + TRASH_TALK + fixture VoicePort，
	# 保证右下 PTT 与手牌/操作栏同屏；字幕经内部真实 FourPlayerTable 公开注入入口。
	var table = load("res://ui/four_player_table/playable_table.gd").new()
	root.add_child(table)
	table.set_player_persona(
		"林夜彻",
		"res://assets/roguelike/characters/char_lin_yeche.png"
	)
	var intent := SessionIntent.new(&"PRACTICE", &"EAST", &"TRASH_TALK", &"lin_yeche")
	var converted := GameSessionConfig.from_intent(
		intent, 42, "capture-captions", "e4-04-v1", {}
	)
	if not converted.ok:
		print("[capture] captions config failed")
		table.queue_free()
		return
	var driver := PracticeSessionLauncher.new().launch(converted.config)
	if driver == null:
		print("[capture] captions launch failed")
		table.queue_free()
		return
	var bc: PlayableBattleController = driver.bc_factory.call(
		42, 0, false, TileId.E, 0
	)
	table._table.bind_battle_state(bc.state, 0, 4)
	var vp: VoicePortModule = bc.mode_modules.voice_port
	if vp != null:
		vp.set_capture_backend(VoicePortModule.CaptureBackend.FIXTURE)
	table.bind_voice_from_battle(bc)
	for _i in range(30):
		await process_frame

	# 字幕走生产 FourPlayerTable 注入入口（非裸脚本旁路）
	var fpt = table._table
	if fpt == null or not fpt.has_method("inject_caption_display"):
		print("[capture] captions: inner FourPlayerTable missing inject API")
		table.queue_free()
		return
	fpt.inject_caption_display({
		"seat": 0, "utterance_id": "cap_zh", "text": "听牌了吗",
		"kind": "TRANSCRIPT_PARTIAL", "source": "local_mic", "lang": "zh",
	})
	fpt.inject_caption_display({
		"seat": 1, "utterance_id": "cap_en", "text": "I am tenpai",
		"kind": "TRANSCRIPT_FINAL", "source": "faster_whisper", "lang": "en",
	})
	var ai_line: Variant = TrashTalkAiLineSelector.select_ai_line({
		"rule_version": "trash_talk_rules_v1",
		"has_first_discard": true,
		"seed": 99, "hand_seq": 4, "window_id": "hand_4_window_0",
		"seat": 2, "discard_server_seq": 12,
		"character_id": "hua_ling", "language": "ja",
		"public_context_tags": ["CTX_DORA_REVEALED"],
	})
	if ai_line != null and fpt.has_method("inject_ai_caption_display"):
		fpt.inject_ai_caption_display(ai_line)
	else:
		fpt.inject_caption_display({
			"seat": 2, "utterance_id": "cap_ja_ai", "text": "リーチ！",
			"kind": "final", "source": "ai_text", "lang": "ja",
		})
	fpt.inject_caption_display({
		"seat": 3, "utterance_id": "cap_zh2", "text": "上家小心",
		"kind": "TRANSCRIPT_FINAL", "source": "server_stt", "lang": "zh",
	})
	var settled := {
		"protocol_version": 1,
		"server_seq": 120,
		"room_id": "room_x",
		"kind": "REWARD_WINDOW_SETTLED",
		"payload": {
			"window_id": "hand_3_window_1",
			"outcome": "FULL_GRANT",
			"settle_reason": "FULL_24_NO_WIN",
			"rule_version": "reward_v2",
			"assignment_version": "assign_v1",
			"prize_pool": ["item_a", "item_b", "item_c", "item_d"],
			"matrix_summary": {"scores": [
				[1000, 0, 0, 0], [0, 1000, 0, 0],
				[0, 0, 1000, 0], [0, 0, 0, 1000],
			]},
			"assignment": {"0": "item_a", "1": "item_b", "2": "item_c", "3": "item_d"},
			"closing_boundary_server_seq": 110,
			"context_boundary_server_seq": 118,
			"grace_deadline_at": "2026-07-22T12:00:01.500Z",
			"grant_count": 4,
			"hand_seq": 3,
			"transcript_summary": {},
		},
		"view_hash": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
	}
	if fpt.has_method("inject_reward_feedback"):
		fpt.inject_reward_feedback(settled)
	for _i in range(30):
		await process_frame
	var ptt_btn = table.get_node_or_null("PttButton")
	if ptt_btn == null:
		print("[capture] captions WARNING: PttButton missing on PlayableTable")
	var img := root.get_texture().get_image()
	var out := "/tmp/shot_battle_captions.png"
	img.save_png(out)
	print("[capture] saved ", out)
	table.queue_free()
	await process_frame
