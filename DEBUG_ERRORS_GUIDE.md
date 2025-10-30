# 🐛 Godot 调试错误追踪指南

## 当前状态
- **编译错误**: 0 ✅
- **运行时错误**: 15 (待诊断)
- **Linter检查**: 全部通过 ✅

## 可能的错误来源

### 1. 信号连接错误
已修复的相关问题:
- ✅ `.bindv()` → `.bind()` (在 hand_display_manager.gd 和 achievement_system.gd)
- ✅ 缺失的 `get_display_name()` 方法 (在 CardData 中已添加)

### 2. 节点初始化问题
已修复的相关问题:
- ✅ `.get_tree()` 在创建前调用 (在 card_animation.gd 中已修复)
- ✅ 空数组 `.back()` 访问 (在 hand_display_manager.gd 中已修复)

### 3. 类型转换/继承问题
检查项目:
- [ ] CardUI 是否能正确继承 Control
- [ ] HandDisplayManager 是否能正确继承 Control
- [ ] CardAnimation 是否能正确继承 Node

### 4. 方法可用性检查
在Godot中调试时，检查以下方法是否可用:
- `get_theme_font()` - Control 类方法
- `get_theme_font_size()` - Control 类方法
- `queue_redraw()` - CanvasItem 类方法
- `create_tween()` - Node 类方法 (从 Godot 4.0 开始)

## 如何查看完整错误列表

1. 打开Godot编辑器
2. 查看底部 "Debugger" 标签页
3. 在 "Errors" 或 "Output" 中查看完整错误信息
4. 复制完整的错误堆栈跟踪

## 可能的错误症状

### 症状A: "Property not found" 或 "Method not found"
可能原因:
- 属性/方法名称拼写错误
- 继承层次不正确
- 类未正确加载

### 症状B: "Null instance" 或 "Invalid call"
可能原因:
- 对象在添加到场景树前被使用
- 信号连接到不存在的方法
- 循环引用导致的初始化顺序问题

### 症状C: "Cannot connect" 或 "Invalid signature"
可能原因:
- 信号参数与槽函数参数不匹配
- 信号/方法定义有误

## 下一步行动

请提供以下信息以便进一步诊断:
```
1. 完整的错误消息 (从 Godot 调试器复制)
2. 错误出现的具体行号
3. 错误的函数/方法名称
4. 错误类型 (TypeError, NameError, 等)
```

**命令:**
按 Ctrl+Shift+C 在Godot控制台复制完整的错误输出
