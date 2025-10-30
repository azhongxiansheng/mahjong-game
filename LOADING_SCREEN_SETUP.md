# 🎮 游戏加载页面设置指南

## 📖 概览

你现在有一个**专业的游戏加载页面**，在玩家进入游戏时显示。

---

## 🎨 加载页面效果

### 显示内容
```
🎴 麻将游戏
正在加载游戏资源

[========>          ] 35%

初始化游戏资源...

💡 麻将小贴士：清一色可得翻倍分数
```

### 加载流程
```
初始化游戏资源... (0-30%) → 1秒
加载麻将牌纹理... (30-70%) → 2秒  
初始化游戏界面... (70-90%) → 1.5秒
准备就绪！        (90-100%) → 1秒
                  总计 ≈ 5.5秒
```

---

## 🚀 如何使用

### 方式 1: 作为启动场景

**在 Godot 编辑器中：**
1. 打开 `res://scenes/loading_screen.tscn`
2. 右键点击场景 → "设为主场景"
3. 按 F5 运行

**结果：**
- 游戏启动时显示加载页面
- 5.5 秒后自动跳转到游戏

### 方式 2: 在代码中调用

```gdscript
# 在某个场景中
func _ready():
    # 进入加载页面
    get_tree().change_scene_to_file("res://scenes/loading_screen.tscn")
```

---

## 🔧 定制加载页面

### 修改加载提示

编辑 `godot/scripts/loading_screen.gd` 中的 `tips` 数组：

```gdscript
var tips = [
    "💡 自定义提示 1",
    "🎯 自定义提示 2",
    "🤖 自定义提示 3",
]
```

### 修改加载时长

编辑 `load_game_async()` 函数中的阶段时长：

```gdscript
# 改变时长（秒）
await _load_phase(0, 30, "初始化游戏资源...", 2.0)  # 原来 1.0
await _load_phase(30, 70, "加载麻将牌纹理...", 3.0)  # 原来 2.0
```

### 修改加载颜色

编辑场景 `loading_screen.tscn` 或脚本中的颜色：

```gdscript
# ColorRect 背景色
color = Color(0.15, 0.15, 0.2, 1.0)  # 深灰色

# 修改为其他颜色
color = Color(0.1, 0.3, 0.2, 1.0)  # 深绿色
```

---

## 📊 加载阶段说明

### 阶段 1: 初始化资源 (0-30%)
- 初始化 Godot 引擎资源
- 加载配置文件

### 阶段 2: 加载纹理 (30-70%)
- 初始化 TextureExtractor
- 提取/缓存 34 个麻将牌纹理

### 阶段 3: 初始化 UI (70-90%)
- 创建 GameController
- 初始化 UI 系统

### 阶段 4: 完成 (90-100%)
- 最后的准备工作
- 准备跳转到游戏

---

## ⚡ 优化提示

### 实际加载速度

当前进度条是**模拟的**，显示时间是固定的。如果你想让进度条反映真实的加载进度，可以：

```gdscript
func load_game_async():
    # 方式 1: 真实加载纹理并计算进度
    var loader = ResourceLoader.new()
    
    # 初始化 TextureExtractor
    var texture_extractor = TextureExtractor.new()
    add_child(texture_extractor)
    progress_bar.value = 30
    
    # 等待初始化
    await get_tree().process_frame
    progress_bar.value = 70
    
    # 创建游戏控制器
    # ... 更多初始化 ...
    progress_bar.value = 100
    
    # 跳转到游戏
    get_tree().change_scene_to_file("res://scenes/main.tscn")
```

---

## 📝 常见问题

### Q: 加载页面不显示？
A: 检查场景路径和脚本绑定是否正确

### Q: 进度条没有动画？
A: 确保 ProgressBar 节点存在且命名正确

### Q: 提示文字显示乱码？
A: 检查文件编码是否为 UTF-8

### Q: 加载时间太长？
A: 可以减少 `_load_phase()` 中的时长参数

---

## ✨ 后续改进

### 推荐的优化
1. [ ] 添加加载动画（旋转的微调图标）
2. [ ] 实现真实的资源加载进度
3. [ ] 添加背景音乐
4. [ ] 缓存纹理到本地（第二次启动更快）
5. [ ] 显示每个加载阶段的详细信息

---

## 📦 文件位置

- **场景**: `res://scenes/loading_screen.tscn`
- **脚本**: `res://scripts/loading_screen.gd`
- **启动配置**: Project Settings → General → Run → Main Scene

---

**就这么简单！你现在有一个专业的游戏加载页面了！** 🎉
