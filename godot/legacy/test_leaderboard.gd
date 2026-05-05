class_name TestLeaderboard
extends Node

## 排行榜系统单元测试

var leaderboard_system: LeaderboardSystem
var rank_calculator: RankCalculator

func _ready() -> void:
    """初始化测试"""
    print("\n" + "═" * 60)
    print("🧪 开始排行榜系统单元测试")
    print("═" * 60 + "\n")

    leaderboard_system = LeaderboardSystem.new()
    rank_calculator = RankCalculator.new()

    # 运行所有测试
    test_leaderboard_entry()
    test_leaderboard_system()
    test_rank_calculator()
    test_rewards_calculation()
    test_json_export_import()

    print("\n" + "═" * 60)
    print("✅ 所有测试完成")
    print("═" * 60 + "\n")

## 测试 LeaderboardEntry
func test_leaderboard_entry() -> void:
    print("\n📝 测试 LeaderboardEntry...")

    # 创建条目
    var entry = LeaderboardEntry.new("player_1", "Alice")
    assert entry.player_id == "player_1", "玩家 ID 应为 'player_1'"
    assert entry.player_name == "Alice", "玩家名称应为 'Alice'"
    assert entry.rating == 1000, "初始等级分应为 1000"

    # 更新统计
    entry.update_stats({
        "wins": 5,
        "losses": 2,
        "score": 150,
        "rating_change": 20
    })

    assert entry.wins == 5, "胜场数应为 5"
    assert entry.losses == 2, "负场数应为 2"
    assert entry.games == 7, "总对局数应为 7"
    assert entry.rating == 1020, "更新后等级分应为 1020"
    assert abs(entry.win_rate - 0.714) < 0.01, "胜率应接近 71.4%"

    # 测试等级
    assert entry.get_tier() == "白银", "等级应为白银"
    assert entry.get_tier_emoji() == "⚪", "等级图标应为 ⚪"

    print("  ✅ LeaderboardEntry 测试通过")

## 测试 LeaderboardSystem
func test_leaderboard_system() -> void:
    print("\n📝 测试 LeaderboardSystem...")

    # 创建多个玩家
    var player1 = LeaderboardEntry.new("p1", "Alice")
    player1.rating = 1500
    player1.wins = 20

    var player2 = LeaderboardEntry.new("p2", "Bob")
    player2.rating = 1200
    player2.wins = 15

    var player3 = LeaderboardEntry.new("p3", "Charlie")
    player3.rating = 1800
    player3.wins = 25

    # 添加到排行榜
    leaderboard_system.add_entry(player1)
    leaderboard_system.add_entry(player2)
    leaderboard_system.add_entry(player3)

    assert leaderboard_system.entries.size() == 3, "应有 3 个玩家"

    # 测试排名
    var top_3 = leaderboard_system.get_top(3)
    assert top_3[0].player_id == "p3", "排名第一应为 Charlie (1800)"
    assert top_3[1].player_id == "p1", "排名第二应为 Alice (1500)"
    assert top_3[2].player_id == "p2", "排名第三应为 Bob (1200)"

    # 测试玩家排名
    assert leaderboard_system.get_player_rank("p3") == 1, "Charlie 排名应为 1"
    assert leaderboard_system.get_player_rank("p1") == 2, "Alice 排名应为 2"
    assert leaderboard_system.get_player_rank("p2") == 3, "Bob 排名应为 3"

    # 测试玩家条目获取
    var entry = leaderboard_system.get_entry("p1")
    assert entry.player_name == "Alice", "获取的条目应为 Alice"

    # 测试统计
    var stats = leaderboard_system.get_statistics()
    assert stats.total_players == 3, "总玩家数应为 3"
    assert stats.max_rating == 1800, "最高等级分应为 1800"
    assert stats.min_rating == 1200, "最低等级分应为 1200"

    print("  ✅ LeaderboardSystem 测试通过")

## 测试 RankCalculator
func test_rank_calculator() -> void:
    print("\n📝 测试 RankCalculator...")

    # 测试 ELO 计算 - 高等级玩家击败低等级玩家
    var change1 = rank_calculator.calculate_rating_change(1500, 1200, true)
    assert change1 < 0, "高等级玩家获胜应该只能获得少量等级分"

    # 测试 ELO 计算 - 低等级玩家击败高等级玩家
    var change2 = rank_calculator.calculate_rating_change(1200, 1500, true)
    assert change2 > 0, "低等级玩家击败高等级玩家应该获得大量等级分"
    assert change2 > abs(change1), "低等级玩家的收益应大于高等级玩家的损失"

    # 测试 ELO 计算 - 失败情况
    var change3 = rank_calculator.calculate_rating_change(1500, 1200, false)
    assert change3 < 0, "失败应该导致等级分下降"

    # 测试等级描述
    assert rank_calculator.get_tier_description(750) == "🥉 青铜"
    assert rank_calculator.get_tier_description(1000) == "⚪ 白银"
    assert rank_calculator.get_tier_description(1500) == "🟡 黄金"
    assert rank_calculator.get_tier_description(2000) == "💎 钻石"

    print("  ✅ RankCalculator 测试通过")

## 测试奖励计算
func test_rewards_calculation() -> void:
    print("\n📝 测试奖励计算...")

    # 测试第一名奖励
    var rewards1 = rank_calculator.calculate_rewards(1, 100, true)
    assert rewards1.gold == 100 + 10, "第一名胜利的金币计算有误"
    assert rewards1.exp == 50 + 20, "第一名胜利的经验计算有误"

    # 测试第二名奖励
    var rewards2 = rank_calculator.calculate_rewards(2, 100, false)
    assert rewards2.gold == 80 + 10, "第二名失败的金币计算有误"

    # 测试排名外奖励
    var rewards3 = rank_calculator.calculate_rewards(50, 200, false)
    assert rewards3.gold == 10 + 20, "排名外玩家的金币计算有误"

    print("  ✅ 奖励计算测试通过")

## 测试 JSON 导出导入
func test_json_export_import() -> void:
    print("\n📝 测试 JSON 导出导入...")

    # 导出 JSON
    var json_data = leaderboard_system.export_to_json(3)
    assert json_data.length() > 0, "导出的 JSON 应不为空"

    # 创建新的排行榜系统
    var new_system = LeaderboardSystem.new()

    # 导入 JSON
    var success = new_system.import_from_json(json_data)
    assert success, "JSON 导入应该成功"
    assert new_system.entries.size() == 3, "导入后应有 3 个玩家"

    print("  ✅ JSON 导出导入测试通过")

## 打印测试结果摘要
func _exit_tree() -> void:
    """清理"""
    queue_free()
