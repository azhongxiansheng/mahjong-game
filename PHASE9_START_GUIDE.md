# 🚀 Phase 9 好友社交系统 - 快速启动指南

**项目**: 麻将游戏多人在线版  
**阶段**: Phase 9 - Friend & Social System Implementation  
**状态**: ⏳ 即将开始  
**预计耗时**: 4-5 天  
**完成度**: 0%

---

## 📋 本阶段目标

在 Phase 8.2 成就系统完成的基础上，实现完整的好友社交系统，包括：

1. ✅ **前端好友系统** (Friend, FriendSystem, FriendManager)
2. ✅ **好友UI** (FriendUI, FriendNotifier)
3. ✅ **私聊系统** (ChatMessage, ChatSystem, ChatUI)
4. ✅ **后端API** (friend.go, chat.go handlers)
5. ✅ **数据库架构** (friend_schema.sql, chat_schema.sql)
6. ✅ **测试和文档** (单元测试、集成测试、API文档)

---

## 🎯 核心概念

### 好友系统架构
```
玩家操作 (添加好友/删除好友/查看列表)
    ↓
FriendManager 管理 (监听玩家交互)
    ↓
FriendSystem 处理 (添加、删除、查询)
    ↓
发出更新信号
    ↓
FriendUI 更新 (显示好友列表)
    ↓
后端 API 保存 (持久化)
```

### 好友类型
| 类型 | 描述 | 示例 |
|-----|------|------|
| 好友 | 已确认的好友关系 | 已添加并互相关注 |
| 待确认 | 等待对方确认 | 已发送邀请 |
| 黑名单 | 屏蔽的玩家 | 不想看到的用户 |
| 推荐 | 系统推荐 | 高等级玩家 |

### 聊天系统
```
玩家发送消息
    ↓
ChatSystem 处理
    ↓
ChatNotifier 显示
    ↓
后端保存消息
    ↓
推送给接收方
```

---

## 📁 文件列表

### 需要创建的文件

#### 前端好友系统 (GDScript)
```
godot/scripts/
├── friend.gd                      # 单个好友类 (80+ 行)
├── friend_system.gd               # 好友管理系统 (200+ 行)
├── friend_manager.gd              # 好友交互管理 (150+ 行)
├── friend_ui.gd                   # 好友UI面板 (250+ 行)
├── friend_notifier.gd             # 好友通知系统 (100+ 行)
└── test_friend.gd                 # 单元测试 (250+ 行)
```

#### 前端聊天系统 (GDScript)
```
godot/scripts/
├── chat_message.gd                # 消息类 (60+ 行)
├── chat_system.gd                 # 聊天管理系统 (200+ 行)
├── chat_ui.gd                     # 聊天UI面板 (250+ 行)
└── test_chat.gd                   # 聊天测试 (150+ 行)
```

#### 后端 (Go)
```
backend/handlers/
├── friend.go                      # 好友API处理器 (350+ 行)
└── chat.go                        # 聊天API处理器 (300+ 行)

backend/database/
├── friend_schema.sql              # 好友数据库架构 (100+ 行)
└── chat_schema.sql                # 聊天数据库架构 (80+ 行)
```

#### 场景
```
godot/scenes/
├── friend_ui.tscn                 # 好友列表场景
└── chat_ui.tscn                   # 聊天窗口场景
```

#### 文档
```
backend/
├── API_FRIEND.md                  # 好友API文档 (300+ 行)
└── API_CHAT.md                    # 聊天API文档 (250+ 行)
```

---

## 💻 代码模板

### 1. Friend.gd (单个好友数据结构)

