extends GutTest

# AudioManager autoload — 单元测试 cover BC event → SFX key 映射 +
# play() 静默回退 / pool 循环。autoload 已由 project.godot 注册,跑测试
# 时通过 /root/AudioManager 拿。


func _am() -> Node:
	return get_tree().root.get_node_or_null("AudioManager")


func test_autoload_registered() -> void:
	assert_not_null(_am(), "/root/AudioManager autoload 应已挂载")


# ---- sfx_key_for_event 映射 ----

func test_tile_drawn_maps_to_tile_draw() -> void:
	assert_eq(AudioManager.sfx_key_for_event(&"TILE_DRAWN"), "tile_draw")


func test_tile_discarded_maps_to_tile_click() -> void:
	assert_eq(AudioManager.sfx_key_for_event(&"TILE_DISCARDED"), "tile_click")


func test_riichi_declared_maps_to_riichi_chime() -> void:
	assert_eq(AudioManager.sfx_key_for_event(&"RIICHI_DECLARED"), "riichi_chime")


func test_tsumo_declared_waits_for_confirmed_win() -> void:
	assert_eq(AudioManager.sfx_key_for_event(&"TSUMO_DECLARED"), "")


func test_ron_declared_waits_for_confirmed_win() -> void:
	assert_eq(AudioManager.sfx_key_for_event(&"RON_DECLARED"), "")


func test_exhaustive_draw_maps_to_draw_chime() -> void:
	assert_eq(AudioManager.sfx_key_for_event(&"EXHAUSTIVE_DRAW"), "draw_chime")


func test_abortive_draw_maps_to_abortive_chime() -> void:
	assert_eq(AudioManager.sfx_key_for_event(&"ABORTIVE_DRAW"), "abortive_chime")


func test_haitei_houtei_have_no_invented_dora_flip_sfx() -> void:
	assert_eq(AudioManager.sfx_key_for_event(&"HAITEI"), "")
	assert_eq(AudioManager.sfx_key_for_event(&"HOUTEI"), "")


# WIN_DECLARED yakuman_multiplier>=1 → yakuman_chime
func test_win_declared_yakuman_maps_to_yakuman() -> void:
	assert_eq(AudioManager.sfx_key_for_event(&"WIN_DECLARED",
		{"yakuman_multiplier": 1}), "yakuman_chime")


# 普通和牌同样只在不可取消的 WIN_DECLARED 播一次。
func test_win_declared_non_yakuman_maps_to_win_chime() -> void:
	assert_eq(AudioManager.sfx_key_for_event(&"WIN_DECLARED",
		{"yakuman_multiplier": 0}), "win_chime")


# PLAYER_ACTION kind=chi/pon/kan → chi_tap
func test_player_action_chi_maps_to_chi_tap() -> void:
	assert_eq(AudioManager.sfx_key_for_event(&"PLAYER_ACTION",
		{"kind": "chi"}), "chi_tap")


func test_player_action_minkan_maps_to_chi_tap() -> void:
	assert_eq(AudioManager.sfx_key_for_event(&"PLAYER_ACTION",
		{"kind": "minkan"}), "chi_tap")


# 不相关的 PLAYER_ACTION(如 discard / tsumo_accept)不响,SFX 已由
# TILE_DISCARDED / TSUMO_DECLARED cover
func test_player_action_discard_no_sfx() -> void:
	assert_eq(AudioManager.sfx_key_for_event(&"PLAYER_ACTION",
		{"kind": "discard", "tile_id": 0}), "")


# 未知 event type 返空(静默,无效果)
func test_unknown_event_no_sfx() -> void:
	assert_eq(AudioManager.sfx_key_for_event(&"FOOBAR_EVENT"), "")


# ---- play() 静默回退测试(资源不存在不应崩) ----

func test_play_missing_key_does_not_crash() -> void:
	# 即使 SFX 资源不在,play 应静默退出
	var am: Node = _am()
	if am == null:
		return
	am.play("nonexistent_sfx_key")
	# 跑到这里没崩就 ok
	assert_true(true)


func test_play_with_zero_volume_silent_short_circuit() -> void:
	var am: Node = _am()
	if am == null:
		return
	var saved: float = am.sfx_volume
	am.sfx_volume = 0.0
	am.play("button_click")  # 应早出
	am.sfx_volume = saved
	assert_true(true)  # 主要确认不崩


func test_character_voice_variants_rotate_deterministically() -> void:
	var am: Node = _am()
	if am == null:
		return
	am.stop_character_voice()
	assert_true(am.play_character_voice(&"bao_luo", &"ability", 20))
	assert_true(String(am.current_character_voice_path()).ends_with("ability_01.wav"))
	am.stop_character_voice()
	assert_true(am.play_character_voice(&"bao_luo", &"ability", 20))
	assert_true(String(am.current_character_voice_path()).ends_with("ability_02.wav"))
	am.stop_character_voice()
	assert_true(am.play_character_voice(&"qiu_jue", &"entry", 10))
	assert_true(String(am.current_character_voice_path()).ends_with("entry_01.wav"))
	am.stop_character_voice()
	assert_true(am.play_character_voice(&"qiu_jue", &"entry", 10))
	assert_true(String(am.current_character_voice_path()).ends_with("entry_02.wav"))
	am.stop_character_voice()


func test_ying_li_ability_variants_load_and_rotate_deterministically() -> void:
	var am: Node = _am()
	if am == null:
		return
	am.stop_character_voice()
	assert_true(am.play_character_voice(&"ying_li", &"ability", 20))
	assert_true(String(am.current_character_voice_path()).ends_with("ability_01.wav"))
	am.stop_character_voice()
	assert_true(am.play_character_voice(&"ying_li", &"ability", 20))
	assert_true(String(am.current_character_voice_path()).ends_with("ability_02.wav"))
	am.stop_character_voice()


func test_playable_table_exit_stops_ying_li_voice() -> void:
	var am: Node = _am()
	if am == null:
		return
	am.stop_character_voice()
	assert_true(am.play_character_voice(&"ying_li", &"entry", 10))
	var table = load("res://ui/four_player_table/playable_table.gd").new()
	add_child(table)
	table.queue_free()
	await get_tree().process_frame
	assert_eq(am.current_character_voice_path(), "")
	assert_eq(am.character_voice_pending_count(), 0)


func test_high_priority_character_voice_interrupts_normal_and_queues_peer() -> void:
	var am: Node = _am()
	if am == null:
		return
	am.stop_character_voice()
	assert_true(am.play_character_voice(&"qiu_jue", &"entry", 10))
	assert_true(am.play_character_voice(&"qiu_jue", &"ability", 20))
	assert_true(String(am.current_character_voice_path()).contains("ability_"))
	assert_true(am.play_character_voice(&"qiu_jue", &"win", 20))
	assert_eq(am.character_voice_pending_count(), 1)
	am.stop_character_voice()
	assert_eq(am.current_character_voice_path(), "")
	assert_eq(am.character_voice_pending_count(), 0)


func test_dropped_normal_voice_does_not_consume_variant() -> void:
	var am: Node = _am()
	if am == null:
		return
	am.stop_character_voice()
	assert_true(am.play_character_voice(&"qiu_jue", &"entry", 10))
	assert_false(am.play_character_voice(&"qiu_jue", &"advantage", 10))
	am.stop_character_voice()
	assert_true(am.play_character_voice(&"qiu_jue", &"advantage", 10))
	assert_true(String(am.current_character_voice_path()).ends_with("advantage_01.wav"))
	am.stop_character_voice()
