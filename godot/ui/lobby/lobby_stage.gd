extends Control

# #302 新生产大厅的可见舞台。只发 UI 意图，不持有会话或对局业务。

signal practice_requested
signal match_requested
signal notice_requested
signal help_requested
signal settings_requested
signal character_codex_requested(source: Control)
signal item_codex_requested(source: Control)
signal rules_requested(source: Control)
signal bgm_requested(source: Control)
signal sfx_requested(source: Control)

const HOOK_NAMES := [
	"LobbyStage", "EnvironmentBackdrop", "CharacterStage", "ResidentPortrait",
	"PlayerAvatar", "TopResourceBar", "IdentityPlaque", "ResourcePlaque",
	"ResidentNameplate", "ResidentName", "ResidentRole",
	"ModeBannerRail", "PracticeButton", "MatchButton",
	"RulesBannerButton", "OmamoriRail", "BottomNav", "StatusLabel",
	"NoticeButton", "HelpButton", "SettingsButton", "CharacterCodexButton",
	"ItemCodexButton", "RulesButton", "BgmButton", "SfxButton",
]

const DEFAULT_RESIDENT_ID := &"lin_yeche"
const DEFAULT_RESIDENT_CUTOUT := "res://assets/ui/lobby_stage/resident_lin_yeche_cutout.png"
const DEFAULT_RESIDENT_AVATAR := "res://assets/ui/lobby_stage/resident_lin_yeche_avatar.png"


func _ready() -> void:
	_apply_existing_resident()
	_style_chrome()
	_connect_actions()
	_configure_focus_path()


func _apply_existing_resident() -> void:
	var characters := CharacterPool.all()
	if characters.is_empty():
		return
	var resident := characters[0] as Character
	if resident == null or resident.id != DEFAULT_RESIDENT_ID:
		return
	if resident.portrait_path == "" or not ResourceLoader.exists(resident.portrait_path):
		return
	if not ResourceLoader.exists(DEFAULT_RESIDENT_CUTOUT) or not ResourceLoader.exists(DEFAULT_RESIDENT_AVATAR):
		return
	var portrait := $CharacterStage/ResidentPortrait as TextureRect
	var avatar := $TopResourceBar/IdentityPlaque/IdentityRow/PlayerAvatar as TextureRect
	portrait.texture = load(DEFAULT_RESIDENT_CUTOUT) as Texture2D
	avatar.texture = load(DEFAULT_RESIDENT_AVATAR) as Texture2D
	$CharacterStage/ResidentNameplate/NameplateCopy/ResidentName.text = resident.display_name
	var seat_name := resident.description.get_slice("。", 0)
	$CharacterStage/ResidentNameplate/NameplateCopy/ResidentRole.text = "%s · 常驻雀士" % seat_name
	portrait.set_meta("source_portrait_path", resident.portrait_path)
	avatar.set_meta("source_portrait_path", resident.portrait_path)


func get_hook_nodes() -> Array[Node]:
	var hooks: Array[Node] = []
	for node_name in HOOK_NAMES:
		var found := find_child(node_name, true, false)
		if found != null:
			hooks.append(found)
	return hooks


func set_status(text: String) -> void:
	$StatusLabel.text = text


func _connect_actions() -> void:
	$ModeBannerRail/PracticeButton.pressed.connect(func() -> void: practice_requested.emit())
	$ModeBannerRail/MatchButton.pressed.connect(func() -> void: match_requested.emit())
	$ModeBannerRail/RulesBannerButton.pressed.connect(
		func() -> void: rules_requested.emit($ModeBannerRail/RulesBannerButton))
	$OmamoriRail/NoticeButton.pressed.connect(func() -> void: notice_requested.emit())
	$OmamoriRail/HelpButton.pressed.connect(func() -> void: help_requested.emit())
	$OmamoriRail/SettingsButton.pressed.connect(func() -> void: settings_requested.emit())
	$OmamoriRail/CharacterCodexButton.pressed.connect(
		func() -> void: character_codex_requested.emit($OmamoriRail/CharacterCodexButton))
	$OmamoriRail/ItemCodexButton.pressed.connect(
		func() -> void: item_codex_requested.emit($OmamoriRail/ItemCodexButton))
	$OmamoriRail/RulesButton.pressed.connect(
		func() -> void: rules_requested.emit($OmamoriRail/RulesButton))
	$BottomNav/NavRow/CharacterNavButton.pressed.connect(
		func() -> void: character_codex_requested.emit($BottomNav/NavRow/CharacterNavButton))
	$BottomNav/NavRow/ItemNavButton.pressed.connect(
		func() -> void: item_codex_requested.emit($BottomNav/NavRow/ItemNavButton))
	$BottomNav/NavRow/RulesNavButton.pressed.connect(
		func() -> void: rules_requested.emit($BottomNav/NavRow/RulesNavButton))
	$BottomNav/NavRow/BgmButton.pressed.connect(
		func() -> void: bgm_requested.emit($BottomNav/NavRow/BgmButton))
	$BottomNav/NavRow/SfxButton.pressed.connect(
		func() -> void: sfx_requested.emit($BottomNav/NavRow/SfxButton))
	$TopResourceBar/ResourcePlaque/ResourceRow/ActivityButton.pressed.connect(
		func() -> void: notice_requested.emit())


func _configure_focus_path() -> void:
	var practice := $ModeBannerRail/PracticeButton as Button
	var match_button := $ModeBannerRail/MatchButton as Button
	var rules := $ModeBannerRail/RulesBannerButton as Button
	practice.focus_neighbor_bottom = practice.get_path_to(match_button)
	match_button.focus_neighbor_top = match_button.get_path_to(practice)
	match_button.focus_neighbor_bottom = match_button.get_path_to(rules)
	rules.focus_neighbor_top = rules.get_path_to(match_button)


func _style_chrome() -> void:
	for panel in [
		$TopResourceBar/IdentityPlaque,
		$TopResourceBar/ResourcePlaque,
		$CharacterStage/ResidentNameplate,
		$BottomNav,
	]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.035, 0.025, 0.025, 0.88)
		style.border_color = Color(0.68, 0.12, 0.07, 0.82)
		style.set_border_width_all(1)
		style.set_corner_radius_all(8)
		style.shadow_color = Color(0, 0, 0, 0.55)
		style.shadow_size = 8
		panel.add_theme_stylebox_override("panel", style)
	for button in $BottomNav/NavRow.get_children():
		if button is Button:
			DesignTokens.apply_button_role(button as Button, DesignTokens.BtnRole.GHOST)
	var activity := $TopResourceBar/ResourcePlaque/ResourceRow/ActivityButton as Button
	DesignTokens.apply_button_role(activity, DesignTokens.BtnRole.GHOST)
