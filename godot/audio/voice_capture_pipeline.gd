class_name VoiceCapturePipeline extends Node

# E4-01（#243）：AudioStreamMicrophone + 独立 bus + AudioEffectCapture。
# 仅 PTT 按下期间运行；松开销毁节点/效果并清缓冲。

const BUS_NAME := "VoiceMicCapture"

var _port: VoicePortModule = null
var _player: AudioStreamPlayer = null
var _bus_idx: int = -1
var _capture: AudioEffectCapture = null
var _active: bool = false
var _mix_rate: int = 48000


func bind_voice_port(port: VoicePortModule) -> void:
	_port = port
	if _port != null:
		_port.attach_capture_pipeline(self)


func mix_rate() -> int:
	return _mix_rate


func is_active() -> bool:
	return _active


func start_capture() -> bool:
	if _active:
		return true
	# 在任何 mic 节点/bus/effect 创建前 fail-closed。
	if not bool(ProjectSettings.get_setting("audio/driver/enable_input", false)):
		return false
	# Godot 4.6：Dummy 驱动（无真实输入时 CoreAudio 回退）不得假装可采。
	var driver_name: String = AudioServer.get_driver_name()
	if driver_name == "Dummy":
		return false
	var devices: PackedStringArray = AudioServer.get_input_device_list()
	if devices.is_empty():
		return false
	_mix_rate = int(AudioServer.get_mix_rate())
	if _mix_rate <= 0:
		_mix_rate = 48000
	if not _setup_bus_and_player():
		_teardown_hardware()
		return false
	_active = true
	if _port != null:
		_port.mark_live_microphone_nodes(true)
	return true


func stop_capture() -> void:
	if not _active and _player == null and _capture == null:
		return
	_active = false
	if _capture != null:
		_capture.clear_buffer()
	_teardown_hardware()
	if _port != null:
		_port.mark_live_microphone_nodes(false)


func _process(_delta: float) -> void:
	if not _active or _capture == null or _port == null:
		return
	if not _port.is_capturing():
		return
	var available: int = _capture.get_frames_available()
	if available <= 0:
		return
	var stereo: PackedVector2Array = _capture.get_buffer(available)
	if stereo.is_empty():
		return
	_port.feed_capture_samples(stereo, _mix_rate)


func _setup_bus_and_player() -> bool:
	_teardown_hardware()
	_bus_idx = AudioServer.get_bus_index(BUS_NAME)
	if _bus_idx < 0:
		_bus_idx = AudioServer.bus_count
		AudioServer.add_bus()
		AudioServer.set_bus_name(_bus_idx, BUS_NAME)
	# 避免扬声器回放本席麦克风
	AudioServer.set_bus_mute(_bus_idx, true)
	# 清掉旧 effect
	while AudioServer.get_bus_effect_count(_bus_idx) > 0:
		AudioServer.remove_bus_effect(_bus_idx, 0)
	_capture = AudioEffectCapture.new()
	AudioServer.add_bus_effect(_bus_idx, _capture, 0)

	_player = AudioStreamPlayer.new()
	_player.name = "VoiceMicPlayer"
	_player.stream = AudioStreamMicrophone.new()
	_player.bus = BUS_NAME
	add_child(_player)
	_player.play()
	# 无输入设备时 Godot 可能静默失败；用一帧后缓冲峰值无法在此可靠检测。
	# 调用方在无设备环境应使用 FIXTURE backend。LIVE 仍构造链路。
	return true


func _teardown_hardware() -> void:
	if _player != null and is_instance_valid(_player):
		if _player.playing:
			_player.stop()
		_player.queue_free()
	_player = null
	if _bus_idx >= 0:
		var idx: int = AudioServer.get_bus_index(BUS_NAME)
		if idx >= 0:
			while AudioServer.get_bus_effect_count(idx) > 0:
				AudioServer.remove_bus_effect(idx, 0)
			# 保留 bus 名称槽位但静音；移除 bus 可能导致索引抖动
			AudioServer.set_bus_mute(idx, true)
	_capture = null
	_bus_idx = AudioServer.get_bus_index(BUS_NAME)
	_active = false


func _exit_tree() -> void:
	stop_capture()
	if _port != null:
		_port.attach_capture_pipeline(null)
