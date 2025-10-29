# 🔧 故障排查指南

**最后更新**: 2025年10月29日  
**版本**: v1.0

---

## 📋 快速导航

- [quick_setup.bat 错误](#quick_setupbat-错误)
- [Python 脚本错误](#python-脚本错误)
- [Godot 脚本错误](#godot-脚本错误)
- [网络问题](#网络问题)
- [文件系统问题](#文件系统问题)

---

## quick_setup.bat 错误

### ❌ 问题 1: "Python 未找到"

**错误消息**：
```
❌ 未找到 Python，请先安装 Python 3.x
```

**原因**：
- Python 未安装
- Python 未添加到 PATH 环境变量

**解决方案**：
```
1. 下载 Python 3.x：https://www.python.org/downloads/
2. 安装时勾选 "Add Python to PATH"
3. 重启命令行窗口
4. 验证安装：python --version
5. 重新运行 quick_setup.bat
```

### ❌ 问题 2: "下载失败"

**错误消息**：
```
❌ 下载失败
```

**原因**：
- Python 脚本有错误
- 网络连接问题
- 权限问题

**解决方案**：
```bash
# 1. 直接运行 Python 脚本查看详细错误
python download_wechat_icon.py

# 2. 检查网络连接
ping github.com

# 3. 如果仍然失败，尝试强制刷新
python download_wechat_icon.py --force

# 4. 查看具体错误信息
python download_wechat_icon.py 2>&1
```

### ❌ 问题 3: "未知参数"

**错误消息**：
```
❌ 未知参数: xxx
使用 --help 查看帮助信息
```

**原因**：
- 参数名称错误
- 参数格式不正确

**解决方案**：
```bash
# 查看正确的参数
quick_setup.bat --help

# 正确用法示例
quick_setup.bat --size 40 --format svg
quick_setup.bat --size 64
quick_setup.bat --format png
```

### ❌ 问题 4: "权限被拒绝"

**错误消息**：
```
❌ 无法写入文件: ...
权限被拒绝
```

**原因**：
- Godot 编辑器正在使用文件
- 文件权限不足
- 文件被其他程序占用

**解决方案**：
```
1. 关闭 Godot 编辑器
2. 右键点击 quick_setup.bat
3. 选择"以管理员身份运行"
4. 或者在 PowerShell 中运行：
   Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
   & ".\quick_setup.bat"
```

---

## Python 脚本错误

### ❌ 问题 1: "ImportError: No module named 'PIL'"

**错误消息**：
```
⚠ PIL 库未安装，无法生成 PNG 图标
💡 请运行: pip install Pillow
```

**原因**：
- PNG 格式需要 Pillow 库，但未安装

**解决方案**：
```bash
# 安装 Pillow
pip install Pillow

# 重新运行
python download_wechat_icon.py --format png
```

### ❌ 问题 2: "GitHub 下载失败"

**错误消息**：
```
⚠ GitHub 下载失败: [Errno 11001] getaddrinfo failed
```

**原因**：
- 网络连接问题
- GitHub 不可访问
- DNS 问题

**解决方案**：
```bash
# 1. 检查网络连接
ping github.com

# 2. 脚本会自动生成本地图标（不需要手动处理）
# 继续运行，会自动生成

# 3. 如果需要强制刷新，使用 --force
python download_wechat_icon.py --force

# 4. 尝试更换 DNS（如果 GitHub 无法访问）
# Windows: ipconfig /flushdns
```

### ❌ 问题 3: "Permission denied"

**错误消息**：
```
❌ 无法写入目标文件: ...
Permission denied
```

**原因**：
- 缺少写入权限
- 文件被占用

**解决方案**：
```bash
# 1. 关闭所有占用文件的程序（包括 Godot）
# 2. 清理缓存后重试
python download_wechat_icon.py --clear-cache
python download_wechat_icon.py --force

# 3. 或者用管理员身份运行
# Windows: 右键 - 以管理员身份运行
# Linux/Mac: sudo python download_wechat_icon.py
```

### ❌ 问题 4: "无效的参数"

**错误消息**：
```
❌ 不支持的尺寸: 100
支持的尺寸: [32, 40, 48, 64, 128]
```

**原因**：
- 尺寸不在支持列表中

**解决方案**：
```bash
# 使用支持的尺寸
python download_wechat_icon.py --size 40    # ✅ 正确
python download_wechat_icon.py --size 64    # ✅ 正确
python download_wechat_icon.py --size 100   # ❌ 错误

# 或保持默认（40x40）
python download_wechat_icon.py
```

---

## Godot 脚本错误

### ❌ 问题 1: "API 错误 - make_absolute_path"

**错误消息**：
```
Static function "make_absolute_path()" not found in base "GDScriptNativeClass".
```

**原因**：
- Godot 4.x 中 API 已改变

**解决方案**：
```
✅ 已修复！使用最新版本的脚本
文件：godot/scripts/wechat_icon_downloader.gd
已使用 DirAccess.make_dir_absolute() 替代
```

### ❌ 问题 2: "图标不显示"

**错误消息**：
```
加载画面中微信登录按钮没有显示图标
```

**原因**：
- 图标文件不存在
- 资源缓存未刷新
- 纹理路径不正确

**解决方案**：
```
1. 检查图标文件是否存在
   godot/assets/wechat_icon.svg 或
   godot/assets/wechat_icon.png

2. 刷新 Godot 资源缓存
   菜单 → 文件 → 刷新
   或按 Ctrl + Shift + R

3. 重新打开加载画面场景
   scenes/loading_screen.tscn

4. 按 F5 运行测试

5. 如果仍未显示，手动运行下载
   quick_setup.bat 或
   python download_wechat_icon.py
```

### ❌ 问题 3: "下载超时"

**错误消息**：
```
下载超时或连接被拒绝
```

**原因**：
- 网络连接慢
- 服务器响应缓慢

**解决方案**：
```
1. 检查网络连接速度
2. 重新尝试
3. 使用强制刷新
   python download_wechat_icon.py --force
4. 或者离线使用缓存的图标
```

---

## 网络问题

### ❌ 问题 1: "无法连接到 GitHub"

**症状**：
```
⚠ GitHub 下载失败
HTTP 错误或超时
```

**原因**：
- 网络连接问题
- 防火墙阻止
- GitHub 维护中

**解决方案**：
```bash
# 1. 测试网络连接
ping github.com
ping baidu.com

# 2. 检查防火墙设置
# Windows: 控制面板 → Windows Defender 防火墙

# 3. 脚本会自动生成本地图标（无需额外操作）

# 4. 如果需要手动处理，直接使用本地生成
python download_wechat_icon.py  # 会自动生成

# 5. 稍后重试当网络恢复时
```

### ❌ 问题 2: "DNS 问题"

**症状**：
```
[Errno 11001] getaddrinfo failed
[Errno -2] Name or service not known
```

**原因**：
- DNS 解析失败

**解决方案**：
```bash
# Windows：清除 DNS 缓存
ipconfig /flushdns

# Linux：重启 systemd-resolved
sudo systemctl restart systemd-resolved

# Mac：清除 DNS 缓存
sudo dscacheutil -flushcache

# 使用替代 DNS（可选）
# 在系统网络设置中更改为 8.8.8.8 或 1.1.1.1
```

---

## 文件系统问题

### ❌ 问题 1: "目录不存在"

**症状**：
```
❌ 无法打开目录: godot/assets
```

**原因**：
- 目录结构不完整
- 路径错误

**解决方案**：
```bash
# 1. 检查目录结构
ls -la godot/assets/
# 或 Windows
dir godot\assets\

# 2. 如果目录不存在，脚本会自动创建
# 3. 手动创建（如果需要）
mkdir godot/assets

# 4. 确保在项目根目录运行
cd D:\MahjongGame
python download_wechat_icon.py
```

### ❌ 问题 2: "磁盘空间不足"

**症状**：
```
❌ 无法写入文件: 磁盘空间不足
```

**原因**：
- 磁盘空间满了

**解决方案**：
```bash
# 1. 清理缓存
python download_wechat_icon.py --clear-cache

# 2. 清理其他不需要的文件
# 3. 检查磁盘空间
# Windows: C: 盘右键 → 属性
# Linux: df -h

# 4. 清理临时文件后重试
```

### ❌ 问题 3: "文件被占用"

**症状**：
```
❌ 无法修改文件: 文件被其他进程占用
```

**原因**：
- Godot 编辑器打开了文件
- 其他程序占用

**解决方案**：
```
1. 关闭 Godot 编辑器
2. 关闭其他占用文件的程序
3. 重新运行脚本
4. 如果仍未解决，重启计算机
```

---

## 快速修复清单

### 遇到问题时按顺序尝试

```
☐ 1. 检查错误消息，查找本文档中的对应问题
☐ 2. 尝试建议的解决方案
☐ 3. 清理缓存：python download_wechat_icon.py --clear-cache
☐ 4. 强制刷新：python download_wechat_icon.py --force
☐ 5. 关闭 Godot 编辑器，重新尝试
☐ 6. 以管理员身份运行脚本
☐ 7. 检查网络连接
☐ 8. 重启计算机
☐ 9. 查看其他错误消息，搜索文档
☐ 10. 如仍未解决，检查日志文件获取更多信息
```

---

## 获取更多帮助

### 诊断信息

运行以下命令获取诊断信息：

```bash
# 1. Python 版本
python --version

# 2. 检查下载脚本
python download_wechat_icon.py --help

# 3. 查看缓存目录
ls -la user://wechat_icons_cache/

# 4. 检查生成的文件
ls -la godot/assets/wechat_icon*

# 5. 查看元数据
cat godot/assets/wechat_icon.json
```

### 相关文档

- 📖 [快速启动指南](WECHAT_ICON_QUICK_START.md)
- 🚀 [完整部署指南](docs/🚀_微信图标自动下载部署指南.md)
- 🎯 [实现总结](IMPLEMENTATION_SUMMARY.md)
- 🐛 [Bug 修复报告](BUG_FIX_REPORT.md)

---

## 常见问题 (FAQ)

### Q: 为什么 GitHub 下载经常失败？
**A**: 可能是网络问题。不用担心，脚本会自动生成本地图标，功能完全相同。

### Q: 可以离线使用吗？
**A**: 可以。首次下载后会缓存，后续完全可以离线使用。

### Q: 图标文件在哪里？
**A**: 在 `godot/assets/wechat_icon.svg` 或 `godot/assets/wechat_icon.png`

### Q: 如何删除缓存的图标？
**A**: 运行 `python download_wechat_icon.py --clear-cache`

### Q: 支持多平台吗？
**A**: 支持！Windows、macOS、Linux 都支持。但 quick_setup.bat 仅在 Windows 上运行。其他平台使用 Python 脚本。

---

## 获得技术支持

如果问题仍未解决：

1. 📖 阅读相关文档
2. 🔍 检查此故障排查指南
3. 🌐 访问官方文档和社区论坛
4. 💬 查看脚本的错误日志

---

**最后更新**: 2025年10月29日  
**版本**: v1.0  
**维护者**: AI 代码助手

**祝您使用愉快！** 🎉
