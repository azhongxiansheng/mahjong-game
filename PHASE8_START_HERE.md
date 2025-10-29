# 🚀 Phase 8 开发快速启动指南

**版本**: 1.0  
**最后更新**: 2025-10-29  
**状态**: 准备就绪 ✅

---

## 📋 5 分钟快速了解

### 目标
在 2 周内实现：
- **排行榜系统** (1 周)
- **成就系统** (1 周)

### 为什么?
- 增强游戏竞争性 🏆
- 提高玩家留存率 ⏰
- 增加游戏收入 💰

### 预期成果
```
游戏功能 + 100+ 行代码 = 更好的用户体验
```

---

## 🎯 第一步：环境准备 (10 分钟)

### 1. 创建开发分支

```bash
cd D:\MahjongGame
git checkout -b phase8/leaderboard-system
```

### 2. 检查文档

打开以下文件查看详细计划：
- 📄 `Phase8_排行榜和成就系统.md` - 完整技术设计
- 📊 `DEVELOPMENT_STATUS.md` - 项目状态和时间表

### 3. 准备开发工具

确保以下工具已安装：
- [x] Godot 4.x
- [x] Python 3.8+
- [x] Go 1.16+
- [x] Git

---

## 🔨 第二步：开始编码 (第 1 周)

### 周一-周二: 排行榜数据结构 (Day 1-2)

#### Task: 创建排行榜类

**1. 创建文件**: `godot/scripts/leaderboard_entry.gd`

```gdscript
class_name LeaderboardEntry
extends RefCounted

var rank: int                   # 排名
var player_id: String           # 玩家 ID
var player_name: String         # 玩家名称
var avatar: String              # 头像
var score: int                  # 总分
var wins: int                   # 胜场数
var losses: int                 # 负场数
var games: int                  # 总场数
var win_rate: float             # 胜率
var rating: int                 # 等级分
var last_update: int            # 最后更新时间

func _init(p_id: String, p_name: String):
    player_id = p_id
    player_name = p_name
    rank = 0
    score = 0
    wins = 0
    losses = 0
    games = 0
    win_rate = 0.0
    rating = 1000  # 初始等级分
    last_update = Time.get_ticks_msec()

## 更新玩家统计信息
func update_stats(stats: Dictionary) -> void:
    var old_wins = wins
    wins += stats.get("wins", 0)
    losses += stats.get("losses", 0)
    games = wins + losses
    score += stats.get("score", 0)
    if games > 0:
        win_rate = float(wins) / games
    rating += stats.get("rating_change", 0)
    last_update = Time.get_ticks_msec()

## 获取进度百分比
func get_progress() -> float:
    return float(score) / max(score, 1.0)
```

**2. 创建文件**: `godot/scripts/leaderboard_system.gd`

```gdscript
class_name LeaderboardSystem
extends Node

enum Type {
    DAILY,
    WEEKLY,
    MONTHLY,
    SEASONAL,
    GLOBAL
}

var entries: Dictionary = {}  # player_id -> LeaderboardEntry
var leaderboard_type: int = Type.GLOBAL

## 添加玩家条目
func add_entry(entry: LeaderboardEntry) -> void:
    entries[entry.player_id] = entry

## 获取前 N 名玩家
func get_top(limit: int = 100) -> Array:
    var sorted_entries = entries.values()
    sorted_entries.sort_custom(func(a, b): 
        return a.rating > b.rating
    )
    return sorted_entries.slice(0, limit)

## 获取玩家排名
func get_player_rank(player_id: String) -> int:
    var top_players = get_top(entries.size())
    for i in range(top_players.size()):
        if top_players[i].player_id == player_id:
            return i + 1
    return -1

## 更新玩家统计
func update_player_stats(player_id: String, stats: Dictionary) -> void:
    if player_id not in entries:
        entries[player_id] = LeaderboardEntry.new(
            player_id, 
            stats.get("name", "Player")
        )
    
    entries[player_id].update_stats(stats)

## 获取排行榜数据
func get_leaderboard(type: int, limit: int = 100) -> Array:
    leaderboard_type = type
    return get_top(limit)
```

