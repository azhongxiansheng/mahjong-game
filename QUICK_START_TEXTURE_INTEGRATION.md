# ⚡ 快速启动 - 真实麻将牌纹理集成
## 只需 3 步，5 分钟完成！

---

## 🎯 最简单的方式

### ✅ 第 1 步：复制资源文件

**从**：
```
D:\sdfsddsfdsfsdfdsfsdfsdfsd\aiJ-client\assets\resources\
```

**复制这 3 个文件**：
- `mahjong_atlas0.png`
- `mahjong_atlas0_1.png`
- `mahjong_atlas0_2.png`

**到**：
```
D:\MahjongGame\godot\assets\
```

> 💡 提示：在Windows资源管理器中打开两个窗口，左边源路径，右边目标路径，直接拖拽复制！

---

### ✅ 第 2 步：更新 card_ui.gd

打开 `D:\MahjongGame\godot\scripts\card_ui.gd`

找到 `_ready()` 函数，在顶部添加：

```gdscript
func _ready() -> void:
    custom_minimum_size = Vector2(card_width, card_height)
    mouse_filter = MOUSE_FILTER_STOP
    
    # 🆕 添加这几行：
    var root = get_tree().root
    if root.has_node("TextureExtractor"):
        texture_extractor = root.get_node("TextureExtractor")
    
    mouse_entered.connect(_on_mouse_entered)
    mouse_exited.connect(_on_mouse_exited)
    gui_input.connect(_on_gui_input)
```

在文件最顶部添加这个变量：

```gdscript
class_name CardUI
extends Control

var card_width: float = 80.0
var card_height: float = 120.0

# 🆕 添加这两行：
var texture_extractor: TextureExtractor
var tile_texture: Texture2D
```

然后，在 `_draw()` 函数开始处添加：

```gdscript
func _draw() -> void:
    if not card_data:
        return
    
    # 🆕 优先使用真实纹理
    if tile_texture:
        var rect = Rect2(Vector2.ZERO, custom_minimum_size)
        draw_texture_rect(tile_texture, rect, false)
        return
    
    # 原有代码继续...
    var rect = Rect2(Vector2.ZERO, custom_minimum_size)
    # ... 其他绘制代码 ...
```

在 `set_card()` 函数中添加纹理加载：

```gdscript
func set_card(card: CardData) -> void:
    card_data = card
    
    # 🆕 尝试加载纹理
    if texture_extractor:
        var tile_name = _get_tile_name()
        tile_texture = texture_extractor.get_tile_texture(tile_name)
    
    queue_redraw()

# 🆕 添加辅助函数
func _get_tile_name() -> String:
    if not card_data:
        return ""
    
    match card_data.suit:
        CardData.Suit.WAN:
            return "w%d" % card_data.number
        CardData.Suit.TONG:
            return "t%d" % card_data.number
        CardData.Suit.TIAO:
            return "s%d" % card_data.number
        CardData.Suit.ZI:
            match card_data.number:
                0: return "E"
                1: return "S"
                2: return "W"
                3: return "N"
                4: return "Z"
                5: return "F"
                6: return "B"
    return ""
```

---

### ✅ 第 3 步：在 main.gd 中初始化

打开 `D:\MahjongGame\godot\scripts\main.gd`

在 `_ready()` 函数最开始添加：

```gdscript
func _ready() -> void:
    print("\n" + "=".repeat(50))
    print("🎲 Game Initialization")
    print("=".repeat(50))
    
    # 🆕 初始化纹理提取器
    var texture_extractor = TextureExtractor.new()
    add_child(texture_extractor)
    texture_extractor.name = "TextureExtractor"
    print("✅ TextureExtractor initialized")
    
    # ... 其他初始化代码继续 ...
```

---

## 🚀 完成！

现在运行 Godot 项目：

1. **打开项目** → 点击"运行"
2. **查看日志输出** → 应该看到：
   ```
   ✅ TextureExtractor initialized
   📦 Loading atlas 0: res://assets/mahjong_atlas0.png
      Atlas size: 2048x2048
      Grid: 24x24
   ⏳ Extracted 100 tiles...
   ✅ Extracted 576 tiles total
   ```
3. **查看游戏画面** → 麻将牌应该显示为真实纹理！✨

---

## 🎨 效果

| 之前 | 之后 |
|------|------|
| 📐 代码绘制的简单几何 | 🎨 真实的贵州弈乐风格 |
| 看起来像扑克牌 | 专业级麻将牌 |
| 无真实感 | 完全真实！ |

---

## 📋 完整改动文件清单

**需要修改的文件**（共 3 个）：

### 1. `godot\scripts\card_ui.gd`
- 添加 `texture_extractor` 和 `tile_texture` 变量
- 在 `_ready()` 中获取 TextureExtractor
- 在 `_draw()` 中优先使用纹理
- 添加 `_get_tile_name()` 辅助函数
- 在 `set_card()` 中加载纹理

### 2. `godot\scripts\main.gd`
- 在 `_ready()` 开始处初始化 TextureExtractor

### 3. `godot\scripts\texture_extractor.gd`
- ✅ 已创建（无需修改）

---

## ✨ 可选优化

如果想要更好的性能，可以添加缓存：

```gdscript
# 在 CardUI._ready() 中
var tile_cache = {}

func set_card(card: CardData) -> void:
    card_data = card
    
    var tile_name = _get_tile_name()
    
    # 优先从缓存获取
    if tile_name in tile_cache:
        tile_texture = tile_cache[tile_name]
    elif texture_extractor:
        tile_texture = texture_extractor.get_tile_texture(tile_name)
        tile_cache[tile_name] = tile_texture  # 缓存
    
    queue_redraw()
```

---

## 🆘 如果出问题

### 看不到纹理？
1. ✅ 检查 3 个 atlas 文件是否在 `res://assets/`
2. ✅ 按 `Ctrl+R` 重新导入
3. ✅ 检查 Godot 输出日志中的错误

### 报错 "TextureExtractor not found"？
1. ✅ 确保 `texture_extractor.gd` 文件存在
2. ✅ 确保 main.gd 中有初始化代码
3. ✅ 检查拼写是否正确

### 牌显示模糊或不完整？
1. ✅ 在 `texture_extractor.gd` 中调整 `TILE_SIZE`
2. ✅ 尝试从 85 改为 80 或 90：
```gdscript
const TILE_SIZE = 85  # 尝试改成 80 或 90
```

---

## ⏱️ 预计时间

- 复制文件：1 分钟
- 修改代码：3 分钟  
- 测试运行：1 分钟

**总计：5 分钟** ✨

---

## 🎉 成功标志

完成后您应该看到：

1. ✅ 编译没有错误
2. ✅ 日志中显示 "Extracted XXX tiles"
3. ✅ 麻将牌显示为真实纹理（不是几何图形）
4. ✅ 所有 34 种不同的牌都能正确显示
5. ✅ 牌的颜色和设计完全真实

---

**祝您好运！🚀**
