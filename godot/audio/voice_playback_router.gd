class_name VoicePlaybackRouter extends Node

# E4-01（#243）：远端席（除 local_seat 外的 0–3）→ 有界队列消费 → AudioStreamGeneratorPlayback。
# PCM16 mono 解码后复制到左右声道。从 VoicePort.local_seat() 动态推导，不硬编码 seat0。

const GENERATOR_BUFFER_LENGTH: float = 0.1  # 秒

var _port: VoicePortModule = null
var _players: Dictionary = {}  # seat -> AudioStreamPlayer
var _generators: Dictionary = {}  # seat -> AudioStreamGenerator
var _frames_pushed: Dictionary = {}  # seat -> int
var _connected: bool = false


func bind_voice_port(port: VoicePortModule) -> void:
	if _port != null and _connected and _port.remote_frame_accepted.is_connected(_on_remote_frame):
		_port.remote_frame_accepted.disconnect(_on_remote_frame)
	_connected = false
	_clear_players()
	_port = port
	_ensure_players()
	if _port != null:
		if not _port.remote_frame_accepted.is_connected(_on_remote_frame):
			_port.remote_frame_accepted.connect(_on_remote_frame)
		_connected = true


func has_player_for_seat(seat: int) -> bool:
	return _players.has(seat) and is_instance_valid(_players[seat])


func frames_pushed_for_seat(seat: int) -> int:
	return int(_frames_pushed.get(seat, 0))


func release_all() -> void:
	if _port != null and _connected and _port.remote_frame_accepted.is_connected(_on_remote_frame):
		_port.remote_frame_accepted.disconnect(_on_remote_frame)
	_connected = false
	_clear_players()
	_port = null


func _remote_seats() -> Array:
	if _port == null:
		return []
	return _port.remote_seats()


func _clear_players() -> void:
	for seat in _players.keys():
		var p: AudioStreamPlayer = _players[seat]
		if p != null and is_instance_valid(p):
			if p.playing:
				p.stop()
			p.queue_free()
	_players.clear()
	_generators.clear()
	_frames_pushed.clear()


func _ensure_players() -> void:
	for seat_v in _remote_seats():
		var seat: int = int(seat_v)
		if has_player_for_seat(seat):
			continue
		var gen := AudioStreamGenerator.new()
		gen.mix_rate = float(VoicePcmConverter.TARGET_SAMPLE_RATE)
		gen.buffer_length = GENERATOR_BUFFER_LENGTH
		var player := AudioStreamPlayer.new()
		player.name = "VoicePlaybackSeat%d" % seat
		player.stream = gen
		player.bus = "Master"
		add_child(player)
		player.play()
		_players[seat] = player
		_generators[seat] = gen
		_frames_pushed[seat] = 0


func _on_remote_frame(frame: Dictionary) -> void:
	# 信号触发时帧已入队；推迟到下一空闲抽帧，避免阻塞信号栈。
	var seat_v: Variant = frame.get("seat", null)
	if typeof(seat_v) != TYPE_INT:
		return
	var seat: int = int(seat_v)
	if _port != null and seat != _port.local_seat() and seat >= 0 and seat <= 3:
		call_deferred("_drain_seat", seat)


func _process(_delta: float) -> void:
	if _port == null:
		return
	for seat_v in _remote_seats():
		_drain_seat(int(seat_v))


func _drain_seat(seat: int) -> void:
	if not has_player_for_seat(seat):
		return
	var player: AudioStreamPlayer = _players[seat]
	if player == null or not is_instance_valid(player):
		return
	if not player.playing:
		player.play()
	var playback := player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		return
	while _port.remote_queue_size(seat) > 0:
		# 保留一点缓冲空间，避免一次性打满
		if playback.get_frames_available() < VoicePcmConverter.SAMPLES_PER_FRAME:
			break
		var frame: Dictionary = _port.pop_remote_frame(seat)
		if frame.is_empty():
			break
		var pcm: PackedByteArray = frame.get("pcm", PackedByteArray()) as PackedByteArray
		var stereo: PackedVector2Array = VoicePcmConverter.pcm16_mono_to_stereo_frames(pcm)
		for s in stereo:
			playback.push_frame(s)
		_frames_pushed[seat] = int(_frames_pushed.get(seat, 0)) + 1


func _exit_tree() -> void:
	release_all()
