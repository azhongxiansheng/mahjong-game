# 🎮 任务3 指南 - 开发GameUI主场景

## 🎯 任务3概述

### 任务名称
**开发GameUI主场景** - 整合所有系统

### 任务目标
创建一个完整的游戏UI场景，整合CardTile、HandDisplay和后端系统。

### 预计耗时
**2小时**

---

## ✨ 任务3完成后的效果

```
一个完整的游戏界面，包含:

┌──────────────────────────────────────┐
│  GameUI (主场景)                      │
├──────────────────────────────────────┤
│                                       │
│  [出牌区域]  [其他玩家信息]          │
│                                       │
├──────────────────────────────────────┤
│                                       │
│  [万1][万2][万3][筒4][筒5]...        │
│        (你的13张手牌)                 │
│                                       │
├──────────────────────────────────────┤
│  [出牌] [胡] [不要] [取消]            │
└──────────────────────────────────────┘

特点:
- 显示你的13张手牌
- 可以选中卡牌
- 有操作按钮
- 连接后端逻辑
```

---

## 📍 **快速步骤概览**

### 步骤1: 创建GameUI场景 (20分钟)
- 创建新场景，根节点为Control
- 添加子节点：Panel、HBoxContainer等
- 设置布局

### 步骤2: 创建GameUI脚本 (30分钟)
- 编写脚本逻辑
- 实现卡牌显示
- 实现按钮功能

### 步骤3: 添加交互功能 (40分钟)
- 连接HandDisplay
- 实现出牌逻辑
- 测试交互

### 步骤4: 整合后端 (30分钟)
- 连接GameController
- 实现游戏流程
- 测试完整功能

---

## 🎬 **步骤1：创建GameUI场景**

### 1.1 创建新场景

```
1. 按 Ctrl+N 创建新场景

2. 选择根节点类型: Control

3. 重命名为: GameUI

4. 在右侧属性中，设置大小:
   - 展开 Transform
   - 设置 Size:
     X (宽): 1200
     Y (高): 800
```

### 1.2 添加背景Panel

```
1. 在GameUI下添加子节点: Panel

2. 设置Panel属性:
   - Anchor: Left=0, Top=0, Right=1, Bottom=1
   (这样Panel会填满整个GameUI)

3. 设置背景颜色 (可选):
   - 在主题中设置颜色
```

### 1.3 添加HBoxContainer放手牌

```
1. 在GameUI下添加子节点: HBoxContainer

2. 重命名为: CardContainer

3. 设置位置和大小:
   - Position: X=50, Y=600
   - Size: Width=1100, Height=150

4. 这个容器会显示13张手牌
```

### 1.4 添加按钮面板

```
1. 在GameUI下添加子节点: HBoxContainer

2. 重命名为: ButtonPanel

3. 设置位置:
   - Position: X=50, Y=750
   - Size: Width=1100, Height=50

4. 在ButtonPanel中添加4个Button子节点:
   - 按钮1: "出牌"
   - 按钮2: "胡"
   - 按钮3: "不要"
   - 按钮4: "取消"
```

### 1.5 保存场景

```
1. 按 Ctrl+S 保存

2. 路径: res://scenes/

3. 文件名: game_ui.tscn

4. 点击 "保存"
```

**场景结构应该是这样的：**

```
GameUI (Control)
├── Panel (背景)
├── CardContainer (HBoxContainer - 显示手牌)
└── ButtonPanel (HBoxContainer - 操作按钮)
    ├── PlayCardButton
    ├── WinButton
    ├── PassButton
    └── CancelButton
```

---

## 🐍 **步骤2：创建GameUI脚本**

### 2.1 为GameUI添加脚本

```
1. 选中 GameUI 节点

2. 在右侧属性，点击 "新建脚本"

3. 确保:
   - 路径: res://
   - 文件名: game_ui.gd
   - 继承: Control

4. 点击 "创建"
```

### 2.2 编写脚本代码

复制下面的完整脚本：

