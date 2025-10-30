# 🔍 加载页面故障排查指南

## 问题现象
```
调试进程停止 (Debugging process stopped)
```

这通常表示：
1. ❌ 加载页面没有正确设置为主场景
2. ❌ 场景文件不存在或路径错误
3. ❌ 脚本有运行时错误
4. ❌ 节点命名不匹配

---

## 🔧 检查步骤

### 步骤 1: 验证加载页面文件

检查这些文件是否存在：
```
✓ res://scenes/loading_screen.tscn
✓ res://scripts/loading_screen.gd
```

**操作：** 在 Godot 文件系统中查看

### 步骤 2: 验证主场景设置

**操作：**
1. 打开 Project → Project Settings
2. 找到 General → Run 部分
3. 查看 "Main Scene" 应该指向：`res://scenes/loading_screen.tscn`

如果是 `res://scenes/main.tscn`，改为 `res://scenes/loading_screen.tscn`

### 步骤 3: 检查节点名称

在 `loading_screen.tscn` 中，验证这些节点存在：
```
LoadingScreen (根节点)
  └─ ColorRect
  └─ VBoxContainer
      ├─ TitleLabel
      ├─ SubtitleLabel
      ├─ Spacer1
      ├─ ProgressBar  ← 这个很重要
      ├─ Spacer2
      ├─ StatusLabel  ← 这个很重要
      ├─ Spacer3
      └─ TipsLabel    ← 这个很重要
```

### 步骤 4: 检查脚本绑定

1. 选择 LoadingScreen 节点
2. 查看右侧的 Script 属性
3. 确保指向 `res://scripts/loading_screen.gd`

---

## 📋 快速修复方案

### 方案 A: 恢复原主场景

如果加载页面有问题，恢复为原来的场景：

1. Project → Project Settings
2. General → Run → Main Scene
3. 改为 `res://scenes/main.tscn`
4. F5 运行

这样游戏直接进入，跳过加载页面。

### 方案 B: 重新创建加载页面

如果文件损坏，手动创建：

**步骤：**

1. 新建 Scene → CanvasLayer（命名为 LoadingScreen）
2. 添加子节点：
   - ColorRect（全屏背景）
   - VBoxContainer（布局容器）
3. 在 VBoxContainer 中添加：
   - Label（标题）
   - ProgressBar（进度条）
   - Label（状态文字）
   - Label（提示文字）
4. 将脚本 `loading_screen.gd` 附加到根节点

---

## 🐛 常见错误及解决

### 错误 1: "Could not find node..."
```
⚠️ 脚本中引用的节点不存在
```

**解决：** 检查 @onready 变量的节点路径是否与场景中的节点名称完全匹配

```gdscript
# 确保这些节点存在
@onready var progress_bar = $VBoxContainer/ProgressBar
@onready var status_label = $VBoxContainer/StatusLabel
@onready var tips_label = $VBoxContainer/TipsLabel
```

### 错误 2: "Could not change scene..."
```
❌ 无法跳转到 main.tscn
```

**解决：** 确保 `res://scenes/main.tscn` 存在且可访问

### 错误 3: 加载页面显示但一直不跳转

**原因：** 脚本中 `await` 语句没有正确执行

**解决：** 检查是否有异常被静默捕获。添加调试日志：

```gdscript
func load_game_async():
    print("🔄 开始加载...")
    
    # 添加更多调试信息
    await _load_phase(0, 30, "初始化游戏资源...", 1.0)
    print("✅ 阶段 1 完成")
    
    await _load_phase(30, 70, "加载麻将牌纹理...", 2.0)
    print("✅ 阶段 2 完成")
    
    await _load_phase(70, 90, "初始化游戏界面...", 1.5)
    print("✅ 阶段 3 完成")
    
    await _load_phase(90, 100, "准备就绪！", 1.0)
    print("✅ 阶段 4 完成")
    
    print("🎮 即将跳转到游戏...")
    await get_tree().process_frame
    
    var error = get_tree().change_scene_to_file("res://scenes/main.tscn")
    if error != OK:
        print("❌ 场景切换失败: ", error)
    else:
        print("✅ 已跳转到游戏")
```

---

## 🎯 推荐的临时解决方案

如果加载页面暂时有问题，**先跳过它**：

1. Project → Project Settings
2. General → Run → Main Scene
3. 设为 `res://scenes/main.tscn`
4. F5 测试游戏是否能运行

**验证：**
- ✅ 能否看到手牌？
- ✅ 手牌是否显示清晰的麻将牌纹理？
- ✅ 是否能点击选择卡牌？

如果游戏本身可以正常运行，说明核心逻辑没问题，只是加载页面有配置问题。

---

## 📝 检查清单

- [ ] loading_screen.tscn 存在
- [ ] loading_screen.gd 存在
- [ ] 脚本已附加到场景
- [ ] 所有节点名称匹配
- [ ] Main Scene 正确设置
- [ ] main.tscn 存在且可访问
- [ ] 控制台没有其他错误信息

---

## 💡 下一步

**如果上述都检查过了，还是不行：**

1. 打开 Godot 编辑器的输出窗口 (底部)
2. 查看完整的错误信息
3. 贴出完整的错误日志，我来帮你诊断

---

**暂时的解决方案：直接进入游戏！** 

设置 main.tscn 为主场景，验证游戏核心功能是否正常，再回头修复加载页面。

