# 🚀 Railway 部署修复指南

## 问题
```
❌ Failed to deploy
⚠️ "Script start.sh not found"
❌ "Railpack could not determine how to build the app"
```

## 原因
Railway 不知道如何启动您的 Go 后端应用

## 🛠️ 解决方案

我已经为您创建了：

1. **Procfile** - 告诉 Railway 如何启动应用
2. **.railway.json** - Railway 的配置文件

### 现在您需要做的：

#### 方式 1: 手动推送这两个文件（推荐）

```bash
cd D:\MahjongGame

# 查看新文件
git status

# 应该看到:
# Procfile
# .railway.json

# 添加并推送
git add Procfile .railway.json

git commit -m "Fix: Add Railway configuration files for Go deployment"

git push origin main
```

#### 方式 2: 在 Railway 界面中手动配置

1. 打开 Railway: https://railway.app/dashboard
2. 进入 mahjong-game 项目
3. 点击 Settings
4. 找到 "Start Command"
5. 填入: `cd backend && go run main.go`
6. 点击 "Redeploy"

## 📝 配置文件内容

### Procfile
```
web: cd backend && go run main.go
```

### .railway.json
```json
{
  "build": {
    "builder": "nixpacks"
  },
  "deploy": {
    "startCommand": "cd backend && go run main.go"
  }
}
```

## ✅ 验证

部署成功的标志：
- ✅ "Service running" (而不是 Failed)
- ✅ 看到日志: "🚀 服务器启动在端口 :8080"
- ✅ 能访问: https://your-url.railway.app/api/health

## 🎯 快速步骤

1. 推送 Procfile 和 .railway.json 到 GitHub
2. Railway 会自动检测到新文件
3. 自动重新部署
4. 等待成功！

## 💡 说明

Procfile 告诉 Railway：
- `web:` = 这是 Web 服务
- `cd backend &&` = 进入 backend 目录
- `go run main.go` = 运行主程序

这样 Railway 就能正确地构建和启动您的应用！

---

**完成这些步骤后，重新部署应该会成功！** 🎲
