class_name RankCalculator
extends Node

## 排名计算器 - 基于 ELO 等级分系统
## 计算玩家等级分变化、奖励和其他排名相关数据

# ELO 系统参数
const K_FACTOR = 32 # 等级分变动系数
const BASE_RATING = 1000 # 基础等级分
const MAX_RATING = 3000 # 最大等级分
const MIN_RATING = 400 # 最小等级分

func _ready() -> void:
    """初始化排名计算器"""
    print("✅ 排名计算器已初始化 (ELO K因子: %d)" % K_FACTOR)

## 计算等级分变化 (ELO 算法)
func calculate_rating_change(
    player_rating: int,
    opponent_rating: int,
    player_won: bool
) -> int:
    """
    计算玩家的等级分变化 (基于 ELO 算法)

    参数:
        player_rating: 玩家当前等级分
        opponent_rating: 对手等级分
        player_won: 玩家是否获胜

    返回:
        等级分变化量 (可正可负)
    """
    # 计算玩家获胜的概率
    var expected_score = 1.0 / (1.0 + pow(10.0, float(opponent_rating - player_rating) / 400.0))

    # 实际比赛结果 (1 = 赢, 0 = 输)
    var actual_score = 1.0 if player_won else 0.0

    # 计算等级分变化
    var rating_change = int(K_FACTOR * (actual_score - expected_score))

    return rating_change

## 计算多人比赛的等级分变化
func calculate_multiplayer_rating_change(
    player_rating: int,
    other_ratings: Array,
    rank: int
) -> int:
    """
    计算多人比赛的等级分变化

    参数:
        player_rating: 玩家当前等级分
        other_ratings: 其他玩家的等级分数组
        rank: 玩家的比赛排名 (1 = 第一, 数字越小越好)

    返回:
        等级分变化量
    """
    if other_ratings.is_empty():
        return 0

    var avg_opponent_rating = 0
    for rating in other_ratings:
        avg_opponent_rating += rating
    avg_opponent_rating /= other_ratings.size()

    # 根据排名计算结果
    var actual_score = 1.0 / float(rank) # 第一名 = 1.0, 第二名 = 0.5 等

    # 计算期望分数
    var expected_score = 1.0 / (1.0 + pow(10.0, float(avg_opponent_rating - player_rating) / 400.0))

    # 计算变化
    var rating_change = int(K_FACTOR * (actual_score - expected_score))

    return rating_change

## 根据排名和得分计算奖励
func calculate_rewards(rank: int, score: int, is_victory: bool = false) -> Dictionary:
    """
    根据排名和得分计算奖励

    参数:
        rank: 玩家排名 (1-based)
        score: 玩家得分
        is_victory: 是否获胜

    返回:
        包含金币、经验等奖励的字典
    """
    var gold = 0
    var exp = 0
    var points = 0

    # 根据排名分配基础奖励
    match rank:
        1: # 第一名
            gold = 100
            exp = 50
            points = 50
        2: # 第二名
            gold = 80
            exp = 40
            points = 40
        3: # 第三名
            gold = 60
            exp = 30
            points = 30
        _
            if rank <= 10:
                gold = 40
                exp = 20
                points = 20
            elif rank <= 100:
                gold = 20
                exp = 10
                points = 10
            else:
                gold = 10
                exp = 5
                points = 5

    # 根据得分添加额外奖励
    var score_bonus_gold = score / 10
    var score_bonus_exp = score / 5
    var score_bonus_points = score / 20

    gold += score_bonus_gold
    exp += score_bonus_exp
    points += score_bonus_points

    # 如果是获胜，增加 50% 奖励
    if is_victory:
        gold = int(gold * 1.5)
        exp = int(exp * 1.5)
        points = int(points * 1.5)

    return {
        "gold": gold,
        "exp": exp,
        "points": points,
        "rank": rank,
        "score": score,
        "is_victory": is_victory
    }

## 根据排名计算分段分 (排位赛)
func calculate_rank_points(
    current_points: int,
    rank: int,
    victory: bool
) -> Dictionary:
    """
    计算排位分变化

    参数:
        current_points: 当前分段分
        rank: 排名
        victory: 是否胜利

    返回:
        包含新分数和分段的字典
    """
    var points_change = 0

    if victory:
        if rank == 1:
            points_change = 50
        elif rank == 2:
            points_change = 30
        elif rank == 3:
            points_change = 20
        else:
            points_change = 10
    else:
        if rank > 10:
            points_change = -5
        else:
            points_change = 0

    var new_points = current_points + points_change

    # 计算分段 (Tier)
    var tier = _calculate_tier(new_points)

    return {
        "old_points": current_points,
        "new_points": new_points,
        "change": points_change,
        "tier": tier
    }

