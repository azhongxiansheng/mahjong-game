# 🎯 微信图标下载工具 - 完整入门指南

**最后更新**: 2025年10月29日  
**版本**: v2.0.1  
**语言**: 中文 | English

---

## 📋 目录

1. [系统要求](#系统要求)
2. [快速开始](#快速开始)
3. [详细步骤](#详细步骤)
4. [常见问题](#常见问题)
5. [故障排查](#故障排查)

---

## 系统要求

### 最低要求

| 项目 | 要求 |
|------|------|
| 操作系统 | Windows 7+, macOS 10.14+, Linux |
| Python | 3.6+ |
| Godot | 4.0+ |
| 磁盘空间 | 50 MB (缓存最多 20 MB) |
| 网络 | 可选（网络不可用时自动生成） |

### 推荐配置

| 项目 | 推荐 |
|------|------|
| 操作系统 | Windows 10+, macOS 11+, Ubuntu 20.04+ |
| Python | 3.8+ |
| Godot | 4.1+ |
| 磁盘空间 | 100+ MB |
| 网络 | 高速网络 (>1 Mbps) |

---

## 快速开始

### ⏱️ 30 秒完成（Windows）

```bash
# 步骤 1: 进入项目目录
# 在文件浏览器中打开项目文件夹

# 步骤 2: 双击运行
# 找到 quick_setup.bat 文件，双击运行

# 步骤 3: 完成！
# 等待脚本完成，图标已自动下载到 godot/assets/
```

### ⏱️ 30 秒完成（其他平台）

```bash
# 步骤 1: 打开终端
# 进入项目根目录

# 步骤 2: 运行命令
python download_wechat_icon.py

# 步骤 3: 完成！
# 图标已下载到 godot/assets/
```

---

## 详细步骤

### 步骤 1: 检查系统环境

#### Windows

```bash
# 打开 PowerShell 或命令提示符

# 检查 Python
python --version

# 应该显示类似：Python 3.8.0 或更新版本
```

如果显示 "命令未找到"，请 [安装 Python](#安装-python)。

#### macOS / Linux

```bash
# 打开终端

# 检查 Python
python3 --version

# 应该显示类似：Python 3.8.0 或更新版本
```

如果显示 "command not found"，请 [安装 Python](#安装-python)。

### 步骤 2: 导航到项目目录

#### Windows
```bash
# 方式 1: 用 PowerShell
cd D:\MahjongGame

# 方式 2: 在文件浏览器中打开，Shift + 右键 → 在此处打开 PowerShell
```

#### macOS / Linux
```bash
cd ~/MahjongGame
# 或替换为你的实际路径
```

### 步骤 3: 验证安装（可选）

```bash
# 运行测试脚本（仅 Windows）
test_setup.bat

# 或者直接运行下载脚本查看帮助
python download_wechat_icon.py --help
```

### 步骤 4: 下载图标

#### 最简单的方式

```bash
# 使用默认参数（40x40 SVG）
# Windows
quick_setup.bat

# 其他平台
python download_wechat_icon.py
```

#### 自定义参数

```bash
# 下载其他尺寸
quick_setup.bat --size 64

# 下载 PNG 格式（需要 Pillow 库）
quick_setup.bat --format png

# 两个参数同时指定
quick_setup.bat --size 48 --format svg

# 强制刷新（忽略缓存）
quick_setup.bat --force

# 清理缓存
quick_setup.bat --clear-cache
```

### 步骤 5: 验证成功

检查这些标志说明成功：

```bash
# ✅ 看到这些消息
✅ 图标已部署: ...
✅ 主图标已创建: ...
✅ 图标下载部署完成！

# ✅ 文件已创建
# 在 godot/assets/ 中看到这些文件：
# - wechat_icon.svg（或 .png）
# - wechat_icon.json（元数据）
```

### 步骤 6: 在 Godot 中测试（可选）

```
1. 打开 Godot 编辑器
2. 打开项目：选择 godot 文件夹
3. 打开场景：scenes/loading_screen.tscn
4. 按 F5 运行
5. 查看登录按钮是否显示微信图标
```

---

## 常见问题

### ❓ Python 未安装怎么办？

**安装 Python：**

#### Windows

1. 访问 https://www.python.org/downloads/
2. 下载最新的 Python 3.x
3. 运行安装程序
4. **重要**：勾选 "Add Python to PATH"
5. 点击 "Install Now"
6. 重启计算机或终端

验证安装：
```bash
python --version
```

#### macOS

```bash
# 使用 Homebrew
brew install python3

# 验证
python3 --version
```

#### Linux (Ubuntu/Debian)

```bash
sudo apt update
sudo apt install python3 python3-pip

# 验证
python3 --version
```

---

### ❓ 脚本运行出错怎么办？

**常见错误和解决方案：**

| 错误 | 原因 | 解决方案 |
|------|------|---------|
| `未找到 Python` | Python 未安装或不在 PATH | 安装 Python，添加到 PATH |
| `GitHub 下载失败` | 网络问题 | 脚本会自动生成本地图标 |
| `权限被拒绝` | 权限不足 | 关闭 Godot，以管理员身份运行 |
| `无法写入文件` | 文件被占用 | 关闭所有占用文件的程序 |

详细排查请查看 [TROUBLESHOOTING.md](TROUBLESHOOTING.md)

---

### ❓ 支持哪些尺寸和格式？

**支持的尺寸：**
- 32x32 (小)
- 40x40 (推荐 ⭐)
- 48x48 (中)
- 64x64 (大)
- 128x128 (超大)

**支持的格式：**
- SVG (推荐 - 矢量，无损缩放)
- PNG (需要 Pillow 库)

```bash
# 示例
python download_wechat_icon.py --size 64 --format svg
```

---

### ❓ 可以离线使用吗？

**是的！**

1. 首次下载时需要网络
2. 下载后会自动缓存
3. 后续可以完全离线使用
4. 缓存位置：`user://wechat_icons_cache/`

---

### ❓ 如何更新图标？

```bash
# 方式 1: 强制刷新（重新下载）
quick_setup.bat --force

# 方式 2: 清理缓存后重新下载
quick_setup.bat --clear-cache
python download_wechat_icon.py
```

---

### ❓ 图标在哪里？

下载后的图标位置：

```
godot/
├── assets/
│   ├── wechat_icon.svg          ← 主图标
│   ├── wechat_icon.json         ← 元数据
│   ├── wechat_icon_32x32.svg    ← 其他尺寸
│   ├── wechat_icon_40x40.svg
│   ├── wechat_icon_64x64.svg
│   └── wechat_icon_128x128.svg
```

---

## 故障排查

### 问题排查流程图

```
遇到错误
    ↓
查看错误消息
    ↓
找到对应的错误说明
    ↓
按照建议尝试解决
    ↓
成功？ ← No → 查看 TROUBLESHOOTING.md
    ↓ Yes
完成！✅
```

### 常用命令

```bash
# 查看帮助
python download_wechat_icon.py --help
# 或 (Windows)
quick_setup.bat --help

# 清理缓存
python download_wechat_icon.py --clear-cache

# 默认下载 (40x40 SVG)
python download_wechat_icon.py

# 强制刷新
python download_wechat_icon.py --force

# 下载特定规格
python download_wechat_icon.py --size 64 --format png
```

---

## 高级用法

### 在 Godot 脚本中手动下载

```gdscript
# 创建管理器
var icon_manager = WeChatIconManager.new()
add_child(icon_manager)

# 快速下载（40x40 SVG）
await icon_manager.auto_download_icon(func(success, msg):
    print("下载完成:", success)
)

# 或指定参数
await icon_manager.download_icon(64, "png", false, func(success, msg):
    print("下载完成:", success, msg)
)
```

### 命令行高级用法

```bash
# 下载多个尺寸
for size in 32 40 48 64 128; do
    python download_wechat_icon.py --size $size
done

# 在 CI/CD 中自动下载
python download_wechat_icon.py --force

# 脚本中使用（返回值）
python download_wechat_icon.py
echo "返回代码: $?"  # 0 = 成功, 非 0 = 失败
```

---

## 下一步

### ✅ 已完成的事情
- [x] 系统检查
- [x] 环境准备
- [x] 图标下载
- [x] 验证安装

### 🚀 接下来可以做的事

1. **基础使用**
   - [ ] 在 Godot 中打开游戏
   - [ ] 测试登录界面
   - [ ] 验证图标显示

2. **进阶功能**
   - [ ] 自定义图标尺寸
   - [ ] 集成其他登录方式
   - [ ] 添加暗黑主题支持

3. **部署发布**
   - [ ] 构建游戏
   - [ ] 测试多平台
   - [ ] 提交到应用商店

---

## 文档导航

| 文档 | 用途 |
|------|------|
| 📖 [本文档](GETTING_STARTED.md) | 完整入门指南 |
| ⚡ [快速启动](WECHAT_ICON_QUICK_START.md) | 30秒快速开始 |
| 🚀 [完整指南](docs/🚀_微信图标自动下载部署指南.md) | 详细说明 |
| 🔧 [故障排查](TROUBLESHOOTING.md) | 问题解决 |
| 🎯 [实现总结](IMPLEMENTATION_SUMMARY.md) | 技术细节 |
| 🐛 [Bug 报告](BUG_FIX_REPORT.md) | 已修复问题 |

---

## 获取帮助

### 快速查找

- **30 秒快速开始**: 见 [快速启动](WECHAT_ICON_QUICK_START.md)
- **遇到错误**: 查看 [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
- **想了解更多**: 阅读 [完整指南](docs/🚀_微信图标自动下载部署指南.md)

### 诊断信息

遇到问题时收集这些信息可以帮助快速解决：

```bash
# Python 版本
python --version

# 操作系统
# Windows: systeminfo | findstr /C:"OS Name"
# macOS: system_profiler SPSoftwareDataType
# Linux: lsb_release -d

# Godot 版本
# 在 Godot 编辑器中查看：帮助 → 关于

# 网络连接
ping github.com

# 项目结构
ls -la godot/assets/
```

---

## 技术支持

| 问题类型 | 查看位置 |
|---------|---------|
| 下载失败 | [TROUBLESHOOTING.md](TROUBLESHOOTING.md#python-脚本错误) |
| 脚本出错 | [TROUBLESHOOTING.md](TROUBLESHOOTING.md#quick_setupbat-错误) |
| Godot 问题 | [TROUBLESHOOTING.md](TROUBLESHOOTING.md#godot-脚本错误) |
| 网络问题 | [TROUBLESHOOTING.md](TROUBLESHOOTING.md#网络问题) |
| 文件问题 | [TROUBLESHOOTING.md](TROUBLESHOOTING.md#文件系统问题) |

---

## 反馈和贡献

如果您：
- 🐛 发现了 bug
- 💡 有改进建议
- 📝 发现文档错误
- ✨ 想贡献代码

请查看相关文档或提交反馈！

---

## 许可证

本项目使用 MIT 许可证，完全遵守微信品牌规范。

---

**现在就开始！** 🚀

```bash
# Windows
quick_setup.bat

# macOS / Linux
python download_wechat_icon.py
```

---

**最后更新**: 2025年10月29日  
**版本**: v2.0.1  
**维护者**: AI 代码助手

**祝您使用愉快！** 🎉

