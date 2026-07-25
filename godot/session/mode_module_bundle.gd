class_name ModeModuleBundle extends RefCounted

# E2-04（#234）：会话构造期模式模块包。
# 由 GameSessionConfig.game_mode 一次性决定；运行中不可切换或被客户端 payload 伪造。
# STANDARD：四零（不创建角色能力/库存/RewardWindow/Momentum/TextAnalyzer/语音）。
# TRASH_TALK：创建最小生产模块对象；首窗能力 unarmed；不实现 E5 业务副作用。

const TRASH_TALK_COMMAND_KINDS := ["ITEM_USE"]
const TRASH_TALK_EVENT_KINDS := [
	"REWARD_WINDOW_OPENED",
	"REWARD_WINDOW_CLOSING",
	"REWARD_WINDOW_SETTLED",
	"REWARD_WINDOW_CANCELLED",
	"ITEM_GRANTED",
	"ITEM_CONSUMED",
	"ITEM_APPLIED",
	"CHARACTER_ABILITY_ARMED",
	"CHARACTER_ABILITY_DISARMED",
]

## 冻结于 from_config；外部直接赋值在 _frozen 后无效。
var _game_mode: StringName = GameSessionConfig.MODE_STANDARD
var game_mode: StringName:
	get:
		return _game_mode
	set(value):
		if _frozen:
			return
		_game_mode = value
var character_ability_slots: Array = []
var item_inventory: ItemInventoryModule = null
var reward_window: RewardWindowModule = null
var momentum: Momentum = null
var text_analyzer: TextAnalyzer = null
var voice_port: VoicePortModule = null

var _frozen: bool = false


static func from_config(config: GameSessionConfig) -> ModeModuleBundle:
	if config == null:
		return null
	var mode: StringName = config.game_mode
	if mode != GameSessionConfig.MODE_STANDARD and mode != GameSessionConfig.MODE_TRASH_TALK:
		return null

	var bundle := ModeModuleBundle.new()
	bundle._frozen = false
	bundle._game_mode = mode
	if mode == GameSessionConfig.MODE_TRASH_TALK:
		bundle._build_trash_talk_modules(config)
	# STANDARD：字段保持 null / 空数组
	bundle._frozen = true
	return bundle


func is_standard() -> bool:
	return game_mode == GameSessionConfig.MODE_STANDARD


func is_trash_talk() -> bool:
	return game_mode == GameSessionConfig.MODE_TRASH_TALK


func accepts_command_kind(kind: String) -> bool:
	if kind.is_empty():
		return false
	if is_standard() and kind in TRASH_TALK_COMMAND_KINDS:
		return false
	return true


func accepts_event_kind(kind: String) -> bool:
	if kind.is_empty():
		return false
	if is_standard() and kind in TRASH_TALK_EVENT_KINDS:
		return false
	return true


## 运行中禁止切换模式。
func try_switch_mode(_new_mode: StringName) -> bool:
	return false


## 拒绝客户端事件/payload 伪造模式切换。
func apply_client_mode_override(_payload: Variant) -> bool:
	return false


func _build_trash_talk_modules(config: GameSessionConfig) -> void:
	reward_window = RewardWindowModule.new()
	item_inventory = ItemInventoryModule.new()
	momentum = Momentum.new()
	text_analyzer = TextAnalyzer.new()
	voice_port = VoicePortModule.new()
	# E4-01：练习场 seat 0；room_id 默认 session_id，公共场未来由 authority 覆盖。
	voice_port.bind_context(config, 0)
	character_ability_slots = []
	var ids: Array = config.character_ids
	for seat in range(4):
		var cid: StringName = &""
		if seat < ids.size():
			cid = StringName(ids[seat])
		var ch: Character = CharacterPool.find(cid)
		var ability_id: StringName = &""
		if ch != null:
			ability_id = ch.ability_id
		var skill: SkillResource = null
		if ability_id != &"":
			skill = BossAbilityFactory.build(ability_id)
		# 首窗 unarmed：对象可创建，不注册 registry，can_receive_hooks=false
		character_ability_slots.append(
			CharacterAbilitySlot.new(seat, cid, ability_id, skill, false)
		)
