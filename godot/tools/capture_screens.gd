extends SceneTree

# 一次性视觉验证工具：实例化大厅 / 战斗桌场景，渲染若干帧后把视口
# 截图存到 /tmp，供人工核对新资产与牌桌渲染效果。
#
# 跑法（必须带窗口渲染，不能 --headless）：
#   godot --path godot -s tools/capture_screens.gd

const SHOTS := [
	["res://ui/lobby/lobby_shell.tscn", "lobby_shell"],
	["res://ui/four_player_table/four_player_table.tscn", "four_player_table"],
]
const CAPTURE_SIZE := Vector2i(1600, 900)


func _initialize() -> void:
	_run()


func _run() -> void:
	# 使用产品固定视口，截图直接核对 1600×900 契约。
	root.content_scale_size = CAPTURE_SIZE
	DisplayServer.window_set_size(CAPTURE_SIZE)
	await process_frame
	await process_frame
	if OS.get_environment("MAHJONG_CAPTURE_TARGET") == "result":
		await _capture_result_breakdown()
		print("[capture] done")
		quit()
		return
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
		await RenderingServer.frame_post_draw
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
	await _capture_result_breakdown()
	await _capture_lobby_audio_popup()
	# 额外:一张「带牌局的战斗桌」截图,真实绑定 BattleState 让 38 张麻将牌、
	# dealer 标记、当前回合金边、座位分数都一起亮相,证明对战可玩。
	await _capture_battle_with_state()
	# E4-01：欢乐场 PTT 空闲 / 按下态截图（不遮挡手牌与行动栏）。
	await _capture_battle_ptt()
	# E4-04 / #246：多语字幕 + partial + AI + 奖励 banner 同屏。
	await _capture_battle_captions()
	# E5-06 / #254：奖池 HUD + 反馈条 + 库存抽屉 1600×900。
	await _capture_reward_feedback_254()
	# E8-04 / #377：公共 committed 投影 playing / recipient≠0 / reconnecting 冻结。
	await _capture_public_table_projection_377()
	# E8-05 / #378：可操作 decision / multi-option pick / pending lock / ERROR 恢复。
	await _capture_public_command_loop_378()
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
	await RenderingServer.frame_post_draw
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
	await process_frame
	var yaku_tab := shell.get_node_or_null("%CodexYakuTab") as Button
	if yaku_tab:
		yaku_tab.pressed.emit()
	for _i in range(40):
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var out := "/tmp/shot_lobby_codex.png"
	img.save_png(out)
	print("[capture] saved ", out)
	shell.queue_free()
	await process_frame


