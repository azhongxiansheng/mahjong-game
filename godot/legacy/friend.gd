class_name Friend
extends RefCounted

## 好友基础信息
var friend_id: String              # 好友ID
var friend_name: String            # 好友名称
var avatar: String = ""            # 头像URL
var status: String = "offline"     # 在线状态 (online/offline/playing)
var level: int = 1                 # 等级
var rating: int = 1000             # 评分

## 关系数据
var relationship: String = "friend"  # 关系类型 (friend/pending/blocked)
var created_at: int = 0            # 创建时间戳
var last_seen: int = 0             # 最后在线时间

## 统计数据
var total_games: int = 0           # 与此好友的对局数
var wins: int = 0                  # 赢的局数
var win_rate: float = 0.0          # 胜率

## 初始化
func _init(p_id: String, p_name: String) -> void:
    """初始化好友对象"""
    friend_id = p_id
    friend_name = p_name
    created_at = int(Time.get_ticks_msec() / 1000)
    last_seen = created_at


## 公共方法

func is_online() -> bool:
    """检查好友是否在线"""
    return status == "online" or status == "playing"


func is_playing() -> bool:
    """检查好友是否在游戏中"""
    return status == "playing"


func get_display_text() -> String:
    """获取显示文本"""
    var status_icon = "🟢" if is_online() else "⚫"
    return "[%s] %s (Lv.%d ⭐%d)" % [status_icon, friend_name, level, rating]


func get_status_text() -> String:
    """获取状态文本"""
    match status:
        "online":
            return "在线"
        "offline":
            return "离线"
        "playing":
            return "游戏中"
        _:
            return "未知"


func update_status(new_status: String) -> void:
    """更新状态"""
    status = new_status
    if new_status != "offline":
        last_seen = int(Time.get_ticks_msec() / 1000)


func update_stats(stats: Dictionary) -> void:
    """更新统计数据"""
    if stats.has("level"):
        level = stats["level"]
    if stats.has("rating"):
        rating = stats["rating"]
    if stats.has("total_games"):
        total_games = stats["total_games"]
    if stats.has("wins"):
        wins = stats["wins"]

    # 重新计算胜率
    if total_games > 0:
        win_rate = float(wins) / float(total_games)
    else:
        win_rate = 0.0


func calculate_win_rate() -> float:
    """计算胜率"""
    if total_games == 0:
        return 0.0
    return float(wins) / float(total_games)


func add_game_result(won: bool) -> void:
    """添加一局游戏结果"""
    total_games += 1
    if won:
        wins += 1
    win_rate = calculate_win_rate()


func get_tier() -> String:
    """根据评分获取等级"""
    if rating < 600:
        return "新手"
    elif rating < 800:
        return "青铜"
    elif rating < 1000:
        return "白银"
    elif rating < 1400:
        return "黄金"
    elif rating < 1800:
        return "铂金"
    else:
        return "钻石"


func get_tier_emoji() -> String:
    """根据等级获取emoji"""
    if rating < 600:
        return "🌱"
    elif rating < 800:
        return "🥉"
    elif rating < 1000:
        return "🥈"
    elif rating < 1400:
        return "🥇"
    elif rating < 1800:
        return "💎"
    else:
        return "👑"


func get_progress() -> float:
    """获取进度 (0-1)"""
    var current_rating = float(rating)
    var tier_min = 0.0
    var tier_max = 600.0

    # 确定当前等级范围
    match get_tier():
        "青铜":
            tier_min = 600.0
            tier_max = 800.0
        "白银":
            tier_min = 800.0
            tier_max = 1000.0
        "黄金":
            tier_min = 1000.0
            tier_max = 1400.0
        "铂金":
            tier_min = 1400.0
            tier_max = 1800.0
        "钻石":
            tier_min = 1800.0
            tier_max = 3000.0

    if tier_max <= tier_min:
        return 1.0

    return (current_rating - tier_min) / (tier_max - tier_min)


func to_dict() -> Dictionary:
    """转换为字典"""
    return {
        "friend_id": friend_id,
        "friend_name": friend_name,
        "avatar": avatar,
        "status": status,
        "level": level,
        "rating": rating,
        "relationship": relationship,
        "created_at": created_at,
        "last_seen": last_seen,
        "total_games": total_games,
        "wins": wins,
        "win_rate": win_rate,
        "tier": get_tier(),
        "tier_emoji": get_tier_emoji()
    }


func from_dict(data: Dictionary) -> void:
    """从字典恢复"""
    if data.has("friend_id"):
        friend_id = data["friend_id"]
    if data.has("friend_name"):
        friend_name = data["friend_name"]
    if data.has("avatar"):
        avatar = data["avatar"]
    if data.has("status"):
        status = data["status"]
    if data.has("level"):
        level = data["level"]
    if data.has("rating"):
        rating = data["rating"]
    if data.has("relationship"):
        relationship = data["relationship"]
    if data.has("created_at"):
        created_at = data["created_at"]
    if data.has("last_seen"):
        last_seen = data["last_seen"]
    if data.has("total_games"):
        total_games = data["total_games"]
    if data.has("wins"):
        wins = data["wins"]
    if data.has("win_rate"):
        win_rate = data["win_rate"]


func get_summary() -> String:
    """获取摘要文本"""
    var tier_text = "%s %s" % [get_tier_emoji(), get_tier()]
    var status_text = get_status_text()
    var rate_text = "%.1f%%" % (win_rate * 100)

    return "%s | 等级:%s | 状态:%s | 胜率:%s (%d/%d)" % [
        get_display_text(),
        tier_text,
        status_text,
        rate_text,
        wins,
        total_games
    ]
