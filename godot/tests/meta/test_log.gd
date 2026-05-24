extends GutTest

# Log autoload — 中央化日志测试。


func _log() -> Node:
	return get_tree().root.get_node("/root/Log")


func before_each() -> void:
	_log().clear()


# ---- autoload ----

func test_autoload_registered() -> void:
	assert_not_null(_log(), "/root/Log autoload 应已挂载")


func test_levels_defined() -> void:
	# Level enum 4 个值
	assert_eq(_log().Level.DEBUG, 0)
	assert_eq(_log().Level.INFO, 1)
	assert_eq(_log().Level.WARN, 2)
	assert_eq(_log().Level.ERR, 3)


# ---- 4 个入口都进 buffer ----

func test_info_adds_entry() -> void:
	var L = _log()
	L.info("test", "hello")
	assert_eq(L.size(), 1)
	var r = L.recent(5)
	assert_eq(r.size(), 1)
	assert_eq(r[0]["level"], L.Level.INFO)
	assert_eq(r[0]["tag"], "test")
	assert_eq(r[0]["msg"], "hello")


func test_all_levels_recorded() -> void:
	var L = _log()
	L.debug("t", "d")
	L.info("t", "i")
	L.warn("t", "w")
	L.err("t", "e")
	assert_eq(L.size(), 4)


# ---- min_level 过滤 ----

func test_min_level_filters_debug() -> void:
	var L = _log()
	L.min_level = L.Level.INFO
	L.debug("t", "should be filtered")
	L.info("t", "should pass")
	assert_eq(L.size(), 1)
	# 复原
	L.min_level = L.Level.DEBUG


# ---- recent() 取最近 N 条 ----

func test_recent_returns_in_order() -> void:
	var L = _log()
	L.info("t", "a")
	L.info("t", "b")
	L.info("t", "c")
	var r = L.recent(3)
	assert_eq(r.size(), 3)
	assert_eq(r[0]["msg"], "a")
	assert_eq(r[1]["msg"], "b")
	assert_eq(r[2]["msg"], "c")


func test_recent_caps_at_buffer_size() -> void:
	var L = _log()
	# 写入超出 ring capacity 的条数
	var n: int = L.RING_CAPACITY + 50
	for i in range(n):
		L.info("t", "msg %d" % i)
	# size 应停在 RING_CAPACITY
	assert_eq(L.size(), L.RING_CAPACITY)
	# recent(N) 应只返最近 N 条
	var r = L.recent(10)
	assert_eq(r.size(), 10)
	# 最后一条应是 "msg %d" % (n-1)
	assert_eq(r[9]["msg"], "msg %d" % (n - 1))


# ---- log_emitted signal ----

func test_log_emitted_signal() -> void:
	var L = _log()
	watch_signals(L)
	L.info("net", "connected")
	assert_signal_emitted(L, "log_emitted")
	var params = get_signal_parameters(L, "log_emitted")
	assert_eq(params[0], L.Level.INFO)
	assert_eq(params[1], "net")
	assert_eq(params[2], "connected")


# ---- format_line static ----

func test_format_line_static() -> void:
	var L = _log()
	var entry: Dictionary = {
		"level": L.Level.WARN, "tag": "audio", "msg": "fallback"
	}
	var s: String = L.format_line(entry)
	assert_true(s.contains("audio"))
	assert_true(s.contains("fallback"))
	assert_true(s.contains("W"), "WARN level 应显 W 标")


# ---- clear ----

func test_clear_wipes_buffer() -> void:
	var L = _log()
	L.info("t", "1")
	L.info("t", "2")
	assert_eq(L.size(), 2)
	L.clear()
	assert_eq(L.size(), 0)