func _capture_result_breakdown() -> void:
	var table = load("res://ui/four_player_table/playable_table.gd").new()
	root.add_child(table)
	for _i in range(20):
		await process_frame
	var characters := CharacterPool.all()
	if not characters.is_empty():
		table.set_player_persona(characters[0].display_name, characters[0].portrait_path)
	var shell: Dictionary = table._create_result_modal_shell()
	var panel := shell["panel"] as Panel
	var title := Label.new()
	title.text = "林夜澈　和牌"
	title.position = Vector2(36, 24)
	title.size = Vector2(828, 38)
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color("d9b65b"))
	panel.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "荣和 · 40符 3番"
	subtitle.position = Vector2(36, 64)
	subtitle.size = Vector2(828, 24)
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color("f4ead2d9"))
	panel.add_child(subtitle)
	var portrait: Texture2D = null
	if not characters.is_empty() and ResourceLoader.exists(characters[0].portrait_path):
		portrait = load(characters[0].portrait_path) as Texture2D
	table._build_result_winner_portrait(panel, portrait,
		characters[0].display_name if not characters.is_empty() else "玩家")
	var detail_tabs: TabContainer = table._build_result_detail_tabs(panel, {
		"han": 3,
		"fu": 40,
		"base_points": 1280,
		"winner_total": 5200,
		"winner_seat": 0,
		"discarder_seat": 2,
		"payout": {2: 5200},
		"yaku_names": [
			{"name": "立直", "han": 1},
			{"name": "平和", "han": 1},
			{"name": "断幺九", "han": 1},
		],
		"fu_breakdown": {
			"raw_fu": 38,
			"rounded_fu": 40,
			"items": [
				{"key": "base", "label": "副底", "fu": 20},
				{"key": "menzen_ron", "label": "门清荣和", "fu": 10},
				{"key": "pair", "label": "役牌雀头", "fu": 2},
				{"key": "wait", "label": "嵌张听牌", "fu": 2},
				{"key": "meld", "label": "暗刻·中张牌", "fu": 4},
			],
		},
	})
	for _i in range(240):
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("/tmp/shot_battle_result_breakdown.png")
	print("[capture] saved /tmp/shot_battle_result_breakdown.png")
	detail_tabs.current_tab = 1
	for _i in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	var fu_img := root.get_texture().get_image()
	fu_img.save_png("/tmp/shot_battle_result_fu_breakdown.png")
	print("[capture] saved /tmp/shot_battle_result_fu_breakdown.png")
	table.queue_free()
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
	await RenderingServer.frame_post_draw
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
	# #340：走真实 ability factory/hook/state → FourPlayerTable reveal strip，
	# 截完清理，避免污染后续牌桌基线截图。
	BossAbilityFactory.inject(bc.registry, &"char_akagi_passive_v1", 0)
	bc.scheduler.emit_event(BattleEvent.make(&"TILE_DRAWN", 0))
	table._table.bind_battle_state(bc.state, 0, 4)
	for _i in range(8):
		await process_frame
	var reveal_img := root.get_texture().get_image()
	reveal_img.save_png("/tmp/shot_battle_lin_reveal.png")
	print("[capture] saved /tmp/shot_battle_lin_reveal.png")
	bc.state.revealed_tiles.clear()
	table._table.bind_battle_state(bc.state, 0, 4)
	# #341：同一通用揭示组件由白透璃 profile 提供“镜华”标签；真实 hook
	# 在三个对手座位各投影两张，不复制第二套 UI。
	var bai_bc := BattleController.new(341, 0, false, TileId.E)
	table.bind_character_ids([&"bai_touli", &"qiu_jue", &"lin_yeche", &"hua_ling"])
	table.set_player_persona("白透璃",
		"res://assets/roguelike/characters/char_bai_touli.png")
	BossAbilityFactory.inject(bai_bc.registry, &"char_washizu_passive_v1", 0)
	bai_bc.scheduler.emit_event(BattleEvent.make(&"GAME_BEGIN", 0))
	table._table.bind_battle_state(bai_bc.state, 0, 4)
	for _i in range(8):
		await process_frame
	var bai_reveal_img := root.get_texture().get_image()
	bai_reveal_img.save_png("/tmp/shot_battle_bai_touli_reveal.png")
	print("[capture] saved /tmp/shot_battle_bai_touli_reveal.png")
	# #344：安澄青复用顶部 reveal 牌面显示本人下一摸，并由 catalog 路由
	# 顶部专属 toast；不在 PlayableTable 写角色 ID 分支。
	var an_bc := BattleController.new(344, 0, false, TileId.E)
	table.bind_character_ids([&"an_cheng", &"qiu_jue", &"lin_yeche", &"hua_ling"])
	table.set_player_persona("安澄青",
		"res://assets/roguelike/characters/char_an_cheng.png")
	var an_skill := BossAbilityFactory.build(&"char_awai_passive_v1")
	an_bc.activate_single_skill_for_event(an_skill, 0, &"GAME_BEGIN")
	table._table.bind_battle_state(an_bc.state, 0, 4)
	table._handle_event_toast(an_bc.events[-1] as BattleEvent)
	for _i in range(8):
		await process_frame
	var an_reveal_img := root.get_texture().get_image()
	an_reveal_img.save_png("/tmp/shot_battle_an_cheng_prediction.png")
	print("[capture] saved /tmp/shot_battle_an_cheng_prediction.png")
	# #345：渊汐本人普通摸后显示 live wall 顶三张，并落在 y=84 顶部安全空档。
	var yuan_bc := BattleController.new(345, 0, false, TileId.E)
	if table._toast_label != null:
		table._toast_label.visible = false
	table.bind_character_ids([&"yuan_xi", &"qiu_jue", &"lin_yeche", &"hua_ling"])
	table.set_player_persona("渊汐",
		"res://assets/roguelike/characters/char_yuan_xi.png")
	BossAbilityFactory.inject(yuan_bc.registry, &"char_koromo_passive_v1", 0)
	yuan_bc._step_draw()
	table._table.bind_battle_state(yuan_bc.state, 0, 4)
	table._handle_event_toast(yuan_bc.events[-1] as BattleEvent)
	for _i in range(8):
		await process_frame
	var yuan_reveal_img := root.get_texture().get_image()
	yuan_reveal_img.save_png("/tmp/shot_battle_yuan_xi_wall_top.png")
	print("[capture] saved /tmp/shot_battle_yuan_xi_wall_top.png")
	# #347：先示独立四席条件预测条；四格按本地 viewer 映射，不复用 #344 单张模块。
	var xian_bc := BattleController.new(347, 2, false, TileId.E, 3)
	table._reward_local_seat = 2
	table.bind_character_ids([&"qiu_jue", &"lin_yeche", &"xian_shi", &"hua_ling"])
	table.set_player_persona("先示",
		"res://assets/roguelike/characters/char_xian_shi.png")
	BossAbilityFactory.inject(xian_bc.registry, &"char_toki_passive_v1", 2)
	xian_bc.scheduler.emit_event(BattleEvent.make(&"GAME_BEGIN", 2))
	table._table.set_local_seat(2)
	table._table.bind_battle_state(xian_bc.state, 0, 4)
	table._handle_event_toast(BattleEvent.make(&"SKILL_TRIGGERED", 2, null, {
		"skill_id": &"char_toki_passive_v1",
		"skill_name": "先示·四席窥运",
		"source_event": &"GAME_BEGIN",
	}))
	for _i in range(8):
		await process_frame
	var xian_forecast_img := root.get_texture().get_image()
	xian_forecast_img.save_png("/tmp/shot_battle_xian_shi_forecast.png")
	print("[capture] saved /tmp/shot_battle_xian_shi_forecast.png")
	table._reward_local_seat = 0
	table._table.set_local_seat(0)
	table.bind_character_ids([&"lin_yeche", &"qiu_jue", &"bai_touli", &"hua_ling"])
	table.set_player_persona("林夜彻",
		"res://assets/roguelike/characters/char_lin_yeche.png")
	table._table.bind_battle_state(bc.state, 0, 4)
	# 状态 B/方案1：真实 PlayableTable 的固定仪式带 + 真实手牌候选/禁用层。
	var player := table._table.seat_panels[0] as SeatPanel
	var allowed: Array = []
	for slot_index in mini(3, player._hand_slots.size()):
		allowed.append(int(player._hand_slots[slot_index].get_meta(
			"hand_instance_id", Tile.INVALID_INSTANCE_ID)))
	player.set_hand_clickable(true)
	player.dim_hand_except(allowed)
	table._action_panel.enter_waiting_claim(true, true, true, true, 1)
	for _i in range(8):
		await process_frame
	var claim_img := root.get_texture().get_image()
	claim_img.save_png("/tmp/shot_battle_claim_candidates.png")
	print("[capture] saved /tmp/shot_battle_claim_candidates.png")
	player.clear_hand_dim()
	table._action_panel.enter_waiting_riichi_confirm()
	player.set_riichi(true)
	for _i in range(8):
		await process_frame
	var riichi_img := root.get_texture().get_image()
	riichi_img.save_png("/tmp/shot_battle_riichi_confirm.png")
	print("[capture] saved /tmp/shot_battle_riichi_confirm.png")
	table._action_panel.enter_idle("等待 AI…")
	player.set_riichi(false)
	player.set_hand_clickable(false)
	# 确认态特殊役横幅：只调用生产 MomentBand 入口，避免同时
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


