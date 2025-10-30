# 🎨 麻将游戏UI系统 - 开发指南

**创建日期**: 2025-10-30  
**版本**: 0.1.0  
**状态**: 🟡 UI系统框架实现中

---

## 📋 系统概览

### 新增的UI组件

```
CardUI (卡牌单个显示)
  ├─ 正面显示 (花色、数字、符号)
  ├─ 背面显示 (棋盘图案)
  ├─ 选中状态 (黄色边框)
  ├─ 高亮状态 (白色边框)
  └─ 鼠标交互 (点击、悬停)

HandDisplayManager (手牌管理器)
  ├─ 按花色分组显示
  ├─ 自动排序和排列
  ├─ 单选/取消选择
  ├─ 高亮效果
  └─ 信号系统

CardAnimation (卡牌动画)
  ├─ 摸牌动画 (0.3秒)
  ├─ 出牌动画 (0.4秒)
  ├─ 胡牌动画 (0.5秒)
  ├─ 听牌闪烁
  ├─ 碰/杠动画
  └─ 错误抖动效果
```

---

## 🎮 CardUI - 卡牌显示

### 基础用法

```gdscript
# 创建卡牌UI
var card_ui = CardUI.new()
card_ui.set_card(card_data)
add_child(card_ui)

# 显示卡牌正面
card_ui.set_show_face(true)

# 选中卡牌
card_ui.set_selected(true)

# 高亮卡牌
card_ui.set_highlighted(true)
```

### 卡牌颜色和样式

```gdscript
# 万牌 - 蓝色
# 筒牌 - 橙色
# 条牌 - 绿色
# 字牌 - 红色

# 卡牌尺寸
card_ui.card_width = 60.0
card_ui.card_height = 90.0
```

### 信号

```gdscript
# 卡牌被点击
card_ui.card_clicked.connect(_on_card_clicked)

# 鼠标进入卡牌
card_ui.card_hovered.connect(_on_card_hovered)

# 鼠标离开卡牌
card_ui.card_unhovered.connect(_on_card_unhovered)
```

---

## 🖱️ HandDisplayManager - 手牌显示

### 基础用法

```gdscript
# 创建手牌管理器
var hand_display = HandDisplayManager.new()
add_child(hand_display)

# 设置玩家手牌
hand_display.set_hand(game_state.player_hand)

# 获取选中的卡牌
var selected_card = hand_display.get_selected_card()

# 清空选择
hand_display.clear_selection()

# 刷新显示
hand_display.refresh_display()
```

### 功能特性

1. **自动分组**
   ```gdscript
   # 按花色自动分组: 万、筒、条、字
   # 每组内按数字排序
   # 自动创建花色标签
   ```

2. **卡牌选择**
   ```gdscript
   # 单选模式 - 同时只能选一张
   # 点击卡牌切换选择状态
   # 发出信号通知主程序
   ```

3. **交互反馈**
   ```gdscript
   # 悬停高亮
   # 选中边框
   # 鼠标反馈
   ```

### 信号

```gdscript
# 卡牌被选中
hand_display.card_selected.connect(_on_card_selected)

# 卡牌被取消选择
hand_display.card_deselected.connect(_on_card_deselected)
```

---

## ✨ CardAnimation - 卡牌动画

### 摸牌动画

```gdscript
# 从牌库位置摸到手牌位置
var animation = CardAnimation.new()
add_child(animation)

await animation.animate_draw_card(card_ui, from_pos, to_pos)
```

### 出牌动画

```gdscript
# 从手牌位置出到弃牌堆
await animation.animate_play_card(card_ui, from_pos, to_pos)
```

### 胡牌动画

```gdscript
# 所有手牌放大和闪烁
var winning_cards = []  # 手牌UI列表
await animation.animate_win(winning_cards)
```

### 碰牌动画

```gdscript
# 三张牌从中间分散
var peng_cards = []  # 三张卡牌UI
await animation.animate_peng(peng_cards, position)
```

### 杠牌动画

```gdscript
# 四张牌围绕中心旋转
var kong_cards = []  # 四张卡牌UI
await animation.animate_kong(kong_cards, center_position)
```

### 听牌提示动画

```gdscript
# 卡牌闪烁提示
await animation.animate_ting_hint(card_ui)
```

### 错误提示动画

```gdscript
# 控件抖动
await animation.animate_error_shake(control)
```

---

## 🔌 集成到GameController

### 改进的GameController

