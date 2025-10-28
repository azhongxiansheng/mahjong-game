# 🎮 第一步教程 - 创建你的第一个卡牌组件

## 👋 欢迎！这是最详细的手把手教程

我会带你逐步完成**任务1: 创建CardTile卡牌瓦片组件**

不要急，一步一步来。每个步骤都很简单。

---

## ✨ 今天会发生什么

你将创建一个可以显示麻将牌的游戏组件。

完成后，你会在Godot中看到这样的效果:
```
┌─────────────┐
│    万       │
│             │
│      1      │
│             │
└─────────────┘
```

---

## 🎬 开始前的准备 (2分钟)

### 第1步: 打开Godot编辑器

```
1. 双击启动 Godot 4.5.1
2. 点击 "打开项目"
3. 选择: D:\MahjongGame
4. 点击 "打开"

等待项目加载... (可能需要10-30秒)
```

**你会看到**:
```
左边: 场景树 (空的)
中间: 编辑器区域
右边: 属性检查器
```

---

## 🎯 现在开始创建CardTile (第1部分)

### 步骤 1.1: 创建新场景

```
1. 在Godot菜单栏，点击 "场景" → "新建场景"
   (或按快捷键 Ctrl+N)

2. 会弹出一个对话框，选择根节点类型
   → 找到 "Control" 
   → 点击它

3. 你会看到一个新的Control节点出现在场景树中
```

**当前状态**:
```
场景树:
└── Control (这就是你的根节点)
```

### 步骤 1.2: 重命名节点为 CardTile

```
1. 在场景树中，右键点击 "Control" 节点
2. 选择 "重命名"
3. 清空现有的文字，输入: CardTile
4. 按 Enter 确认
```

**当前状态**:
```
场景树:
└── CardTile (根节点已重命名)
```

---

## 🎨 添加子节点 (第2部分)

现在我们要给CardTile添加三个子节点。

### 步骤 2.1: 添加第一个子节点 - TextureRect

```
1. 在场景树中，点击选中 CardTile 节点
2. 在Godot顶部菜单，点击 "场景" → "新建子节点"
   (或右键 CardTile → "添加子节点")

3. 会弹出一个节点选择窗口
4. 在搜索框中输入: TextureRect
5. 点击第一个结果 "TextureRect"
6. 点击 "创建" 按钮
```

**当前状态**:
```
场景树:
└── CardTile
    └── TextureRect (新添加的子节点)
```

### 步骤 2.2: 添加第二个子节点 - Label (用于显示数字)

```
1. 在场景树中，点击选中 CardTile 节点 (不是TextureRect!)
2. 点击 "场景" → "新建子节点"
3. 搜索框输入: Label
4. 点击 "Label"
5. 点击 "创建"
```

**当前状态**:
```
场景树:
└── CardTile
    ├── TextureRect
    └── Label (新添加)
```

### 步骤 2.3: 添加第三个子节点 - Label (用于显示花色)

```
1. 再次确保 CardTile 节点被选中
2. 点击 "场景" → "新建子节点"
3. 搜索框输入: Label
4. 点击 "Label"
5. 点击 "创建"
```

**当前状态**:
```
场景树:
└── CardTile
    ├── TextureRect
    ├── Label
    └── Label (新添加)
```

---

## 📝 重命名Label节点

现在我们需要给两个Label节点改名，让脚本能找到它们。

### 步骤 3.1: 重命名第一个Label为 "Label"

```
1. 在场景树中，点击第一个 Label 节点
   (第二个和第三个节点中间的那个)

2. 右键 → 重命名
3. 输入: Label
4. 按 Enter

💡 提示: 在Godot中，Control类的直接子节点可以通过 $NodeName 访问
        所以我们需要精确的节点名称
```

### 步骤 3.2: 重命名第二个Label为 "SuitLabel"

```
1. 在场景树中，点击第二个 Label 节点
   (最后一个节点)

2. 右键 → 重命名
3. 输入: SuitLabel
4. 按 Enter
```

**当前状态**:
```
场景树:
└── CardTile
    ├── TextureRect
    ├── Label
    └── SuitLabel
```

**完美！** 你的场景结构现在就是脚本需要的样子。

---

## 💾 保存场景 (第3部分)

### 步骤 4.1: 保存场景文件

```
1. 按 Ctrl+S 保存
   (或菜单 "文件" → "保存场景")

2. 会弹出一个保存对话框
3. 确保路径是: D:\MahjongGame\godot\scenes\
4. 文件名输入: card_tile.tscn
5. 点击 "保存"
```

**重要**: 文件名必须是 `card_tile.tscn`，不能有空格或大写字母。

**当前状态**:
```
✅ 场景文件已保存
位置: godot/scenes/card_tile.tscn
```

---

## 🐍 现在创建脚本 (第4部分)

现在我们给CardTile节点关联一个脚本。

### 步骤 5.1: 为CardTile节点附加脚本

```
1. 在场景树中，选中 CardTile 节点

2. 在右侧属性面板的顶部，找到 "脚本" 属性
   (如果看不到，向上滚动属性面板)

3. 你会看到一个空的脚本框和一个 📝 图标
4. 点击那个 📝 图标 (或点击 "新建脚本")

5. 会弹出创建脚本的对话框
6. 确保:
   - 路径: res://scripts/
   - 文件名: card_tile.gd
   - 语言: GDScript
7. 点击 "创建" 按钮
```

