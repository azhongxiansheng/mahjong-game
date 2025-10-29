# 🎯 Phase 8: 排行榜和成就系统 - 完整开发计划

**规划日期**: 2025-10-29  
**版本**: 1.0  
**优先级**: ⭐⭐⭐⭐⭐ 最高优先级  
**预计周期**: 1-2 周

---

## 📋 目录

1. [系统概述](#系统概述)
2. [技术架构](#技术架构)
3. [Phase 8.1 排行榜系统](#phase-81-排行榜系统)
4. [Phase 8.2 成就系统](#phase-82-成就系统)
5. [实现步骤](#实现步骤)
6. [测试计划](#测试计划)
7. [部署检查](#部署检查)

---

## 系统概述

### 8.1 排行榜系统

#### 功能需求
- 展示全球玩家排名
- 多种排行榜类型（日/周/月/赛季/全局）
- 实时排名计算和更新
- 玩家历史排名追踪
- 排名奖励和激励

#### 技术指标
```
性能目标:
- 排行榜加载时间 < 500ms
- 排名计算耗时 < 100ms
- 支持 1000+ 玩家
- 实时更新延迟 < 1s
```

#### 数据结构
```gdscript
class LeaderboardEntry:
    var rank: int              # 排名
    var player_id: String      # 玩家 ID
    var player_name: String    # 玩家名称
    var avatar: String         # 头像 URL
    var score: int             # 总分数
    var wins: int              # 胜场数
    var losses: int            # 负场数
    var games: int             # 总场数
    var win_rate: float        # 胜率
    var rating: int            # 等级分
    var last_update: int       # 最后更新时间
```

### 8.2 成就系统

#### 功能需求
- 多种成就分类（胜利、特殊、得分、连胜、收集、挑战）
- 成就进度追踪
- 成就解锁通知
- 成就奖励系统
- 成就展示界面

#### 成就分类
```
胜利相关 (Wins):
  - First Victory: 赢得首场游戏
  - Streak Master: 连胜 5 场
  - Dominator: 连胜 10 场
  - Legend: 连胜 20 场

特殊胡牌 (Special Wins):
  - Hu Master: 完成 10 次胡牌
  - Perfect Hu: 完成 50 次胡牌
  - Hu Expert: 完成 100 次胡牌
  - Listening Expert: 听牌 100 次

得分相关 (Scores):
  - Century: 单局 100+ 分
  - Champion: 单局 200+ 分
  - Legend Score: 单局 300+ 分

连胜相关 (Streaks):
  - Win Streak 5: 连胜 5 场
  - Win Streak 10: 连胜 10 场
  - Win Streak 20: 连胜 20 场

收集相关 (Collections):
  - Card Collector: 使用所有卡牌类型
  - Position Master: 在所有位置赢过
```

---

## 技术架构

### 系统架构图
```
GameManager (主管理器)
├── LeaderboardSystem (排行榜系统)
│   ├── LeaderboardData (数据存储)
│   ├── RankCalculator (排名计算)
│   ├── LeaderboardUI (UI 显示)
│   └── LeaderboardAPI (API 接口)
├── AchievementSystem (成就系统)
│   ├── AchievementData (数据存储)
│   ├── AchievementTracker (进度追踪)
│   ├── AchievementNotifier (通知系统)
│   ├── AchievementUI (UI 显示)
│   └── AchievementAPI (API 接口)
└── Database (数据库)
    ├── leaderboard.db
    ├── achievements.db
    └── player_stats.db
```

### 数据流图
```
游戏结束
  ↓
更新玩家统计
  ↓
检查成就解锁
  ↓
发送成就通知
  ↓
计算排名变化
  ↓
更新排行榜
  ↓
刷新 UI 显示
```

---

## Phase 8.1: 排行榜系统

### 开发任务清单

#### Task 1: 数据结构设计 (2-3 天)

```gdscript
# 1. 创建 LeaderboardEntry 类
class_name LeaderboardEntry
extends RefCounted

var rank: int
var player_id: String
var player_name: String
var avatar: String
var score: int
var wins: int
var losses: int
var games: int
var win_rate: float
var rating: int
var last_update: int

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

# 2. 创建 Leaderboard 类（排行榜管理）
class_name Leaderboard
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
var last_reset: int = 0

func add_entry(entry: LeaderboardEntry) -> void:
    entries[entry.player_id] = entry

func get_top(limit: int = 100) -> Array:
    var sorted_entries = entries.values()
    sorted_entries.sort_custom(func(a, b): return a.rating > b.rating)
    return sorted_entries.slice(0, limit)

func get_player_rank(player_id: String) -> int:
    var top_players = get_top(entries.size())
    for i in range(top_players.size()):
        if top_players[i].player_id == player_id:
            return i + 1
    return -1

func update_stats(player_id: String, stats: Dictionary) -> void:
    if player_id not in entries:
        entries[player_id] = LeaderboardEntry.new(player_id, stats.get("name", "Player"))
    
    var entry = entries[player_id]
    entry.score += stats.get("score", 0)
    entry.wins += stats.get("wins", 0)
    entry.losses += stats.get("losses", 0)
    entry.games += stats.get("games", 0)
    entry.win_rate = float(entry.wins) / max(entry.games, 1)
    entry.rating += stats.get("rating_change", 0)
    entry.last_update = Time.get_ticks_msec()
```

#### Task 2: 排名计算引擎 (3-4 天)

```gdscript
class_name RankCalculator
extends Node

# 等级分计算模型（基于 ELO 系统）
const K_FACTOR = 32  # 等级分变动系数
const BASE_RATING = 1000

func calculate_rating_change(player_rating: int, opponent_rating: int, result: bool) -> int:
    """计算等级分变化 (胜为 true，负为 false)"""
    var expected_score = 1.0 / (1.0 + pow(10.0, (opponent_rating - player_rating) / 400.0))
    var actual_score = 1.0 if result else 0.0
    var rating_change = int(K_FACTOR * (actual_score - expected_score))
    return rating_change

func calculate_rewards(rank: int, score: int) -> Dictionary:
    """根据排名和得分计算奖励"""
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
            else:
                gold = 20
                exp = 10
    
    # 根据得分额外奖励
    gold += score / 10
    exp += score / 5
    
    return {"gold": gold, "exp": exp}

func calculate_daily_leaderboard_reset() -> int:
    """计算每日排行榜重置时间"""
    var now = Time.get_ticks_msec()
    var seconds_per_day = 86400
    var today_start = (now / 1000) / seconds_per_day * seconds_per_day
    var tomorrow_start = today_start + seconds_per_day
    return tomorrow_start * 1000 - now
```

#### Task 3: 排行榜 UI 设计 (4-5 天)

创建文件：`godot/scenes/leaderboard_ui.tscn` 和 `godot/scripts/leaderboard_ui.gd`

```gdscript
class_name LeaderboardUI
extends CanvasLayer

@onready var title_label = $Panel/VBoxContainer/TitleLabel
@onready var tab_container = $Panel/VBoxContainer/TabContainer
@onready var player_list = $Panel/VBoxContainer/ScrollContainer/VBoxContainer

# 排行榜数据
var leaderboard_system: LeaderboardSystem
var current_type: int = 0
var entries: Array = []

func _ready() -> void:
    _init_tabs()
    _setup_signals()
    refresh_leaderboard(LeaderboardSystem.Type.GLOBAL)

func _init_tabs() -> void:
    """初始化排行榜类型标签"""
    var types = ["全局", "赛季", "月度", "周度", "日度"]
    for i in range(types.size()):
        var tab = tab_container.add_tab_item(types[i])
        tab_container.set_tab_icon(i, preload("res://assets/icons/leaderboard.svg"))

func refresh_leaderboard(type: int) -> void:
    """刷新排行榜显示"""
    current_type = type
    entries = leaderboard_system.get_leaderboard(type, 100)
    _update_ui()

func _update_ui() -> void:
    """更新 UI 显示"""
    player_list.clear()
    
    for i in range(entries.size()):
        var entry = entries[i]
        var item = _create_entry_item(entry, i + 1)
        player_list.add_child(item)

func _create_entry_item(entry: LeaderboardEntry, rank: int) -> HBoxContainer:
    """创建排行榜条目 UI"""
    var container = HBoxContainer.new()
    container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    
    # 排名
    var rank_label = Label.new()
    rank_label.text = str(rank)
    rank_label.custom_minimum_size = Vector2(40, 50)
    
    # 玩家名称
    var name_label = Label.new()
    name_label.text = entry.player_name
    name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    
    # 等级分
    var rating_label = Label.new()
    rating_label.text = str(entry.rating)
    rating_label.custom_minimum_size = Vector2(80, 50)
    
    # 胜率
    var winrate_label = Label.new()
    winrate_label.text = "%.1f%%" % (entry.win_rate * 100)
    winrate_label.custom_minimum_size = Vector2(80, 50)
    
    container.add_child(rank_label)
    container.add_child(name_label)
    container.add_child(rating_label)
    container.add_child(winrate_label)
    
    return container
```

#### Task 4: 后端 API 集成 (3-4 天)

修改 `backend/main.go` 和 `backend/handlers/leaderboard.go`

```go
// 获取排行榜
func GetLeaderboard(c *gin.Context) {
    leaderboard_type := c.DefaultQuery("type", "GLOBAL")
    limit := c.DefaultQuery("limit", "100")
    
    // 从数据库查询排行榜数据
    // 计算排名和排名变化
    // 返回 JSON
    
    c.JSON(200, gin.H{
        "success": true,
        "data": leaderboard_data,
    })
}

// 更新玩家排名
func UpdatePlayerRank(player_id string, stats map[string]interface{}) {
    // 更新玩家统计
    // 重新计算排名
    // 发送排名变化通知
}
```

---

## Phase 8.2: 成就系统

### 开发任务清单

#### Task 1: 成就定义和数据结构 (2-3 天)

```gdscript
class_name Achievement
extends RefCounted

var id: String                  # 成就 ID
var name: String                # 成就名称
var description: String         # 成就描述
var icon: String                # 成就图标
var category: String            # 成就分类
var progress: int               # 当前进度
var target: int                 # 目标进度
var reward_gold: int            # 金币奖励
var reward_exp: int             # 经验奖励
var reward_gem: int             # 宝石奖励
var unlocked: bool              # 是否已解锁
var unlock_time: int            # 解锁时间

func _init(p_id: String, p_name: String, p_target: int = 1):
    id = p_id
    name = p_name
    target = p_target
    progress = 0
    unlocked = false
    unlock_time = 0

func add_progress(amount: int) -> bool:
    """增加进度，返回是否解锁"""
    if unlocked:
        return false
    
    progress = min(progress + amount, target)
    
    if progress >= target:
        unlocked = true
        unlock_time = Time.get_ticks_msec()
        return true
    
    return false

func get_progress_percent() -> float:
    return float(progress) / max(target, 1)


class_name AchievementSystem
extends Node

var achievements: Dictionary = {}  # achievement_id -> Achievement
var player_achievements: Dictionary = {}  # player_id -> [achievements]

# 成就定义
const ACHIEVEMENTS_DATA = [
    # 胜利相关
    {
        "id": "first_victory",
        "name": "首胜",
        "category": "wins",
        "target": 1,
        "reward": {"gold": 50, "exp": 25}
    },
    {
        "id": "streak_5",
        "name": "连胜 5 场",
        "category": "streaks",
        "target": 5,
        "reward": {"gold": 200, "exp": 100}
    },
    {
        "id": "streak_10",
        "name": "连胜 10 场",
        "category": "streaks",
        "target": 10,
        "reward": {"gold": 500, "exp": 250}
    },
    # 特殊胡牌
    {
        "id": "hu_master",
        "name": "胡牌大师",
        "category": "special_wins",
        "target": 10,
        "reward": {"gold": 150, "exp": 75}
    },
    # 得分相关
    {
        "id": "century",
        "name": "百分成就",
        "category": "scores",
        "target": 1,
        "reward": {"gold": 100, "exp": 50}
    },
]

func _ready() -> void:
    _init_achievements()

func _init_achievements() -> void:
    """初始化成就定义"""
    for data in ACHIEVEMENTS_DATA:
        var achievement = Achievement.new(data.id, data.name, data.get("target", 1))
        achievement.category = data.category
        achievement.reward_gold = data.reward.gold
        achievement.reward_exp = data.reward.exp
        achievements[data.id] = achievement

func add_player(player_id: String) -> void:
    """为新玩家初始化成就"""
    player_achievements[player_id] = {}
    for ach_id in achievements.keys():
        player_achievements[player_id][ach_id] = achievements[ach_id].duplicate()

func add_progress(player_id: String, achievement_id: String, amount: int = 1) -> bool:
    """增加成就进度"""
    if player_id not in player_achievements:
        add_player(player_id)
    
    if achievement_id not in player_achievements[player_id]:
        return false
    
    var achievement = player_achievements[player_id][achievement_id]
    if achievement.add_progress(amount):
        # 成就解锁，发送通知
        print("🏆 成就已解锁: %s" % achievement.name)
        return true
    
    return false

func get_player_achievements(player_id: String) -> Dictionary:
    """获取玩家成就"""
    if player_id not in player_achievements:
        add_player(player_id)
    return player_achievements[player_id]

func get_achievement_progress(player_id: String, achievement_id: String) -> Dictionary:
    """获取成就进度"""
    var achievement = player_achievements[player_id][achievement_id]
    return {
        "progress": achievement.progress,
        "target": achievement.target,
        "percent": achievement.get_progress_percent(),
        "unlocked": achievement.unlocked,
        "unlock_time": achievement.unlock_time
    }
```

#### Task 2: 成就追踪系统 (3-4 天)

```gdscript
class_name AchievementTracker
extends Node

var achievement_system: AchievementSystem
var player_id: String
var current_session_stats: Dictionary = {}

func _ready() -> void:
    pass

func track_game_end(game_result: Dictionary) -> Array:
    """游戏结束时追踪成就进度"""
    var unlocked = []
    
    # 胜利相关成就
    if game_result.get("won", false):
        if achievement_system.add_progress(player_id, "first_victory"):
            unlocked.append("first_victory")
    
    # 特殊胡牌成就
    if game_result.get("hu_count", 0) > 0:
        var hu_count = game_result.get("hu_count", 0)
        if achievement_system.add_progress(player_id, "hu_master", hu_count):
            unlocked.append("hu_master")
    
    # 得分相关成就
    var score = game_result.get("score", 0)
    if score >= 100:
        if achievement_system.add_progress(player_id, "century"):
            unlocked.append("century")
    
    # 连胜相关成就
    var win_streak = game_result.get("win_streak", 0)
    if win_streak >= 5:
        if achievement_system.add_progress(player_id, "streak_5", 1):
            unlocked.append("streak_5")
    
    if win_streak >= 10:
        if achievement_system.add_progress(player_id, "streak_10", 1):
            unlocked.append("streak_10")
    
    return unlocked

func track_action(action: String, data: Dictionary) -> void:
    """追踪玩家行动"""
    match action:
        "win_game":
            current_session_stats["wins"] = current_session_stats.get("wins", 0) + 1
        "lose_game":
            current_session_stats["losses"] = current_session_stats.get("losses", 0) + 1
        "hu":
            current_session_stats["hu_count"] = current_session_stats.get("hu_count", 0) + 1
        "high_score":
            current_session_stats["high_score"] = max(current_session_stats.get("high_score", 0), data.get("score", 0))
```

#### Task 3: 成就 UI 和通知 (3-4 天)

```gdscript
class_name AchievementUI
extends CanvasLayer

@onready var achievement_grid = $ScrollContainer/GridContainer
@onready var achievement_details = $AchievementDetails

var achievement_system: AchievementSystem
var player_id: String

func _ready() -> void:
    refresh_achievements()

func refresh_achievements() -> void:
    """刷新成就显示"""
    achievement_grid.clear()
    
    var achievements = achievement_system.get_player_achievements(player_id)
    for ach_id in achievements.keys():
        var achievement = achievements[ach_id]
        var card = _create_achievement_card(achievement)
        achievement_grid.add_child(card)

func _create_achievement_card(achievement: Achievement) -> PanelContainer:
    """创建成就卡片"""
    var panel = PanelContainer.new()
    panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    panel.custom_minimum_size = Vector2(150, 200)
    
    var vbox = VBoxContainer.new()
    
    # 成就图标
    var icon = TextureRect.new()
    icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH
    icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    if achievement.unlocked:
        icon.modulate = Color.WHITE
    else:
        icon.modulate = Color.GRAY
    
    # 成就名称
    var name_label = Label.new()
    name_label.text = achievement.name
    name_label.alignment = HORIZONTAL_ALIGNMENT_CENTER
    
    # 进度条
    var progress_bar = ProgressBar.new()
    progress_bar.value = achievement.get_progress_percent()
    
    # 进度文本
    var progress_label = Label.new()
    progress_label.text = "%d/%d" % [achievement.progress, achievement.target]
    progress_label.alignment = HORIZONTAL_ALIGNMENT_CENTER
    
    vbox.add_child(icon)
    vbox.add_child(name_label)
    vbox.add_child(progress_bar)
    vbox.add_child(progress_label)
    
    panel.add_child(vbox)
    return panel


class_name AchievementNotifier
extends Node

signal achievement_unlocked(achievement: Achievement)

func notify_unlock(achievement: Achievement) -> void:
    """成就解锁时发送通知"""
    emit_signal("achievement_unlocked", achievement)
    
    # 显示弹窗
    var notification = _create_notification(achievement)
    add_child(notification)
    
    # 播放音效
    _play_unlock_sound()

func _create_notification(achievement: Achievement) -> Control:
    """创建通知 UI"""
    # 创建弹窗界面
    var panel = PanelContainer.new()
    # ... UI 设置
    return panel

func _play_unlock_sound() -> void:
    """播放成就解锁音效"""
    var audio = AudioStreamPlayer.new()
    audio.bus = "SFX"
    add_child(audio)
    audio.play()
```

---

## 实现步骤

### 第 1 周：排行榜系统

**周一-周二**: 数据结构 + 排名计算
```bash
1. 创建 LeaderboardEntry 类
2. 创建 Leaderboard 管理类
3. 实现 RankCalculator
4. 基础单元测试
```

**周三**: 排行榜 UI
```bash
1. 设计 UI 界面
2. 创建 LeaderboardUI 脚本
3. 与排行榜系统集成
4. UI 测试
```

**周四-周五**: 后端 API
```bash
1. 创建 API 端点
2. 数据库查询
3. 性能优化
4. API 测试
```

### 第 2 周：成就系统

**周一-周二**: 成就定义 + 追踪
```bash
1. 定义 20+ 个成就
2. 创建 Achievement 类
3. 实现 AchievementTracker
4. 单元测试
```

**周三-周四**: UI 和通知
```bash
1. 创建 AchievementUI
2. 成就卡片设计
3. 解锁通知系统
4. UI 测试
```

**周五**: 集成和优化
```bash
1. 与游戏流程集成
2. 性能优化
3. 全面测试
4. 文档编写
```

---

## 测试计划

### 单元测试

```gdscript
# 排行榜测试
func test_leaderboard_ranking():
    var leaderboard = Leaderboard.new()
    # 添加玩家条目
    # 验证排名计算
    # 验证排名变化

func test_rank_calculator():
    var calculator = RankCalculator.new()
    # 测试 ELO 计算
    # 验证奖励计算

# 成就测试
func test_achievement_progress():
    var achievement = Achievement.new("test", "Test Achievement", 10)
    # 增加进度
    # 验证进度百分比
    # 验证解锁逻辑

func test_achievement_tracker():
    var tracker = AchievementTracker.new()
    # 模拟游戏结束事件
    # 验证成就进度更新
    # 验证成就解锁通知
```

### 集成测试

```bash
1. 创建测试场景
2. 运行完整游戏流程
3. 验证排行榜更新
4. 验证成就追踪
5. 检查性能指标
```

### UI 测试

```bash
1. 验证排行榜显示正确
2. 验证成就卡片显示
3. 验证弹窗通知
4. 测试不同屏幕分辨率
5. 测试国际化（中文/英文）
```

---

## 部署检查

### 代码审查清单

- [ ] 所有函数有文档注释
- [ ] 所有参数有类型提示
- [ ] 没有硬编码的数值（使用常量）
- [ ] 遵循代码风格规范
- [ ] 没有调试代码（print 语句）
- [ ] 无编译错误和警告

### 性能检查清单

- [ ] 排行榜加载 < 500ms
- [ ] 排名计算 < 100ms
- [ ] UI 帧率 ≥ 60 FPS
- [ ] 内存使用 < 50MB
- [ ] 支持 1000+ 玩家

### 功能检查清单

- [ ] 排行榜正确显示排名
- [ ] 排名实时更新
- [ ] 成就正确追踪
- [ ] 成就正确解锁
- [ ] 通知正确显示
- [ ] 奖励正确计算

### 部署清单

- [ ] 编译无错误
- [ ] 测试通过
- [ ] 文档完整
- [ ] Git 提交信息清晰
- [ ] Changelog 更新
- [ ] 版本号更新

---

**预计完成**: 2025-11-12 (2 周)  
**优先级**: ⭐⭐⭐⭐⭐  
**下一阶段**: Phase 8.2 成就系统 → Phase 9 社交系统