```gdscript
class_name GameController
extends Node

var hand_display: HandDisplayManager
var animation: CardAnimation

func _ready() -> void:
	# ... 现有代码 ...
	
	# 初始化UI系统
	hand_display = HandDisplayManager.new()
	add_child(hand_display)
	
	animation = CardAnimation.new()
	add_child(animation)
	
	# 连接信号
	hand_display.card_selected.connect(_on_card_selected)

func player_draw_card() -> void:
	# ... 现有逻辑 ...
	
	# 添加动画
	var card_ui = hand_display.card_ui_nodes[-1]
	await animation.animate_draw_card(card_ui, deck_pos, hand_pos)

func _on_card_selected(card: CardData) -> void:
	# 玩家选择了要出的牌
	player_play_card(card)
```

---

## 🎨 自定义样式

### 修改卡牌颜色

```gdscript
# 在CardUI中修改
var color_wan: Color = Color(0.2, 0.4, 0.8)      # 万牌
var color_tong: Color = Color(0.8, 0.5, 0.2)    # 筒牌
var color_tiao: Color = Color(0.2, 0.7, 0.3)    # 条牌
var color_letter: Color = Color(0.7, 0.2, 0.3)  # 字牌
```

### 修改卡牌尺寸

```gdscript
# 在CardUI中修改
card_ui.card_width = 70.0   # 更宽
card_ui.card_height = 100.0 # 更高

# 在HandDisplayManager中修改
hand_display.card_spacing = 8.0     # 卡牌间距
hand_display.suit_spacing = 20.0    # 花色间距
```

### 修改动画速度

```gdscript
# 在CardAnimation中修改
animation.draw_duration = 0.5   # 摸牌更慢
animation.play_duration = 0.6   # 出牌更慢
animation.win_duration = 0.8    # 胡牌更慢
```

---

## 📊 UI架构图

```
┌─────────────────────────────────────────┐
│           Main Scene (main.gd)          │
│                                         │
│  ┌─────────────────────────────────┐   │
│  │    GameController               │   │
│  │  ┌─────────────────────────┐    │   │
│  │  │ HandDisplayManager      │    │   │
│  │  │  ├─ CardUI[]            │    │   │
│  │  │  └─ 信号系统            │    │   │
│  │  └─────────────────────────┘    │   │
│  │  ┌─────────────────────────┐    │   │
│  │  │ CardAnimation           │    │   │
│  │  │  ├─ Tween动画           │    │   │
│  │  │  └─ 效果管理            │    │   │
│  │  └─────────────────────────┘    │   │
│  └─────────────────────────────────┘   │
│                                         │
│  GameState (状态管理)                  │
│  ├─ 玩家手牌                           │
│  ├─ AI手牌                             │
│  └─ 游戏状态                           │
│                                         │
└─────────────────────────────────────────┘
```

---

## 🚀 后续开发方向

### 立即可做
- [ ] 完整集成到main.gd
- [ ] 测试卡牌显示效果
- [ ] 调整卡牌大小和颜色
- [ ] 测试动画流畅度

### 短期
- [ ] 改进卡牌正面绘制（使用字体）
- [ ] 添加卡牌音效
- [ ] 弃牌堆显示
- [ ] 对手卡牌显示（背面）

### 中期
- [ ] 胡牌显示界面
- [ ] 听牌提示面板
- [ ] 游戏信息显示
- [ ] 游戏日志窗口

### 长期
- [ ] 完整UI美化
- [ ] 主菜单
- [ ] 设置界面
- [ ] 排行榜显示

---

## 🧪 测试清单

### 卡牌显示测试
- [ ] CardUI能正确显示各花色卡牌
- [ ] 正面和背面显示正确
- [ ] 选中状态边框显示
- [ ] 高亮效果正常

### 手牌管理测试
- [ ] 手牌按花色分组
- [ ] 手牌按数字排序
- [ ] 单选功能正常
- [ ] 信号发送正确

### 动画测试
- [ ] 摸牌动画流畅
- [ ] 出牌动画流畅
- [ ] 胡牌动画有视觉冲击
- [ ] 碰/杠动画正确

---

## 💻 代码文件

```
godot/scripts/
├── card_ui.gd              ⭐ 卡牌单个显示 (150+ 行)
├── hand_display_manager.gd ⭐ 手牌显示管理 (120+ 行)
├── card_animation.gd       ⭐ 卡牌动画 (180+ 行)
└── game_controller.gd      (需要集成新组件)
```

**总计**: 450+ 行新UI代码

---

## 📝 更新日志

### v0.1.0 (2025-10-30)
- ✨ 创建CardUI卡牌显示组件
- ✨ 创建HandDisplayManager手牌管理器
- ✨ 创建CardAnimation动画系统
- 📝 编写UI系统开发指南

---

**下一步**: 现在可以集成到游戏中并进行测试了！

🎨 **准备好美化游戏界面了吗？** 告诉我你的想法！
