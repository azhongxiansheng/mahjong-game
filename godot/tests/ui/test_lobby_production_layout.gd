extends GutTest

# E1-03（#227）：生产级 1600×900 大厅布局与稳定交互挂点。
# 规则选择态由 #228 接入；图鉴内容与音频业务归 #229。

const LOBBY_SCENE := "res://ui/lobby/lobby_shell.tscn"
const STAGE_SCENE := "res://ui/lobby/lobby_stage.tscn"
const DESIGN_SIZE := Vector2(1600, 900)
const ASSET_ROOT := "res://assets/ui/lobby_stage/"

const REQUIRED_CONTROLS := [
	"LobbyStage",
	"EnvironmentBackdrop",
	"CharacterStage",
	"ResidentPortrait",
	"PlayerAvatar",
	"TopResourceBar",
	"IdentityPlaque",
	"ResourcePlaque",
	"ResidentNameplate",
	"ResidentName",
	"ResidentRole",
	"ModeBannerRail",
	"PracticeButton",
	"MatchButton",
	"RulesBannerButton",
	"OmamoriRail",
	"BottomNav",
	"NoticeButton",
	"HelpButton",
	"SettingsButton",
	"CharacterCodexButton",
	"ItemCodexButton",
	"RulesButton",
	"BgmButton",
	"SfxButton",
	"RuleDrawerHost",
]

const UTILITY_SIGNALS := {
	"NoticeButton": "notice_pressed",
	"HelpButton": "help_pressed",
	"SettingsButton": "settings_pressed",
	"CharacterCodexButton": "character_codex_pressed",
	"ItemCodexButton": "item_codex_pressed",
	"RulesButton": "rules_pressed",
	"BgmButton": "bgm_pressed",
	"SfxButton": "sfx_pressed",
}


func _spawn_lobby(size: Vector2 = DESIGN_SIZE) -> LobbyShell:
	var host := Control.new()
	host.name = "LobbyTestHost"
	host.size = size
	add_child_autofree(host)
	var shell: LobbyShell = load(LOBBY_SCENE).instantiate()
	host.add_child(shell)
	return shell


func _global_rect(node: Control) -> Rect2:
	return node.get_global_rect()


func test_production_lobby_exposes_all_stable_layout_hooks() -> void:
	var shell := _spawn_lobby()
	await get_tree().process_frame
	for node_name in REQUIRED_CONTROLS:
		var node := shell.get_node_or_null("%%%s" % node_name)
		assert_not_null(node, "大厅应提供稳定挂点 %%%s" % node_name)
		assert_true(node is Control, "%%%s 应为 UI Control" % node_name)


