# 🎮 游戏前端 - 游戏流程快速指南

**创建日期**: 2025-10-30  
**版本**: 0.1.0 (Alpha)  
**状态**: 🟡 核心流程实现中

---

## 📌 项目现状

### ✅ 刚完成的核心组件

#### 1. GameState - 游戏状态管理器
📄 文件: `godot/scripts/game_state.gd`

**功能**:
- 游戏状态枚举 (IDLE, PLAYER_TURN, AI_TURN, SHOW_WIN, GAME_OVER)
- 玩家和AI的手牌管理
- 游戏分数跟踪
- 状态转换和信号系统

**关键方法**:
```gdscript
# 状态转换
game_state.transition_to(GameState.State.PLAYER_TURN)

# 检查回合
game_state.is_player_turn()
game_state.is_ai_turn()

# 开始/结束回合
game_state.start_new_round()
game_state.end_round(winner)
```

#### 2. GameController - 游戏流程控制器
📄 文件: `godot/scripts/game_controller.gd`

**功能**:
- 完整的游戏流程管理
- 牌库创建和洗牌
- 玩家和AI的行动处理
- 胡牌检测和回合判定

**关键方法**:
```gdscript
# 初始化游戏
controller.initialize_game()

# 玩家操作
controller.player_draw_card()
controller.player_play_card(card)

# AI操作（自动）
# AI在回合时自动决策

# 查询状态
controller.get_debug_info()
```

#### 3. Main - 主游戏场景脚本
📄 文件: `godot/scripts/main.gd`

**功能**:
- 游戏初始化
- 事件监听和处理
- 调试输入处理
- 玩家交互

**调试快捷键**:
- `D` - 摸牌
- `1-9` - 出牌 (按手牌位置选择)
- `I` - 查看手牌信息
- `S` - 查看游戏状态
- `ESC` - 返回登录

---

## 🎯 完整游戏流程

### 流程图

```
┌─────────────────────┐
│   游戏初始化        │
│  创建控制器和牌库   │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│   第 N 轮开始       │
│  发牌（各13张）     │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────────────────┐
│   玩家回合                      │
│  1. 摸牌（→14张）              │
│  2. 选择出牌（→13张）          │
│  3. AI响应（检查胡牌）         │
└──────────┬──────────────────────┘
           │
      是否胡牌？
      /           \
    是            否
   /               \
▼                   ▼
胡牌显示    ┌─────────────────────┐
并计分      │   AI回合            │
▼           │  1. 摸牌（→14张）   │
判断       │  2. 决策出牌        │
下一轮      │  3. 玩家响应        │
或结束      └──────────┬──────────┘
游戏              │
           是否胡牌？
           /           \
         是            否
        /               \
       ▼                 ▼
    计分    回到玩家回合
    并判断  (循环)
    是否
    继续
```

### 详细流程说明

**第1步: 游戏初始化**
```gdscript
# 在main.gd中
game_controller = GameController.new()
game_controller._ready()
game_controller.initialize_game()
```

**第2步: 创建牌库**
```gdscript
# 在game_controller.gd中
_create_deck()      # 创建108张牌（4套完整的牌）
_shuffle_deck()     # 洗牌
_deal_cards()       # 发牌（玩家13张，AI13张）
```

**第3步: 玩家回合**
```gdscript
# 玩家摸牌
player_draw_card()  # 手牌变为14张

# 玩家出牌
player_play_card(card)  # 选择一张牌出掉

# 系统检查
_check_ai_win()     # 检查AI是否能胡
```

**第4步: AI回合**
```gdscript
# 自动执行 (延迟1秒)
_ai_turn()          # 执行AI回合
  ├─ ai_play_card() # AI出牌
  └─ _check_player_win()  # 检查玩家是否能胡
```

**第5步: 胡牌检测**
```gdscript
# 胡牌检测使用核心算法
var win_result = win_checker.check_win(hand)
if win_result and win_result.is_win:
    # 触发胡牌事件
    win_detected.emit(winner, win_info)
```

---

## 🚀 快速测试

### 方法1: 在Godot编辑器中运行

1. **打开项目**
   - 打开 `D:\MahjongGame\godot\`
   - Godot编辑器会自动加载项目

2. **设置主场景**
   - 在Godot中，点击 `File → Open Scene`
   - 选择 `res://main.tscn`
   - 点击右上角的播放按钮运行

3. **游戏将自动启动**
   - 看到初始化日志
   - 等待玩家操作提示

### 方法2: 命令行运行

```bash
cd D:\MahjongGame\godot
godot --run
```

### 测试场景

**场景1: 玩家先胡牌**
1. 按 `I` 查看手牌
2. 按 `D` 摸牌（变为14张）
3. 按 `S` 查看状态
4. 如果能胡牌，系统会自动检测

**场景2: AI后胡牌**
1. 按 `D` 摸牌
2. 按 `1` 或其他按键出牌
3. 等待AI回合
4. AI自动出牌和判定