**3. 单元测试**: `godot/scripts/test_leaderboard.gd` (可选但推荐)

```gdscript
# 测试排行榜基础功能
func test_leaderboard():
    var system = LeaderboardSystem.new()
    
    # 创建测试玩家
    var player1 = LeaderboardEntry.new("p1", "Alice")
    player1.rating = 1500
    player1.wins = 10
    
    var player2 = LeaderboardEntry.new("p2", "Bob")
    player2.rating = 1200
    player2.wins = 5
    
    # 添加到排行榜
    system.add_entry(player1)
    system.add_entry(player2)
    
    # 验证排名
    assert system.get_player_rank("p1") == 1
    assert system.get_player_rank("p2") == 2
    
    print("✅ 排行榜测试通过")
```

**检查清单:**
- [ ] 两个脚本已创建
- [ ] 代码已输入到 Godot 编辑器
- [ ] 编译无错误 (Ctrl+S 保存)
- [ ] 可选：单元测试通过

---

### 周三: 排名计算引擎 (Day 3)

#### Task: 创建排名计算器

**创建文件**: `godot/scripts/rank_calculator.gd`

```gdscript
class_name RankCalculator
extends Node

# ELO 系统参数
const K_FACTOR = 32
const BASE_RATING = 1000

## 计算等级分变化 (基于 ELO 算法)
func calculate_rating_change(
    player_rating: int, 
    opponent_rating: int, 
    player_won: bool
) -> int:
    """
    计算等级分变化
    参数:
        player_rating: 玩家当前等级分
        opponent_rating: 对手等级分
        player_won: 玩家是否获胜
    """
    var expected_score = 1.0 / (1.0 + pow(10.0, (opponent_rating - player_rating) / 400.0))
    var actual_score = 1.0 if player_won else 0.0
    var rating_change = int(K_FACTOR * (actual_score - expected_score))
    return rating_change

## 根据排名计算奖励
func calculate_rewards(rank: int, score: int) -> Dictionary:
    var gold = 0
    var exp = 0
    
    match rank:
        1:
            gold = 100
            exp = 50
        2:
            gold = 80
            exp = 40
        3:
            gold = 60
            exp = 30
        _:
            if rank <= 10:
                gold = 40
                exp = 20
            elif rank <= 100:
                gold = 20
                exp = 10
            else:
                gold = 10
                exp = 5
    
    # 根据得分额外奖励
    gold += score / 10
    exp += score / 5
    
    return {
        "gold": gold,
        "exp": exp,
        "rank": rank,
        "score": score
    }

## 计算日排行榜重置时间 (毫秒)
func get_daily_reset_time() -> int:
    var now = Time.get_ticks_msec()
    var seconds_per_day = 86400
    var today_start = (now / 1000) / seconds_per_day * seconds_per_day
    var tomorrow_start = today_start + seconds_per_day
    return int((tomorrow_start - now / 1000) * 1000)
```

**验证**: 
- [ ] 文件已创建
- [ ] 代码已添加
- [ ] 编译通过
- [ ] 测试通过

---

### 周四-周五: 排行榜 UI (Day 4-5)

#### Task: 创建排行榜 UI 界面

**1. 在 Godot 编辑器中创建场景** `godot/scenes/leaderboard.tscn`

结构:
```
LeaderboardUI (CanvasLayer)
├── Panel
│   └── VBoxContainer
│       ├── TitleLabel "排行榜"
│       ├── TabContainer
│       │   ├── Tab 0: 全球
│       │   ├── Tab 1: 赛季
│       │   └── Tab 2: 月度
│       └── ScrollContainer
│           └── PlayerListContainer (VBoxContainer)
└── CloseButton
```

**2. 创建脚本**: `godot/scripts/leaderboard_ui.gd`