**当前状态**:
```
✅ 脚本文件已创建
位置: godot/scripts/card_tile.gd
✅ 脚本已关联到CardTile节点
```

---

## 📄 编写脚本代码 (第5部分)

现在Godot会自动打开新创建的脚本文件进行编辑。

### 步骤 6.1: 清空默认代码

脚本编辑器会有一些默认代码。我们需要全部替换。

```
1. 按 Ctrl+A 选中所有代码
2. 删除它们
3. 现在编辑器是空白的
```

### 步骤 6.2: 复制完整的CardTile脚本

现在你需要复制下面的完整脚本代码。

**请注意**: 这是标准的GDScript代码，复制它即可。

```gdscript
class_name CardTile
extends Control

# 属性
var card_data: CardData
var is_selected: bool = false
var is_highlighted: bool = false

# UI引用
@onready var card_label = $Label
@onready var suit_label = $SuitLabel

# 信号
signal card_pressed(card_data: CardData)
signal card_selected(card_data: CardData)

func _ready() -> void:
	gui_input.connect(_on_gui_input)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	custom_minimum_size = Vector2(80, 120)

func set_card(card: CardData) -> void:
	card_data = card
	update_display()

func update_display() -> void:
	if not card_data:
		return
	card_label.text = str(card_data.number)
	suit_label.text = _get_suit_name(card_data.suit)
	modulate = _get_suit_color(card_data.suit)

func _get_suit_name(suit: int) -> String:
	match suit:
		0: return "万"
		1: return "筒"
		2: return "条"
		3: return "字"
	return ""

func _get_suit_color(suit: int) -> Color:
	match suit:
		0: return Color.RED
		1: return Color.BLUE
		2: return Color.GREEN
		3: return Color.YELLOW
	return Color.WHITE

func highlight() -> void:
	is_highlighted = true
	self_modulate = Color.WHITE

func unhighlight() -> void:
	is_highlighted = false
	self_modulate = Color(0.7, 0.7, 0.7)

func select() -> void:
	is_selected = true
	scale = Vector2(1.1, 1.1)
	card_selected.emit(card_data)

func deselect() -> void:
	is_selected = false
	scale = Vector2(1.0, 1.0)

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		card_pressed.emit(card_data)

func _on_mouse_entered() -> void:
	highlight()

func _on_mouse_exited() -> void:
	if not is_selected:
		unhighlight()
```

### 步骤 6.3: 粘贴代码

```
1. 在脚本编辑器中，按 Ctrl+V 粘贴
2. 代码会填充到编辑器中
3. 检查一下，确保没有缺少任何部分
```

### 步骤 6.4: 保存脚本

```
1. 按 Ctrl+S 保存脚本
   (或菜单 "文件" → "保存")

2. 等待一下，Godot会进行代码检查
3. 如果没有错误，脚本会被编译
```

**当前状态**:
```
✅ 脚本代码已输入
✅ 脚本已保存
✅ Godot已编译脚本
```

---

## ✅ 第一个任务完成！

现在你已经成功创建了:

```
✅ CardTile 场景文件 (godot/scenes/card_tile.tscn)
✅ CardTile 脚本文件 (godot/scripts/card_tile.gd)
✅ 完整的场景结构 (TextureRect + 2个Label)
✅ 脚本中的所有功能
```

---

## 🎉 测试你的创建 (可选但推荐)

想要看看你创建的东西能工作吗？

### 快速测试步骤:

```
1. 在Godot中创建一个简单的测试场景
2. 实例化(复制)CardTile场景到测试场景中
3. 按F5运行游戏
4. 你应该会看到一个可交互的卡牌对象

但这是可选的。现在主要是要确保CardTile能正确创建。
```

---

## 🎯 下一步

完成这个任务后:

1. 在 `WEEK11_PROGRESS.md` 中标记"任务1"为完成
2. 记录完成时间
3. 准备开始"任务2"

---

## 💡 常见问题和解决方案

### Q: "我按了Ctrl+N但什么都没发生"
**A**: 
- 尝试使用菜单栏: 点击 "场景" → "新建场景"
- 或者尝试使用右键菜单

### Q: "TextureRect找不到"
**A**: 
- 在搜索框中只输入 "Texture"，应该就能看到
- 或者输入 "Rect"

### Q: "保存时找不到 godot/scenes 文件夹"
**A**: 
- 文件夹应该已经存在
- 确保你选择的是 D:\MahjongGame 项目
- 如果没有 scenes 文件夹，创建它

### Q: "脚本粘贴后有红色错误"
**A**: 
- 这很正常，Godot可能还没完成编译
- 等几秒钟
- 如果错误持续，检查是否正确复制了所有代码

### Q: "我看不到脚本编辑器"
**A**: 
- 脚本编辑器可能在另一个标签页
- 查看Godot顶部的标签栏
- 点击 "card_tile.gd" 标签

---

## 🏁 完成后

当你完成这个教程时:

- ✅ 你会有一个可工作的CardTile组件
- ✅ 你已经学会了如何在Godot中创建场景和脚本
- ✅ 你已经准备好进行任务2了

---

**现在就开始吧！** 🚀

第一步: 打开Godot  
第二步: 按 Ctrl+N 创建新场景  
第三步: 选择 Control 作为根节点  

**你可以做到！** 💪

---

*教程生成时间: 2025-10-28*  
*预计完成时间: 1小时*
