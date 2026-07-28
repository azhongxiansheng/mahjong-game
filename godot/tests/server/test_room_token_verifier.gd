extends GutTest

# #240：RoomTokenVerifier + Go 跨语言 fixture（只验不重签）。

const FIXTURE := "res://tests/_fixtures/room_token_crosslang.json"
const SECRET_LEN_OK := "0123456789abcdef0123456789abcdef"


func test_crosslang_go_issued_token_verifies() -> void:
	assert_true(FileAccess.file_exists(FIXTURE), "缺 Go 跨语言 fixture，先跑 go test ./internal/tokens")
	if not FileAccess.file_exists(FIXTURE):
		return
	var raw := FileAccess.get_file_as_string(FIXTURE)
	var doc: Variant = JSON.parse_string(raw)
	assert_true(typeof(doc) == TYPE_DICTIONARY, "fixture JSON")
	if typeof(doc) != TYPE_DICTIONARY:
		return
	var d: Dictionary = doc
	var secret: String = str(d["secret"])
	var token: String = str(d["token"])
	var claims_doc: Dictionary = d["claims"]
	var issued: int = int(d["issued_at_unix"])
	var v := RoomTokenVerifier.new()
	assert_true(v.set_secret(secret))
	var claims: Dictionary = v.verify(
		token,
		str(claims_doc["room_id"]),
		int(claims_doc["seat"]),
		issued
	)
	assert_false(claims.is_empty(), "Go 签发 token 必须被 GDScript 验证")
	if claims.is_empty():
		return
	assert_eq(str(claims["room_id"]), "room-fixture")
	assert_eq(int(claims["seat"]), 1)
	assert_eq(str(claims["session_id"]), "sess-fixture")
	assert_eq(str(claims["round_kind"]), "EAST")
	assert_eq(str(claims["game_mode"]), "STANDARD")
	assert_eq((claims["participants"] as Array).size(), 4)
	assert_eq(str((claims["participants"] as Array)[0]), "HUMAN")
	assert_eq(str((claims["participants"] as Array)[2]), "AI")
	assert_true(claims.has("character_ids"), "claims 必须含 character_ids")
	assert_eq((claims["character_ids"] as Array).size(), 4)
	assert_eq(str((claims["character_ids"] as Array)[0]), "lin_yeche")
	assert_eq(str((claims["character_ids"] as Array)[1]), "qiu_jue")


func test_session_token_cannot_impersonate_room_token() -> void:
	# 构造伪 session 形态 v1.g.…（即使 HMAC 碰巧，typ 必须拒绝）
	var v := RoomTokenVerifier.new()
	assert_true(v.set_secret(SECRET_LEN_OK))
	var fake_guest := "v1.g.eyJ0eXAiOiJndWVzdCJ9.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	var claims := v.verify(fake_guest, "room-fixture", 1, 1784894400)
	assert_true(claims.is_empty(), "session/guest typ 不得当 room")


func test_cross_room_seat_and_tamper_fail() -> void:
	assert_true(FileAccess.file_exists(FIXTURE))
	if not FileAccess.file_exists(FIXTURE):
		return
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	var v := RoomTokenVerifier.new()
	assert_true(v.set_secret(str(d["secret"])))
	var token: String = str(d["token"])
	var issued: int = int(d["issued_at_unix"])
	assert_true(v.verify(token, "other-room", 1, issued).is_empty(), "跨房")
	assert_true(v.verify(token, "room-fixture", 0, issued).is_empty(), "跨座")
	var bad := token
	if bad.length() > 2:
		var ch := bad[bad.length() - 1]
		bad = bad.substr(0, bad.length() - 1) + ("B" if ch == "A" else "A")
	assert_true(v.verify(bad, "room-fixture", 1, issued).is_empty(), "篡改签名")
	# 过期：now >= expires_at
	var expires_at_unix: int = int(d["expires_at_unix"])
	assert_true(v.verify(token, "room-fixture", 1, expires_at_unix).is_empty(), "到期边界拒绝")


func test_weak_secret_rejected() -> void:
	var v := RoomTokenVerifier.new()
	assert_false(v.set_secret("short"))
	assert_false(v.has_secret())
