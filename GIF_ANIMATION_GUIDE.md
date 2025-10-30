# GIF动画集成指南

## 方法1：AnimatedSprite2D（推荐）

### 步骤：
1. 将GIF分解为PNG帧序列（使用在线工具或ffmpeg）
2. 放到 `godot/assets/feifan_logo_frames/` 目录
3. 在Godot中使用AnimatedSprite2D

**命令行分解GIF：**
```bash
ffmpeg -i feifan_logo.gif godot/assets/feifan_logo_frames/frame_%03d.png
```

## 方法2：WebM视频（适合复杂动画）

### 步骤：
1. 将GIF转换为WebM格式
2. 使用VideoStreamPlayer播放

**转换命令：**
```bash
ffmpeg -i feifan_logo.gif -c:v libvpx-vp9 -pix_fmt yuva420p feifan_logo.webm
```

## 方法3：在线转换工具

- https://ezgif.com/gif-to-sprite （GIF转精灵图）
- https://cloudconvert.com/gif-to-webm （GIF转WebM）

## 如果你有动画GIF：

直接把文件放到 `d:\MahjongGame\godot\assets\` 目录
告诉我文件名，我会自动集成到登录界面
