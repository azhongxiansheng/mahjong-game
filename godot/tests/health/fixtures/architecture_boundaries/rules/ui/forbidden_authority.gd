extends RefCounted

var server: LocalLoopbackServer

func read_authority(target: Object) -> Variant:
	var auth := target
	auth.get("_private_state")
	return target.get_meta("local_authority")