func _capture_public_table_projection_377() -> void:
	# #377：1600×900 公共只读投影 — playing 本席下方 / recipient≠0 / reconnecting 冻结。
	# 路径：NBC committed core_table → PublicCasualNetworkSession.bind → PlayableTable。
	var Adapter = load("res://ui/four_player_table/public_table_projection_adapter.gd")
	var PlayableScr = load("res://ui/four_player_table/playable_table.gd")

	# --- fixture helpers（与 GUT #377 对齐的最小合法 core）---
	var make_tile := func(tile_id: int, copy_index: int, red: bool = false) -> Dictionary:
		return {
			"instance_id": TileId.ALL.find(tile_id) * 4 + copy_index,
			"tile_id": tile_id,
			"is_red_dora": red,
			"owner_seat": copy_index,
		}
	var make_core := func(recip: int) -> Dictionary:
		var own_a: Dictionary = make_tile.call(TileId.W5, 0, true)
		var own_b: Dictionary = make_tile.call(TileId.W5, 1, false)
		var seats: Array = []
		for s in range(4):
			var river: Array = [make_tile.call(TileId.W4, s)]
			var melds: Array = []
			if s == 1:
				var w1: Dictionary = make_tile.call(TileId.W1, 1)
				var w2: Dictionary = make_tile.call(TileId.W2, 1)
				var w3: Dictionary = make_tile.call(TileId.W3, 0)
				melds = [{
					"meld_id": 1, "kind": "CHI", "from_seat": 0,
					"called_tile_instance_id": int(w3["instance_id"]),
					"added_tile_instance_id": -1,
					"tiles": [w1, w2, w3],
				}]
			var concealed: Array = [own_a, own_b] if s == recip else []
			var count: int = 2 if s == recip else 13
			seats.append({
				"seat": s,
				"seat_wind": [TileId.E, TileId.S_WIND, TileId.W_WIND, TileId.N][s],
				"score": 25000 + s * 100,
				"concealed_tiles": concealed,
				"concealed_count": count,
				"last_drawn_tile_instance_id": -1,
				"river": river,
				"melds": melds,
				"riichi_declared": s == 2,
				"riichi_double": false,
				"riichi_discard_index": 0 if s == 2 else -1,
			})
		return {
			"recipient_seat": recip, "hand_seq": 0, "dealer_seat": 0,
			"current_seat": recip, "phase": "DISCARD", "round_wind": TileId.E,
			"hand_number": 1, "honba": 2, "riichi_sticks": 1, "live_wall_count": 66,
			"dora_indicators": [make_tile.call(TileId.S1, 0)], "seats": seats,
		}
	var make_snap := func(seq: int, recip: int, core: Dictionary) -> Dictionary:
		return {
			"snapshot_server_seq": seq, "next_server_seq": seq + 1,
			"seat_view": recip,
			"modules": [
				{"module_key": "core_table", "schema_version": 1, "payload": core},
				MatchingMetaSnapshotProvider.fixture_module(
					["lin_yeche", "an_cheng", "bai_touli", "hua_ling"],
					["HUMAN", "AI", "AI", "AI"]
				),
			],
		}

	# 1) playing 正常（recipient=0）
	var table0 = PlayableScr.new()
	root.add_child(table0)
	var room0 := "capture-377-r0"
	var nbc0 := NetworkedBattleController.new(room0, 0)
	var core0: Dictionary = make_core.call(0)
	var payload0: Dictionary = make_snap.call(1, 0, core0)
	var ne0 := NetworkedEvent.make(
		"ROOM_SNAPSHOT", 1, room0, payload0, ProtocolViewCodec.compute_view_hash(payload0))
	if ne0 != null:
		nbc0.ingest_networked_event(ne0)
	var sess0 := PublicCasualNetworkSession.new()
	root.add_child(sess0)
	sess0.room_id = room0
	sess0.seat = 0
	sess0.nbc = nbc0
	sess0.bind_playable_table(table0)
	if table0.has_method("sync_public_table_projection"):
		table0.sync_public_table_projection()
	for _i in range(20):
		await process_frame
	await RenderingServer.frame_post_draw
	var img0 := root.get_texture().get_image()
	var out0 := "/tmp/shot_public_table_377_playing.png"
	img0.save_png(out0)
	print("[capture] saved ", out0, " size=", img0.get_width(), "x", img0.get_height(),
		" recip=0 wall=", core0.get("live_wall_count"))
	sess0.release()
	sess0.queue_free()
	table0.queue_free()
	await process_frame

	# 2) recipient=2 本席在下方
	var table2 = PlayableScr.new()
	root.add_child(table2)
	var room2 := "capture-377-r2"
	var nbc2 := NetworkedBattleController.new(room2, 2)
	var core2: Dictionary = make_core.call(2)
	var payload2: Dictionary = make_snap.call(1, 2, core2)
	var ne2 := NetworkedEvent.make(
		"ROOM_SNAPSHOT", 1, room2, payload2, ProtocolViewCodec.compute_view_hash(payload2))
	if ne2 != null:
		nbc2.ingest_networked_event(ne2)
	var sess2 := PublicCasualNetworkSession.new()
	root.add_child(sess2)
	sess2.room_id = room2
	sess2.seat = 2
	sess2.nbc = nbc2
	sess2.bind_playable_table(table2)
	if table2.has_method("sync_public_table_projection"):
		table2.sync_public_table_projection()
	for _i in range(20):
		await process_frame
	await RenderingServer.frame_post_draw
	var img2 := root.get_texture().get_image()
	var out2 := "/tmp/shot_public_table_377_recipient2.png"
	img2.save_png(out2)
	print("[capture] saved ", out2, " size=", img2.get_width(), "x", img2.get_height(),
		" recip=2 bottom_abs=", Adapter.absolute_seat(0, 2) if Adapter else 2)
	# 3) reconnecting：冻结 committed + 真实 PublicMatchStatusOverlay（preload 脚本）
	nbc2.force_resync_for_authority_gap()
	if table2.has_method("sync_public_table_projection"):
		table2.sync_public_table_projection()
	var OverlayScr: GDScript = load("res://ui/lobby/public_match_status_overlay.gd") as GDScript
	var overlay: Control = OverlayScr.new() as Control
	table2.add_child(overlay)
	if overlay.has_method("present"):
		overlay.call("present", {
			"state": "reconnecting",
			"round_kind": "EAST",
			"game_mode": "STANDARD",
			"error_code": "RESYNC_REQUIRED",
			"message": "authority resync required",
			"can_retry": true,
		})
	for _j in range(12):
		await process_frame
	await RenderingServer.frame_post_draw
	var img3 := root.get_texture().get_image()
	var out3 := "/tmp/shot_public_table_377_reconnecting.png"
	img3.save_png(out3)
	var retry_btn: Button = overlay.find_child("PublicMatchRetryButton", true, false) as Button
	var blocking := false
	if overlay.has_method("is_blocking"):
		blocking = bool(overlay.call("is_blocking"))
	print("[capture] saved ", out3, " size=", img3.get_width(), "x", img3.get_height(),
		" blocking=", blocking,
		" retry_visible=", retry_btn != null and retry_btn.visible,
		" retry_focus=", retry_btn != null and retry_btn.has_focus())
	sess2.release()
	sess2.queue_free()
	table2.queue_free()
	await process_frame

	# 4) TURN_PROMPT 全动作只读栏：真实 SNAP → TURN 经 session/bridge/NBC
	# 与 GUT test_turn_prompt_maps_real_kan_riichi_kyuusyu_and_dim_discards 同形
	var table_t = PlayableScr.new()
	root.add_child(table_t)
	var room_t := "capture-377-turn"
	var nbc_t := NetworkedBattleController.new(room_t, 0)
	# 本席 7 张手牌（含 ANKAN 四张赤/五 + DISCARD 实体）
	var t0: Dictionary = make_tile.call(TileId.W1, 0)
	var t1: Dictionary = make_tile.call(TileId.S2, 0)
	var a0: Dictionary = make_tile.call(TileId.W5, 0, true)
	var a1: Dictionary = make_tile.call(TileId.W5, 1)
	var a2: Dictionary = make_tile.call(TileId.W5, 2)
	var a3: Dictionary = make_tile.call(TileId.W5, 3)
	var added: Dictionary = make_tile.call(TileId.HAKU, 0)
	var core_t: Dictionary = make_core.call(0)
	var seats_t: Array = core_t["seats"]
	var own_t: Dictionary = seats_t[0]
	own_t["concealed_tiles"] = [t0, t1, a0, a1, a2, a3, added]
	own_t["concealed_count"] = 7
	own_t["last_drawn_tile_instance_id"] = int(t1["instance_id"])
	seats_t[0] = own_t
	core_t["seats"] = seats_t
	core_t["phase"] = "DISCARD"
	var snap_t: Dictionary = make_snap.call(1, 0, core_t)
	var vh_t := ProtocolViewCodec.compute_view_hash(snap_t)
	var ne_snap := NetworkedEvent.make("ROOM_SNAPSHOT", 1, room_t, snap_t, vh_t)
	var turn_payload := {
		"hand_seq": 0,
		"decision_id": "550e8400-e29b-41d4-a716-4466554400aa",
		"seat": 0,
		"hand": [t0, t1, a0, a1, a2, a3, added],
		"last_drawn_tile_instance_id": int(t1["instance_id"]),
		"allowed_actions": [
			{
				"kind": "DISCARD",
				"payload_options": [
					{"tile_instance_id": int(t0["instance_id"])},
					{"tile_instance_id": int(t1["instance_id"])},
				],
			},
			{"kind": "RIICHI", "payload_options": [{"tile_instance_id": int(t1["instance_id"])}]},
			{
				"kind": "KAN",
				"payload_options": [
					{
						"kan_kind": "ANKAN",
						"tile_instance_ids": [
							int(a0["instance_id"]), int(a1["instance_id"]),
							int(a2["instance_id"]), int(a3["instance_id"]),
						],
					},
					{
						"kan_kind": "ADDED_KAN",
						"meld_id": 1,
						"added_tile_instance_id": int(added["instance_id"]),
					},
				],
			},
			{"kind": "TSUMO", "payload_options": [{}]},
			{
				"kind": "DECLARE_ABORTIVE_DRAW",
				"payload_options": [{"reason": "KYUUSYU_KYUUHAI"}],
			},
		],
	}
	var ne_turn := NetworkedEvent.make("TURN_PROMPT", 2, room_t, turn_payload, vh_t)
	var sess_t := PublicCasualNetworkSession.new()
	root.add_child(sess_t)
	sess_t.room_id = room_t
	sess_t.seat = 0
	sess_t.nbc = nbc_t
	sess_t.seq_bridge.bind_networked_controller(nbc_t)
	sess_t.bind_playable_table(table_t)
	# 生产 wire 入口（禁止直接 _present_public_allowed_actions）
	if ne_snap != null and sess_t.has_method("ingest_authority_wire_for_test"):
		sess_t.ingest_authority_wire_for_test(JSON.stringify(ne_snap.to_dict()))
	elif ne_snap != null:
		nbc_t.ingest_networked_event(ne_snap)
	if ne_turn != null and sess_t.has_method("ingest_authority_wire_for_test"):
		sess_t.ingest_authority_wire_for_test(JSON.stringify(ne_turn.to_dict()))
	elif ne_turn != null:
		nbc_t.ingest_networked_event(ne_turn)
	if table_t.has_method("sync_public_table_projection"):
		table_t.sync_public_table_projection()
	for _k in range(24):
		await process_frame
	await RenderingServer.frame_post_draw
	var img_t := root.get_texture().get_image()
	var out_t := "/tmp/shot_public_table_377_turn_actions.png"
	img_t.save_png(out_t)
	var ap = table_t.get("_action_panel")
	var vis := {
		"tsumo": false, "riichi": false, "ankan": false,
		"added": false, "kyuusyu": false,
	}
	if ap != null:
		for pair in [
			["tsumo", "_btn_tsumo"], ["riichi", "_btn_riichi"],
			["ankan", "_btn_ankan"], ["added", "_btn_added_kan"],
			["kyuusyu", "_btn_kyuusyu"],
		]:
			var b = ap.get(pair[1])
			if b != null:
				vis[pair[0]] = b.visible
	print("[capture] saved ", out_t, " size=", img_t.get_width(), "x", img_t.get_height(),
		" buttons=", vis, " snap_ok=", ne_snap != null, " turn_ok=", ne_turn != null)
	sess_t.release()
	sess_t.queue_free()
	table_t.queue_free()
	await process_frame


