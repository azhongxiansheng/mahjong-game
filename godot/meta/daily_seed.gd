class_name DailySeed

# Daily seed — 每天 00:00 (本地时间) 切换。同一天全服同 seed,玩家社区可比
# 通关时间 / 总分 / 役満次数。RunFlow 在 daily 模式下用 today_seed() 替代
# Time.get_ticks_msec()。
#
# 不依赖 UTC:用 Time.get_date_dict_from_system() 取本地日期。中国服 / 日本
# 服玩家天然在同一时区,无歧义;海外玩家用自己本地日期(无负面体验)。
#
# Seed 公式: year * 10000 + month * 100 + day,例如 2026-05-26 → 20260526。
# 这样:
#   1. 直接看 seed 就知道是哪天
#   2. 不同日期 seed 跨度 == 1 让 RNG 充分混淆(测试过 seed 20260525 vs
#      20260526 生成的 ChapterMap 完全不同)
#   3. 简单可读,玩家分享截图带 "今日 #20260526" 更社区友好


# 今日 daily seed。
static func today_seed() -> int:
	var d: Dictionary = Time.get_date_dict_from_system()
	return int(d.year) * 10000 + int(d.month) * 100 + int(d.day)


# 把 daily seed 格式化为 "2026-05-26 #日挑战" 字串,显示在 UI 上。
static func today_display() -> String:
	var d: Dictionary = Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [int(d.year), int(d.month), int(d.day)]
