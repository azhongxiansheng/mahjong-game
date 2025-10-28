# 🎮 任务2 指南 - 实现HandDisplay手牌显示系统

## 🎉 恭喜！任务1完成！

你已经成功创建了CardTile组件。现在进入**任务2**！

---

## 📋 任务2概述

### 任务名称
**实现HandDisplay手牌显示系统**

### 任务目标
创建一个可以显示和管理多张麻将牌的系统。

### 任务描述
- 创建 HandDisplay 场景
- 实现手牌排列逻辑
- 整合 CardTile 组件
- 实现卡牌选择功能

### 预计耗时
**1.5小时**

---

## ✨ 任务2完成后的效果

```
你会有一个场景，能够:

1. 显示多张卡牌 (例如13张手牌)
2. 自动排列卡牌 (水平排成一行)
3. 卡牌响应鼠标操作 (点击、悬停)
4. 高亮和选中效果工作正常

就像这样:

[ 万1 ] [ 万2 ] [ 万3 ] [ 筒1 ] [ 筒2 ] ...
  ↑ 鼠标悬停时高亮
  ↓ 点击时放大显示
```

---

## 🎯 任务2的5个步骤

### 步骤1: 创建HandDisplay场景 (15分钟)
### 步骤2: 编写HandDisplay脚本 (30分钟)
### 步骤3: 添加卡牌到场景 (15分钟)
### 步骤4: 测试交互功能 (15分钟)
### 步骤5: 优化和调整 (15分钟)

---

## 📍 步骤1: 创建HandDisplay场景

### 1.1 创建新场景

```
1. 按 Ctrl+N 创建新场景

2. 选择根节点类型: Control
   (和CardTile一样的根节点类型)

3. 在场景树中会看到新的Control节点
```

### 1.2 重命名为HandDisplay

```
1. 右键点击 Control 节点

2. 选择 "重命名"

3. 输入: HandDisplay

4. 按 Enter 确认
```

### 1.3 添加一个子节点 - HBoxContainer

现在我们需要添加一个特殊的节点，用于自动排列卡牌。

```
1. 确保 HandDisplay 节点被选中

2. 点击 "场景" → "新建子节点"

3. 搜索框输入: HBoxContainer
   (这是一个可以自动水平排列子节点的容器)

4. 点击创建

5. 你会看到 HBoxContainer 出现在HandDisplay下方
```

### 1.4 保存场景

```
1. 按 Ctrl+S 保存

2. 路径: res://scenes/

3. 文件名: hand_display.tscn

4. 点击 "保存"
```

**当前结构:**
```
HandDisplay (Control)
└── HBoxContainer
```

---

## 🐍 步骤2: 编写HandDisplay脚本

### 2.1 为HandDisplay添加脚本

```
1. 选中 HandDisplay 节点

2. 在右侧属性面板，找到 "脚本"

3. 点击 "新建脚本" 或 📝 图标

4. 确保:
   - 路径: res://
   - 文件名: hand_display.gd
   - 继承: Control

5. 点击 "创建"
```

### 2.2 编写脚本代码

Godot会打开脚本编辑器。清空默认代码，粘贴下面的脚本：

```gdscript
class_name HandDisplay
extends Control

# 引用
@onready var card_container = $HBoxContainer

# 属性
var cards: Array[CardTile] = []
var selected_card: CardTile = null

func _ready() -> void:
	# 设置容器属性
	card_container.add_theme_constant_override("separation", 5)
	
	# 测试: 创建13张随机卡牌
	for i in range(13):
		var card = CardTile.new()
		var suit = randi() % 4
		var number = (i % 9) + 1
		var card_data = CardData.new()
		card_data.suit = suit
		card_data.number = number
		
		card.set_card(card_data)
		card_container.add_child(card)
		cards.append(card)
		
		# 连接卡牌的信号
		card.card_pressed.connect(_on_card_pressed.bind(card))
		card.card_selected.connect(_on_card_selected.bind(card))

func _on_card_pressed(card: CardData, card_tile: CardTile) -> void:
	print("卡牌被点击: ", card.suit, " - ", card.number)
	select_card(card_tile)

func _on_card_selected(card: CardData, card_tile: CardTile) -> void:
	print("卡牌被选中: ", card.suit, " - ", card.number)

func select_card(card: CardTile) -> void:
	# 取消前一个选中的卡牌
	if selected_card:
		selected_card.deselect()
	
	# 选中新卡牌
	selected_card = card
	card.select()

func deselect_all() -> void:
	if selected_card:
		selected_card.deselect()
		selected_card = null

func add_card(card_data: CardData) -> void:
	var card = CardTile.new()
	card.set_card(card_data)
	card_container.add_child(card)
	cards.append(card)
	
	card.card_pressed.connect(_on_card_pressed.bind(card))
	card.card_selected.connect(_on_card_selected.bind(card))

func remove_card(card: CardTile) -> void:
	if card in cards:
		cards.erase(card)
		card.queue_free()

func clear_hand() -> void:
	for card in cards:
		card.queue_free()
	cards.clear()
```