func _capture_public_command_loop_378() -> void:
	# #378：可操作 decision / multi-option pick / pending 锁 / ERROR 恢复 — 须可见控件态。
	# 对齐 #377：先 add_child 等 _ready，再 NBC ingest SNAP/decision，再 bind+sync。
	var PlayableScr = load("res://ui/four_player_table/playable_table.gd")
	var decision := "550e8400-e29b-41d4-a716-4466554400aa"
	var make_tile := func(tile_id: int, copy_index: int, red: bool = false) -> Dictionary:
		return {
			"instance_id": TileId.ALL.find(tile_id) * 4 + copy_index,
			"tile_id": tile_id, "is_red_dora": red, "owner_seat": copy_index,
		}
	var fail := func(msg: String) -> void:
		push_error("[capture#378] HARD FAIL: " + msg)
		print("[capture#378] HARD FAIL: ", msg)
		quit(1)
	var room := "capture-378"
	var table = PlayableScr.new()
	root.add_child(table)
	# 等待真实 _ready：FourPlayerTable + action panel + seat panels
	for _w in range(40):
		await process_frame
		if table._table != null and table._action_panel != null \
				and table._table is FourPlayerTable \
				and (table._table as FourPlayerTable).seat_panels.size() >= 1:
			break
	if table._table == null or table._action_panel == null:
		fail.call("table/action_panel not ready")
		return
	var fpt: FourPlayerTable = table._table as FourPlayerTable
	if fpt.seat_panels.is_empty():
		fail.call("seat_panels empty")
		return
	# 与 #377 turn_actions 完全同形的 fixture（已验证 tsumo 可见）
	var t0: Dictionary = make_tile.call(TileId.W1, 0)
	var t1: Dictionary = make_tile.call(TileId.S2, 0)
	var a0: Dictionary = make_tile.call(TileId.W5, 0, true)
	var a1: Dictionary = make_tile.call(TileId.W5, 1)
	var a2: Dictionary = make_tile.call(TileId.W5, 2)
	var a3: Dictionary = make_tile.call(TileId.W5, 3)
	var added: Dictionary = make_tile.call(TileId.HAKU, 0)
	var hand_tiles: Array = [t0, t1, a0, a1, a2, a3, added]
	var iid_of := func(d: Dictionary) -> int:
		return int(d["instance_id"])
	var seats: Array = []
	for s in range(4):
		var concealed: Array = hand_tiles.duplicate() if s == 0 else []
		seats.append({
			"seat": s,
			"seat_wind": [TileId.E, TileId.S_WIND, TileId.W_WIND, TileId.N][s],
			"score": 25000 + s * 100,
			"concealed_tiles": concealed,
			"concealed_count": concealed.size() if s == 0 else 13,
			"last_drawn_tile_instance_id": iid_of.call(t1) if s == 0 else -1,
			"river": [make_tile.call(TileId.W4, s)],
			"melds": [],
			"riichi_declared": false,
			"riichi_double": false,
			"riichi_discard_index": -1,
		})
	var core := {
		"recipient_seat": 0, "hand_seq": 0, "dealer_seat": 0, "current_seat": 0,
		"phase": "DISCARD", "round_wind": TileId.E, "hand_number": 1, "honba": 2,
		"riichi_sticks": 1, "live_wall_count": 66,
		"dora_indicators": [make_tile.call(TileId.S1, 0)], "seats": seats,
	}
	var snap_pay := {
		"snapshot_server_seq": 1, "next_server_seq": 2, "seat_view": 0,
		"modules": [
			{"module_key": "core_table", "schema_version": 1, "payload": core},
			MatchingMetaSnapshotProvider.fixture_module(
				["lin_yeche", "an_cheng", "bai_touli", "hua_ling"],
				["HUMAN", "AI", "AI", "AI"]),
		],
	}
	var vh := ProtocolViewCodec.compute_view_hash(snap_pay)
	var ne_snap := NetworkedEvent.make("ROOM_SNAPSHOT", 1, room, snap_pay, vh)
	var turn_pay := {
		"hand_seq": 0, "decision_id": decision, "seat": 0,
		"hand": hand_tiles.duplicate(),
		"last_drawn_tile_instance_id": iid_of.call(t1),
		"allowed_actions": [
			{"kind": "DISCARD", "payload_options": [
				{"tile_instance_id": iid_of.call(t0)},
				{"tile_instance_id": iid_of.call(t1)},
			]},
			{"kind": "TSUMO", "payload_options": [{}]},
			{"kind": "RIICHI", "payload_options": [
				{"tile_instance_id": iid_of.call(t0)},
			]},
			{"kind": "KAN", "payload_options": [
				{"kan_kind": "ANKAN", "tile_instance_ids": [
					iid_of.call(a0), iid_of.call(a1), iid_of.call(a2), iid_of.call(a3),
				]},
				{"kan_kind": "ADDED_KAN", "meld_id": 1,
					"added_tile_instance_id": iid_of.call(added)},
			]},
		],
	}
	var ne_turn := NetworkedEvent.make("TURN_PROMPT", 2, room, turn_pay, vh)
	var nbc := NetworkedBattleController.new(room, 0)
	# STANDARD 必需 core_table + matching_meta（#374）
	snap_pay = {
		"snapshot_server_seq": 1, "next_server_seq": 2, "seat_view": 0,
		"modules": [
			{"module_key": "core_table", "schema_version": 1, "payload": core},
			MatchingMetaSnapshotProvider.fixture_module(
				["lin_yeche", "an_cheng", "bai_touli", "hua_ling"],
				["HUMAN", "AI", "AI", "AI"]),
		],
	}
	vh = ProtocolViewCodec.compute_view_hash(snap_pay)
	ne_snap = NetworkedEvent.make("ROOM_SNAPSHOT", 1, room, snap_pay, vh)
	ne_turn = NetworkedEvent.make("TURN_PROMPT", 2, room, turn_pay, vh)
	var sess := PublicCasualNetworkSession.new()
	root.add_child(sess)
	sess.room_id = room
	sess.seat = 0
	sess.nbc = nbc
	if sess.seq_bridge != null:
		sess.seq_bridge.bind_networked_controller(nbc)
	sess.bind_playable_table(table)
	# bind 会启动 reward sync；必须事后关闭，避免覆盖手动库存 rows
	table._reward_sync_active = false
	if ne_snap == null:
		fail.call("ne_snap null")
		return
	if not nbc.ingest_networked_event(ne_snap):
		fail.call("SNAP ingest failed err=%s" % nbc.last_snapshot_error())
		return
	if ne_turn == null or not nbc.ingest_networked_event(ne_turn):
		fail.call("TURN ingest failed resync=%s" % str(nbc.resync_required()))
		return
	if table.has_method("sync_public_table_projection"):
		table.sync_public_table_projection()
	var core_view: Dictionary = nbc.get_core_table_view()
	if core_view.is_empty():
		fail.call("core empty")
		return
	fpt.bind_core_table_view(core_view)
	table._reward_sync_active = false
	# 库存：open 会 _sync_drawer_rows 清空；必须 open 后再 set_instances，并再关 sync
	if fpt.item_inventory_drawer != null:
		fpt.open_inventory_drawer()
		fpt.item_inventory_drawer.set_instances([{
			"item_instance_id": "ii_cap_378",
			"item_id": "wall_collapse_v1",
			"display_name": "牌墙崩塌",
			"status": "held",
			"effect_summary": "开局减墙",
		}])
		fpt.set_inventory_use_locked(false)
	for _i in range(24):
		await process_frame
		table._reward_sync_active = false
	await RenderingServer.frame_post_draw
	# 硬断言 decision 态
	var hand_n := 0
	var bottom = fpt.seat_panels[0]
	if bottom != null:
		for s in bottom.get("_hand_slots"):
			if s != null and is_instance_valid(s):
				hand_n += 1
	var ap = table._action_panel
	var tsumo_vis: bool = ap != null and ap.get("_btn_tsumo") != null and bool(ap.get("_btn_tsumo").visible)
	var riichi_vis: bool = ap != null and ap.get("_btn_riichi") != null and bool(ap.get("_btn_riichi").visible)
	var inv_n := 0
	var use_vis := false
	if fpt.item_inventory_drawer != null:
		inv_n = int(fpt.item_inventory_drawer.get("_visible_count"))
		var ub = fpt.item_inventory_drawer.find_child("UseButton", true, false)
		use_vis = ub != null and ub.visible and not ub.disabled
	if hand_n <= 0 or not (tsumo_vis or riichi_vis) or inv_n < 1 or not use_vis:
		fail.call("decision hard assert hand=%d tsumo=%s riichi=%s inv=%d use=%s" % [
			hand_n, str(tsumo_vis), str(riichi_vis), inv_n, str(use_vis)])
		return
	var img1 := root.get_texture().get_image()
	var out1 := "/tmp/shot_public_command_378_decision.png"
	img1.save_png(out1)
	print("[capture] saved ", out1, " size=", img1.get_width(), "x", img1.get_height(),
		" state=operable_decision tsumo_visible=", tsumo_vis, " hand=", hand_n, " inv=", inv_n)

	# multi-option pick
	var claim_pay := {
		"hand_seq": 0, "decision_id": decision, "discarded_by_seat": 1,
		"discarded_tile": make_tile.call(TileId.W3, 1),
		"allowed_actions": [
			{"kind": "PASS", "payload_options": [{}]},
			{"kind": "PON", "payload_options": [{
				"companion_tile_instance_ids": [iid_of.call(a0), iid_of.call(a1)],
			}]},
			{"kind": "CHI", "payload_options": [
				{"companion_tile_instance_ids": [iid_of.call(t0), iid_of.call(t1)]},
				{"companion_tile_instance_ids": [iid_of.call(t1), iid_of.call(a0)]},
			]},
			{"kind": "KAN", "payload_options": [{
				"kan_kind": "MINKAN",
				"companion_tile_instance_ids": [iid_of.call(a0), iid_of.call(a1), iid_of.call(a2)],
			}]},
		],
	}
	var ne_claim := NetworkedEvent.make("CLAIM_WINDOW", 3, room, claim_pay, vh)
	if ne_claim == null or not nbc.ingest_networked_event(ne_claim):
		fail.call("CLAIM ingest failed")
		return
	table.sync_public_table_projection()
	for _j0 in range(12):
		await process_frame
	var chi_before: bool = ap != null and ap.get("_btn_chi") != null and bool(ap.get("_btn_chi").visible)
	if not chi_before:
		fail.call("claim CHI button not visible before pick")
		return
	table._action_panel.player_action_chosen.emit({"action": "chi"})
	if table._seat_panel_player != null and table._seat_panel_player.has_method("dim_hand_except"):
		table._seat_panel_player.dim_hand_except([iid_of.call(t0), iid_of.call(t1), iid_of.call(a0)])
	for _j in range(16):
		await process_frame
	await RenderingServer.frame_post_draw
	var dim_count := 0
	var bright_count := 0
	if table._seat_panel_player != null:
		for slot in table._seat_panel_player.get("_hand_slots"):
			if slot == null or not is_instance_valid(slot):
				continue
			var tile_n = slot.get_node_or_null("Tile")
			if tile_n == null:
				# 部分实现把 modulate 放在 slot 上
				if slot is CanvasItem:
					var sm: Color = (slot as CanvasItem).modulate
					if sm.r < 0.9 or sm.a < 0.9:
						dim_count += 1
					else:
						bright_count += 1
				continue
			var is_dimmed := false
			if tile_n.has_method("is_dim"):
				is_dimmed = bool(tile_n.is_dim())
			elif tile_n is CanvasItem:
				var mod: Color = (tile_n as CanvasItem).modulate
				is_dimmed = mod.r < 0.9 or mod.a < 0.9
			if is_dimmed:
				dim_count += 1
			else:
				bright_count += 1
	if dim_count <= 0 or bright_count <= 0:
		fail.call("multi_pick dim/bright hard assert dim=%d bright=%d pick=%s" % [
			dim_count, bright_count, str(table.get("_public_pick_kind"))])
		return
	var img2 := root.get_texture().get_image()
	var out2 := "/tmp/shot_public_command_378_multi_pick.png"
	img2.save_png(out2)
	print("[capture] saved ", out2, " size=", img2.get_width(), "x", img2.get_height(),
		" state=multi_option_pick dim=", dim_count, " bright=", bright_count)

	# pending lock
	table._lock_public_inputs("命令处理中…")
	fpt.open_inventory_drawer()
	fpt.item_inventory_drawer.set_instances([{
		"item_instance_id": "ii_cap_378",
		"item_id": "wall_collapse_v1",
		"display_name": "牌墙崩塌",
		"status": "held",
		"effect_summary": "开局减墙",
	}])
	fpt.set_inventory_use_locked(true)
	for _k in range(12):
		await process_frame
	await RenderingServer.frame_post_draw
	var use_locked := bool(fpt.is_inventory_use_locked())
	var hand_clickable := true
	if table._seat_panel_player != null and table._seat_panel_player.has_method("is_hand_clickable"):
		hand_clickable = bool(table._seat_panel_player.is_hand_clickable())
	elif table._seat_panel_player != null:
		hand_clickable = false  # lock 路径 set_hand_clickable(false)
	var skip_vis := ap != null and ap.get("_btn_skip") != null and bool(ap.get("_btn_skip").visible)
	var chi_locked_vis := ap != null and ap.get("_btn_chi") != null and bool(ap.get("_btn_chi").visible)
	if not use_locked or chi_locked_vis:
		fail.call("pending lock hard assert use_locked=%s chi_vis=%s" % [str(use_locked), str(chi_locked_vis)])
		return
	var img3 := root.get_texture().get_image()
	var out3 := "/tmp/shot_public_command_378_pending_lock.png"
	img3.save_png(out3)
	print("[capture] saved ", out3, " size=", img3.get_width(), "x", img3.get_height(),
		" state=pending_lock inventory_use_locked=", use_locked, " skip_visible=", skip_vis)

	# ERROR restore
	table._unlock_public_inputs_restore_decision()
	table.sync_public_table_projection()
	fpt.set_inventory_use_locked(false)
	fpt.open_inventory_drawer()
	fpt.item_inventory_drawer.set_instances([{
		"item_instance_id": "ii_cap_378",
		"item_id": "wall_collapse_v1",
		"display_name": "牌墙崩塌",
		"status": "held",
		"effect_summary": "开局减墙",
	}])
	for _m in range(16):
		await process_frame
	await RenderingServer.frame_post_draw
	var chi_vis := ap != null and ap.get("_btn_chi") != null and bool(ap.get("_btn_chi").visible)
	var pon_vis := ap != null and ap.get("_btn_pon") != null and bool(ap.get("_btn_pon").visible)
	var pass_vis := ap != null and ap.get("_btn_skip") != null and bool(ap.get("_btn_skip").visible)
	var use_ok := false
	if fpt.item_inventory_drawer != null:
		var ub2 = fpt.item_inventory_drawer.find_child("UseButton", true, false)
		use_ok = ub2 != null and ub2.visible and not ub2.disabled
	if not chi_vis or not (pon_vis or pass_vis) or not use_ok:
		fail.call("error_restore hard assert chi=%s pon=%s pass=%s use=%s" % [
			str(chi_vis), str(pon_vis), str(pass_vis), str(use_ok)])
		return
	var img4 := root.get_texture().get_image()
	var out4 := "/tmp/shot_public_command_378_error_restore.png"
	img4.save_png(out4)
	print("[capture] saved ", out4, " size=", img4.get_width(), "x", img4.get_height(),
		" state=error_restore chi_visible=", chi_vis)
	table._reward_sync_active = false
	sess.release()
	sess.queue_free()
	table.queue_free()
	await process_frame