## 计算日排行榜重置时间 (毫秒)
func get_daily_reset_time() -> int:
    """返回距离下次日重置的毫秒数"""
    var now = Time.get_ticks_msec()
    var seconds_per_day = 86400
    var today_start_seconds = (now / 1000) / seconds_per_day * seconds_per_day
    var tomorrow_start_seconds = today_start_seconds + seconds_per_day
    return int((tomorrow_start_seconds - now / 1000) * 1000)

## 计算周排行榜重置时间 (毫秒)
func get_weekly_reset_time() -> int:
    """返回距离下次周重置的毫秒数 (周一 00:00)"""
    var now = Time.get_ticks_msec()
    var now_seconds = now / 1000
    var now_days = now_seconds / 86400

    # 计算本周一 (第 3 天是周一)
    var day_of_week = (now_days + 3) % 7
    var days_until_monday = (7 - day_of_week) % 7
    if days_until_monday == 0:
        days_until_monday = 7

    var next_monday_seconds = now_seconds + (days_until_monday * 86400)
    var next_monday_start = (next_monday_seconds / 86400) * 86400

    return int((next_monday_start - now_seconds) * 1000)

## 获取玩家等级描述
func get_tier_description(rating: int) -> String:
    """根据等级分获取等级描述"""
    if rating < 600:
        return "🌱 新手"
    elif rating < 800:
        return "🥉 青铜"
    elif rating < 1000:
        return "🥈 白银"
    elif rating < 1400:
        return "🥇 黄金"
    elif rating < 1800:
        return "💎 铂金"
    else:
        return "👑 钻石"

## 内部方法：计算分段等级
func _calculate_tier(points: int) -> String:
    """根据分段分计算等级"""
    match points:
        0..599
            return "铜"
        600..1199
            return "银"
        1200..1799
            return "金"
        1800..2399
            return "铂"
        2400..(2 ** 31 - 1)
            return "钻"
        _
            return "未定级"

## 获取赛季奖励
func get_season_rewards(rating: int, final_rank: int) -> Dictionary:
    """
    获取赛季奖励

    参数:
        rating: 最终等级分
        final_rank: 最终排名

    返回:
        赛季奖励字典
    """
    var rewards = {
        "gold": 0,
        "gem": 0,
        "title": "",
        "avatar_frame": ""
    }

    # 根据等级分分配奖励
    match rating:
        0..799:
            rewards.gold = 100
            rewards.gem = 5
            rewards.title = "初生之秀"
        800..1199:
            rewards.gold = 200
            rewards.gem = 10
            rewards.title = "初来乍到"
        1200..1599:
            rewards.gold = 300
            rewards.gem = 20
            rewards.title = "崭露头角"
        1600..1999:
            rewards.gold = 500
            rewards.gem = 50
            rewards.title = "锋芒毕露"
        2000..2399:
            rewards.gold = 800
            rewards.gem = 100
            rewards.title = "功成名就"
        _
            rewards.gold = 1000
            rewards.gem = 200
            rewards.title = "声名远扬"

    # 根据排名追加奖励
    if final_rank <= 10:
        rewards.gold += 1000
        rewards.gem += 100
        rewards.avatar_frame = "金框"
    elif final_rank <= 100:
        rewards.gold += 500
        rewards.gem += 50
        rewards.avatar_frame = "银框"

    return rewards

## 生成排名统计报告
func generate_ranking_report(entries: Array) -> String:
    """
    生成排名统计报告

    参数:
        entries: LeaderboardEntry 数组

    返回:
        统计报告文本
    """
    if entries.is_empty():
        return "📊 暂无排名数据"

    var report = "📊 排名统计报告\n"
    report += "══════════════════════════════════════════════════\n"

    var total_players = entries.size()
    var avg_rating = 0
    var max_rating = 0
    var min_rating = 3000

    for entry in entries:
        avg_rating += entry.rating
        max_rating = max(max_rating, entry.rating)
        min_rating = min(min_rating, entry.rating)

    avg_rating /= total_players

    report += "总玩家数: %d\n" % total_players
    report += "平均等级分: %d\n" % avg_rating
    report += "最高等级分: %d (%s)\n" % [max_rating, get_tier_description(max_rating)]
    report += "最低等级分: %d (%s)\n" % [min_rating, get_tier_description(min_rating)]
    report += "══════════════════════════════════════════════════"

    return report
