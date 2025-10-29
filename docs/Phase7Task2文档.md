# Phase 7 Task 7.2: 玩家配对和房间系统 📋

## 🎯 任务目标

实现完整的房间管理系统和玩家配对系统，包括：
- **房间管理** - 创建、加入、离开房间，管理房间状态和玩家
- **玩家配对** - 队列管理、技能匹配、排位配对
- **大厅管理** - 协调房间和配对系统
- **UI展示** - 显示房间列表、配对状态、玩家信息

---

## 📦 实现的模块

### 1. **RoomManager** (房间管理器)

```gdscript
class_name RoomManager
```

**功能：**
- 房间创建和销毁
- 玩家加入和离开
- 房间状态管理
- 得分追踪

**核心方法：**
| 方法 | 说明 |
|------|------|
| `create_room()` | 创建新房间 |
| `join_room()` | 玩家加入房间 |
| `leave_room()` | 玩家离开房间 |
| `set_room_state()` | 设置房间状态 |
| `get_room()` | 获取房间信息 |
| `get_joinable_rooms()` | 获取可加入的房间 |

**房间状态：**
- `WAITING` - 等待中（可加入）
- `READY` - 准备就绪
- `PLAYING` - 游戏进行中
- `FINISHED` - 游戏已结束

---

### 2. **PlayerMatcher** (玩家配对系统)

```gdscript
class_name PlayerMatcher
```

**功能：**
- 玩家队列管理
- 休闲和排位模式配对
- 技能等级匹配
- 配对历史记录

**核心方法：**
| 方法 | 说明 |
|------|------|
| `join_queue()` | 加入匹配队列 |
| `leave_queue()` | 离开匹配队列 |
| `try_match()` | 尝试进行配对 |
| `update_player_skill()` | 更新玩家技能 |
| `get_queue_position()` | 获取队列位置 |

**配对模式：**
- `CASUAL` - 休闲模式（快速配对）
- `RANKED` - 排位模式（技能匹配）
- `FRIEND` - 好友模式

**玩家等级：**
- 青铜 → 白银 → 黄金 → 铂金 → 钻石 → 大师

**配对算法：**
1. **排位配对** - 按等级和技能等级排序，容限 ±0.5
2. **休闲配对** - FIFO（先进先出）快速配对

---

### 3. **LobbyManager** (大厅管理器)

```gdscript
class_name LobbyManager
extends Node
```

**功能：**
- 协调房间和配对系统
- 玩家信息管理
- 统计信息收集

**核心方法：**
| 方法 | 说明 |
|------|------|
| `create_room()` | 创建房间 |
| `join_room()` | 加入房间 |
| `start_matchmaking()` | 开始配对 |
| `cancel_matchmaking()` | 取消配对 |
| `update_player_stats()` | 更新玩家统计 |

**信号：**
```gdscript
signal lobby_initialized()
signal player_info_updated(player_id: String)
signal room_list_updated(rooms: Array)
signal match_status_changed(status: String)
```

---

### 4. **LobbyUI** (大厅界面)

```gdscript
class_name LobbyUI
extends Control
```

**功能：**
- 显示房间列表
- 显示玩家统计
- 配对状态显示
- 房间和配对操作

**主要操作：**
- `create_room()` - 创建房间
- `join_room()` - 加入房间
- `start_matchmaking()` - 开始配对
- `cancel_matchmaking()` - 取消配对

---

## 🔄 工作流程

### 房间模式工作流

```
1. 玩家创建房间
   └─ LobbyUI.create_room()
      └─ LobbyManager.create_room()
         └─ RoomManager.create_room()

2. 其他玩家加入
   └─ LobbyUI.join_room()
      └─ LobbyManager.join_room()
         └─ RoomManager.join_room()

3. 房主启动游戏
   └─ LobbyUI.start_game()
      └─ LobbyManager.start_room_game()
         └─ RoomManager.set_room_state(PLAYING)
```

### 配对模式工作流

```
1. 玩家加入配对队列
   └─ LobbyUI.start_matchmaking()
      └─ LobbyManager.start_matchmaking()
         └─ PlayerMatcher.join_queue()

2. 系统定期尝试配对
   └─ LobbyManager._process()
      └─ PlayerMatcher.try_match()
         ├─ _match_ranked() 或
         └─ _match_casual()

3. 配对成功后自动创建房间和启动游戏
   └─ LobbyManager._on_match_found()
      ├─ create_room()
      ├─ join_room() (所有玩家)
      └─ start_room_game()
```

---

## 📊 数据结构

### 房间信息