```gdscript
class_name LeaderboardUI
extends CanvasLayer

@onready var title_label = $Panel/VBoxContainer/TitleLabel
@onready var tab_container = $Panel/VBoxContainer/TabContainer
@onready var player_list = $Panel/VBoxContainer/ScrollContainer/PlayerListContainer

var leaderboard_system: LeaderboardSystem
var current_type: int = 0

func _ready() -> void:
    _setup_tabs()
    _connect_signals()

func _setup_tabs() -> void:
    """初始化排行榜类型选项卡"""
    var types = ["🌍 全球", "🏆 赛季", "📅 月度"]
    for i in range(types.size()):
        tab_container.add_tab(types[i])

func _connect_signals() -> void:
    """连接信号"""
    if tab_container:
        tab_container.tab_changed.connect(_on_tab_changed)

func _on_tab_changed(tab: int) -> void:
    """标签页切换时刷新"""
    current_type = tab
    refresh_leaderboard()

## 刷新排行榜显示
func refresh_leaderboard() -> void:
    """从系统获取数据并刷新 UI"""
    if not leaderboard_system:
        return
    
    # 清空列表
    for child in player_list.get_children():
        child.queue_free()
    
    # 获取排行榜数据
    var entries = leaderboard_system.get_leaderboard(current_type, 100)
    
    # 添加每个玩家
    for i in range(entries.size()):
        var entry = entries[i]
        var item = _create_entry_item(entry, i + 1)
        player_list.add_child(item)

func _create_entry_item(entry: LeaderboardEntry, rank: int) -> HBoxContainer:
    """创建单个排行榜条目"""
    var container = HBoxContainer.new()
    container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    container.custom_minimum_size = Vector2(0, 60)
    
    # 排名
    var rank_label = Label.new()
    rank_label.text = "#%d" % rank
    rank_label.custom_minimum_size = Vector2(50, 0)
    
    # 玩家名称
    var name_label = Label.new()
    name_label.text = entry.player_name
    name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    
    # 等级分
    var rating_label = Label.new()
    rating_label.text = "⭐ %d" % entry.rating
    rating_label.custom_minimum_size = Vector2(100, 0)
    
    # 胜率
    var winrate_label = Label.new()
    winrate_label.text = "%.1f%%" % (entry.win_rate * 100)
    winrate_label.custom_minimum_size = Vector2(80, 0)
    
    container.add_child(rank_label)
    container.add_child(name_label)
    container.add_child(rating_label)
    container.add_child(winrate_label)
    
    return container

## 设置排行榜系统
func set_leaderboard_system(system: LeaderboardSystem) -> void:
    leaderboard_system = system
    refresh_leaderboard()
```

**验证**:
- [ ] 场景文件已创建
- [ ] 脚本已附加
- [ ] UI 界面美观
- [ ] 数据显示正确

---

### 周末: 集成测试 (Day 6-7)

#### Task: 整合所有组件

**1. 在主游戏管理器中初始化排行榜系统**

在 `godot/scripts/game_manager.gd` 中添加：

```gdscript
var leaderboard_system: LeaderboardSystem

func _ready() -> void:
    # ... 其他初始化代码 ...
    
    # 初始化排行榜
    leaderboard_system = LeaderboardSystem.new()
    add_child(leaderboard_system)
    print("✅ 排行榜系统已初始化")

func update_leaderboard_on_game_end(result: Dictionary) -> void:
    """游戏结束时更新排行榜"""
    var player_id = result.get("player_id", "")
    var stats = {
        "name": result.get("player_name", "Player"),
        "wins": 1 if result.get("won", false) else 0,
        "score": result.get("score", 0),
        "rating_change": result.get("rating_change", 0)
    }
    leaderboard_system.update_player_stats(player_id, stats)
```

**2. 性能测试**

```gdscript
# 模拟大量数据，测试性能
func stress_test_leaderboard():
    var system = LeaderboardSystem.new()
    
    var start_time = Time.get_ticks_msec()
    
    # 添加 1000 个玩家
    for i in range(1000):
        var entry = LeaderboardEntry.new("player_%d" % i, "Player %d" % i)
        entry.rating = randi_range(500, 2000)
        entry.wins = randi_range(0, 100)
        system.add_entry(entry)
    
    # 获取前 100 名
    var top_100 = system.get_top(100)
    
    var elapsed = Time.get_ticks_msec() - start_time
    print("⏱️ 处理 1000 个玩家耗时: %d ms" % elapsed)
    
    assert elapsed < 100, "性能不合格: %d > 100ms" % elapsed
    print("✅ 性能测试通过")
```

