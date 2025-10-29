class_name LeaderboardEntry
extends RefCounted

## 玩家排行榜条目数据类
## 存储玩家在排行榜中的排名、统计和其他信息

var rank: int                      # 当前排名
var player_id: String              # 玩家唯一 ID
var player_name: String            # 玩家名称
var avatar: String                 # 玩家头像 URL
var score: int                     # 总积分
var wins: int                      # 胜场数
var losses: int                    # 负场数
var games: int                     # 总对局数
var win_rate: float                # 胜率 (0.0 - 1.0)
var rating: int                    # 等级分 (ELO)
var last_update: int               # 最后更新时间戳 (毫秒)

func _init(p_id: String, p_name: String) -> void:
    """
    初始化排行榜条目
    参数:
        p_id: 玩家 ID
        p_name: 玩家名称
    """
    player_id = p_id
    player_name = p_name
    rank = 0
    avatar = ""
    score = 0
    wins = 0
    losses = 0
    games = 0
    win_rate = 0.0
    rating = 1000  # 初始等级分
    last_update = Time.get_ticks_msec()

## 更新玩家统计信息
func update_stats(stats: Dictionary) -> void:
    """
    更新玩家统计信息
    参数 stats 字典支持以下键:
        - wins: 新增胜场数 (int)
        - losses: 新增负场数 (int)
        - score: 新增积分 (int)
        - rating_change: 等级分变化 (int)
        - avatar: 玩家头像 URL (String)
    """
    if stats.has("wins"):
        wins += stats.get("wins", 0)
    
    if stats.has("losses"):
        losses += stats.get("losses", 0)
    
    if stats.has("score"):
        score += stats.get("score", 0)
    
    # 更新总对局数
    games = wins + losses
    
    # 重新计算胜率
    if games > 0:
        win_rate = float(wins) / float(games)
    
    # 更新等级分
    if stats.has("rating_change"):
        rating += stats.get("rating_change", 0)
    
    # 更新头像 (如果提供)
    if stats.has("avatar"):
        avatar = stats.get("avatar", "")
    
    # 更新时间戳
    last_update = Time.get_ticks_msec()

## 获取进度百分比 (基于积分)
func get_progress() -> float:
    """返回玩家的进度百分比 (0.0 - 1.0)"""
    if score == 0:
        return 0.0
    # 假设目标是 1000 分
    var max_score = 1000.0
    return min(float(score) / max_score, 1.0)

## 获取玩家等级 (基于等级分)
func get_tier() -> String:
    """根据等级分返回玩家等级"""
    match rating:
        0..799:
            return "青铜"
        800..1199:
            return "白银"
        1200..1599:
            return "黄金"
        1600..1999:
            return "铂金"
        2000..2399:
            return "钻石"
        2400..(2**31 - 1):
            return "大师"
        _:
            return "未评级"

## 获取玩家等级图标 (emoji)
func get_tier_emoji() -> String:
    """返回对应等级的表情符号"""
    match rating:
        0..799:
            return "🥉"  # 青铜
        800..1199:
            return "⚪"  # 白银
        1200..1599:
            return "🟡"  # 黄金
        1600..1999:
            return "🟢"  # 铂金
        2000..2399:
            return "💎"  # 钻石
        2400..(2**31 - 1):
            return "👑"  # 大师
        _:
            return "❓"

## 获取统计信息字典
func get_stats() -> Dictionary:
    """返回玩家所有统计信息的字典"""
    return {
        "rank": rank,
        "player_id": player_id,
        "player_name": player_name,
        "avatar": avatar,
        "score": score,
        "wins": wins,
        "losses": losses,
        "games": games,
        "win_rate": win_rate,
        "rating": rating,
        "tier": get_tier(),
        "tier_emoji": get_tier_emoji(),
        "last_update": last_update
    }

## 获取排行榜显示文本
func get_display_text() -> String:
    """返回排行榜条目的显示文本"""
    var tier_emoji = get_tier_emoji()
    return "%s %s | %s | ⭐%d | %d场 | %.1f%%" % [
        "#%d" % rank,
        tier_emoji,
        player_name,
        rating,
        games,
        win_rate * 100
    ]
