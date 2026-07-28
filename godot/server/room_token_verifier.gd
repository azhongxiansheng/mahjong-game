class_name RoomTokenVerifier
extends RefCounted

# #240：校验 CP 签发的 room_token（HMAC-SHA256，与 Go tokens 包线格式一致）。
# 线格式：v1.r.<payload_b64url>.<sig_b64url>
# 不得日志输出 token 或密钥。网络端到端未验证。

const TOKEN_VERSION := "v1"
const TYP_ROOM := "r"
const CLAIM_ROOM := "room"
const MIN_SECRET_LEN := 32

var _secret: PackedByteArray = PackedByteArray()
var _crypto: Crypto = Crypto.new()


func _init(secret: String = "") -> void:
	if not secret.is_empty():
		set_secret(secret)


func set_secret(secret: String) -> bool:
	if secret.length() < MIN_SECRET_LEN:
		_secret = PackedByteArray()
		return false
	_secret = secret.to_utf8_buffer()
	return true


func has_secret() -> bool:
	return _secret.size() >= MIN_SECRET_LEN


## 成功返回 claims Dictionary（不含原始 token）；失败返回 {}。
## now_unix < 0 时使用系统时间；测试可注入固定 now 以消费 Go 跨语言 fixture。
func verify(token: Variant, expected_room_id: String, expected_seat: int, now_unix: int = -1) -> Dictionary:
	if not has_secret():
		return {}
	if typeof(token) != TYPE_STRING:
		return {}
	var tok: String = token
	if tok.is_empty():
		return {}
	# session_token 为 v1.g.…，此处要求 typ=r
	var parts: PackedStringArray = tok.split(".")
	if parts.size() != 4:
		return {}
	if parts[0] != TOKEN_VERSION or parts[1] != TYP_ROOM:
		return {}
	var signing_input := "%s.%s.%s" % [parts[0], parts[1], parts[2]]
	var sig: PackedByteArray = _b64url_decode(parts[3])
	if sig.is_empty():
		return {}
	var expected: PackedByteArray = _crypto.hmac_digest(
		HashingContext.HASH_SHA256,
		_secret,
		signing_input.to_utf8_buffer()
	)
	if not _const_eq(expected, sig):
		return {}
	var raw: PackedByteArray = _b64url_decode(parts[2])
	if raw.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var p: Dictionary = parsed
	if not _validate_payload(p):
		return {}
	var expires_at_unix: int = int(p["exp"])
	var now: int = now_unix
	if now < 0:
		now = int(Time.get_unix_time_from_system())
	# Go：!now.Before(exp) → 过期（等于 expires_at 也失败）
	if now >= expires_at_unix:
		return {}
	var room_id := str(p["room_id"])
	var seat: int = int(p["seat"])
	if room_id != expected_room_id or seat != expected_seat:
		return {}
	var parts_out: Array = []
	for item in p["participants"]:
		parts_out.append(str(item))
	var chars_out: Array = []
	for item in p["character_ids"]:
		chars_out.append(str(item))
	return {
		"room_id": room_id,
		"seat": seat,
		"session_id": str(p["session_id"]),
		"expires_at_unix": expires_at_unix,
		"round_kind": str(p["round_kind"]),
		"game_mode": str(p["game_mode"]),
		"participants": parts_out,
		"character_ids": chars_out,
	}


func _validate_payload(p: Dictionary) -> bool:
	for k in ["typ", "room_id", "seat", "session_id", "exp", "round_kind", "game_mode", "participants", "character_ids"]:
		if not p.has(k):
			return false
	if str(p["typ"]) != CLAIM_ROOM:
		return false
	if typeof(p["room_id"]) != TYPE_STRING or str(p["room_id"]).is_empty():
		return false
	if typeof(p["session_id"]) != TYPE_STRING or str(p["session_id"]).is_empty():
		return false
	if not (typeof(p["seat"]) == TYPE_INT or typeof(p["seat"]) == TYPE_FLOAT):
		return false
	var seat: int = int(p["seat"])
	if seat < 0 or seat > 3:
		return false
	if not (typeof(p["exp"]) == TYPE_INT or typeof(p["exp"]) == TYPE_FLOAT):
		return false
	var rk := str(p["round_kind"])
	if rk != "EAST" and rk != "HANCHAN":
		return false
	var gm := str(p["game_mode"])
	if gm != "STANDARD" and gm != "TRASH_TALK":
		return false
	if typeof(p["participants"]) != TYPE_ARRAY:
		return false
	var arr: Array = p["participants"]
	if arr.size() != 4:
		return false
	var human := 0
	for item in arr:
		var kind := str(item)
		if kind == "HUMAN":
			human += 1
		elif kind != "AI":
			return false
	if human < 1:
		return false
	if typeof(p["character_ids"]) != TYPE_ARRAY:
		return false
	var chars: Array = p["character_ids"]
	if chars.size() != 4:
		return false
	for item in chars:
		var cid := str(item)
		if cid.is_empty():
			return false
		if CharacterPool.find(StringName(cid)) == null:
			return false
	return true


static func _b64url_decode(s: String) -> PackedByteArray:
	if s.is_empty():
		return PackedByteArray()
	var t := s.replace("-", "+").replace("_", "/")
	while t.length() % 4 != 0:
		t += "="
	var out: PackedByteArray = Marshalls.base64_to_raw(t)
	return out


static func _const_eq(a: PackedByteArray, b: PackedByteArray) -> bool:
	if a.size() != b.size():
		return false
	var diff := 0
	for i in range(a.size()):
		diff |= int(a[i]) ^ int(b[i])
	return diff == 0
