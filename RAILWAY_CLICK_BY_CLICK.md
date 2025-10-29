# 🖱️ Railway 一步一步点击指南

## 第一步：打开 Railway Dashboard

```
访问: https://railway.app
登录您的账户
```

---

## 第二步：找到项目

```
在左侧看到 mahjong-game 项目
点击进入
```

---

## 第三步：选择 web 服务

```
在左侧看到 "web" 服务
点击 web 服务
```

---

## 第四步：进入 Settings

```
在右侧看到多个标签：
  - Deployments
  - Variables  
  - Metrics
  - Settings  ← 点击这个

点击 Settings 标签
```

---

## 第五步：找到启动命令字段

```
在 Settings 页面中查找：
  - "Start Command"
  - "Build Command"
  - "Run Command"
  - "Command"

其中之一应该存在
```

---

## 第六步：输入启动命令

```
在启动命令字段中输入：

go run main.go

或

bash start.sh
```

---

## 第七步：保存

```
点击 "Save"、"Apply" 或 "Deploy" 按钮
（具体按钮文字可能不同）
```

---

## 第八步：重新启动

```
返回 Deployments 标签

在右上角找到 "Restart" 或 "Redeploy" 按钮
点击它
```

---

## 第九步：等待

```
⏳ 等待 2-3 分钟

查看 Logs 标签：
  - 如果看到绿色文字和启动日志 → 成功 ✅
  - 如果看到红色错误 → 失败，查看错误信息
```

---

## 第十步：测试

```
如果部署成功，您应该看到：

🎮 麻将游戏后端服务器启动
🚀 服务器在 :8080 运行
✅ 服务器已启动，等待连接...

然后尝试访问：
https://your-railway-url.railway.app/api/health

应该返回：
{"status":"ok","version":"0.1.0"}
```

---

## 🆘 如果找不到某个字段

| 看不到的字段 | 尝试这样做 |
|-------------|----------|
| Settings 标签 | 向右滑动标签栏 |
| Start Command | 在 Environment 部分查找 |
| Restart 按钮 | 在页面右上角或右下角查找 |
| Logs 标签 | 返回 Deployments 标签，然后向下滚动 |

---

## 💡 快速贴士

- **Settings 通常在最右边**
- **Restart 按钮通常在右上角**
- **Logs 通常在部署记录下方**
- **如果没看到任何输入框，向下滚动**
- **有些文字可能显示为中文也可能是英文**

---

**准备好了吗？现在就开始吧！** 🚀
