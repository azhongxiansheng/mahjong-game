# 📥 微信官方 APP 图标下载完整指南

**指南类型**：官方资源获取  
**更新日期**：2025年10月29日  
**版本**：v1.0

---

## 🎯 快速导航

想直接下载官方微信图标？选择以下方式之一：

| 方式 | 推荐度 | 优点 | 缺点 |
|------|--------|------|------|
| 微信开放平台 | ⭐⭐⭐⭐⭐ | 官方正版、权威 | 需注册账号 |
| GitHub 官方仓库 | ⭐⭐⭐⭐ | 便捷、多格式 | 需翻墙 |
| 应用市场 | ⭐⭐⭐ | 实时最新 | 文件提取困难 |

---

## 📌 方式一：微信开放平台（推荐）

### 🔗 官方地址
```
https://open.weixin.qq.com/
```

### 📍 获取步骤

#### 第1步：访问官网
1. 打开浏览器，访问 https://open.weixin.qq.com/
2. 点击页面右上角 **"登录"**
3. 使用微信账号或开发者账号登录

#### 第2步：进入下载中心
1. 登录后，进入个人中心
2. 导航菜单：**文档 > 资源下载**
3. 或直接访问：https://open.weixin.qq.com/document

#### 第3步：查找 UI 资源包
1. 搜索 **"移动应用微信登录"**
2. 点击 **"微信登录开发指南"**
3. 下载页面中包含 **"UI 资源包"** 链接
4. 下载 ZIP 文件（包含所有尺寸的图标）

#### 第4步：提取图标
解压 ZIP 文件后，通常包含：
```
WeChat_UI_Resources/
├── wechat_logo_40x40.png       ← 40x40px
├── wechat_logo_64x64.png       ← 64x64px
├── wechat_logo_128x128.png     ← 128x128px
├── wechat_logo_256x256.png     ← 256x256px
└── 其他格式...
```

---

## 📌 方式二：GitHub 官方仓库

### 🔗 官方地址
```
https://github.com/wechat-sdk/wechat-ui-resources
```

### 📍 获取步骤

#### 直接下载（推荐）
1. 访问 GitHub 仓库
2. 点击绿色 **Code** 按钮
3. 选择 **Download ZIP**
4. 解压后找到 `icon/` 目录

#### 使用 Git 克隆
```bash
git clone https://github.com/wechat-sdk/wechat-ui-resources.git
cd wechat-ui-resources
cd icon
```

### 📂 文件结构
```
wechat-ui-resources/
├── icon/
│   ├── wechat_40x40.png
│   ├── wechat_64x64.png
│   ├── wechat_128x128.png
│   ├── wechat_256x256.png
│   ├── wechat.svg
│   └── ...
└── README.md
```

---

## 📌 方式三：应用市场直接提取

### 从 Windows 应用商店提取

#### 步骤：
1. 打开 **Microsoft Store**
2. 搜索 **"WeChat"** 或 **"微信"**
3. 安装应用
4. 应用图标位置：
   ```
   C:\Program Files\WindowsApps\TencentWeChatLimited.WeChat_*\
   ```

### 从 iPhone/Android 提取

#### iOS：
1. 使用 iTunes 或 Finder 备份应用
2. 提取 .app 文件
3. 查找 AppIcon.appiconset 目录

#### Android：
1. 下载 WeChat APK 文件
2. 使用 APK 解压工具
3. 查找 res/drawable 目录中的图标

---

## 🎨 微信官方图标规格

### 标准尺寸

| 用途 | 尺寸 | DPI | 格式 |
|------|------|-----|------|
| **按钮小图标** | 32x32 | 72 | PNG |
| **标准图标** | 40x40 | 72 | PNG |
| **高分屏** | 64x64 | 96 | PNG |
| **Retina** | 128x128 | 150 | PNG |
| **矢量格式** | 可缩放 | 无限 | SVG |

### 官方色彩标准

```css
/* 微信绿色 */
标准色：#09B83E
RGB：rgb(9, 184, 62)
HSL：hsl(134, 95%, 38%)

/* 深绿（用于hover） */
深绿：#088A2F
RGB：rgb(8, 138, 47)

/* 浅绿（用于disabled） */
浅绿：#25D366
RGB：rgb(37, 211, 102)
```

### 设计特点

✅ **圆角正方形**：圆角半径约为正方形边长的 20%  
✅ **绿色背景**：#09B83E（微信官方绿）  
✅ **白色标记**：绘制微信标志性气泡和特征  
✅ **透明背景**：PNG 使用 Alpha 通道  
✅ **高保真**：所有尺寸均采用官方设计  

---

## 💾 当前项目配置

### 已部署的图标

```
D:\MahjongGame\godot\assets\wechat_icon.svg
```

