extends Node

# Log - 中央化日志 autoload。统一替换散落的 print() / push_warning() / push_error(),
# 加 level + tag + 时间戳 + ring buffer 让 DebugOverlay 等工具可读 recent logs。
#
# 用法:
#   Log.info("battle", "hand started seed=%d" % seed)
#   Log.warn("audio", "fallback to silent (key=%s)" % key)
#   Log.err("save", "failed to write user://savegame.json: %s" % err)
#
# Levels (按严重度递增):
#   DEBUG -- 详细诊断,默认 dev 开 release 关
#   INFO  -- 正常运行流摘要(开局/胡牌/通关)
#   WARN  -- 非致命异常(fallback/missing asset),走 push_warning
#   ERROR -- 业务异常,走 push_error + 留 stack trace
#
# Ring buffer 默认 200 行,DebugOverlay F3 可调 show_recent_logs() 取最近 20 条。

enum Level { DEBUG, INFO, WARN, ERR }

const LEVEL_LABELS: Dictionary = {
	Level.DEBUG: "D",
	Level.INFO: "I",
	Level.WARN: "W",
	Level.ERR: "E",
}

const RING_CAPACITY: int = 200

# 全局最低 level — 低于此 level 的不入 buffer 不打 stdout。
# release builds 可设 Level.INFO 屏蔽 DEBUG;暂全开 DEBUG 便于诊断。
var min_level: int = Level.DEBUG

# Ring buffer:[{level, tag, msg, ts_ms}, ...]。head = next write idx。
var _ring: Array = []
var _ring_head: int = 0

# 任意 log 进来 emit;DebugOverlay 可 connect 显示 ticker
signal log_emitted(level: int, tag: String, msg: String, ts_ms: int)


func _ready() -> void:
	# 预先分配 buffer 避免 array 扩容抖动
	for _i in range(RING_CAPACITY):
		_ring.append(null)


# ---- 公开 API ----

func debug(tag: String, msg: String) -> void:
	_log(Level.DEBUG, tag, msg)


func info(tag: String, msg: String) -> void:
	_log(Level.INFO, tag, msg)


func warn(tag: String, msg: String) -> void:
	_log(Level.WARN, tag, msg)
	push_warning("[%s] %s" % [tag, msg])


func err(tag: String, msg: String) -> void:
	_log(Level.ERR, tag, msg)
	push_error("[%s] %s" % [tag, msg])


# 取最近 N 条(按时间正序,最旧在前)
func recent(n: int = 20) -> Array:
	var out: Array = []
	var start_idx: int = (_ring_head - n + RING_CAPACITY) % RING_CAPACITY
	for i in range(min(n, RING_CAPACITY)):
		var idx: int = (start_idx + i) % RING_CAPACITY
		var entry = _ring[idx]
		if entry != null:
			out.append(entry)
	return out


# 清空 buffer(测试用)
func clear() -> void:
	for i in range(RING_CAPACITY):
		_ring[i] = null
	_ring_head = 0


# 当前 buffer 大小(非 null 条目数)
func size() -> int:
	var c: int = 0
	for entry in _ring:
		if entry != null:
			c += 1
	return c


# ---- 内部 ----

func _log(level: int, tag: String, msg: String) -> void:
	if level < min_level:
		return
	var ts: int = Time.get_ticks_msec()
	var entry: Dictionary = {
		"level": level,
		"tag": tag,
		"msg": msg,
		"ts_ms": ts,
	}
	_ring[_ring_head] = entry
	_ring_head = (_ring_head + 1) % RING_CAPACITY
	# stdout — Godot 把 print 收到 console + editor output 窗
	print("[%s][%s] %s" % [LEVEL_LABELS.get(level, "?"), tag, msg])
	log_emitted.emit(level, tag, msg, ts)


# 格式化 1 行用于显示(level + tag + msg)
static func format_line(entry: Dictionary) -> String:
	var lvl: int = int(entry.get("level", Level.INFO))
	var tag: String = String(entry.get("tag", "-"))
	var msg: String = String(entry.get("msg", ""))
	return "[%s] %s: %s" % [LEVEL_LABELS.get(lvl, "?"), tag, msg]
