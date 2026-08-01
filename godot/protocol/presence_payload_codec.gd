class_name PresencePayloadCodec extends RefCounted

# ARCH-03 #393：在场/接入 payload codec —— PLAYER_JOINED。
# 校验语义与拆分前 NetworkedEvent 完全一致。

const PLAYER_JOINED_KEYS := ["seat", "participant_kind", "display_name", "connected"]

const PARTICIPANT_KINDS := ["HUMAN", "AI"]


static func validate_player_joined(p: Dictionary) -> Variant:
	if not EventPayloadCodecUtil._has_exact_keys(p, PLAYER_JOINED_KEYS):
		return null
	var seat: Variant = EventPayloadCodecUtil._require_seat(p["seat"])
	if seat == null:
		return null
	if typeof(p["participant_kind"]) != TYPE_STRING:
		return null
	var participant_kind: String = p["participant_kind"]
	if participant_kind not in PARTICIPANT_KINDS:
		return null
	if typeof(p["display_name"]) != TYPE_STRING:
		return null
	var name: String = p["display_name"]
	if name.strip_edges().is_empty():
		return null
	if name != name.strip_edges():
		return null
	if typeof(p["connected"]) != TYPE_BOOL:
		return null
	return {
		"seat": int(seat),
		"participant_kind": participant_kind,
		"display_name": name,
		"connected": bool(p["connected"]),
	}
