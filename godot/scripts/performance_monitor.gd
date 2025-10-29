# 性能监控工具
# 用于收集和分析听牌检查的性能指标
#
# 用法:
#   var monitor = PerformanceMonitor.new()
#   monitor.record_check(use_cache, time_ms)
#   monitor.print_report()

class_name PerformanceMonitor

# 性能指标
var _metrics: Dictionary = {
	"total_checks": 0,
	"cache_hits": 0,
	"cache_misses": 0,
	"total_time_ms": 0.0,
	"max_time_ms": 0.0,
	"min_time_ms": 999999.0,
	"async_checks": 0
}

# 时间序列数据 (用于分析趋势)
var _time_series: Array = []

# ========================
# 主要API方法
# ========================

# 记录一次检查操作
# use_cache: 是否使用了缓存
# time_ms: 消耗的时间 (毫秒)
func record_check(use_cache: bool, time_ms: float) -> void:
	_metrics["total_checks"] += 1

	if use_cache:
		_metrics["cache_hits"] += 1
	else:
		_metrics["cache_misses"] += 1

	_metrics["total_time_ms"] += time_ms
	_metrics["max_time_ms"] = max(_metrics["max_time_ms"], time_ms)
	_metrics["min_time_ms"] = min(_metrics["min_time_ms"], time_ms)

	# 记录时间序列
	_time_series.append({
		"time": time_ms,
		"use_cache": use_cache,
		"timestamp": Time.get_ticks_msec()
	})

# 记录异步检查
func record_async_check() -> void:
	_metrics["async_checks"] += 1

# 获取缓存命中率 (百分比)
func get_cache_hit_rate() -> float:
	var total = _metrics["total_checks"]
	if total == 0:
		return 0.0
	return float(_metrics["cache_hits"]) / total * 100.0

# 获取平均耗时 (毫秒)
func get_average_time() -> float:
	var total = _metrics["total_checks"]
	if total == 0:
		return 0.0
	return _metrics["total_time_ms"] / total

# 获取总耗时 (毫秒)
func get_total_time() -> float:
	return _metrics["total_time_ms"]

# 获取最大耗时 (毫秒)
func get_max_time() -> float:
	return _metrics["max_time_ms"]

# 获取最小耗时 (毫秒)
func get_min_time() -> float:
	if _metrics["min_time_ms"] == 999999.0:
		return 0.0
	return _metrics["min_time_ms"]

# 获取总检查数
func get_total_checks() -> int:
	return _metrics["total_checks"]

# 获取命中数
func get_cache_hits() -> int:
	return _metrics["cache_hits"]

# 获取未命中数
func get_cache_misses() -> int:
	return _metrics["cache_misses"]

# ========================
# 分析方法
# ========================

# 计算标准差
func get_standard_deviation() -> float:
	var total = _metrics["total_checks"]
	if total == 0:
		return 0.0

	var average = get_average_time()
	var variance = 0.0

	for data in _time_series:
		var time = data["time"]
		variance += pow(time - average, 2)

	variance /= total
	return sqrt(variance)

# 获取缓存节省的时间
func get_time_saved() -> float:
	var hit_count = _metrics["cache_hits"]
	if hit_count == 0:
		return 0.0

	# 假设缓存命中平均节省 40ms (50ms原始 - 1ms缓存)
	return hit_count * 40.0

# 计算性能改进百分比 (相对于无缓存)
func get_performance_improvement() -> float:
	var miss_time = _metrics["cache_misses"] * 50.0  # 假设无缓存 50ms
	var actual_time = _metrics["total_time_ms"]

	if miss_time == 0:
		return 0.0

	return (miss_time - actual_time) / miss_time * 100.0

# ========================
# 报告方法
# ========================

# 打印简单报告
func print_report() -> void:
	print("\n╔════════════════════════════════════════╗")
	print("║       🎯 性能监控报告                  ║")
	print("╚════════════════════════════════════════╝")

	print("\n📊 基本统计:")
	print("  总检查数:    %d" % _metrics["total_checks"])
	print("  命中次数:    %d" % _metrics["cache_hits"])
	print("  未命中:      %d" % _metrics["cache_misses"])
	print("  命中率:      %.1f%%" % get_cache_hit_rate())

	print("\n⏱️  时间统计 (ms):")
	print("  总耗时:      %.2f" % get_total_time())
	print("  平均:        %.2f" % get_average_time())
	print("  最大:        %.2f" % get_max_time())
	print("  最小:        %.2f" % get_min_time())
	print("  标准差:      %.2f" % get_standard_deviation())

	print("\n💰 性能收益:")
	print("  节省时间:    %.2fms" % get_time_saved())
	print("  改进:        %.1f%%" % get_performance_improvement())

	if _metrics["async_checks"] > 0:
		print("\n🔄 异步操作:")
		print("  异步检查:    %d" % _metrics["async_checks"])

	print("\n")

# 打印详细报告
func print_detailed_report() -> void:
	print_report()

	print("📈 时间序列分析 (最近50条):")
	var start = max(0, _time_series.size() - 50)
	for i in range(start, _time_series.size()):
		var data = _time_series[i]
		var cache_mark = "✓" if data["use_cache"] else "✗"
		print("  [%d] %s %.1fms" % [i - start + 1, cache_mark, data["time"]])

# 导出为JSON字符串
func export_json() -> String:
	var json = {
		"total_checks": _metrics["total_checks"],
		"cache_hits": _metrics["cache_hits"],
		"cache_misses": _metrics["cache_misses"],
		"hit_rate": "%.1f%%" % get_cache_hit_rate(),
		"average_time_ms": "%.2f" % get_average_time(),
		"total_time_ms": "%.2f" % get_total_time(),
		"time_saved_ms": "%.2f" % get_time_saved(),
		"performance_improvement": "%.1f%%" % get_performance_improvement()
	}
	return JSON.stringify(json)

# 重置所有统计数据
func reset() -> void:
	_metrics = {
		"total_checks": 0,
		"cache_hits": 0,
		"cache_misses": 0,
		"total_time_ms": 0.0,
		"max_time_ms": 0.0,
		"min_time_ms": 999999.0,
		"async_checks": 0
	}
	_time_series.clear()
