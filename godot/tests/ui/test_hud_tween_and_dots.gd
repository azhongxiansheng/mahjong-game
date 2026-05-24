extends GutTest

# RunHud 数字 tween + flash & PlayerActionPanel "AI 思考中" 点点动画。


# ---- HUD HP/gold tween ----

const RUN_HUD := preload("res://ui/run/run_hud.tscn")


func _make_hud() -> RunHud:
	var hud: RunHud = RUN_HUD.instantiate()
	add_child_autofree(hud)
	return hud


# 首次 bind 不 tween,直接 set
func test_hud_first_bind_jumps_no_tween() -> void:
	var hud := _make_hud()
	await get_tree().process_frame
	var rs := RunState.new(42)
	rs.hp = 30
	rs.max_hp = 50
	rs.gold = 10
	hud.bind_run_state(rs)
	# 首次 bind 后 _last_hp 应等于 new_hp (无 tween 起跳)
	assert_eq(hud._last_hp, 30, "首次 bind _last_hp 应直接 = new_hp")
	assert_eq(hud._last_gold, 10, "首次 bind _last_gold 应直接 = new_gold")


# 第二次 bind 不同 HP 值时,_last_hp 立刻更新到新值(tween 是异步的不影响 var)
func test_hud_second_bind_updates_last_hp() -> void:
	var hud := _make_hud()
	await get_tree().process_frame
	var rs := RunState.new(42)
	rs.hp = 50
	rs.max_hp = 50
	rs.gold = 100
	hud.bind_run_state(rs)
	# 第二次 bind:hp 减 10
	rs.hp = 40
	hud.bind_run_state(rs)
	assert_eq(hud._last_hp, 40)


# Max HP 变化时 jump 不 tween(章节升级场景)
func test_hud_max_hp_change_jumps() -> void:
	var hud := _make_hud()
	await get_tree().process_frame
	var rs := RunState.new(42)
	rs.hp = 30
	rs.max_hp = 50
	hud.bind_run_state(rs)
	# Max HP 升到 60(章节升级) — 应 jump 不 tween
	rs.max_hp = 60
	rs.hp = 60
	hud.bind_run_state(rs)
	assert_eq(hud._last_hp, 60)
	assert_eq(hud._last_max_hp, 60)


# 同值再 bind 不应崩(tween 跳过)
func test_hud_same_value_no_op() -> void:
	var hud := _make_hud()
	await get_tree().process_frame
	var rs := RunState.new(42)
	rs.hp = 50
	rs.max_hp = 50
	hud.bind_run_state(rs)
	hud.bind_run_state(rs)
	assert_eq(hud._last_hp, 50)


# ---- PlayerActionPanel dots animation ----

const ACTION_PANEL := preload("res://ui/four_player_table/player_action_panel.tscn")


func _make_panel() -> PlayerActionPanel:
	var p: PlayerActionPanel = ACTION_PANEL.instantiate()
	add_child_autofree(p)
	return p


func test_enter_idle_with_ellipsis_starts_dots() -> void:
	var p := _make_panel()
	await get_tree().process_frame
	p.enter_idle("AI 出牌中…")
	# 启动后 _dots_base_text 应去掉 "…"
	assert_eq(p._dots_base_text, "AI 出牌中")
	# tween 应有效
	assert_true(p._dots_tween != null and p._dots_tween.is_valid(),
		"dots tween 应启动")


func test_enter_idle_without_ellipsis_no_tween() -> void:
	var p := _make_panel()
	await get_tree().process_frame
	p.enter_idle("立直！")
	# 无 "…" 不应启动 tween
	assert_true(p._dots_tween == null or not p._dots_tween.is_valid(),
		"无省略号不应启动 dots tween")


# 三点循环计数
func test_set_dots_n_suffix() -> void:
	var p := _make_panel()
	await get_tree().process_frame
	p._dots_base_text = "X"
	p._set_dots(0)
	assert_eq(p._label_status.text, "X")
	p._set_dots(1)
	assert_eq(p._label_status.text, "X·")
	p._set_dots(3)
	assert_eq(p._label_status.text, "X···")


# enter_idle 切换文本应停止旧的 tween 启新的
func test_re_enter_idle_resets_dots_tween() -> void:
	var p := _make_panel()
	await get_tree().process_frame
	p.enter_idle("AI 出牌中…")
	var old_tween = p._dots_tween
	p.enter_idle("等待对家鸣牌…")
	assert_true(p._dots_tween != old_tween, "新 enter_idle 应启用新 tween")
	assert_eq(p._dots_base_text, "等待对家鸣牌")
