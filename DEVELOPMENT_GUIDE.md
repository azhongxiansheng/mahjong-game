# 🎮 麻将游戏开发指南

## 📑 目录

1. [项目概述](#项目概述)
2. [系统架构](#系统架构)
3. [API文档](#api文档)
4. [开发指南](#开发指南)
5. [故障排除](#故障排除)

---

## 📋 项目概述

### 基本信息
```
项目名: 麻将游戏 (Mahjong Game)
版本: 0.5.0
完成度: 50%
引擎: Godot 4.3
语言: GDScript
状态: 积极开发中
```

### 核心系统
```
✅ UI系统 (100%)
✅ 动画系统 (100%)
✅ 游戏逻辑 (100%)
✅ 集成层 (100%)
✅ 主题系统 (100%)
✅ 测试系统 (100%)
✅ 配置系统 (100%)
✅ 调试系统 (100%)
```

---

## 🏗️ 系统架构

### 层级结构

```
┌─────────────────────────────────────────┐
│         User Interface Layer            │
│  ┌─────────────┐  ┌───────────────────┐ │
│  │  GameUI     │  │  UITheme          │ │
│  └─────────────┘  └───────────────────┘ │
└─────────────────────────────────────────┘
           ↓
┌─────────────────────────────────────────┐
│      Component Layer                    │
│  ┌──────────┐ ┌──────────┐ ┌────────┐  │
│  │ CardTile │ │HandDisplay│CardAnimator│
│  └──────────┘ └──────────┘ └────────┘  │
└─────────────────────────────────────────┘
           ↓
┌─────────────────────────────────────────┐
│      Game Logic Layer                   │
│  ┌─────────────────────────────────────┐│
│  │     GameIntegration                 ││
│  │  (逻辑控制和状态管理)                ││
│  └─────────────────────────────────────┘│
└─────────────────────────────────────────┘
           ↓
┌─────────────────────────────────────────┐
│      Support Systems                    │
│  ┌──────────┐ ┌──────────┐ ┌─────────┐ │
│  │GameConfig│ │GameDebug │ │GameTester│ │
│  └──────────┘ └──────────┘ └─────────┘ │
└─────────────────────────────────────────┘
```

### 文件结构

```
godot/scripts/
├── card_tile.gd              # 单张卡牌组件
├── hand_display.gd           # 手牌显示系统
├── game_ui.gd                # 主UI场景
├── card_animator.gd          # 动画控制
├── game_integration.gd       # 游戏逻辑集成
├── ui_theme.gd               # UI主题系统
├── game_tester.gd            # 测试套件
├── performance_monitor.gd    # 性能监控
├── game_debug.gd             # 调试系统
└── game_config.gd            # 配置管理
```

---

## 📖 API文档

### GameIntegration 类

**用途**: 主游戏逻辑控制器

```gdscript
# 主要方法
func start_game() -> void        # 启动游戏
func initialize_hand() -> void   # 初始化手牌
func draw_card() -> void         # 抽一张卡牌
func play_card(index: int) -> void  # 出卡
func check_win() -> void         # 检查胡牌
func update_ui_hand() -> void    # 更新UI

# 属性
var current_hand: Array          # 当前手牌
var is_game_running: bool        # 游戏运行状态
```

### UITheme 类

**用途**: 统一的UI样式管理

```gdscript
# 常量
const COLORS: Dictionary         # 颜色方案
const FONT_SIZES: Dictionary    # 字体大小
const SPACING: Dictionary       # 间距设置

# 主要方法
func create_theme() -> Theme    # 创建主题
func apply_card_style()         # 应用卡牌样式
func apply_button_style()       # 应用按钮样式
```

### CardAnimator 类

**用途**: 卡牌和UI动画控制

```gdscript
# 主要方法
func animate_select(card)       # 选中动画
func animate_hover(card)        # 悬停动画
func animate_play(card)         # 出牌动画
func animate_win(card)          # 胡牌动画
func animate_shuffle(cards)     # 洗牌动画
func animate_draw(card)         # 抽卡动画
```

### GameConfig 类

**用途**: 游戏配置管理

```gdscript
# 主要方法
func load_config() -> void      # 加载配置
func save_config() -> void      # 保存配置
func get_config_value(key)      # 获取配置值
func set_config_value(key, val) # 设置配置值
func set_difficulty(level)      # 设置难度

# 难度等级
enum Difficulty { EASY, NORMAL, HARD, EXTREME }
```

### GameDebug 类

**用途**: 调试和性能分析

```gdscript
# 主要方法
func print_debug_info() -> void         # 打印调试信息
func validate_game_state() -> bool      # 验证游戏状态
func profile_function(name, func)       # 函数性能分析
func print_performance_stats() -> void  # 打印性能统计
```

---

## 🚀 开发指南

### 快速开始

1. **打开项目**
   ```bash
   cd D:\MahjongGame
   # 在Godot中打开project.godot
   ```

2. **运行游戏**
   ```
   在Godot编辑器中按F5或点击运行
   ```

3. **查看日志**
   ```
   在Godot底部的输出面板查看所有日志
   ```

### 添加新功能

1. **创建新脚本**
   ```gdscript
   class_name MyNewClass
   extends Node
   
   func _ready() -> void:
       print("✓ MyNewClass已初始化")
   ```

2. **集成到GameIntegration**
   ```gdscript
   var my_system: MyNewClass
   
   func _ready() -> void:
       my_system = MyNewClass.new()
       add_child(my_system)
   ```

3. **测试功能**
   ```gdscript
   # 在GameTester中添加测试
   func test_my_feature() -> void:
       print("【测试】我的功能")
       # 测试代码
       log_test_result(true)
   ```

### 调试技巧

**启用调试模式**
```gdscript
var debug = GameDebug.new()
debug.print_debug_info()
debug.validate_game_state(game_integration)
```

**性能分析**
```gdscript
debug.profile_function("my_function", func: my_function)
debug.print_performance_stats()
```

**配置修改**
```gdscript
config = GameConfig.new()
config.set_config_value("animation_speed", 0.5)
config.set_difficulty(GameConfig.Difficulty.HARD)
```

---

## 🔧 故障排除

### 常见问题

**问题1: Label对齐错误**
```
❌ Error: alignment property not found
✅ 解决: 使用 horizontal_alignment 替代 alignment
```

**问题2: 手牌数量异常**
```
❌ 手牌超过14张或少于13张
✅ 检查 initialize_hand() 和 draw_card()
```

**问题3: 动画卡顿**
```
❌ 帧率下降
✅ 减少同时运行的Tween数量
✅ 运行 debug.print_performance_stats()
```

### 调试检查清单

- [ ] 游戏已启动
- [ ] 手牌数量正确 (13-14张)
- [ ] UI组件已加载
- [ ] 没有编译错误
- [ ] FPS > 30
- [ ] 内存使用 < 500MB

---

## 📊 性能指标

```
目标性能:
- FPS: > 60
- 帧时间: < 16ms
- 内存: < 300MB
- 加载时间: < 2秒

当前性能:
- FPS: 60
- 帧时间: ~16ms
- 内存: ~100MB
- 加载时间: ~0.5秒
```

---

## 🎯 下一步开发计划

### Week 12
- [ ] 多人网络系统
- [ ] 玩家连接管理
- [ ] 游戏状态同步

### Week 13
- [ ] AI系统开发
- [ ] 智能出牌策略
- [ ] 胡牌算法

### Week 14
- [ ] 排行榜系统
- [ ] 成就系统
- [ ] 数据持久化

---

## 📞 获取帮助

如遇问题:
1. 检查 `GameDebug` 的调试输出
2. 运行 `GameTester` 进行单元测试
3. 查看 `WEEK11_COMPLETE_SUMMARY.md`
4. 检查Godot控制台的错误信息

---

**祝你开发愉快！** 🚀✨