func test_1600_by_900_is_a_full_stage_with_two_primary_entries_and_light_edge_chrome() -> void:
	var shell := _spawn_lobby()
	await get_tree().process_frame
	await get_tree().process_frame

	var bounds := Rect2(shell.global_position, DESIGN_SIZE)
	var backdrop := _global_rect(shell.get_node("%EnvironmentBackdrop") as Control)
	var top := _global_rect(shell.get_node("%TopResourceBar") as Control)
	var identity := _global_rect(shell.get_node("%IdentityPlaque") as Control)
	var resources := _global_rect(shell.get_node("%ResourcePlaque") as Control)
	var character := _global_rect(shell.get_node("%CharacterStage") as Control)
	var nameplate := _global_rect(shell.get_node("%ResidentNameplate") as Control)
	var entries := _global_rect(shell.get_node("%ModeBannerRail") as Control)
	var omamori := _global_rect(shell.get_node("%OmamoriRail") as Control)
	var bottom := _global_rect(shell.get_node("%BottomNav") as Control)

	assert_eq(backdrop, bounds, "批准的日式雀庄环境必须全幅覆盖 16:9 舞台")
	for region in [top, identity, resources, character, nameplate, entries, omamori, bottom]:
		assert_true(bounds.encloses(region), "主要布局区域不得越出 1600×900 画布")
	assert_lt(character.get_center().x, DESIGN_SIZE.x * 0.55, "角色必须占据左侧主舞台")
	assert_gt(entries.position.x, DESIGN_SIZE.x * 0.52, "双主入口必须位于右侧舞台")
	assert_gt(omamori.position.x, entries.end.x, "御守功能列必须单侧贴边且不遮玩法入口")
	assert_lte(top.position.y, 24.0, "资源/活动带必须贴近顶部")
	assert_gte(bottom.end.y, DESIGN_SIZE.y - 24.0, "角色化导航必须贴近底部且不裁切")
	assert_lt(identity.end.x, DESIGN_SIZE.x * 0.38, "身份短札不得形成整宽顶部黑栏")
	assert_gt(resources.position.x, DESIGN_SIZE.x * 0.60, "资源短札应贴右并让出环境中段")
	assert_false(identity.intersects(resources), "左右顶部短札不得相连成整宽黑栏")
	assert_lt(bottom.size.x, 650.0, "底部功能层应贴合真实按钮宽度，不保留大片空黑区")
	assert_lt(nameplate.size.y, 100.0, "角色名札应保持短促，不得遮挡角色下半身")
	assert_lte(nameplate.end.x, entries.position.x, "角色名札不得侵入玩法入口")
	assert_eq((shell.get_node("%ModeBannerRail") as Control).get_child_count(), 3,
		"规则次级木札仍须保留第三个稳定入口")
	var practice := shell.get_node("%PracticeButton") as Control
	var match_button := shell.get_node("%MatchButton") as Control
	var rules := shell.get_node("%RulesBannerButton") as Control
	assert_almost_eq(practice.size.y, match_button.size.y, 1.0, "两项一级入口应保持等权")
	assert_gt(practice.size.y, rules.size.y * 1.35, "练习入口必须显著高于规则次级木札")
	assert_gt(match_button.size.y, rules.size.y * 1.35, "匹配入口必须显著高于规则次级木札")
	assert_null(shell.find_child("MainRow", true, false), "新骨架不得复用旧左右分栏")
	assert_null(shell.find_child("RootVBox", true, false), "新骨架不得复用旧 SaaS 容器")


func test_1280_by_720_degradation_keeps_stage_regions_separate_and_inside_bounds() -> void:
	var compact_size := Vector2(1280, 720)
	var shell := _spawn_lobby(compact_size)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(shell.size, DESIGN_SIZE,
		"1280×720 窗口应按项目 stretch 契约缩放 1600×900 逻辑舞台，不重排业务控件")
	var bounds := Rect2(shell.global_position, shell.size)
	var regions: Array[Control] = [
		shell.get_node("%IdentityPlaque") as Control,
		shell.get_node("%ResourcePlaque") as Control,
		shell.get_node("%CharacterStage") as Control,
		shell.get_node("%ResidentNameplate") as Control,
		shell.get_node("%ModeBannerRail") as Control,
		shell.get_node("%OmamoriRail") as Control,
		shell.get_node("%BottomNav") as Control,
	]
	for region in regions:
		var rect := _global_rect(region)
		assert_true(bounds.encloses(rect), "%s 不得在 1280×720 缩放舞台越界：%s / %s" % [
			region.name, rect, bounds,
		])
	var entries := _global_rect(shell.get_node("%ModeBannerRail") as Control)
	var omamori := _global_rect(shell.get_node("%OmamoriRail") as Control)
	var nameplate := _global_rect(shell.get_node("%ResidentNameplate") as Control)
	var bottom := _global_rect(shell.get_node("%BottomNav") as Control)
	assert_false(entries.intersects(omamori), "降级尺寸下御守不得遮挡主入口")
	assert_false(nameplate.intersects(bottom), "降级尺寸下角色名札不得遮挡底部导航")