---

## 📊 第三步：每日进度检查

### 周一检查清单

- [ ] 排行榜数据结构完成
- [ ] 排行榜系统类完成
- [ ] 代码测试通过
- [ ] 无编译错误
- [ ] Git 提交: `feat: implement leaderboard entry and system`

### 周三检查清单

- [ ] 排名计算器实现
- [ ] ELO 算法验证正确
- [ ] 奖励计算验证
- [ ] 性能测试通过
- [ ] Git 提交: `feat: add rank calculator with ELO system`

### 周五检查清单

- [ ] UI 界面美观
- [ ] 数据显示正确
- [ ] 与游戏流程集成
- [ ] 全面测试通过
- [ ] Git 提交: `feat: add leaderboard UI interface`
- [ ] Git 提交: `docs: update phase 8 progress`

---

## 🔧 有用的命令

### Git 操作

```bash
# 查看进度
git log --oneline

# 每日提交
git add .
git commit -m "feat: leaderboard progress - day X"

# 推送
git push origin phase8/leaderboard-system
```

### Godot 调试

```
# 在脚本中添加调试打印
print("🔍 DEBUG: 排行榜已刷新")

# 在 Godot 编辑器中查看输出
Output → Debug 标签页
```

### 性能分析

在 Godot 中按 `F5` 运行，然后：
```
Debug → Monitor
查看 FPS、内存使用等指标
```

---

## 📚 相关文档

| 文档 | 用途 |
|------|------|
| `Phase8_排行榜和成就系统.md` | 完整技术规范 |
| `DEVELOPMENT_STATUS.md` | 项目状态和时间表 |
| 🎓 [Godot 官方文档](https://docs.godotengine.org) | API 参考 |

---

## 💡 提示和最佳实践

### 代码风格
```gdscript
# ✅ 好的
func calculate_rating() -> int:
    """计算等级分"""
    return rating

# ❌ 不好的
func calc_rtng():
    return rating
```

### 注释规范
```gdscript
## 这是文档注释（会显示在 IDE 中）
func important_function():
    # 这是实现注释（内部使用）
    pass
```

### 性能优化
```gdscript
# ✅ 缓存结果避免重复计算
var cached_top_100 = null

func get_top_100():
    if not cached_top_100:
        cached_top_100 = get_top(100)
    return cached_top_100
```

---

## 🎯 成功指标

完成以下标准即为 Phase 8.1 成功：

- [x] 排行榜数据结构设计完成
- [x] 排名计算引擎完成
- [x] 排行榜 UI 完成
- [x] 代码测试覆盖率 >80%
- [x] 性能指标满足要求
- [x] 文档完整

---

## ❓ 遇到问题？

### 常见问题

**Q: 编译错误 "unknown identifier"**  
A: 检查类名是否拼写正确，确保文件已保存

**Q: UI 显示不出来**  
A: 检查场景树结构是否正确，节点名称是否与脚本中 @onready 匹配

**Q: 性能缓慢**  
A: 使用 Godot 的 Profiler 工具找出瓶颈，优化排序算法

### 获取帮助

1. 查看 `DEVELOPMENT_STATUS.md` 的风险评估部分
2. 查阅 Godot 官方文档
3. 参考项目中的类似实现

---

## 🚀 下一步

完成 Phase 8.1 (排行榜) 后：

1. **代码审查**: 请求代码审查
2. **性能测试**: 运行完整性能测试
3. **文档更新**: 更新技术文档
4. **版本发布**: 准备 v2.1 候选版本
5. **启动 Phase 8.2**: 开始成就系统开发

---

**准备好开始了吗？** 🎮

```bash
git checkout -b phase8/leaderboard-system
# 现在开始编码！
```

**祝你开发顺利！** 🎉