```gdscript
class_name Friend
extends RefCounted

# 好友基础信息
var friend_id: String              # 好友ID
var friend_name: String            # 好友名称
var avatar: String                 # 头像URL
var status: String                 # 在线状态 (online/offline/playing)
var level: int                      # 等级
var rating: int                     # 评分

# 关系数据
var relationship: String           # 关系类型 (friend/pending/blocked)
var created_at: int                # 创建时间戳
var last_seen: int                 # 最后在线时间

# 统计数据
var total_games: int               # 与此好友的对局数
var wins: int                       # 赢的局数
var win_rate: float                # 胜率

# 方法
func _init(p_id: String, p_name: String) -> void:
    friend_id = p_id
    friend_name = p_name

func is_online() -> bool:
    return status == "online"

func get_display_text() -> String:
    var status_icon = "🟢" if is_online() else "⚫"
    return "[%s] %s (Lv.%d ⭐%d)" % [status_icon, friend_name, level, rating]

func to_dict() -> Dictionary:
    return {
        "friend_id": friend_id,
        "friend_name": friend_name,
        "status": status,
        "level": level,
        "rating": rating,
        "relationship": relationship,
        "last_seen": last_seen
    }
```

### 2. ChatMessage.gd (聊天消息)

```gdscript
class_name ChatMessage
extends RefCounted

# 消息数据
var message_id: String
var sender_id: String
var sender_name: String
var receiver_id: String
var content: String
var created_at: int
var is_read: bool = false

# 方法
func _init(p_sender: String, p_receiver: String, p_content: String) -> void:
    sender_id = p_sender
    receiver_id = p_receiver
    content = p_content
    message_id = "%s_%d" % [sender_id, Time.get_ticks_msec()]
    created_at = int(Time.get_ticks_msec() / 1000)

func get_display_text() -> String:
    var time_str = Time.get_datetime_dict_from_system()
    return "[%s] %s: %s" % [sender_name, time_str, content]

func to_dict() -> Dictionary:
    return {
        "message_id": message_id,
        "sender_id": sender_id,
        "content": content,
        "created_at": created_at,
        "is_read": is_read
    }
```

### 3. FriendSystem.gd (好友管理)

```gdscript
class_name FriendSystem
extends Node

var friends: Dictionary = {}        # 已确认好友
var pending_requests: Array = []    # 待确认请求
var blocked_players: Array = []     # 黑名单

signal friend_added(friend: Friend)
signal friend_removed(friend_id: String)
signal friend_status_changed(friend_id: String, new_status: String)
signal friend_request_received(from_player_id: String, from_player_name: String)

func add_friend(friend: Friend) -> bool:
    """添加好友"""
    if friends.has(friend.friend_id):
        return false
    
    friends[friend.friend_id] = friend
    friend_added.emit(friend)
    return true

func remove_friend(friend_id: String) -> bool:
    """删除好友"""
    if not friends.has(friend_id):
        return false
    
    friends.erase(friend_id)
    friend_removed.emit(friend_id)
    return true

func get_all_friends() -> Array:
    """获取所有好友"""
    return friends.values()

func get_online_friends() -> Array:
    """获取在线好友"""
    var online = []
    for friend in friends.values():
        if friend.is_online():
            online.append(friend)
    return online

func update_friend_status(friend_id: String, new_status: String) -> void:
    """更新好友状态"""
    if friends.has(friend_id):
        friends[friend_id].status = new_status
        friend_status_changed.emit(friend_id, new_status)
```

---

## 🗄️ 数据库架构