func _capture_reward_feedback_254() -> void:
	# 1600×900：真实 LocalLoopback 冻结 journal 经 PublicCasualNetworkSession + NBC 自动同步。
	# 禁止直接 inject_reward_journal_event / apply_reward_views。公共 WS E2E 未验证。
	var table = load("res://ui/four_player_table/playable_table.gd").new()
	root.add_child(table)
	table.set_player_persona(
		"林夜彻",
		"res://assets/roguelike/characters/char_lin_yeche.png"
	)
	var Bal = load("res://meta/reward_feedback_balance_fixtures.gd")
	# 本窗片段：到账 + 真实长 iid；不含下一 OPEN（会刷新奖池文案）
	var events: Array = Bal.self_consistent_full_grant_window_events()
	if events.is_empty():
		print("[capture] #254 missing real full-grant window stream")
		table.queue_free()
		return
	var room := String(Bal.ROOM_ID)
	var iid0 := String(Bal.FULL_GRANT_INSTANCE_IDS["0"])
	var nbc := NetworkedBattleController.new(room, 0)
	nbc.configure_snapshot_registry_for_mode(str(GameSessionConfig.MODE_TRASH_TALK))
	# session 必须入树，结束 release+free，避免 WebSocketPeer/Node 泄漏
	var sess := PublicCasualNetworkSession.new()
	root.add_child(sess)
	sess.room_id = room
	sess.seat = 0
	sess.nbc = nbc
	# 先挂 UI，再逐条真实 ingest，让 session/NBC 自动驱动展示
	# （不依赖练习 local_authority；纯公共 session+NBC 路径）
	sess.bind_playable_table(table)
	for _i in range(8):
		await process_frame

	var fpt = table._table
	if fpt == null:
		print("[capture] #254 missing FourPlayerTable")
		sess.release()
		sess.queue_free()
		table.queue_free()
		return

	for raw in events:
		var d: Dictionary = raw
		var ne: NetworkedEvent = NetworkedEvent.from_dict(d)
		if ne == null:
			print("[capture] #254 from_dict fail kind=", d.get("kind"))
			continue
		if not nbc.ingest_networked_event(ne):
			print("[capture] #254 ingest fail kind=", d.get("kind"), " seq=", d.get("server_seq"))
		await process_frame
		if table.has_method("_sync_reward_feedback_if_advanced"):
			table._sync_reward_feedback_if_advanced()
	for _j in range(10):
		await process_frame
		if table.has_method("_sync_reward_feedback_if_advanced"):
			table._sync_reward_feedback_if_advanced()

	fpt.inject_caption_display({
		"seat": 0, "utterance_id": "cap254_zh", "text": "燃烧起来热血立直",
		"kind": "final", "source": "server_stt", "lang": "zh",
		"character_id": "qiu_jue",
	})
	if fpt.has_method("open_inventory_drawer"):
		fpt.open_inventory_drawer()
	for _i in range(30):
		await process_frame
	var img2 := root.get_texture().get_image()
	var out2 := "/tmp/shot_reward_feedback_254.png"
	img2.save_png(out2)
	print("[capture] saved ", out2, " size=", img2.get_width(), "x", img2.get_height(),
		" inv=", fpt.inventory_count(), " feedback=", fpt.reward_feedback_text(), " iid=", iid0,
		" path=PublicCasualNetworkSession+NBC real journal")
	if fpt.has_method("close_inventory_drawer"):
		fpt.close_inventory_drawer()
	for _i in range(15):
		await process_frame
	var img3 := root.get_texture().get_image()
	var out3 := "/tmp/shot_reward_feedback_254_hud.png"
	img3.save_png(out3)
	print("[capture] saved ", out3, " size=", img3.get_width(), "x", img3.get_height(),
		" feedback=", fpt.reward_feedback_text())
	# 断开引用链并释放 session（_exit_tree→release 会清 WebSocketPeer）
	if table.has_method("_exit_tree"):
		table._exit_tree()
	table.queue_free()
	sess.release()
	sess.queue_free()
	await process_frame
	await process_frame