func test_layout_keeps_top_bottom_unclipped_on_larger_16_by_9_viewport() -> void:
	var shell := _spawn_lobby(Vector2(1920, 1080))
	await get_tree().process_frame
	await get_tree().process_frame

	var top := _global_rect(shell.get_node("%TopResourceBar") as Control)
	var entries := _global_rect(shell.get_node("%ModeBannerRail") as Control)
	var bottom := _global_rect(shell.get_node("%BottomNav") as Control)
	assert_lte(top.end.x, 1920.0, "放大窗口后顶栏不得裁切")
	assert_lte(entries.end.x, 1920.0, "放大窗口后三入口不得裁切")
	assert_lte(bottom.end.x, 1920.0, "放大窗口后底栏不得越过右边界")
	assert_lte(bottom.end.y, 1080.0, "放大窗口后底栏不得越过下边界")


func test_stage_uses_existing_character_pool_portrait_and_real_atlas_regions() -> void:
	var resident_cutout_path := ASSET_ROOT + "resident_lin_yeche_cutout.png"
	var resident_avatar_path := ASSET_ROOT + "resident_lin_yeche_avatar.png"
	for file_name in [
		"lobby_environment_16x9.png",
		"mode_banner_sheet_transparent.png",
		"side_omamori_icons_transparent.png",
		"resident_lin_yeche_cutout.png",
		"resident_lin_yeche_avatar.png",
	]:
		assert_true(ResourceLoader.exists(ASSET_ROOT + file_name), "批准资产必须进入生产加载路径：%s" % file_name)
	assert_true(ResourceLoader.exists(STAGE_SCENE), "可见大厅必须来自独立 LobbyStage 场景")
	var shell := _spawn_lobby()
	await get_tree().process_frame
	var backdrop := shell.get_node("%EnvironmentBackdrop") as TextureRect
	var portrait := shell.get_node("%ResidentPortrait") as TextureRect
	var avatar := shell.get_node("%PlayerAvatar") as TextureRect
	var resident := CharacterPool.all()[0] as Character
	assert_eq(backdrop.texture.resource_path, ASSET_ROOT + "lobby_environment_16x9.png")
	assert_not_null(resident)
	assert_eq(resident.id, &"lin_yeche", "当前生产大厅默认角色身份必须来自 CharacterPool 首位")
	assert_eq(portrait.get_meta("source_portrait_path", ""), resident.portrait_path,
		"透明舞台立绘必须记录其真实 CharacterPool 来源")
	assert_eq(avatar.get_meta("source_portrait_path", ""), resident.portrait_path,
		"顶栏头像必须与舞台立绘来自同一生产角色图")
	assert_eq(portrait.texture.resource_path, resident_cutout_path,
		"大厅舞台必须消费现有角色图派生的透明 cutout")
	assert_eq(avatar.texture.resource_path, resident_avatar_path,
		"顶栏必须消费同源裁切头像")
	assert_eq((shell.get_node("%ResidentName") as Label).text, resident.display_name,
		"角色名札必须绑定当前真实常驻角色")
	assert_true((shell.get_node("%ResidentRole") as Label).text.contains("读脊"),
		"角色名札应显示角色既有原创席位语义")
	assert_false(portrait.texture.resource_path.contains("hero_male_transparent"),
		"被否决的漂移角色不得进入生产路径")
	for button_name in ["PracticeButton", "MatchButton", "RulesBannerButton"]:
		var banner := shell.get_node("%%%s" % button_name) as Button
		var art := banner.find_child("BannerArt", true, false) as TextureRect
		assert_true(art.texture is AtlasTexture, "%s 必须从批准素材表裁切真实区域" % button_name)
		assert_gt((art.texture as AtlasTexture).region.size.x, 0.0)


