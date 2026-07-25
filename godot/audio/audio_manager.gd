extends Node

# AudioManager - autoload 单例,负责播放 SFX 与 BGM。
# 通过 BC event type → SFX key 映射在 PlayableTable._handle_event_toast 旁路
# 接入。volume_db 可通过 master_volume / sfx_volume 调节。
#
# SFX 文件位于 res://assets/sfx/<name>.wav,由
# godot/tools/asset_gen/procedural_sfx.py 程序化生成。生成后 Godot 导入
# 为 .import 同名文件(import_type=AudioStreamPCM),loop=false。

const SFX_DIR := "res://assets/sfx/"

# 同时多少个 SFX 可重叠播放 — UI/对战节奏不会超过这个数
const POOL_SIZE := 8

var _player_pool: Array[AudioStreamPlayer] = []
var _next_player: int = 0

# 缓存已加载的 AudioStream 避免每次重新 load
var _stream_cache: Dictionary = {}

# 用户音量设置 (0.0 = 静音, 1.0 = 满音量),底层走 linear_to_db
var sfx_volume: float = 0.8
# BGM 音量；赋值时实时同步唯一 BgmPlayer.volume_db（走 Master，不引入独立 BGM bus）
var bgm_volume: float = 0.6:
	set(value):
		bgm_volume = clampf(value, 0.0, 1.0)
		_sync_bgm_player_volume()

var _bgm_player: AudioStreamPlayer = null


func _ready() -> void:
	# 提前建好播放器池,避免运行时 new 卡顿
	for i in range(POOL_SIZE):
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_player_pool.append(p)
	_ensure_bgm_player()


## 播放本地 BGM。path 缺失时安全退化（不报错、不创建第二个 Player）。
func play_bgm(path: String) -> void:
	_ensure_bgm_player()
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	var already_same := (
		_bgm_player.stream != null
		and _bgm_player.stream.resource_path == path
		and _bgm_player.playing
	)
	if already_same:
		_sync_bgm_player_volume()
		return
	var stream: AudioStream = load(path) as AudioStream
	if stream == null:
		return
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	_bgm_player.stream = stream
	_sync_bgm_player_volume()
	_bgm_player.play()


func stop_bgm() -> void:
	if _bgm_player != null and _bgm_player.playing:
		_bgm_player.stop()


func _ensure_bgm_player() -> void:
	if _bgm_player != null and is_instance_valid(_bgm_player):
		return
	var existing := get_node_or_null("BgmPlayer") as AudioStreamPlayer
	if existing != null:
		_bgm_player = existing
	else:
		_bgm_player = AudioStreamPlayer.new()
		_bgm_player.name = "BgmPlayer"
		_bgm_player.bus = "Master"
		add_child(_bgm_player)
	_sync_bgm_player_volume()


func _sync_bgm_player_volume() -> void:
	if _bgm_player == null or not is_instance_valid(_bgm_player):
		return
	if bgm_volume <= 0.0:
		_bgm_player.volume_db = -80.0
	else:
		_bgm_player.volume_db = linear_to_db(bgm_volume)


# 播放 SFX。key 即 res://assets/sfx/<key>.wav 的 basename。
# pitch_variation 在 [1.0-variation, 1.0+variation] 范围内随机化音调,
# 让连续触发(如 tile_click)不显得机械。默认 0 = 不变。
func play(key: String, pitch_variation: float = 0.0, volume_scale: float = 1.0) -> void:
	if sfx_volume <= 0.0:
		return
	var stream: AudioStream = _get_stream(key)
	if stream == null:
		return
	var p: AudioStreamPlayer = _player_pool[_next_player]
	_next_player = (_next_player + 1) % POOL_SIZE
	p.stream = stream
	p.volume_db = linear_to_db(clamp(sfx_volume * volume_scale, 0.001, 1.0))
	if pitch_variation > 0.0:
		p.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	else:
		p.pitch_scale = 1.0
	p.play()


# 强制停止所有正在播放的 SFX(场景切换 / 局结束清场)。
func stop_all() -> void:
	for p in _player_pool:
		if p.playing:
			p.stop()


# 内部:按 key 取 stream,缓存命中直接返。
func _get_stream(key: String) -> AudioStream:
	if _stream_cache.has(key):
		return _stream_cache[key]
	var path := SFX_DIR + key + ".wav"
	if not ResourceLoader.exists(path):
		# 不打印 error 让缺资产时静默退化(开发期生成 SFX 前不卡运行)
		return null
	var stream: AudioStream = load(path)
	_stream_cache[key] = stream
	return stream


# BC 事件 → SFX key 映射。PlayableTable 在事件流上 dispatch 时调用。
# 返回空字符串表示该事件无对应 SFX。
static func sfx_key_for_event(event_type: StringName, extra: Dictionary = {}) -> String:
	match event_type:
		&"TILE_DRAWN":
			return "tile_draw"
		&"TILE_DISCARDED":
			return "tile_click"
		&"RIICHI_DECLARED":
			return "riichi_chime"
		&"TSUMO_DECLARED", &"RON_DECLARED":
			return ""  # 候选态可能取消；统一等最终 WIN_DECLARED
		&"WIN_DECLARED":
			# yakuman_multiplier >= 1 → 役満版 chime
			if int(extra.get("yakuman_multiplier", 0)) >= 1:
				return "yakuman_chime"
			return "win_chime"
		&"EXHAUSTIVE_DRAW":
			return "draw_chime"
		&"ABORTIVE_DRAW":
			return "abortive_chime"
		&"NAGASHI_MANGAN":
			return "win_chime"
		&"PLAYER_ACTION":
			var kind := String(extra.get("kind", ""))
			match kind:
				"chi", "pon":
					return "chi_tap"
				"minkan", "ankan", "added_kan":
					return "chi_tap"  # kan 复用 chi_tap (3 快 tap)
			return ""
		&"GAME_BEGIN":
			return "game_begin"
		_:
			return ""
