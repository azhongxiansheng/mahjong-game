## 好友系统单元测试
##
## 测试用例:
## - Friend 类基础功能
## - FriendSystem 好友管理
## - 状态和统计更新
## - JSON 导出/导入
##
extends Node

## 测试结果统计
var test_count = 0
var pass_count = 0
var fail_count = 0


## 初始化
func _ready() -> void:
    """运行所有测试"""
    print("\n========== 好友系统单元测试 ==========\n")
    
    # Friend 类测试
    test_friend_creation()
    test_friend_status()
    test_friend_stats()
    test_friend_tier()
    test_friend_serialization()
    
    # FriendSystem 测试
    test_friend_system_creation()
    test_add_remove_friend()
    test_friend_queries()
    test_friend_filtering()
    test_friend_requests()
    test_blocking()
    test_system_statistics()
    test_system_serialization()
    
    # 打印总结
    print_summary()


## Friend 类测试

func test_friend_creation() -> void:
    """测试 Friend 对象创建"""
    var friend = Friend.new("player_001", "张三")
    assert_equal(friend.friend_id, "player_001", "Friend ID should match")
    assert_equal(friend.friend_name, "张三", "Friend name should match")
    assert_equal(friend.status, "offline", "Default status should be offline")
    assert_equal(friend.rating, 1000, "Default rating should be 1000")
    pass_test("Friend 对象创建")


func test_friend_status() -> void:
    """测试 Friend 状态管理"""
    var friend = Friend.new("player_002", "李四")
    
    # 测试在线状态检查
    assert_false(friend.is_online(), "Should be offline initially")
    assert_false(friend.is_playing(), "Should not be playing initially")
    
    # 测试状态更新
    friend.update_status("online")
    assert_true(friend.is_online(), "Should be online after update")
    assert_false(friend.is_playing(), "Should not be playing when online")
    
    friend.update_status("playing")
    assert_true(friend.is_online(), "Should be online when playing")
    assert_true(friend.is_playing(), "Should be playing")
    
    friend.update_status("offline")
    assert_false(friend.is_online(), "Should be offline")
    
    pass_test("Friend 状态管理")


func test_friend_stats() -> void:
    """测试 Friend 统计数据"""
    var friend = Friend.new("player_003", "王五")
    
    # 测试游戏结果
    friend.add_game_result(true)
    assert_equal(friend.total_games, 1, "Total games should be 1")
    assert_equal(friend.wins, 1, "Wins should be 1")
    assert_equal(friend.win_rate, 1.0, "Win rate should be 1.0")
    
    friend.add_game_result(false)
    assert_equal(friend.total_games, 2, "Total games should be 2")
    assert_equal(friend.wins, 1, "Wins should still be 1")
    assert_equal(friend.win_rate, 0.5, "Win rate should be 0.5")
    
    # 测试统计更新
    var stats = {"level": 10, "rating": 1200, "total_games": 5, "wins": 4}
    friend.update_stats(stats)
    assert_equal(friend.level, 10, "Level should update")
    assert_equal(friend.rating, 1200, "Rating should update")
    assert_equal(friend.total_games, 5, "Total games should update")
    assert_equal(friend.win_rate, 0.8, "Win rate should recalculate")
    
    pass_test("Friend 统计数据")


func test_friend_tier() -> void:
    """测试 Friend 等级系统"""
    var friend = Friend.new("player_004", "赵六")
    
    # 测试各种评分对应的等级
    friend.rating = 500
    assert_equal(friend.get_tier(), "新手", "500 rating should be 新手")
    assert_equal(friend.get_tier_emoji(), "🌱", "新手 emoji should be 🌱")
    
    friend.rating = 700
    assert_equal(friend.get_tier(), "青铜", "700 rating should be 青铜")
    assert_equal(friend.get_tier_emoji(), "🥉", "青铜 emoji should be 🥉")
    
    friend.rating = 900
    assert_equal(friend.get_tier(), "白银", "900 rating should be 白银")
    
    friend.rating = 1200
    assert_equal(friend.get_tier(), "黄金", "1200 rating should be 黄金")
    
    friend.rating = 1600
    assert_equal(friend.get_tier(), "铂金", "1600 rating should be 铂金")
    
    friend.rating = 2000
    assert_equal(friend.get_tier(), "钻石", "2000 rating should be 钻石")
    
    pass_test("Friend 等级系统")


