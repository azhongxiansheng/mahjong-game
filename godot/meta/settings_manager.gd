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

# Settings 变化时 emit;AudioManager 可以 connect 在线响应
signal settings_changed


func _ready() -> void:
	_load_from_disk()
	# 启动后同步 AudioManager 音量(避免 AudioManager._ready 时 SettingsManager 还没载)
	_apply_to_audio()


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


# ---- internal ----

func _apply_to_audio() -> void:
	var am = get_node_or_null("/root/AudioManager")
	if am != null and "sfx_volume" in am:
		am.sfx_volume = sfx_volume


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


func _save_to_disk() -> void:
	var d: Dictionary = {
		"sfx_volume": sfx_volume,
		"bgm_volume": bgm_volume,
	}
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SettingsManager._save_to_disk: can't open %s" % SETTINGS_PATH)
		return
	file.store_string(JSON.stringify(d, "\t"))
	file.close()