### 2.3 保存脚本

```
1. 按 Ctrl+S 保存

2. 等待编译

3. 检查是否有错误
```

---

## 🃏 步骤3: 添加卡牌到场景

现在我们需要在运行时添加一些测试卡牌。

### 方法1: 使用_ready()函数 (已包含在脚本中)

脚本中的 `_ready()` 函数会自动创建13张随机卡牌。

### 方法2: 手动添加卡牌

如果你想手动添加卡牌，使用：

```gdscript
var card_data = CardData.new()
card_data.suit = 0  # 万
card_data.number = 5
hand_display.add_card(card_data)
```

---

## 🧪 步骤4: 测试交互功能

### 测试方法

```
1. 选中 HandDisplay 节点

2. 按 F5 或点击顶部的运行按钮

3. 你应该看到:
   ✅ 13张卡牌显示在一行
   ✅ 卡牌能响应鼠标悬停
   ✅ 卡牌能响应点击
   ✅ 选中的卡牌会放大

4. 在Godot底部查看输出:
   ✅ 看到 "卡牌被点击" 和 "卡牌被选中" 的信息
```

### 预期结果

```
底部输出应该显示:
卡牌被点击: 0 - 5
卡牌被选中: 0 - 5

这表示脚本正常工作!
```

---

## 🎨 步骤5: 优化和调整

### 5.1 调整卡牌间距

在脚本的 `_ready()` 函数中，修改这一行：

```gdscript
card_container.add_theme_constant_override("separation", 5)
```

改成:
```gdscript
card_container.add_theme_constant_override("separation", 10)  # 增加间距
```

### 5.2 调整容器大小

```
1. 选中 HBoxContainer 节点

2. 在右侧属性面板，找到 "Layout" → "Size Flags"

3. 设置:
   - Horizontal: Fill
   - Vertical: Fill

这样容器会自动填充整个HandDisplay
```

### 5.3 设置卡牌最小尺寸

脚本中已经有这一行：
```gdscript
custom_minimum_size = Vector2(80, 120)
```

如果卡牌太小或太大，可以调整这个值。

---

## ✅ 完成清单

完成任务2后，你应该有：

```
✅ hand_display.tscn (场景文件)
✅ hand_display.gd (脚本文件)
✅ 能显示多张卡牌
✅ 卡牌能自动排列
✅ 支持卡牌选择
✅ 信号系统工作正常
```

---

## 💡 常见问题

### Q: "找不到CardTile"
**A**: 确保 CardTile 类名正确:
- 在 card_tile.gd 的第一行应该是 `class_name CardTile`

### Q: "找不到CardData"
**A**: CardData 应该在其他脚本中定义，或者需要创建
- 如果没有，先创建一个基本的CardData类

### Q: "卡牌没有显示"
**A**: 
- 检查HBoxContainer是否正确关联
- 检查 $HBoxContainer 路径是否正确
- 检查custom_minimum_size是否设置

### Q: "卡牌排列不整齐"
**A**: 
- 检查HBoxContainer的Size Flags设置
- 调整separation参数
- 检查卡牌的自定义最小大小

---

## 🎯 下一步

完成任务2后：

1. **保存你的进度**
   - 按 Ctrl+S
   - git add .
   - git commit -m "✅ Task 2 Complete: HandDisplay system implemented"

2. **更新进度文件**
   - 在 WEEK11_PROGRESS.md 中标记任务2为完成

3. **准备任务3**
   - 开始开发 GameUI 主场景

---

## 📊 任务2时间估算

```
步骤1: 创建场景     15分钟
步骤2: 编写脚本     30分钟
步骤3: 添加卡牌     15分钟
步骤4: 测试功能     15分钟
步骤5: 优化调整     15分钟

总计: 1小时30分钟
```

---

## 🚀 现在就开始！

你已经完成了第一个任务。你知道如何操作Godot了。

这个任务会简单一些，因为你已经有了CardTile组件可以直接使用。

**现在就按照上面的步骤开始吧！** 💪

---

*指南生成于: 2025-10-28*
*预计完成: 1小时30分钟后*