func test_friend_serialization() -> void:
    """测试 Friend 序列化"""
    var friend = Friend.new("player_005", "孙七")
    friend.level = 15
    friend.rating = 1500
    friend.status = "online"
    friend.add_game_result(true)
    
    # 测试转换为字典
    var dict = friend.to_dict()
    assert_equal(dict["friend_id"], "player_005", "Dict should have friend_id")
    assert_equal(dict["friend_name"], "孙七", "Dict should have friend_name")
    assert_equal(dict["level"], 15, "Dict should have level")
    assert_equal(dict["rating"], 1500, "Dict should have rating")
    
    # 测试从字典恢复
    var new_friend = Friend.new("temp", "temp")
    new_friend.from_dict(dict)
    assert_equal(new_friend.friend_id, "player_005", "Restored friend_id should match")
    assert_equal(new_friend.level, 15, "Restored level should match")
    assert_equal(new_friend.total_games, 1, "Restored total_games should match")
    
    pass_test("Friend 序列化")


## FriendSystem 类测试

func test_friend_system_creation() -> void:
    """测试 FriendSystem 创建"""
    var system = FriendSystem.new()
    
    assert_equal(system.get_friend_count(), 0, "Should have 0 friends initially")
    assert_equal(system.get_pending_request_count(), 0, "Should have 0 pending requests")
    
    pass_test("FriendSystem 创建")


func test_add_remove_friend() -> void:
    """测试添加/删除好友"""
    var system = FriendSystem.new()
    var friend = Friend.new("player_101", "朋友一")
    
    # 测试添加
    var result = system.add_friend(friend)
    assert_true(result, "Should successfully add friend")
    assert_equal(system.get_friend_count(), 1, "Friend count should be 1")
    assert_true(system.has_friend("player_101"), "Should have friend")
    
    # 测试重复添加
    result = system.add_friend(friend)
    assert_false(result, "Should not add duplicate friend")
    assert_equal(system.get_friend_count(), 1, "Friend count should still be 1")
    
    # 测试删除
    result = system.remove_friend("player_101")
    assert_true(result, "Should successfully remove friend")
    assert_equal(system.get_friend_count(), 0, "Friend count should be 0")
    assert_false(system.has_friend("player_101"), "Should not have friend")
    
    # 测试删除不存在的好友
    result = system.remove_friend("player_999")
    assert_false(result, "Should fail to remove non-existent friend")
    
    pass_test("FriendSystem 添加/删除")


func test_friend_queries() -> void:
    """测试好友查询"""
    var system = FriendSystem.new()
    
    # 添加多个好友
    var f1 = Friend.new("p1", "好友1")
    f1.status = "online"
    f1.level = 5
    f1.rating = 1000
    system.add_friend(f1)
    
    var f2 = Friend.new("p2", "好友2")
    f2.status = "playing"
    f2.level = 10
    f2.rating = 1200
    system.add_friend(f2)
    
    var f3 = Friend.new("p3", "好友3")
    f3.status = "offline"
    f3.level = 3
    f3.rating = 800
    system.add_friend(f3)
    
    # 测试获取所有好友
    var all = system.get_all_friends()
    assert_equal(all.size(), 3, "Should have 3 friends")
    
    # 测试获取在线好友
    var online = system.get_online_friends()
    assert_equal(online.size(), 2, "Should have 2 online friends")
    
    # 测试获取游戏中的好友
    var playing = system.get_playing_friends()
    assert_equal(playing.size(), 1, "Should have 1 playing friend")
    
    # 测试获取离线好友
    var offline = system.get_offline_friends()
    assert_equal(offline.size(), 1, "Should have 1 offline friend")
    
    pass_test("FriendSystem 好友查询")


func test_friend_filtering() -> void:
    """测试好友筛选"""
    var system = FriendSystem.new()
    
    # 添加好友
    for i in range(1, 6):
        var friend = Friend.new("player_%d" % i, "玩家%d" % i)
        friend.level = i * 5
        friend.rating = 1000 + i * 100
        system.add_friend(friend)
    
    # 按等级筛选
    var by_level = system.get_friends_by_level(15, 25)
    assert_equal(by_level.size(), 2, "Should have 2 friends in level range")
    
    # 按评分筛选
    var by_rating = system.get_friends_by_rating(1200, 1400)
    assert_equal(by_rating.size(), 3, "Should have 3 friends in rating range")
    
    # 获取评分最高的好友
    var top = system.get_top_friends(3)
    assert_equal(top.size(), 3, "Should have top 3 friends")
    assert_equal(top[0].rating, 1500, "First should have highest rating")
    
    pass_test("FriendSystem 好友筛选")


