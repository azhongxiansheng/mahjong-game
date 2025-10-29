# 微信登录图标获取指南

## 官方图标下载

### 方式1：微信开放平台（推荐）
1. 访问：https://open.weixin.qq.com/
2. 进入「资源中心」→「设计资源」
3. 下载微信登录按钮素材包

### 方式2：微信官方设计规范
1. 访问：https://developers.weixin.qq.com/doc/
2. 查找「微信登录按钮设计规范」
3. 下载官方提供的图标文件

## 图标规格要求

- **格式**: PNG（支持透明背景）
- **尺寸**: 40x40 像素（推荐）或 80x80（2x）
- **颜色**: 纯白色图标（#FFFFFF）
- **背景**: 透明
- **文件名**: wechat_icon.png

## 安装步骤

1. 下载官方微信图标（白色，透明背景）
2. 将文件重命名为 `wechat_icon.png`
3. 复制到项目路径：`d:\MahjongGame\godot\assets\wechat_icon.png`
4. 删除临时的 SVG 文件：
   - `d:\MahjongGame\godot\assets\wechat_icon.svg`
   - `d:\MahjongGame\godot\assets\wechat_icon.svg.import`
5. 在 Godot 编辑器中重新导入资源

## 替代方案

如果无法访问官方资源，可以使用：
- IconFont（阿里巴巴矢量图标库）
- Font Awesome 的微信图标
- 其他开源图标库的微信图标

## 设计规范

根据微信官方要求：
- 登录按钮背景色：#07C160（微信绿）
- 按钮圆角：8-16px
- 图标与文字间距：8-12px
- 最小点击区域：44x44px

## 当前状态

✅ 已预留图标位置（左侧 30px，垂直居中）
✅ 已配置图标尺寸（40x40px）
⏳ 等待替换为官方图标文件