```gdscript
{
  "room_id": "room_1000",
  "room_name": "我的房间",
  "host_id": "player_001",
  "state": 0,                    # WAITING
  "player_count": 2,
  "max_players": 4,
  "players": {
    "player_001": {...},
    "player_002": {...}
  }
}
```

### 玩家信息

```gdscript
{
  "player_id": "player_001",
  "player_name": "优雅的老鹰",
  "rank": 2,                     # GOLD
  "skill_level": 0.65,
  "total_games": 150,
  "wins": 97
}
```

### 队列项

```gdscript
{
  "player_id": "player_001",
  "player_name": "优雅的老鹰",
  "rank": 2,
  "skill_level": 0.65,
  "wait_time": 5234              # 毫秒
}
```

---

## 🧪 使用示例

### 创建房间

```gdscript
var lobby_ui = LobbyUI.new()
lobby_ui.set_player_id("player_001")
lobby_ui.create_room("新手房间", 4)
```

### 加入房间

```gdscript
var rooms = lobby_ui.lobby_manager.get_joinable_rooms()
if rooms.size() > 0:
    lobby_ui.join_room(rooms[0]["room_id"])
```

### 开始配对

```gdscript
lobby_ui.start_matchmaking(PlayerMatcher.MatchMode.CASUAL)
```

### 检查配对进度

```gdscript
var position = lobby_ui.lobby_manager.get_queue_position("player_001")
var wait_time = lobby_ui.lobby_manager.get_queue_wait_time("player_001")
print("队列位置: %d, 等待时间: %dms" % [position, wait_time])
```

---

## 📈 统计和监控

### 获取大厅统计

```gdscript
var stats = lobby_manager.get_lobby_statistics()
print("房间总数: %d" % stats["rooms"]["total_rooms"])
print("等待房间: %d" % stats["rooms"]["waiting_rooms"])
print("在线玩家: %d" % stats["rooms"]["total_players"])
print("配对队列: %d" % stats["queue"]["total_queue"])
```

### 打印状态

```gdscript
lobby_manager.print_lobby_status()
room_manager.print_status()
player_matcher.print_statistics()
```

---

## 🔧 配置参数

### PlayerMatcher

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `MAX_QUEUE_SIZE` | 1000 | 最大队列人数 |
| `MATCH_TIMEOUT` | 30000 | 配对超时（毫秒） |
| `SKILL_TOLERANCE` | 0.5 | 技能差异容限 |

### RoomManager

| 参数 | 说明 |
|------|------|
| `MAX_ROOM` | 无限制 | 
| 房间ID格式 | `room_XXXX` |

---

## 🎮 测试方法

### 运行完整测试

```gdscript
var lobby_ui = LobbyUI.new()
add_child(lobby_ui)
await lobby_ui.test_lobby_flow()
```

### 手动测试场景

```gdscript
# 场景1: 房间创建和加入
1. Player_001 创建房间 "MyRoom"
2. Player_002 查看房间列表
3. Player_002 加入 Player_001 的房间
4. Player_001 启动游戏

# 场景2: 配对
1. Player_001 开始配对 (CASUAL)
2. Player_002 开始配对 (CASUAL)
3. Player_003 开始配对 (CASUAL)
4. Player_004 开始配对 (CASUAL)
5. 系统配对成功，自动创建房间和启动游戏

# 场景3: 排位配对
1. Player_001 (Gold, 65%) 开始排位配对
2. Player_002 (Gold, 68%) 开始排位配对
3. 系统配对成功（技能差异 ±3%）
```

---

## ✅ 实现清单

- [x] RoomManager - 房间创建、管理、状态转换
- [x] PlayerMatcher - 队列管理、算法匹配
- [x] LobbyManager - 协调和信号处理
- [x] LobbyUI - 界面显示和交互
- [x] 信号系统 - 实时通知各模块
- [x] 测试套件 - 完整的测试流程
- [x] 文档 - API参考和使用示例

---

## 🚀 下一步（Task 7.3）

实现**实时游戏同步**：
- 游戏状态同步
- 出牌同步
- 玩家操作广播
- 实时计分更新

---

## 📝 文件列表

| 文件 | 大小 | 说明 |
|------|------|------|
| `room_manager.gd` | 250 行 | 房间管理核心 |
| `player_matcher.gd` | 300 行 | 配对系统核心 |
| `lobby_manager.gd` | 200 行 | 大厅协调器 |
| `lobby_ui.gd` | 250 行 | 大厅UI |

**总代码量：** ~1000 行

---

## 📞 技术支持

如需帮助，请查看：
- API文档：各模块的注释
- 测试用例：`test_lobby_flow()` 函数
- 日志输出：`[RoomManager]`, `[PlayerMatcher]` 等前缀
