class_name EventPayloadCodecRegistry extends RefCounted

# ARCH-03 #393：payload codec 注册表。构造时即冻结（不暴露 register），
# 按 kind 分发到领域 codec；未知 kind / 控制类 kind 一律返回 null 拒绝。
# 校验函数签名统一 (payload, envelope_server_seq)；不需要 seq 的领域忽略之。

var _codecs: Dictionary = {}


func _init() -> void:
	_codecs = {
		"ACTION_APPLIED":
			func(p: Dictionary, _seq: int): return TableFlowPayloadCodec.validate_action_applied(p),
		"TURN_PROMPT":
			func(p: Dictionary, _seq: int): return TableFlowPayloadCodec.validate_turn_prompt(p),
		"CLAIM_WINDOW":
			func(p: Dictionary, _seq: int): return TableFlowPayloadCodec.validate_claim_window(p),
		"ROOM_SNAPSHOT":
			func(p: Dictionary, _seq: int): return SnapshotPayloadCodec.validate_room_snapshot(p),
		"PLAYER_JOINED":
			func(p: Dictionary, _seq: int): return PresencePayloadCodec.validate_player_joined(p),
		"HAND_SETTLED":
			func(p: Dictionary, _seq: int): return SettlementPayloadCodec.validate_hand_settled(p),
		"MATCH_SETTLED":
			func(p: Dictionary, _seq: int): return SettlementPayloadCodec.validate_match_settled(p),
		"REWARD_WINDOW_OPENED":
			func(p: Dictionary, _seq: int): return RewardItemPayloadCodec.validate_reward_opened(p),
		"REWARD_WINDOW_CLOSING":
			func(p: Dictionary, seq: int): return RewardItemPayloadCodec.validate_reward_closing(p, seq),
		"REWARD_WINDOW_SETTLED":
			func(p: Dictionary, seq: int): return RewardItemPayloadCodec.validate_reward_settled(p, seq),
		"REWARD_WINDOW_CANCELLED":
			func(p: Dictionary, seq: int): return RewardItemPayloadCodec.validate_reward_cancelled(p, seq),
		"ITEM_GRANTED":
			func(p: Dictionary, _seq: int): return RewardItemPayloadCodec.validate_item_granted(p),
		"ITEM_CONSUMED":
			func(p: Dictionary, _seq: int): return RewardItemPayloadCodec.validate_item_consumed(p),
		"ITEM_APPLIED":
			func(p: Dictionary, _seq: int): return RewardItemPayloadCodec.validate_item_applied(p),
		"CHARACTER_ABILITY_ARMED":
			func(p: Dictionary, _seq: int): return RewardItemPayloadCodec.validate_ability_armed(p),
		"CHARACTER_ABILITY_DISARMED":
			func(p: Dictionary, _seq: int): return RewardItemPayloadCodec.validate_ability_disarmed(p),
		"SKILL_TRIGGERED":
			func(p: Dictionary, _seq: int): return RewardItemPayloadCodec.validate_skill_triggered(p),
	}


func has_kind(kind: String) -> bool:
	return _codecs.has(kind)


func kinds() -> Array:
	return _codecs.keys()


func validate(kind: String, payload: Dictionary, envelope_server_seq: int) -> Variant:
	if not _codecs.has(kind):
		return null
	return (_codecs[kind] as Callable).call(payload, envelope_server_seq)