func test_entry_and_utility_buttons_emit_public_hook_signals() -> void:
	var shell := _spawn_lobby()
	await get_tree().process_frame
	watch_signals(shell)

	(shell.get_node("%PracticeButton") as Button).pressed.emit()
	assert_signal_emitted(shell, "practice_pressed")
	(shell.get_node("%MatchButton") as Button).pressed.emit()
	assert_signal_emitted(shell, "match_pressed")
	(shell.get_node("%RulesBannerButton") as Button).pressed.emit()
	assert_signal_emitted(shell, "rules_pressed", "第三条牌匾必须映射既有规则入口")
	for button_name in UTILITY_SIGNALS:
		var signal_name: String = UTILITY_SIGNALS[button_name]
		assert_true(shell.has_signal(signal_name), "大厅应声明 %s" % signal_name)
		(shell.get_node("%%%s" % button_name) as Button).pressed.emit()
		assert_signal_emitted(shell, signal_name)


func test_keyboard_focus_reaches_primary_and_utility_actions() -> void:
	var shell := _spawn_lobby()
	await get_tree().process_frame
	var focusable_names := [
		"PracticeButton",
		"MatchButton",
		"RulesBannerButton",
		"NoticeButton",
		"HelpButton",
		"SettingsButton",
		"CharacterCodexButton",
		"ItemCodexButton",
		"RulesButton",
		"BgmButton",
		"SfxButton",
	]
	for node_name in focusable_names:
		var button := shell.get_node("%%%s" % node_name) as Button
		assert_eq(button.focus_mode, Control.FOCUS_ALL, "%%%s 必须支持键盘焦点" % node_name)
	var practice := shell.get_node("%PracticeButton") as Button
	var match_button := shell.get_node("%MatchButton") as Button
	var rules_banner := shell.get_node("%RulesBannerButton") as Button
	assert_eq(
		practice.focus_neighbor_bottom,
		practice.get_path_to(match_button),
		"向下应从电脑练习移动到公共匹配"
	)
	assert_eq(
		match_button.focus_neighbor_top,
		match_button.get_path_to(practice),
		"向上应从公共匹配返回电脑练习"
	)
	assert_eq(match_button.focus_neighbor_bottom, match_button.get_path_to(rules_banner))
	assert_eq(rules_banner.focus_neighbor_top, rules_banner.get_path_to(match_button))


func test_omamori_column_has_six_real_accessible_actions() -> void:
	var shell := _spawn_lobby()
	await get_tree().process_frame
	var rail := shell.get_node("%OmamoriRail") as Control
	var actions: Array[Button] = []
	for child in rail.get_children():
		if child is Button:
			actions.append(child)
	assert_eq(actions.size(), 6, "单侧御守列必须完整承载六个既有功能")
	for button in actions:
		assert_ne(button.text, "", "御守按钮必须保留真实 Button 文本/可访问性语义")
		assert_eq(button.focus_mode, Control.FOCUS_ALL)


func test_rule_drawer_host_is_hidden_and_non_interactive_on_cold_start() -> void:
	var shell := _spawn_lobby()
	await get_tree().process_frame
	var host := shell.get_node("%RuleDrawerHost") as Control
	assert_false(host.visible, "大厅冷启动不应直接展开规则抽屉")
	assert_eq(host.get_child_count(), 1, "#228 应在既有宿主内只挂一个规则抽屉")
	assert_eq(host.mouse_filter, Control.MOUSE_FILTER_IGNORE, "隐藏宿主不得拦截大厅输入")


func test_e1_03_does_not_cross_into_session_voice_or_run_implementation() -> void:
	var script: GDScript = load("res://ui/lobby/lobby_shell.gd")
	assert_not_null(script)
	for forbidden in [
		"GameSessionConfig",
		"run_flow",
		"RunState",
		"voice",
		"Voice",
		"PTT",
		"麦克风",
		"语音",
	]:
		assert_false(script.source_code.contains(forbidden), "#227 不得越界引入：%s" % forbidden)
