class_name LeaderboardSystem
extends Node

## 排行榜系统 - 管理玩家排名和统计
## 支持多种排行榜类型 (日/周/月/赛季/全局)

# 排行榜类型枚举
enum Type {
    DAILY,      # 日排行
    WEEKLY,     # 周排行
    MONTHLY,    # 月排行
    SEASONAL,   # 赛季排行
    GLOBAL      # 全局排行
}

# 排行榜类型名称
const TYPE_NAMES = {
    Type.DAILY: "日排行",
    Type.WEEKLY: "周排行",
    Type.MONTHLY: "月排行",
    Type.SEASONAL: "赛季排行",
    Type.GLOBAL: "全局排行"
}

var entries: Dictionary = {}       # player_id -> LeaderboardEntry
var leaderboard_type: int = Type.GLOBAL
var last_reset: int = 0            # 最后重置时间戳

## 发送的信号
signal leaderboard_updated        # 排行榜已更新
signal player_ranked(player_id: String, rank: int)  # 玩家排名已计算
signal top_players_changed(top_10: Array)  # 前 10 名已变更

func _ready() -> void:
    """初始化排行榜系统"""
    print("✅ 排行榜系统已初始化")
    print("📊 排行榜类型: %s" % TYPE_NAMES[leaderboard_type])

## 添加玩家条目
func add_entry(entry: LeaderboardEntry) -> void:
    """
    添加或更新玩家条目
    参数:
        entry: LeaderboardEntry 对象
    """
    if entry == null:
        print("❌ 条目为空，无法添加")
        return

    entries[entry.player_id] = entry
    print("✅ 玩家已添加: %s (ID: %s)" % [entry.player_name, entry.player_id])

## 获取前 N 名玩家 (按等级分排序)
func get_top(limit: int = 100) -> Array:
    """
    获取前 N 名玩家
    参数:
        limit: 获取的玩家数量 (默认 100)
    返回:
        排序后的玩家条目数组
    """
    if entries.is_empty():
        return []

    var sorted_entries = entries.values()

    # 按等级分降序排序
    sorted_entries.sort_custom(func(a: LeaderboardEntry, b: LeaderboardEntry):
        return a.rating > b.rating
    )

    # 更新每个玩家的排名
    for i in range(sorted_entries.size()):
        sorted_entries[i].rank = i + 1

    # 返回前 N 名
    return sorted_entries.slice(0, min(limit, sorted_entries.size()))

## 获取玩家排名
func get_player_rank(player_id: String) -> int:
    """
    获取特定玩家的排名
    参数:
        player_id: 玩家 ID
    返回:
        玩家排名 (1-based)，未找到返回 -1
    """
    if player_id not in entries:
        return -1

    var top_players = get_top(entries.size())
    for i in range(top_players.size()):
        if top_players[i].player_id == player_id:
            return i + 1

    return -1

## 获取玩家条目
func get_entry(player_id: String) -> LeaderboardEntry:
    """
    获取玩家的排行榜条目
    参数:
        player_id: 玩家 ID
    返回:
        LeaderboardEntry 对象，或 null
    """
    if player_id not in entries:
        return null
    return entries[player_id]

## 更新玩家统计
func update_player_stats(player_id: String, stats: Dictionary) -> void:
    """
    更新玩家的统计信息
    参数:
        player_id: 玩家 ID
        stats: 统计数据字典
    """
    if player_id not in entries:
        # 创建新条目
        var entry = LeaderboardEntry.new(
            player_id,
            stats.get("name", "Player")
        )
        entries[player_id] = entry

    var entry = entries[player_id]
    entry.update_stats(stats)

    # 发送排名更新信号
    var rank = get_player_rank(player_id)
    player_ranked.emit(player_id, rank)

    # 检查前 10 名是否变更
    _check_top_10_changed()

## 获取排行榜数据 (指定类型)
func get_leaderboard(type: int = Type.GLOBAL, limit: int = 100) -> Array:
    """
    获取指定类型的排行榜数据
    参数:
        type: 排行榜类型
        limit: 获取数量
    返回:
        排行榜数据数组
    """
    leaderboard_type = type
    return get_top(limit)

## 获取排行榜统计
func get_statistics() -> Dictionary:
    """获取排行榜的统计信息"""
    if entries.is_empty():
        return {
            "total_players": 0,
            "avg_rating": 0,
            "max_rating": 0,
            "min_rating": 0
        }

    var all_entries = entries.values()
    var ratings = []
    var total_rating = 0

    for entry in all_entries:
        ratings.append(entry.rating)
        total_rating += entry.rating

    ratings.sort()

    return {
        "total_players": all_entries.size(),
        "avg_rating": total_rating / all_entries.size(),
        "max_rating": ratings[-1],
        "min_rating": ratings[0],
        "median_rating": ratings[ratings.size() / 2]
    }

## 重置排行榜 (用于切换排行榜类型)
func reset_leaderboard() -> void:
    """重置排行榜数据"""
    entries.clear()
    last_reset = Time.get_ticks_msec()
    print("🔄 排行榜已重置")
    leaderboard_updated.emit()

## 导出排行榜数据为 JSON
func export_to_json(limit: int = 100) -> String:
    """
    导出排行榜数据为 JSON 格式
    参数:
        limit: 导出数量
    返回:
        JSON 字符串
    """
    var leaderboard = get_top(limit)
    var data = []

    for entry in leaderboard:
        data.append(entry.get_stats())

    return JSON.stringify(data)

## 从 JSON 导入排行榜数据
func import_from_json(json_data: String) -> bool:
    """
    从 JSON 导入排行榜数据
    参数:
        json_data: JSON 字符串
    返回:
        导入是否成功
    """
    var json = JSON.new()
    var error = json.parse(json_data)

    if error != OK:
        print("❌ JSON 解析失败")
        return false

    var data = json.data
    if data == null or not data is Array:
        print("❌ 数据格式无效")
        return false

    reset_leaderboard()

    for player_data in data:
        if player_data is Dictionary:
            var entry = LeaderboardEntry.new(
                player_data.get("player_id", ""),
                player_data.get("player_name", "")
            )
            entry.score = player_data.get("score", 0)
            entry.wins = player_data.get("wins", 0)
            entry.losses = player_data.get("losses", 0)
            entry.games = player_data.get("games", 0)
            entry.win_rate = player_data.get("win_rate", 0.0)
            entry.rating = player_data.get("rating", 1000)
            add_entry(entry)

    print("✅ 排行榜数据已导入: %d 名玩家" % entries.size())
    leaderboard_updated.emit()
    return true

## 检查前 10 名是否变更
func _check_top_10_changed() -> void:
    """检查前 10 名玩家是否有变更"""
    var top_10 = get_top(10)
    top_players_changed.emit(top_10)

## 获取排行榜摘要 (文本格式)
func get_summary(limit: int = 10) -> String:
    """
    获取排行榜摘要文本
    参数:
        limit: 摘要中显示的玩家数量
    返回:
        文本格式的排行榜摘要
    """
    var leaderboard = get_top(limit)
    var summary = "🏆 %s\n" % TYPE_NAMES[leaderboard_type]
    summary += "═" * 50 + "\n"

    for entry in leaderboard:
        summary += entry.get_display_text() + "\n"

    summary += "═" * 50
    return summary

## 打印排行榜 (调试用)
func print_leaderboard(limit: int = 10) -> void:
    """打印排行榜到控制台"""
    print(get_summary(limit))
