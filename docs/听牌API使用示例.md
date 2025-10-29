# 🎓 听牌API使用示例

**文档版本**: 1.0  
**最后更新**: 2025-10-29  
**面向对象**: 游戏开发者、AI开发者、测试人员

---

## 📚 目录

1. [基础使用](#基础使用)
2. [完整游戏流程](#完整游戏流程)
3. [AI集成](#ai集成)
4. [错误处理](#错误处理)
5. [性能优化](#性能优化)
6. [常见场景](#常见场景)

---

## 基础使用

### 示例1: 检查玩家能否胡牌

```gdscript
# 场景: 玩家摸到一张新牌
func handle_drawn_card(card: CardData):
    var hand = player_hand
    hand.add_card(card)  # 手牌变为14张
    
    # 检查是否能胡
    var result = WinChecker.check_win(hand)
    
    if result.can_win:
        print("🎉 恭喜！您可以胡牌！")
        show_win_animation()
    else:
        print("继续摸牌...")
```

### 示例2: 检查玩家能听什么牌

```gdscript
# 场景: 玩家要出牌前，显示可听牌列表
func before_discard():
    var hand = player_hand  # 13张牌
    
    # 获取所有可听的牌
    var ting_cards = WinChecker.check_can_hear(hand)
    
    if ting_cards.size() > 0:
        print("🎯 您可以听以下牌类:")
        for card in ting_cards:
            print("  - %s" % card.get_card_name())
    else:
        print("❌ 暂时无法听牌")
```

---

## 完整游戏流程

### 示例3: 一整轮游戏的听牌逻辑

```gdscript
class_name GameRound

var current_player: Player
var players: Array[Player]

func start_round():
    # 初始化: 每个玩家13张牌
    for player in players:
        player.hand.clear()
        for i in range(13):
            var card = draw_card_from_wall()
            player.hand.add_card(card)
    
    # 开始轮流出牌
    for turn in range(100):  # 最多100圈
        var drawn_card = draw_card_from_wall()
        
        if handle_turn(current_player, drawn_card):
            break  # 游戏结束
        
        current_player = get_next_player()

func handle_turn(player: Player, drawn_card: CardData) -> bool:
    player.hand.add_card(drawn_card)  # 摸牌 (14张)
    
    # 第1步: 检查是否能胡
    var win_result = WinChecker.check_win(player.hand)
    if win_result.can_win:
        announce_win(player, win_result)
        return true  # 游戏结束
    
    # 第2步: 玩家选择出牌 (14张 -> 13张)
    var discard_card = player.choose_discard_card(player.hand)
    player.hand.remove_card(discard_card)
    announce_discard(player, discard_card)
    
    # 第3步: 显示其他玩家可听牌情况
    var listener_ting = WinChecker.check_can_hear(player.hand)
    if listener_ting.size() > 0:
        ui_show_listening_tiles(player, listener_ting)
    
    # 第4步: 检查其他玩家是否要吃/碰/杠/胡
    for other_player in players:
        if other_player == player:
            continue
        
        if other_player.can_hu(discard_card):
            announce_win(other_player, "胡牌")
            return true
    
    return false

func announce_win(player: Player, result: WinResult):
    print("🎉 %s 胡牌! 配置数: %d" % [player.name, result.win_patterns.size()])

func announce_discard(player: Player, card: CardData):
    print("💬 %s 出牌: %s" % [player.name, card.get_card_name()])
```

---

## AI集成

### 示例4: AI决策系统

```gdscript
class_name AIPlayer

var hand: CardHand
var difficulty: int = 1  # 1=简单, 2=中等, 3=困难

func choose_discard_card() -> CardData:
    match difficulty:
        1:
            return ai_easy_choice()
        2:
            return ai_medium_choice()
        3:
            return ai_hard_choice()
    return null

# 简单难度: 随机出牌
func ai_easy_choice() -> CardData:
    var idx = randi() % hand.cards.size()
    return hand.cards[idx]

# 中等难度: 优先出听数少的牌
func ai_medium_choice() -> CardData:
    var best_card = null
    var min_ting = 999
    
    for card in hand.cards:
        hand.remove_card(card)
        
        var ting_count = WinChecker.check_can_hear(hand).size()
        if ting_count < min_ting:
            min_ting = ting_count
            best_card = card
        
        hand.add_card(card)
    
    return best_card

# 困难难度: 优先出最安全的牌(对手需要的牌最少)
func ai_hard_choice() -> CardData:
    var best_card = null
    var min_opponent_ting = 999
    
    for card in hand.cards:
        # 我出这张牌后，对手可以听什么
        hand.remove_card(card)
        var my_ting_after = WinChecker.check_can_hear(hand).size()
        
        # 计算安全分
        var safety_score = 999 - my_ting_after
        
        if safety_score > min_opponent_ting:
            min_opponent_ting = safety_score
            best_card = card
        
        hand.add_card(card)
    
    return best_card

func should_hu(discard_card: CardData) -> bool:
    var temp_hand = CardHand.new()
    for c in hand.cards:
        temp_hand.add_card(c)
    temp_hand.add_card(discard_card)
    
    var result = WinChecker.check_win(temp_hand)
    
    # 困难难度: 只在明确赢多局时才胡
    if difficulty == 3:
        return result.can_win and result.win_patterns.size() > 2
    
    return result.can_win
```

---

## 错误处理

### 示例5: 完整的错误检查

```gdscript
func safe_check_win(hand: CardHand) -> WinResult:
    # 错误检查1: 手牌数量
    if hand.get_card_count() != 14:
        push_error("胡牌检查失败: 手牌数量为 %d, 需要 14" % hand.get_card_count())
        return WinResult.new()
    
    # 错误检查2: 空手牌
    if hand.cards.size() == 0:
        push_error("胡牌检查失败: 手牌为空")
        return WinResult.new()
    
    # 执行检查
    return WinChecker.check_win(hand)

func safe_check_ting(hand: CardHand) -> Array:
    # 错误检查1: 手牌数量
    if hand.get_card_count() != 13:
        push_error("听牌检查失败: 手牌数量为 %d, 需要 13" % hand.get_card_count())
        return []
    
    # 错误检查2: 空手牌
    if hand.cards.size() == 0:
        push_error("听牌检查失败: 手牌为空")
        return []
    
    # 错误检查3: 重复检查 (防止连续调用)
    if not _last_check_time or Time.get_ticks_msec() - _last_check_time < 100:
        return _last_check_result
    
    var result = WinChecker.check_can_hear(hand)
    _last_check_time = Time.get_ticks_msec()
    _last_check_result = result
    
    return result

var _last_check_time: int = 0
var _last_check_result: Array = []
```

---

## 性能优化

### 示例6: 缓存和预计算

```gdscript
class_name TingCache

var cache: Dictionary = {}  # 手牌签名 -> 听牌结果

func get_ting_cards(hand: CardHand) -> Array:
    var signature = hand.get_signature()  # 手牌的唯一标识
    
    # 查找缓存
    if signature in cache:
        return cache[signature]
    
    # 计算并缓存
    var result = WinChecker.check_can_hear(hand)
    cache[signature] = result
    
    return result

func clear_cache():
    cache.clear()
```

### 示例7: 异步检查 (防止卡顿)

```gdscript
class_name AsyncTingChecker

func check_ting_async(hand: CardHand, callback: Callable):
    # 在后台线程检查
    var thread = Thread.new(_async_check)
    thread.start.call_deferred("_on_check_complete", [hand, callback])

func _async_check(hand: CardHand) -> Array:
    return WinChecker.check_can_hear(hand)

func _on_check_complete(args: Array):
    var hand = args[0]
    var callback = args[1]
    var result = _async_check(hand)
    
    # 回到主线程调用回调
    call_deferred(callback, result)
```

---

## 常见场景

### 场景1: UI界面显示可听牌

```gdscript
class_name TingUIDisplay

func display_listening_tiles(player: Player):
    # 获取可听牌
    var ting_cards = WinChecker.check_can_hear(player.hand)
    
    # 清空旧的UI
    clear_listening_display()
    
    if ting_cards.size() == 0:
        label_listening.text = "暂无听牌"
        label_listening.modulate = Color.GRAY
        return
    
    # 显示听牌信息
    var ting_names = []
    for card in ting_cards:
        ting_names.append(card.get_card_name())
    
    label_listening.text = "🎯 听: " + ", ".join(ting_names)
    label_listening.modulate = Color.GREEN
    
    # 高亮可听的牌
    for card_ui in card_ui_list:
        if card_ui.card_data in ting_cards:
            card_ui.highlight()

func clear_listening_display():
    for card_ui in card_ui_list:
        card_ui.unhighlight()
```

### 场景2: 统计分析

```gdscript
class_name GameStatistics

func analyze_game(game_history: Array) -> Dictionary:
    var stats = {
        "total_turns": 0,
        "total_ting_opportunities": 0,
        "average_ting_per_turn": 0.0,
        "most_listened_card": null,
        "max_ting_count": 0
    }
    
    for turn in game_history:
        stats["total_turns"] += 1
        
        var ting_count = turn.ting_cards.size()
        if ting_count > 0:
            stats["total_ting_opportunities"] += 1
            stats["average_ting_per_turn"] += ting_count
        
        if ting_count > stats["max_ting_count"]:
            stats["max_ting_count"] = ting_count
    
    if stats["total_ting_opportunities"] > 0:
        stats["average_ting_per_turn"] /= stats["total_ting_opportunities"]
    
    return stats
```

### 场景3: 提示系统

```gdscript
class_name HintSystem

func get_discard_hint(player: Player) -> CardData:
    var hand = player.hand
    
    # 获取当前听牌情况
    var current_ting = WinChecker.check_can_hear(hand)
    
    # 找出出牌后听牌最多的出法
    var best_discard = null
    var max_ting_after = 0
    
    for card in hand.cards:
        hand.remove_card(card)
        var ting_after = WinChecker.check_can_hear(hand).size()
        
        if ting_after > max_ting_after:
            max_ting_after = ting_after
            best_discard = card
        
        hand.add_card(card)
    
    return best_discard

func get_ai_danger_level(player: Player) -> int:
    var ting_count = WinChecker.check_can_hear(player.hand).size()
    
    if ting_count == 0:
        return 0  # 安全
    elif ting_count < 3:
        return 1  # 低风险
    elif ting_count < 6:
        return 2  # 中等风险
    else:
        return 3  # 高风险
```

---

## 📋 API参考速查

```gdscript
# 主要API
WinChecker.check_win(hand: CardHand) -> WinResult
WinChecker.check_can_hear(hand: CardHand) -> Array[CardData]

# 常用类方法
CardHand.add_card(card: CardData)
CardHand.remove_card(card: CardData)
CardHand.get_card_count() -> int
CardHand.clear()

CardData.new(suit: int, number: int)
CardData.get_card_name() -> String
CardData.get_suit_name() -> String

WinResult.can_win -> bool
WinResult.eye_card -> CardData
WinResult.win_patterns -> Array
```

---

## 🎯 最佳实践

✅ **做这些事:**
- 检查手牌数量后再调用API
- 使用缓存减少重复计算
- 在后台线程中进行复杂计算
- 添加错误日志便于调试
- 测试边界情况

❌ **不要这样做:**
- 在主线程中频繁调用检查
- 修改手牌后不更新缓存
- 忽略返回值的有效性
- 假设输入总是有效的
- 在性能关键路径中使用

---

**需要帮助？** 查看 `听牌功能快速参考指南.md` 或 `听牌功能最终验证报告.md`
