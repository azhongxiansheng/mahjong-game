# 🎯 微信图标快速启动指南

> ⏱️ **30 秒快速开始** | 不需要任何配置

---

## 🚀 最快的方式

### Windows 用户（推荐）✅

```bash
# 只需双击运行这个文件
quick_setup.bat
```

完成！图标已自动下载到 `godot/assets/` 目录。

### 所有平台（命令行）

```bash
# 打开终端，进入项目目录
cd D:\MahjongGame

# 运行一条命令
python download_wechat_icon.py
```

就这么简单！ ✨

---

## 📋 命令快速参考

| 命令 | 说明 |
|------|------|
| `quick_setup.bat` | 下载默认规格（40x40 SVG） |
| `quick_setup.bat --size 64` | 下载 64x64 尺寸 |
| `quick_setup.bat --format png` | 下载 PNG 格式 |
| `quick_setup.bat --force` | 强制刷新（忽略缓存） |
| `quick_setup.bat --clear-cache` | 清理缓存 |
| `quick_setup.bat --help` | 显示帮助 |

---

## 🎮 在游戏中自动下载

游戏启动时会**自动**下载最新图标：

```
1. 打开 Godot 编辑器
2. 运行加载画面场景（F5）
3. 图标在后台自动下载
4. 完成！
```

无需任何手动配置 ✅

---

## 📁 生成的文件

下载完成后会得到：

```
godot/assets/
├── wechat_icon.svg          ← 主图标使用这个
├── wechat_icon.json         ← 元数据
└── wechat_icon_40x40.svg    ← 备份
```

---

## ✅ 验证成功

检查这些标志说明成功：

- [ ] 看到 `✅ 图标已部署`
- [ ] 看到 `✅ 主图标已创建`
- [ ] `godot/assets/` 中有 `.svg` 或 `.png` 文件
- [ ] 文件大小 > 0

---

## 🐛 遇到问题？

### Python 未安装
```
❌ 未找到 Python
→ 下载 Python 3.x: https://www.python.org/downloads/
→ 安装时勾选 "Add Python to PATH"
```

### GitHub 下载失败
```
⚠ GitHub 下载失败
→ 不要紧，脚本会自动生成本地图标
```

### 权限拒绝
```
❌ 无法写入文件
→ 关闭 Godot 编辑器
→ 以管理员身份运行
```

---

## 🎯 支持的规格

| 尺寸 | 格式 | 用途 |
|------|------|------|
| **40x40** ⭐ | SVG | 推荐（登录按钮） |
| 32x32 | SVG/PNG | 小图标 |
| 64x64 | SVG/PNG | 中等图标 |
| 128x128 | SVG/PNG | 大图标 |

---

## 🎨 图标特征

- **颜色**：微信官方绿 (#09B83E)
- **设计**：官方圆角方形 + 气泡
- **格式**：SVG 矢量（支持任意缩放）
- **尺寸**：推荐 40x40px

---

## 🔗 相关文件

| 文件 | 说明 |
|------|------|
| `download_wechat_icon.py` | Python 下载脚本 |
| `quick_setup.bat` | Windows 快速启动 |
| `godot/scripts/wechat_icon_downloader.gd` | Godot 下载器 |
| `godot/scripts/wechat_icon_manager.gd` | Godot 管理器 |
| `docs/🚀_微信图标自动下载部署指南.md` | 完整文档 |

---

## 💡 提示

✅ **缓存智能**：第一次下载后会缓存，再次运行会更快  
✅ **离线可用**：缓存后可离线使用  
✅ **自动生成**：网络问题时自动生成官方风格图标  
✅ **无依赖**：SVG 生成不需要额外库（PNG 需要 PIL）

---

## 🎬 下一步

```bash
# 1. 下载图标
quick_setup.bat

# 2. 打开 Godot 编辑器
cd godot
godot

# 3. 运行游戏测试
# 按 F5 运行加载画面场景

# 4. 查看效果
# 微信登录按钮应该显示官方图标 ✅
```

---

## 📞 需要帮助？

1. 📖 查看完整文档：`docs/🚀_微信图标自动下载部署指南.md`
2. 🔍 查看故障排查部分
3. 🌐 访问微信开放平台：https://open.weixin.qq.com/

---

**现在就开始！** 🚀

```bash
quick_setup.bat
```

---

**最后更新**：2025年10月29日

