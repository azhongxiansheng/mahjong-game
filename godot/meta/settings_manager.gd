extends Node

# SettingsManager - autoload 单例,持久化用户设置(音量等)。
# 与 SaveSystem(对应 Run 进度)分离 — 设置跨 Run 永久保留,不跟着删档清。
#
# 存储格式:user://settings.json
# 字段:sfx_volume (0..1), bgm_volume (0..1), reserved_for_future
#
# 调用流:
#   - AudioManager._ready 调 SettingsManager.sfx_volume 同步音量
#   - SettingsOverlay 滑条改值 → set_sfx_volume → 持久化 + 通知 AudioManager
#
# 容错:文件不存在 / 解析失败 → 用默认值(全开 0.8)

const SETTINGS_PATH: String = "user://settings.json"

var sfx_volume: float = 0.8
var bgm_volume: float = 0.6
# 新手引导首次启动后置 true,RunFlow._ready 不再弹 TutorialOverlay。
# 玩家可在 SettingsOverlay 重置 → 重新看引导。
var tutorial_seen: bool = false
# 全屏模式:true = exclusive fullscreen,false = windowed。DisplayServer 应用。
var fullscreen: bool = false
# 帧率上限:0 = 不限制,>0 = 上限值。Engine.max_fps 直接应用。
# 常用预设:60 / 120 / 144 / 0(unlimited)。
var framerate_cap: int = 60

# T5:跳过开局发牌演出(默认播放)
var skip_deal_animation: bool = false

# Settings 变化时 emit;AudioManager 可以 connect 在线响应
signal settings_changed


func _ready() -> void:
	_load_from_disk()
	# 启动后同步 AudioManager 音量(避免 AudioManager._ready 时 SettingsManager 还没载)
	_apply_to_audio()
	_apply_fullscreen()
	_apply_framerate_cap()


func set_sfx_volume(v: float) -> void:
	sfx_volume = clamp(v, 0.0, 1.0)
	_apply_to_audio()
	_save_to_disk()
	settings_changed.emit()


func set_bgm_volume(v: float) -> void:
	bgm_volume = clamp(v, 0.0, 1.0)
	_apply_to_audio()
	_save_to_disk()
	settings_changed.emit()


func set_tutorial_seen(b: bool) -> void:
	tutorial_seen = b
	_save_to_disk()
	settings_changed.emit()


func set_fullscreen(b: bool) -> void:
	fullscreen = b
	_apply_fullscreen()
	_save_to_disk()
	settings_changed.emit()


func set_skip_deal_animation(b: bool) -> void:
	skip_deal_animation = b
	_save_to_disk()


func set_framerate_cap(fps: int) -> void:
	# 接受 0 (uncap) 或 30-300。其它值 clamp。
	if fps != 0:
		fps = clamp(fps, 30, 300)
	framerate_cap = fps
	_apply_framerate_cap()
	_save_to_disk()
	settings_changed.emit()


# ---- internal ----

func _apply_to_audio() -> void:
	var am = get_node_or_null("/root/AudioManager")
	if am != null and "sfx_volume" in am:
		am.sfx_volume = sfx_volume


func _apply_fullscreen() -> void:
	# Headless 跑 unit test 时 DisplayServer 没窗,跳过避免崩
	if not DisplayServer.has_feature(DisplayServer.FEATURE_SUBWINDOWS):
		return
	var target_mode: int = DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen \
		else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != target_mode:
		DisplayServer.window_set_mode(target_mode)


func _apply_framerate_cap() -> void:
	# 0 = 不限,Engine.max_fps=0 内部表示无限制
	Engine.max_fps = max(0, framerate_cap)


func _load_from_disk() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if file == null:
		return
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return
	sfx_volume = clamp(float(parsed.get("sfx_volume", sfx_volume)), 0.0, 1.0)
	bgm_volume = clamp(float(parsed.get("bgm_volume", bgm_volume)), 0.0, 1.0)
	tutorial_seen = bool(parsed.get("tutorial_seen", false))
	fullscreen = bool(parsed.get("fullscreen", false))
	skip_deal_animation = bool(parsed.get("skip_deal_animation", false))
	var fps_v: int = int(parsed.get("framerate_cap", 60))
	if fps_v != 0:
		fps_v = clamp(fps_v, 30, 300)
	framerate_cap = fps_v


func _save_to_disk() -> void:
	var d: Dictionary = {
		"sfx_volume": sfx_volume,
		"bgm_volume": bgm_volume,
		"tutorial_seen": tutorial_seen,
		"fullscreen": fullscreen,
		"skip_deal_animation": skip_deal_animation,
		"framerate_cap": framerate_cap,
	}
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SettingsManager._save_to_disk: can't open %s" % SETTINGS_PATH)
		return
	file.store_string(JSON.stringify(d, "\t"))
	file.close()
