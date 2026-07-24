class_name ProtocolUuid extends RefCounted

# E2-02 唯一共享 UUID validator：canonical lowercase RFC 4122 v4 + variant 8/9/a/b。

const _UUID_V4_RE := \
	"^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"


static func is_canonical_v4(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var s: String = value
	if s.length() != 36:
		return false
	if s != s.to_lower():
		return false
	var re := RegEx.new()
	if re.compile(_UUID_V4_RE) != OK:
		return false
	return re.search(s) != null