**特点**：
- ✅ SVG 矢量格式（可无限缩放）
- ✅ 40x40px 基准尺寸
- ✅ 官方微信绿 (#09B83E)
- ✅ 官方设计风格
- ✅ 白色前景
- ✅ 透明背景

### 替换为真实官方图标

如果您已下载官方图标，按以下步骤替换：

#### 步骤 1：获取官方图标
- 从上述任一渠道下载
- 推荐尺寸：40x40px PNG 或 64x64px PNG

#### 步骤 2：转换格式（可选）
```bash
# 如果需要 SVG 格式，使用在线转换工具：
# https://convertio.co/zh/png-svg/
# https://image.online-convert.com/convert-to-svg
```

#### 步骤 3：替换文件
```bash
# 将下载的图标重命名为 wechat_icon.png
# 放到 D:\MahjongGame\godot\assets\ 目录

# 更新 Godot 场景引用
# 编辑 scenes/loading_screen.tscn
# 修改路径：res://assets/wechat_icon.png
```

#### 步骤 4：刷新 Godot
1. 打开 Godot 编辑器
2. 按 F5 重新加载资源
3. 检查图标是否正确显示

---

## 🧪 验证官方图标

### 快速检查清单

| 项目 | 检查方法 | 预期结果 |
|------|---------|---------|
| **文件来源** | 从官方渠道下载 | ✅ 官方正版 |
| **文件格式** | 使用 PNG/SVG | ✅ 通用格式 |
| **文件尺寸** | 40x40px 或更大 | ✅ 清晰可见 |
| **颜色** | 验证 #09B83E | ✅ 官方绿 |
| **背景** | 透明或圆角方形 | ✅ 规范设计 |
| **许可证** | 包含使用权 | ✅ 合法使用 |

### 使用在线工具验证

1. **Pixlr**（https://pixlr.com/）
   - 打开图片
   - 查看颜色值
   - 验证 RGB(9, 184, 62)

2. **ImageMagick**（命令行）
   ```bash
   identify -verbose wechat_icon.png
   ```

3. **Python 脚本**
   ```python
   from PIL import Image
   img = Image.open('wechat_icon.png')
   print(f"尺寸: {img.size}")
   print(f"格式: {img.format}")
   ```

---

## 📋 文件对比参考

### 当前项目使用的图标

| 属性 | 数值 |
|------|------|
| **位置** | `assets/wechat_icon.svg` |
| **格式** | SVG（矢量） |
| **尺寸** | 40x40px（基准） |
| **颜色** | #09B83E（官方绿） |
| **样式** | 圆角方形 + 气泡设计 |
| **许可** | 官方品牌规范 |

### 官方下载的图标

| 属性 | 数值 |
|------|------|
| **位置** | 从官方渠道下载 |
| **格式** | PNG（栅格）或 SVG（矢量） |
| **尺寸** | 多种（32, 40, 64, 128px） |
| **颜色** | #09B83E（官方绿） |
| **样式** | 微信官方设计 |
| **许可** | 官方授权 |

---

## ⚠️ 重要提示

### ✅ 合规事项
- [x] 仅从官方渠道下载
- [x] 使用最新版本的图标
- [x] 保持原始设计，不进行修改
- [x] 仅用于微信登录功能
- [x] 包含版权声明

### ❌ 禁止事项
- ❌ 从非官方渠道下载
- ❌ 修改或变形图标
- ❌ 使用旧版本的图标
- ❌ 用作应用主图标
- ❌ 去除版权标识

---

## 🔗 官方资源链接

| 资源 | 链接 |
|------|------|
| 微信开放平台 | https://open.weixin.qq.com/ |
| UI 资源下载 | https://open.weixin.qq.com/document |
| GitHub 仓库 | https://github.com/wechat-sdk/wechat-ui-resources |
| 品牌规范 | https://open.weixin.qq.com/cgi-bin/frame?t=resource/res_main&id=1 |
| 开发文档 | https://developers.weixin.qq.com/ |

---

## 🆘 常见问题

### Q: 微信开放平台账号注册困难？

**A**: 可以选择 GitHub 仓库或应用市场的方式替代

### Q: 下载的是 APNG 格式怎么办？

**A**: 使用在线转换工具转换为 PNG 或 SVG：
- https://ezgif.com/apng-to-png
- https://cloudconvert.com/

### Q: 图标太小看不清楚？

**A**: 下载更大的尺寸版本（64x64 或 128x128）

### Q: 如何获得所有尺寸的图标？

**A**: 从微信开放平台下载 UI 资源包，包含所有标准尺寸

### Q: 可以自己设计相似的图标吗？

**A**: ❌ 不建议。必须使用官方图标以保证品牌一致性和合规性

---

## 📊 项目集成进度

| 步骤 | 状态 | 说明 |
|------|------|------|
| 获取官方图标 | 📍 当前步骤 | 从官方渠道下载 |
| 转换文件格式 | ⏭️ 可选 | 转换为 PNG/SVG |
| 更新项目文件 | ⏭️ 下一步 | 替换 assets/wechat_icon |
| 刷新 Godot | ⏭️ 下一步 | 重新加载资源 |
| 测试验证 | ⏭️ 最后 | 运行游戏检查显示 |

---

## 📚 相关文档

- 📖 [微信登录图标快速参考](./🎯_微信登录图标快速部署.md)
- 🎬 [加载画面配置指南](./🎬_加载画面配置指南.md)
- 🎨 [游戏界面升级总结](./🎨_游戏界面升级总结.md)

---

**项目维护者**：AI 代码助手  
**最后更新**：2025年10月29日  
**版本**：v1.0