func test_friend_requests() -> void:
    """测试好友请求"""
    var system = FriendSystem.new()
    
    # 发送请求
    var result = system.send_friend_request("req_001", "请求者")
    assert_true(result, "Should send friend request")
    assert_equal(system.get_pending_request_count(), 1, "Should have 1 pending request")
    
    # 接受请求
    result = system.accept_friend_request("req_001")
    assert_true(result, "Should accept friend request")
    assert_equal(system.get_pending_request_count(), 0, "Pending should be 0")
    assert_equal(system.get_friend_count(), 1, "Should have 1 friend")
    
    # 发送第二个请求并拒绝
    system.send_friend_request("req_002", "请求者2")
    result = system.reject_friend_request("req_002")
    assert_true(result, "Should reject friend request")
    assert_equal(system.get_pending_request_count(), 0, "Pending should be 0")
    assert_equal(system.get_friend_count(), 1, "Should still have 1 friend")
    
    pass_test("FriendSystem 好友请求")


func test_blocking() -> void:
    """测试屏蔽功能"""
    var system = FriendSystem.new()
    
    # 添加好友
    var friend = Friend.new("friend_001", "好友")
    system.add_friend(friend)
    assert_equal(system.get_friend_count(), 1, "Should have 1 friend")
    
    # 屏蔽玩家
    var result = system.block_player("player_block", "被屏蔽者")
    assert_true(result, "Should block player")
    assert_true(system.is_blocked("player_block"), "Should be blocked")
    
    # 解除屏蔽
    result = system.unblock_player("player_block")
    assert_true(result, "Should unblock player")
    assert_false(system.is_blocked("player_block"), "Should not be blocked")
    
    # 屏蔽好友应移除
    result = system.block_player("friend_001", "好友")
    assert_equal(system.get_friend_count(), 0, "Friend should be removed when blocked")
    
    pass_test("FriendSystem 屏蔽功能")


func test_system_statistics() -> void:
    """测试系统统计"""
    var system = FriendSystem.new()
    
    # 添加好友
    var f1 = Friend.new("p1", "f1")
    f1.status = "online"
    f1.rating = 1000
    f1.add_game_result(true)
    system.add_friend(f1)
    
    var f2 = Friend.new("p2", "f2")
    f2.status = "offline"
    f2.rating = 1200
    f2.add_game_result(false)
    system.add_friend(f2)
    
    # 获取统计信息
    var stats = system.get_statistics()
    assert_equal(stats["total_friends"], 2, "Total friends should be 2")
    assert_equal(stats["online_friends"], 1, "Online friends should be 1")
    assert_equal(stats["offline_friends"], 1, "Offline friends should be 1")
    assert_equal(stats["total_games_with_friends"], 2, "Total games should be 2")
    assert_equal(stats["total_wins_with_friends"], 1, "Total wins should be 1")
    assert_equal(stats["average_friend_rating"], 1100, "Average rating should be 1100")
    
    pass_test("FriendSystem 系统统计")


func test_system_serialization() -> void:
    """测试系统序列化"""
    var system = FriendSystem.new()
    
    # 添加好友
    var f1 = Friend.new("p1", "friend1")
    f1.level = 10
    f1.rating = 1100
    system.add_friend(f1)
    
    # 发送请求
    system.send_friend_request("p2", "pending_friend")
    
    # 屏蔽玩家
    system.block_player("p3", "blocked_player")
    
    # 导出为JSON
    var json_str = system.to_json()
    assert_true(json_str.length() > 0, "JSON should not be empty")
    
    # 导入到新系统
    var new_system = FriendSystem.new()
    var result = new_system.from_json(json_str)
    assert_true(result, "Should successfully import JSON")
    
    # 验证导入数据
    assert_equal(new_system.get_friend_count(), 1, "Should have 1 friend after import")
    assert_equal(new_system.get_pending_request_count(), 1, "Should have 1 pending after import")
    assert_equal(new_system.get_blocked_players().size(), 1, "Should have 1 blocked after import")
    
    var imported_friend = new_system.get_friend("p1")
    assert_equal(imported_friend.level, 10, "Friend level should match")
    assert_equal(imported_friend.rating, 1100, "Friend rating should match")
    
    pass_test("FriendSystem 系统序列化")


## 辅助测试方法

func assert_equal(a, b, message: String) -> void:
    """断言相等"""
    test_count += 1
    if a == b:
        pass_count += 1
    else:
        fail_count += 1
        print("❌ 失败: %s" % message)
        print("   期望: %s, 实际: %s" % [b, a])


func assert_true(value: bool, message: String) -> void:
    """断言真"""
    assert_equal(value, true, message)


func assert_false(value: bool, message: String) -> void:
    """断言假"""
    assert_equal(value, false, message)


func pass_test(test_name: String) -> void:
    """测试通过"""
    print("✅ 通过: %s" % test_name)


func print_summary() -> void:
    """打印测试总结"""
    print("\n========== 测试结果 ==========")
    print("总测试数: %d" % test_count)
    print("✅ 通过: %d" % pass_count)
    print("❌ 失败: %d" % fail_count)
    print("成功率: %.1f%%" % (float(pass_count) / float(test_count) * 100))
    print("==============================\n")
