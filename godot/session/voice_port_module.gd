class_name VoicePortModule extends RefCounted

# E2-04：欢乐场语音接口生产模块（最小对象）。
# 不实现 E4 PTT / 采麦 / STT 业务；默认不申请麦克风。

var microphone_requested: bool = false


func request_microphone() -> bool:
	# E2-04 仅占位；采麦归 #243
	return false