**场景3: 查看听牌提示**
1. 按 `I` 查看手牌
2. 如果有13张牌，会显示听牌列表
3. 这使用了核心的 `WinChecker.check_can_hear()` 算法

---

## 📊 数据流向

```
InputEvent (键盘输入)
    │
    ▼
main.gd (_input事件处理)
    │
    ├─ KEY_D → player_draw_card()
    ├─ KEY_1-9 → player_play_card(card)
    ├─ KEY_I → _print_player_hand()
    ├─ KEY_S → game_state.debug_state()
    └─ KEY_ESC → 返回登录
    
    ▼
game_controller.gd (游戏逻辑)
    │
    ├─ player_draw_card() → 从牌库抽牌
    ├─ player_play_card() → 移除手牌，进行检查
    │   │
    │   ├─ _check_ai_win()
    │   │   │
    │   │   └─ WinChecker.check_win() ← 核心算法
    │   │
    │   └─ 转换到AI回合
    │
    ├─ _ai_turn()
    │   │
    │   ├─ AI决策（从ai_player.gd）
    │   └─ ai_play_card()
    │       │
    │       ├─ _check_player_win()
    │       │   │
    │       │   └─ WinChecker.check_win()
    │       │
    │       └─ 转换到玩家回合
    │
    └─ 胡牌 → 计分 → 下一轮或游戏结束
    
    ▼
GameState (状态管理)
    │
    └─ 发出信号 → main.gd监听并显示
```

---

## 🔍 调试信息

### 查看日志

在Godot编试图集中，可以看到完整的游戏流程日志：

```
🎮 主游戏场景已加载
🎲 游戏初始化中...
🎮 GameController 初始化中...
✅ GameController 初始化完成
🎮 GameState 初始化中...
✅ GameState 初始化完成
🎮 游戏初始化
✅ 牌库创建完成: 108张牌
🔀 牌库已洗牌
✅ 发牌完成
   玩家: 13张
   AI: 13张

🎮 第 1 轮开始

✅ 游戏已初始化，等待玩家操作...

🔵 轮到玩家了！
   操作: 摸牌或出牌
📋 可用操作:
   [D] - 摸牌
   [1-9] - 选择出牌
   [I] - 查看手牌
   [S] - 查看状态
   [ESC] - 退出游戏
```

### 获取调试信息

**按 `S` 查看游戏状态**
```
==================================================
🎮 游戏状态调试信息
当前状态: PLAYER_TURN
当前回合: 1/4
玩家分数: 0 | AI分数: 0
玩家手牌数: 14 | AI手牌数: 13
==================================================
```

**按 `I` 查看手牌**
```
📋 你的手牌 (14张):
──────────────────────────────────────────────────
[0] 万1
[1] 万2
[2] 万3
[3] 筒1
... (更多牌)
──────────────────────────────────────────────────

💡 听牌提示:
   - 万4
   - 筒2
```

---

## 🐛 常见问题

### Q: 游戏无法启动
**A**: 检查 `main.tscn` 是否设置为启动场景

### Q: 玩家不能摸牌或出牌
**A**: 确保当前是玩家回合（日志应显示 `🔵 轮到玩家了！`）

### Q: 没有看到听牌提示
**A**: 只有当手牌恰好13张时才显示听牌提示

### Q: AI不出牌
**A**: AI出牌有1秒延迟，等待一下即可

### Q: 游戏提示"牌库已用完"
**A**: 这是正常的，说明一轮游戏进行了很久。可以出牌加快进度

---

## 📋 下一步工作

### 即将完成
- [ ] 完整的UI界面
- [ ] 手牌拖拽操作
- [ ] 胡牌显示界面
- [ ] 动画和特效

### 短期计划
- [ ] 保存游戏进度
- [ ] 网络同步
- [ ] 多人对战

---

## 🎓 学习资源

### 核心脚本文件位置
```
godot/scripts/
├── game_state.gd        # 游戏状态管理
├── game_controller.gd   # 游戏流程控制
├── main.gd              # 主场景脚本
├── ai_player.gd         # AI决策
├── win_checker.gd       # 胡牌检测 (核心算法)
├── card_data.gd         # 卡牌数据类
└── card_hand.gd         # 手牌管理类
```

### 关键方法文档
- `GameState.transition_to()` - 状态转换
- `GameController.initialize_game()` - 游戏初始化
- `GameController.player_draw_card()` - 玩家摸牌
- `GameController.player_play_card()` - 玩家出牌
- `WinChecker.check_win()` - 胡牌检测

---

## 📞 获取帮助

遇到问题？查看：
1. 控制台日志输出
2. `FRONTEND_DEVELOPMENT_PLAN.md` 中的详细计划
3. 各脚本文件中的注释

---

**现在试试按 `D` 摸牌吧！** 🎮