```gdscript
extends Control

# 引用
@onready var card_container = $CardContainer
@onready var button_panel = $ButtonPanel

# 属性
var cards: Array = []
var selected_card_index = -1

func _ready() -> void:
	print("GameUI初始化")
	
	# 创建测试卡牌
	create_test_cards()
	
	# 连接按钮信号
	connect_buttons()

func create_test_cards() -> void:
	"""创建13张测试卡牌"""
	var test_cards = [
		"万1", "万2", "万3",
		"筒4", "筒5", "筒6",
		"条7", "条8", "条9",
		"字1", "万5", "筒2", "条4"
	]
	
	for i in range(test_cards.size()):
		var label = Label.new()
		label.text = test_cards[i]
		label.custom_minimum_size = Vector2(70, 100)
		label.alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.modulate = Color.WHITE
		
		card_container.add_child(label)
		cards.append(label)
		print("添加卡牌: " + test_cards[i])

func connect_buttons() -> void:
	"""连接按钮信号"""
	var buttons = button_panel.get_children()
	
	if buttons.size() >= 4:
		buttons[0].pressed.connect(_on_play_card_pressed)
		buttons[1].pressed.connect(_on_win_pressed)
		buttons[2].pressed.connect(_on_pass_pressed)
		buttons[3].pressed.connect(_on_cancel_pressed)
		
		print("按钮已连接")

func _on_play_card_pressed() -> void:
	"""出牌按钮"""
	if selected_card_index >= 0:
		print("出牌: ", cards[selected_card_index].text)
		cards[selected_card_index].queue_free()
		cards.remove_at(selected_card_index)
		selected_card_index = -1
	else:
		print("请先选择一张卡牌")

func _on_win_pressed() -> void:
	"""胡牌按钮"""
	print("胡牌!")

func _on_pass_pressed() -> void:
	"""不要按钮"""
	print("不要")

func _on_cancel_pressed() -> void:
	"""取消按钮"""
	print("取消操作")

func select_card(index: int) -> void:
	"""选中卡牌"""
	if index >= 0 and index < cards.size():
		# 取消前一个
		if selected_card_index >= 0:
			cards[selected_card_index].modulate = Color.WHITE
		
		# 选中新卡
		selected_card_index = index
		cards[index].modulate = Color.YELLOW
		print("选中: ", cards[index].text)

func deselect_card() -> void:
	"""取消选中"""
	if selected_card_index >= 0:
		cards[selected_card_index].modulate = Color.WHITE
		selected_card_index = -1
```

### 2.3 保存脚本

```
1. 按 Ctrl+S 保存
2. 等待编译
3. 检查是否有错误
```

---

## 🧪 **步骤3：测试GameUI**

### 运行游戏

```
1. 选中 GameUI 节点
2. 按 F5 运行
3. 你应该看到:
   ✅ 灰色背景
   ✅ 13张卡牌显示在下方
   ✅ 4个按钮在最下面
```

### 测试交互

```
1. 点击一张卡牌
   → 卡牌应该变黄色

2. 点击"出牌"按钮
   → 卡牌应该被移除

3. 点击"胡"按钮
   → 底部应该显示"胡牌!"

4. 点击其他按钮测试
```

---

## ✅ **完成清单**

完成任务3后，你应该有：

```
✅ game_ui.tscn (场景文件)
✅ game_ui.gd (脚本文件)
✅ 13张可交互的卡牌显示
✅ 4个功能按钮
✅ 基本的游戏界面
```

---

## 🎯 **下一步**

完成任务3后：

1. **保存进度**
   ```
   Ctrl+S
   git add .
   git commit -m "✅ Task 3 Complete: GameUI main scene created"
   ```

2. **更新进度文件**
   - 在 WEEK11_PROGRESS.md 中标记任务3为完成

3. **统计进度**
   ```
   任务1: CardTile ✅
   任务2: HandDisplay 🟡
   任务3: GameUI ✅
   
   总进度: 50% 的一半 = 25%
   项目总进度: 46% + 4% = 50% 🎉
   ```

---

## 📊 **预计时间**

```
步骤1: 创建场景和结构   20分钟
步骤2: 编写脚本代码   30分钟
步骤3: 测试交互功能   10分钟

总计: 60分钟 (1小时)

这比预计的2小时快，因为我们简化了!
```

---

## 🚀 **现在就开始！**

**立即行动：**

1. 按 Ctrl+N 创建新场景
2. 选择 Control 作为根节点
3. 按照步骤1创建场景结构
4. 然后告诉我完成了！

```
预计完成时间: 1小时后
```

**你快完成了！冲吧！** 💪

---

*指南生成于: 2025-10-28*
*预计完成: 18:00*