### 好友表结构
```sql
-- 好友关系表
CREATE TABLE IF NOT EXISTS friends (
  id INT AUTO_INCREMENT PRIMARY KEY,
  player_id VARCHAR(50) NOT NULL,
  friend_id VARCHAR(50) NOT NULL,
  relationship VARCHAR(20) NOT NULL, -- friend/pending/blocked
  created_at BIGINT NOT NULL,
  updated_at BIGINT NOT NULL,
  
  UNIQUE KEY unique_friendship (player_id, friend_id),
  INDEX idx_player_id (player_id),
  INDEX idx_relationship (relationship)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 聊天消息表
CREATE TABLE IF NOT EXISTS chat_messages (
  id INT AUTO_INCREMENT PRIMARY KEY,
  sender_id VARCHAR(50) NOT NULL,
  receiver_id VARCHAR(50) NOT NULL,
  content TEXT NOT NULL,
  is_read BOOL DEFAULT FALSE,
  created_at BIGINT NOT NULL,
  
  INDEX idx_receiver_id (receiver_id),
  INDEX idx_created_at (created_at),
  INDEX idx_conversation (sender_id, receiver_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

---

## 🔌 API 设计

### 好友API端点
```
POST   /api/friend/add              # 添加好友
POST   /api/friend/remove           # 删除好友
GET    /api/friend/list             # 获取好友列表
GET    /api/friend/online           # 获取在线好友
POST   /api/friend/block            # 屏蔽玩家
POST   /api/friend/unblock          # 解除屏蔽
```

### 聊天API端点
```
POST   /api/chat/send               # 发送消息
GET    /api/chat/history/:user_id   # 获取聊天历史
POST   /api/chat/read               # 标记为已读
GET    /api/chat/unread             # 获取未读消息
```

---

## 🔧 实现步骤

### 第1天 (Day 1)
- [ ] 创建 `Friend.gd` (好友类)
- [ ] 创建 `FriendSystem.gd` (好友管理)
- [ ] 创建 `FriendManager.gd` (好友交互)
- [ ] 编写单元测试
- [ ] **目标**: 前端好友系统完成

### 第2天 (Day 2)
- [ ] 创建 `FriendUI.gd` (好友UI)
- [ ] 创建 `FriendNotifier.gd` (好友通知)
- [ ] 创建 `friend_ui.tscn` (场景)
- [ ] 编写集成测试
- [ ] **目标**: 前端UI完成

### 第3天 (Day 3)
- [ ] 创建 `ChatMessage.gd` (消息类)
- [ ] 创建 `ChatSystem.gd` (聊天管理)
- [ ] 创建 `ChatUI.gd` (聊天UI)
- [ ] 创建 `chat_ui.tscn` (场景)
- [ ] **目标**: 前端聊天完成

### 第4天 (Day 4)
- [ ] 创建 `friend.go` (后端API)
- [ ] 创建 `chat.go` (后端API)
- [ ] 创建数据库schema
- [ ] 编写API文档
- [ ] **目标**: 后端完成

### 第5天 (Day 5)
- [ ] 完整集成测试
- [ ] 性能优化
- [ ] 最终文档
- [ ] **目标**: 全部完成

---

## 📊 预期代码统计

| 组件 | 代码行数 | 说明 |
|-----|---------|------|
| 前端好友系统 | 680 | 5个GDScript类 |
| 前端聊天系统 | 510 | 3个GDScript类 |
| 测试代码 | 600 | 单元+集成测试 |
| 后端API | 650 | 2个Go handlers |
| 数据库 | 180 | 2个schema |
| 文档 | 550 | API文档 |
| **总计** | **3,170+** | 完整社交系统 |

---

## 💡 设计原则

### 1. 好友系统
- 支持添加/删除/屏蔽
- 显示在线状态
- 记录对局历史
- 统计对战成绩

### 2. 聊天系统
- 一对一私聊
- 消息持久化
- 已读/未读标记
- 离线消息保存

### 3. 性能考虑
- 使用字典快速查询
- 缓存在线状态
- 异步加载消息
- 数据库索引优化

---

## 🚀 快速开始

### 立即开始
1. 复制上面的代码模板
2. 创建所需的 GDScript 文件
3. 按照实现步骤逐步完成
4. 编写测试验证功能
5. 与游戏集成

### 验证步骤
```gdscript
# 在游戏中测试
var friend_system = FriendSystem.new()
add_child(friend_system)

var friend = Friend.new("player_123", "张三")
friend_system.add_friend(friend)

var friends = friend_system.get_all_friends()
print("朋友数: %d" % friends.size())
```

---

## 📞 常见问题

**Q: 如何处理离线消息?**
- A: 在数据库中保存所有消息，玩家上线时检索未读消息

**Q: 如何更新好友在线状态?**
- A: 通过 WebSocket 实时更新，或定期轮询 API

**Q: 如何限制聊天内容?**
- A: 实施内容过滤、敏感词检测、报告系统

---

**预计开始日期**: 2025-11-06  
**预计完成日期**: 2025-11-10  
**目标完成度**: 100%

祝开发顺利！🎊
